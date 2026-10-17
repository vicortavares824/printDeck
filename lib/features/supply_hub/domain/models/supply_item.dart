import 'package:freezed_annotation/freezed_annotation.dart';

part 'supply_item.freezed.dart';
part 'supply_item.g.dart';

@freezed
class SupplyItem with _$SupplyItem {
  const SupplyItem._();

  const factory SupplyItem({
    required String id,
    required String title,
    required String description,
    @Default(1) int quantity,
    @Default(false) bool isBought,
  }) = _SupplyItem;

  factory SupplyItem.fromJson(Map<String, dynamic> json) =>
      _$SupplyItemFromJson(json);

  /// Cria uma nova instância validando regras de negócio mínimas
  factory SupplyItem.create({
    required String id,
    required String title,
    required String description,
    int quantity = 1,
    bool isBought = false,
  }) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'A quantidade mínima deve ser 1.');
    }
    return SupplyItem(
      id: id,
      title: title.trim(),
      description: description.trim(),
      quantity: quantity,
      isBought: isBought,
    );
  }
}
