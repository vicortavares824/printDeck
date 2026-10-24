import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';
import 'supply_api_service.dart';

/// StateNotifier responsável pelo gerenciamento de estado do almoxarifado/compras.
///
/// Offline-first: cada mutação é persistida no box Hive local antes/independente
/// da rede. Falhas de push não apagam o dado local — os ids tocados ficam
/// marcados como pendentes e são reenviados na próxima sincronização.
class InventoryNotifier extends StateNotifier<List<SupplyItem>> {
  final SupplyApiService? _apiService;

  /// Nome do box Hive que guarda os itens do almoxarifado (fonte da verdade
  /// local, sobrevive a reinicializações do app). Espelha o padrão de
  /// [lib/service/local_filament_stock_service.dart].
  static const String boxName = 'supply_hub_items';

  /// Chave reservada dentro do box para a lista (JSON) de ids pendentes de push.
  static const String _pendingKey = '__pending__';

  /// Ids de itens que ainda não foram sincronizados com sucesso na nuvem.
  final Set<String> _pendingSync = <String>{};

  /// Mensagem não-bloqueante do último erro de sincronização (null se nenhum).
  String? _syncError;

  InventoryNotifier([List<SupplyItem>? initialItems, this._apiService])
      : super(initialItems ?? const <SupplyItem>[]) {
    _loadFromHive();
  }

  /// Quantidade de itens aguardando push para a nuvem (leitura não-bloqueante
  /// que a UI pode exibir).
  int get pendingCount => _pendingSync.length;

  /// Último erro de sincronização (não-bloqueante). Null quando não há erro.
  String? get syncError => _syncError;

  /// Carrega os itens do box local no construtor, protegido por
  /// `Hive.isBoxOpen` para ser um no-op quando o box não está aberto
  /// (ex.: caminho de teste, onde o `InventoryNotifier()` sem args deve iniciar
  /// vazio).
  void _loadFromHive() {
    if (!Hive.isBoxOpen(boxName)) return;
    final box = Hive.box<String>(boxName);

    final loaded = <SupplyItem>[];
    for (final entry in box.toMap().entries) {
      if (entry.key == _pendingKey) continue;
      loaded.add(
        SupplyItem.fromJson(jsonDecode(entry.value) as Map<String, dynamic>),
      );
    }
    state = loaded;

    final pendingRaw = box.get(_pendingKey);
    if (pendingRaw != null) {
      final ids = (jsonDecode(pendingRaw) as List<dynamic>).cast<String>();
      _pendingSync
        ..clear()
        ..addAll(ids);
    }
  }

