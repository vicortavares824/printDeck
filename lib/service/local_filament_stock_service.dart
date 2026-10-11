import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalSpool {
  LocalSpool({
    required this.id,
    required this.name,
    required this.material,
    required this.vendor,
    required this.colorHex,
    required this.initialWeightGrams,
    required this.remainingWeightGrams,
    required this.diameterMm,
    required this.price,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String material; // PLA, PETG, ABS, TPU, etc.
  final String vendor;
  final String colorHex;
  final double initialWeightGrams;
  final double remainingWeightGrams;
  final double diameterMm;
  final double price;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'material': material,
        'vendor': vendor,
        'colorHex': colorHex,
        'initialWeightGrams': initialWeightGrams,
        'remainingWeightGrams': remainingWeightGrams,
        'diameterMm': diameterMm,
        'price': price,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LocalSpool.fromMap(Map<String, dynamic> map) => LocalSpool(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        material: map['material'] ?? 'PLA',
        vendor: map['vendor'] ?? '',
        colorHex: map['colorHex'] ?? 'FF0000',
        initialWeightGrams: (map['initialWeightGrams'] as num?)?.toDouble() ?? 1000.0,
        remainingWeightGrams: (map['remainingWeightGrams'] as num?)?.toDouble() ?? 1000.0,
        diameterMm: (map['diameterMm'] as num?)?.toDouble() ?? 1.75,
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt']) : DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());
  factory LocalSpool.fromJson(String source) => LocalSpool.fromMap(jsonDecode(source));
}

class LocalFilamentStockNotifier extends StateNotifier<List<LocalSpool>> {
  LocalFilamentStockNotifier() : super([]) {
    _loadFromHive();
  }

  static const String boxName = 'local_filament_stock';

  void _loadFromHive() {
    if (Hive.isBoxOpen(boxName)) {
      final box = Hive.box<String>(boxName);
      final spools = box.values.map((item) => LocalSpool.fromJson(item)).toList();
      state = spools;
    }
  }

  Future<void> addSpool(LocalSpool spool) async {
    final box = await Hive.openBox<String>(boxName);
    await box.put(spool.id, spool.toJson());
    state = [...state, spool];
  }

  Future<void> removeSpool(String id) async {
    final box = await Hive.openBox<String>(boxName);
    await box.delete(id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> updateRemainingWeight(String id, double newWeight) async {
    final box = await Hive.openBox<String>(boxName);
    final updated = state.map((s) {
      if (s.id == id) {
        final newSpool = LocalSpool(
          id: s.id,
          name: s.name,
          material: s.material,
          vendor: s.vendor,
          colorHex: s.colorHex,
          initialWeightGrams: s.initialWeightGrams,
          remainingWeightGrams: newWeight,
          diameterMm: s.diameterMm,
          price: s.price,
          createdAt: s.createdAt,
        );
        box.put(id, newSpool.toJson());
        return newSpool;
      }
      return s;
    }).toList();
    state = updated;
  }
}

final localFilamentStockProvider =
    StateNotifierProvider<LocalFilamentStockNotifier, List<LocalSpool>>((ref) {
  return LocalFilamentStockNotifier();
});
