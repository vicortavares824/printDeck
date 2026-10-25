import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';
import 'supply_api_service.dart';

/// Erro lancado quando este dispositivo tenta alterar/excluir um item que nao
/// criou (e nao e admin). A UI deve impedir essa acao, mas o notifier tambem
/// se protege para nunca corromper o estado compartilhado.
class NotOwnerException implements Exception {
  NotOwnerException([this.message = 'Apenas o criador do item pode altera-lo.']);
  final String message;
  @override
  String toString() => message;
}

/// StateNotifier responsavel pelo gerenciamento de estado do almoxarifado/compras.
///
/// Offline-first: cada mutacao e persistida no box Hive local antes/independente
/// da rede. Falhas de push nao apagam o dado local.
///
/// Posse (ownership): o inventario e compartilhado (todos veem tudo), mas cada
/// pessoa so pode editar/excluir os itens que criou (ownerId == deviceId deste
/// dispositivo). Um admin (codigo verificado no backend) pode alterar qualquer
/// item. Regra aplicada tambem no backend (fonte da verdade da autorizacao).
class InventoryNotifier extends StateNotifier<List<SupplyItem>> {
  final SupplyApiService? _apiService;

  static const String boxName = 'supply_hub_items';
  static const String _pendingKey = '__pending__';

  final Set<String> _pendingSync = <String>{};
  String? _syncError;

  InventoryNotifier([List<SupplyItem>? initialItems, this._apiService])
      : super(initialItems ?? const <SupplyItem>[]) {
    _loadFromHive();
  }

  int get pendingCount => _pendingSync.length;
  String? get syncError => _syncError;

  String? get _deviceId {
    if (_apiService == null) return null;
    try {
      return SupplyApiService.deviceId;
    } catch (_) {
      return null;
    }
  }

  bool get isAdmin {
    try {
      return SupplyApiService.isAdmin;
    } catch (_) {
      return false;
    }
  }

  /// Regra de posse para UI/estado: pode alterar/excluir se for admin, se o item
  /// ainda nao tem dono conhecido (null => recem-criado local), ou se o dono e
  /// este dispositivo. Itens de outro device sao somente leitura.
  bool canModify(SupplyItem item) {
    if (isAdmin) return true;
    final me = _deviceId;
    if (item.ownerId == null) return true;
    return me != null && item.ownerId == me;
  }

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