  /// Obtém o box local, ou null quando ele não está aberto (ex.: caminho de
  /// teste, onde o Hive não é inicializado). O box é aberto no startup do app
  /// (`openBoxes()` em app_setup.dart), então em produção já está aberto. Todo
  /// acesso ao Hive é guardado por `Hive.isBoxOpen` para ser um no-op seguro
  /// quando o box não está disponível.
  Box<String>? _box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<String>(boxName);
  }

  /// Persiste (upsert) um item no box local.
  Future<void> _persistItem(SupplyItem item) async {
    final box = _box();
    if (box == null) return;
    await box.put(item.id, jsonEncode(item.toJson()));
  }

  /// Persiste a lista inteira de itens no box local (usado após um merge).
  Future<void> _persistAll(List<SupplyItem> items) async {
    final box = _box();
    if (box == null) return;
    // Remove apenas as entradas de item (preserva a chave de pendências) que
    // não existem mais no estado.
    final currentIds = items.map((e) => e.id).toSet();
    final staleKeys = box.keys
        .where((k) => k != _pendingKey && !currentIds.contains(k))
        .toList();
    for (final key in staleKeys) {
      await box.delete(key);
    }
    for (final item in items) {
      await box.put(item.id, jsonEncode(item.toJson()));
    }
  }

  /// Remove um item do box local.
  Future<void> _deleteItem(String id) async {
    final box = _box();
    if (box == null) return;
    await box.delete(id);
  }

  /// Persiste o conjunto de ids pendentes no box local.
  Future<void> _persistPending() async {
    final box = _box();
    if (box == null) return;
    await box.put(_pendingKey, jsonEncode(_pendingSync.toList()));
  }

  /// Gera um identificador único seguro sem dependências externas adicionais
  String _generateUniqueId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'item_${timestamp}_$randomSuffix';
  }

  /// Adiciona um novo item ou incrementa a quantidade caso já exista pelo título.
  /// Se o item já existir no catálogo/comprado, soma a quantidade e define `isBought = false`.
  void addItem({
    required String title,
    required String description,
    required int quantity,
  }) {
    final sanitizedTitle = title.trim();
    final sanitizedDescription = description.trim();
    final validQuantity = quantity > 0 ? quantity : 1;

    if (sanitizedTitle.isEmpty) {
      throw ArgumentError('O título do item não pode ser vazio.');
    }

    final normalizedNewTitle = sanitizedTitle.toLowerCase();
    final existingIndex = state.indexWhere(
      (item) => item.title.trim().toLowerCase() == normalizedNewTitle,
    );

    final SupplyItem touchedItem;
    if (existingIndex != -1) {
      final existingItem = state[existingIndex];
      final updatedItem = existingItem.copyWith(
        quantity: existingItem.quantity + validQuantity,
        isBought: false, // Reativa o item se estiver comprado
        description: sanitizedDescription.isNotEmpty
            ? sanitizedDescription
            : existingItem.description,
      );

      final updatedList = List<SupplyItem>.from(state);
      updatedList[existingIndex] = updatedItem;
      state = updatedList;
      touchedItem = updatedItem;
    } else {
      final newItem = SupplyItem.create(
        id: _generateUniqueId(),
        title: sanitizedTitle,
        description: sanitizedDescription,
        quantity: validQuantity,
        isBought: false,
      );

      state = [newItem, ...state];
      touchedItem = newItem;
    }

    _persistItem(touchedItem);
    _pushToCloud([touchedItem.id]);
  }

  /// Incrementa a quantidade do item especificado pelo ID.
  void incrementQuantity(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(quantity: item.quantity + 1)
        else
          item,
    ];

    _persistTouched(id);
    _pushToCloud([id]);
  }

  /// Decrementa a quantidade do item especificado pelo ID, respeitando o mínimo de 1.
  void decrementQuantity(String id) {
    state = [
      for (final item in state)
        if (item.id == id && item.quantity > 1)
          item.copyWith(quantity: item.quantity - 1)
        else
          item,
    ];

    _persistTouched(id);
    _pushToCloud([id]);
  }

  /// Alterna o status do item entre pendente/a comprar e comprado.
  void toggleBoughtStatus(String id) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isBought: !item.isBought)
        else
          item,
    ];

    _persistTouched(id);
    _pushToCloud([id]);
  }

  /// Remove um item completamente do inventário.
  void removeItem(String id) {
    state = state.where((item) => item.id != id).toList();

    _pendingSync.remove(id);
    _deleteItem(id);
    _persistPending();
    _pushToCloud([]);
  }

  /// Persiste localmente o item de [id] a partir do estado atual.
  void _persistTouched(String id) {
    final idx = state.indexWhere((item) => item.id == id);
    if (idx == -1) return;
    _persistItem(state[idx]);
  }

  /// Envia a lista local para a nuvem (disparo silencioso, não bloqueia a UI).
  ///
  /// [touchedIds] são os ids modificados nesta operação; em caso de falha eles
  /// (mais quaisquer pendentes anteriores) permanecem marcados como pendentes
  /// para reenvio na próxima sincronização. Nada é perdido: o dado já está no
  /// box local.
  Future<void> _pushToCloud(List<String> touchedIds) async {
    final api = _apiService;
    if (api == null) return;
    try {
      await api.pushItems(state);
      // Sucesso: limpa pendências e erro.
      if (_pendingSync.isNotEmpty) {
        _pendingSync.clear();
        await _persistPending();
      }
      _syncError = null;
    } catch (e) {
      // Falha: o dado continua salvo localmente no box Hive. Marcamos os ids
      // tocados como pendentes para retry na próxima sincronização e expomos
      // um sinal não-bloqueante para a UI (nenhuma exceção propaga).
      _pendingSync.addAll(touchedIds);
      _syncError = e.toString();
      await _persistPending();
    }
  }

  /// Puxa os itens da nuvem e faz um merge NÃO-destrutivo por item_id.
  ///
  /// Regra do merge: unimos a lista local e a da nuvem por item_id. A nuvem é
  /// autoritativa para ids já sincronizados (presentes no box como não
  /// pendentes). Um item criado offline e ainda não enviado (id em
  /// `_pendingSync`) NUNCA é descartado — o estado local vence e ele é
  /// reenviado logo em seguida. Após o merge, a lista resultante é persistida
  /// no box local e os itens ainda pendentes são reenviados.
  Future<void> pullFromCloud() async {
    final api = _apiService;
    if (api == null) return;

    final cloudItems = await api.pullItems();
    final cloudById = {for (final item in cloudItems) item.id: item};
    final localById = {for (final item in state) item.id: item};

    final mergedById = <String, SupplyItem>{};

    // 1) Começa com tudo que veio da nuvem (autoritativo para ids sincronizados).
    mergedById.addAll(cloudById);

    // 2) Itens locais pendentes (criados/alterados offline) vencem a nuvem e
    //    nunca são perdidos — mesmo que a nuvem não os conheça ou os conheça
    //    desatualizados.
    for (final entry in localById.entries) {
      if (_pendingSync.contains(entry.key)) {
        mergedById[entry.key] = entry.value;
      }
    }

    final merged = mergedById.values.toList();
    state = merged;

    await _persistAll(merged);

    // Reenvia o que ainda estiver pendente após o merge.
    if (_pendingSync.isNotEmpty) {
      await _pushToCloud(_pendingSync.toList());
    }
  }

  /// Deleta um item localmente e na nuvem.
  Future<void> removeItemWithCloud(String id) async {
    state = state.where((item) => item.id != id).toList();
    _pendingSync.remove(id);
    await _deleteItem(id);
    await _persistPending();

    final api = _apiService;
    if (api != null) {
      try {
        await api.deleteItem(id);
        _syncError = null;
      } catch (e) {
        // Falha ao deletar na nuvem: o item já foi removido localmente; apenas
        // registramos o erro de forma não-bloqueante.
        _syncError = e.toString();
      }
    }
  }
}

/// Provider global para gerenciar a lista de suprimentos (com serviço de API injetado).
final inventoryNotifierProvider =
    StateNotifierProvider<InventoryNotifier, List<SupplyItem>>((ref) {
  final apiService = ref.watch(supplyApiServiceProvider);
  return InventoryNotifier(null, apiService);
});

/// Provider derivado para itens pendentes ("A Comprar / Salvos")
final pendingSupplyItemsProvider = Provider<List<SupplyItem>>((ref) {
  final allItems = ref.watch(inventoryNotifierProvider);
  return allItems.where((item) => !item.isBought).toList();
});

/// Provider derivado para itens finalizados ("Comprados")
final boughtSupplyItemsProvider = Provider<List<SupplyItem>>((ref) {
  final allItems = ref.watch(inventoryNotifierProvider);
  return allItems.where((item) => item.isBought).toList();
});
