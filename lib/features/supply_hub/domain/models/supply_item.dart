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
    // Dono do item = device_id de quem o criou. Null para itens legados
    // (criados antes do controle de posse) ou vindos da nuvem sem dono.
    // ignore: invalid_annotation_target
    @JsonKey(name: 'owner_id') String? ownerId,
  }) = _SupplyItem;

  factory SupplyItem.fromJson(Map<String, dynamic> json) =>
      _$SupplyItemFromJson(json);

  /// Cria uma nova instancia validando regras de negocio minimas
  factory SupplyItem.create({
    required String id,
    required String title,
    required String description,
    int quantity = 1,
    bool isBought = false,
    String? ownerId,
  }) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'A quantidade minima deve ser 1.');
    }
    return SupplyItem(
      id: id,
      title: title.trim(),
      description: description.trim(),
      quantity: quantity,
      isBought: isBought,
      ownerId: ownerId,
    );
  }
}