  Box<String>? _box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<String>(boxName);
  }

  Future<void> _persistItem(SupplyItem item) async {
    final box = _box();
    if (box == null) return;
    await box.put(item.id, jsonEncode(item.toJson()));
  }

  Future<void> _persistAll(List<SupplyItem> items) async {
    final box = _box();
    if (box == null) return;
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

  Future<void> _deleteLocal(String id) async {
    final box = _box();
    if (box == null) return;
    await box.delete(id);
  }

  Future<void> _persistPending() async {
    final box = _box();
    if (box == null) return;
    await box.put(_pendingKey, jsonEncode(_pendingSync.toList()));
  }

  String _generateUniqueId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'item_${timestamp}_$randomSuffix';
  }

  SupplyItem? _requireModifiable(String id) {
    final idx = state.indexWhere((item) => item.id == id);
    if (idx == -1) return null;
    final item = state[idx];
    if (!canModify(item)) {
      throw NotOwnerException();
    }
    return item;
  }

  void addItem({
    required String title,
    required String description,
    required int quantity,
  }) {
    final sanitizedTitle = title.trim();
    final sanitizedDescription = description.trim();
    final validQuantity = quantity > 0 ? quantity : 1;

    if (sanitizedTitle.isEmpty) {
      throw ArgumentError('O titulo do item nao pode ser vazio.');
    }

    final normalizedNewTitle = sanitizedTitle.toLowerCase();
    final existingIndex = state.indexWhere(
      (item) => item.title.trim().toLowerCase() == normalizedNewTitle,
    );

    final SupplyItem touchedItem;
    if (existingIndex != -1) {
      final existingItem = state[existingIndex];
      if (!canModify(existingItem)) {
        throw NotOwnerException();
      }
      final updatedItem = existingItem.copyWith(
        quantity: existingItem.quantity + validQuantity,
        isBought: false,
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
        ownerId: _deviceId,
      );

      state = [newItem, ...state];
      touchedItem = newItem;
    }

    _persistItem(touchedItem);
    _pushToCloud([touchedItem.id]);
  }

  void incrementQuantity(String id) {
    final item = _requireModifiable(id);
    if (item == null) return;
    state = [
      for (final it in state)
        if (it.id == id) it.copyWith(quantity: it.quantity + 1) else it,
    ];
    _persistTouched(id);
    _pushToCloud([id]);
  }

  void decrementQuantity(String id) {
    final item = _requireModifiable(id);
    if (item == null) return;
    state = [
      for (final it in state)
        if (it.id == id && it.quantity > 1)
          it.copyWith(quantity: it.quantity - 1)
        else
          it,
    ];
    _persistTouched(id);
    _pushToCloud([id]);
  }

  void toggleBoughtStatus(String id) {
    final item = _requireModifiable(id);
    if (item == null) return;
    state = [
      for (final it in state)
        if (it.id == id) it.copyWith(isBought: !it.isBought) else it,
    ];
    _persistTouched(id);
    _pushToCloud([id]);
  }

  void removeItem(String id) {
    final item = _requireModifiable(id);
    if (item == null) return;
    state = state.where((it) => it.id != id).toList();
    _pendingSync.remove(id);
    _deleteLocal(id);
    _persistPending();
    _pushToCloud([]);
  }

  void _persistTouched(String id) {
    final idx = state.indexWhere((item) => item.id == id);
    if (idx == -1) return;
    _persistItem(state[idx]);
  }

  Future<void> _pushToCloud(List<String> touchedIds) async {
    final api = _apiService;
    if (api == null) return;
    try {
      final result = await api.pushItems(state);
      if (result.forbidden.isNotEmpty) {
        _syncError =
            'Alguns itens nao sao seus e nao foram salvos: ${result.forbidden.length}.';
      } else {
        _syncError = null;
      }
      // Push bem-sucedido: tudo que era nosso subiu e os recusados (forbidden)
      // nao sao nossos para reenviar. Limpa e persiste as pendencias de forma
      // incondicional para que ids obsoletos nao sobrevivam a um restart.
      final hadPending = _pendingSync.isNotEmpty;
      _pendingSync.clear();
      if (hadPending) {
        await _persistPending();
      }
    } catch (e) {
      _pendingSync.addAll(touchedIds);
      _syncError = e.toString();
      await _persistPending();
    }
  }

  Future<void> pullFromCloud() async {
    final api = _apiService;
    if (api == null) return;

    final cloudItems = await api.pullItems();
    final cloudById = {for (final item in cloudItems) item.id: item};
    final localById = {for (final item in state) item.id: item};

    final mergedById = <String, SupplyItem>{};
    mergedById.addAll(cloudById);
    for (final entry in localById.entries) {
      if (_pendingSync.contains(entry.key)) {
        mergedById[entry.key] = entry.value;
      }
    }

    final merged = mergedById.values.toList();
    state = merged;
    await _persistAll(merged);

    if (_pendingSync.isNotEmpty) {
      await _pushToCloud(_pendingSync.toList());
    }
  }

  Future<void> removeItemWithCloud(String id) async {
    final item = _requireModifiable(id);
    if (item == null) return;

    state = state.where((it) => it.id != id).toList();
    _pendingSync.remove(id);
    await _deleteLocal(id);
    await _persistPending();

    final api = _apiService;
    if (api != null) {
      try {
        await api.deleteItem(id);
        _syncError = null;
      } catch (e) {
        _syncError = e.toString();
      }
    }
  }

  Future<bool> loginAsAdmin(String code) async {
    final api = _apiService;
    if (api == null) return false;
    final ok = await api.verifyAdminCode(code);
    if (ok) {
      state = [...state];
    }
    return ok;
  }

  void logoutAdmin() {
    _apiService?.logoutAdmin();
    state = [...state];
  }
}

final inventoryNotifierProvider =
    StateNotifierProvider<InventoryNotifier, List<SupplyItem>>((ref) {
  final apiService = ref.watch(supplyApiServiceProvider);
  return InventoryNotifier(null, apiService);
});

final pendingSupplyItemsProvider = Provider<List<SupplyItem>>((ref) {
  final allItems = ref.watch(inventoryNotifierProvider);
  return allItems.where((item) => !item.isBought).toList();
});

final boughtSupplyItemsProvider = Provider<List<SupplyItem>>((ref) {
  final allItems = ref.watch(inventoryNotifierProvider);
  return allItems.where((item) => item.isBought).toList();
});
