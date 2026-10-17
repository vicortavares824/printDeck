import 'package:flutter_test/flutter_test.dart';
import 'package:mobileraker/features/supply_hub/application/inventory_notifier.dart';
import 'package:mobileraker/features/supply_hub/domain/models/supply_item.dart';

void main() {
  group('InventoryNotifier - Domain & Application Rules', () {
    late InventoryNotifier notifier;

    setUp(() {
      notifier = InventoryNotifier();
    });

    test('deve inicializar com lista vazia por padrão', () {
      expect(notifier.state, isEmpty);
    });

    test('deve adicionar um novo item com sucesso', () {
      notifier.addItem(
        title: 'Bico V6 0.4mm',
        description: 'Bico de latão para hotend',
        quantity: 2,
      );

      expect(notifier.state.length, 1);
      final item = notifier.state.first;
      expect(item.title, 'Bico V6 0.4mm');
      expect(item.description, 'Bico de latão para hotend');
      expect(item.quantity, 2);
      expect(item.isBought, isFalse);
    });

    test('ao adicionar item com título já existente (mesmo case diferente), deve somar a quantidade e resetar isBought para false', () {
      notifier.addItem(
        title: 'Filamento PLA Preto',
        description: 'Carretel 1kg',
        quantity: 1,
      );

      final originalId = notifier.state.first.id;
      // Marca como comprado primeiro
      notifier.toggleBoughtStatus(originalId);
      expect(notifier.state.first.isBought, isTrue);

      // Adiciona novamente com mesmo título e caixa diferente
      notifier.addItem(
        title: '  filamento pla preto  ',
        description: 'Novo lote',
        quantity: 3,
      );

      expect(notifier.state.length, 1, reason: 'Não deve duplicar o item');
      final updatedItem = notifier.state.first;
      expect(updatedItem.id, originalId);
      expect(updatedItem.quantity, 4, reason: 'Deve somar a quantidade (1 + 3)');
      expect(updatedItem.isBought, isFalse, reason: 'Deve voltar isBought para false');
    });

    test('deve incrementar a quantidade corretamente', () {
      notifier.addItem(
        title: 'Tubo PTFE',
        description: 'Capricórnio 1m',
        quantity: 1,
      );
      final id = notifier.state.first.id;

      notifier.incrementQuantity(id);
      expect(notifier.state.first.quantity, 2);

      notifier.incrementQuantity(id);
      expect(notifier.state.first.quantity, 3);
    });

    test('deve decrementar a quantidade respeitando o piso mínimo de 1', () {
      notifier.addItem(
        title: 'Graxa Branca',
        description: 'Lubrificante para fuso Z',
        quantity: 2,
      );
      final id = notifier.state.first.id;

      notifier.decrementQuantity(id);
      expect(notifier.state.first.quantity, 1);

      // Tentativa de decrementar além do limite de 1
      notifier.decrementQuantity(id);
      expect(notifier.state.first.quantity, 1, reason: 'A quantidade não pode baixar de 1');
    });

    test('deve alternar status isBought corretamente', () {
      notifier.addItem(
        title: 'Termistor 100k',
        description: 'Sensor de temperatura da mesa',
        quantity: 1,
      );
      final id = notifier.state.first.id;
      expect(notifier.state.first.isBought, isFalse);

      notifier.toggleBoughtStatus(id);
      expect(notifier.state.first.isBought, isTrue);

      notifier.toggleBoughtStatus(id);
      expect(notifier.state.first.isBought, isFalse);
    });

    test('deve lançar erro se o título for vazio ou apenas espaços', () {
      expect(
        () => notifier.addItem(title: '   ', description: '', quantity: 1),
        throwsArgumentError,
      );
    });
  });
}
