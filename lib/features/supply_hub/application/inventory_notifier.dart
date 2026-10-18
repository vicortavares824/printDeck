import 'dart:math';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';
import 'supply_api_service.dart';

/// StateNotifier responsável pelo gerenciamento de estado do almoxarifado/compras.
class InventoryNotifier extends StateNotifier<List<SupplyItem>> {
  final SupplyApiService? _apiService;

  InventoryNotifier([List<SupplyItem>? initialItems, this._apiService])
      : super(initialItems ?? const <SupplyItem>[]);

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
    } else {
      final newItem = SupplyItem.create(
        id: _generateUniqueId(),
        title: sanitizedTitle,
        description: sanitizedDescription,
        quantity: validQuantity,
        isBought: false,
      );

      state = [newItem, ...state];
    }

    _pushToCloud();
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

    _pushToCloud();
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

    _pushToCloud();
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

    _pushToCloud();
  }

  /// Remove um item completamente do inventário.
  void removeItem(String id) {
    state = state.where((item) => item.id != id).toList();

    _pushToCloud();
  }

  /// Envia a lista local para a nuvem (disparo silencioso, não bloqueia a UI).
  Future<void> _pushToCloud() async {
    final api = _apiService;
    if (api == null) return;
    try {
      await api.pushItems(state);
    } catch (e) {
      // Falha silenciosa: a nuvem pode estar fora do ar; o dado fica salvo localmente.
    }
  }

  /// Puxa os itens da nuvem e substitui a lista local.
  Future<void> pullFromCloud() async {
    final api = _apiService;
    if (api == null) return;
    final cloudItems = await api.pullItems();
    state = cloudItems;
  }

  /// Deleta um item localmente e na nuvem.
  Future<void> removeItemWithCloud(String id) async {
    state = state.where((item) => item.id != id).toList();
    final api = _apiService;
    if (api != null) {
      try {
        await api.deleteItem(id);
      } catch (e) {
        // Falha silenciosa
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
