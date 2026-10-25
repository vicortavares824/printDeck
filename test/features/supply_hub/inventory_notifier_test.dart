import 'package:flutter_test/flutter_test.dart';
import 'package:mobileraker/features/supply_hub/application/inventory_notifier.dart';
import 'package:mobileraker/features/supply_hub/domain/models/supply_item.dart';

void main() {
  group('InventoryNotifier - Domain & Application Rules', () {
    late InventoryNotifier notifier;

    setUp(() {
      notifier = InventoryNotifier();
    });

    test('deve inicializar com lista vazia por padrao', () {
      expect(notifier.state, isEmpty);
    });

    test('deve adicionar um novo item com sucesso', () {
      notifier.addItem(
        title: 'Bico V6 0.4mm',
        description: 'Bico de latao para hotend',
        quantity: 2,
      );

      expect(notifier.state.length, 1);
      final item = notifier.state.first;
      expect(item.title, 'Bico V6 0.4mm');
      expect(item.description, 'Bico de latao para hotend');
      expect(item.quantity, 2);
      expect(item.isBought, isFalse);
    });

    test('ao adicionar item com titulo ja existente, deve somar a quantidade e resetar isBought', () {
      notifier.addItem(
        title: 'Filamento PLA Preto',
        description: 'Carretel 1kg',
        quantity: 1,
      );

      final originalId = notifier.state.first.id;
      notifier.toggleBoughtStatus(originalId);
      expect(notifier.state.first.isBought, isTrue);

      notifier.addItem(
        title: '  filamento pla preto  ',
        description: 'Novo lote',
        quantity: 3,
      );

      expect(notifier.state.length, 1, reason: 'Nao deve duplicar o item');
      final updatedItem = notifier.state.first;
      expect(updatedItem.id, originalId);
      expect(updatedItem.quantity, 4, reason: 'Deve somar a quantidade (1 + 3)');
      expect(updatedItem.isBought, isFalse, reason: 'Deve voltar isBought para false');
    });

    test('deve incrementar a quantidade corretamente', () {
      notifier.addItem(title: 'Tubo PTFE', description: 'Capricornio 1m', quantity: 1);
      final id = notifier.state.first.id;

      notifier.incrementQuantity(id);
      expect(notifier.state.first.quantity, 2);
      notifier.incrementQuantity(id);
      expect(notifier.state.first.quantity, 3);
    });

    test('deve decrementar a quantidade respeitando o piso minimo de 1', () {
      notifier.addItem(title: 'Graxa Branca', description: 'Lubrificante', quantity: 2);
      final id = notifier.state.first.id;

      notifier.decrementQuantity(id);
      expect(notifier.state.first.quantity, 1);
      notifier.decrementQuantity(id);
      expect(notifier.state.first.quantity, 1, reason: 'A quantidade nao pode baixar de 1');
    });

    test('deve alternar status isBought corretamente', () {
      notifier.addItem(title: 'Termistor 100k', description: 'Sensor', quantity: 1);
      final id = notifier.state.first.id;
      expect(notifier.state.first.isBought, isFalse);

      notifier.toggleBoughtStatus(id);
      expect(notifier.state.first.isBought, isTrue);
      notifier.toggleBoughtStatus(id);
      expect(notifier.state.first.isBought, isFalse);
    });

    test('deve lancar erro se o titulo for vazio ou apenas espacos', () {
      expect(
        () => notifier.addItem(title: '   ', description: '', quantity: 1),
        throwsArgumentError,
      );
    });
  });

  group('InventoryNotifier - Ownership (posse)', () {
    // Sem SupplyApiService injetado, este dispositivo nao tem deviceId nem admin:
    //  - itens com ownerId == null sao tratados como proprios (canModify = true);
    //  - itens com ownerId de outra pessoa sao somente leitura (canModify = false).

    test('owner pode alterar item proprio (ownerId null => tratado como proprio)', () {
      final notifier = InventoryNotifier([
        const SupplyItem(id: 'a', title: 'Meu item', description: '', quantity: 1),
      ]);

      expect(notifier.canModify(notifier.state.first), isTrue);
      notifier.incrementQuantity('a');
      expect(notifier.state.first.quantity, 2);
    });

    test('nao-dono NAO pode alterar item de outra pessoa', () {
      final notifier = InventoryNotifier([
        const SupplyItem(
          id: 'b',
          title: 'Item do colega',
          description: '',
          quantity: 1,
          ownerId: 'outro-device',
        ),
      ]);

      final item = notifier.state.first;
      expect(notifier.canModify(item), isFalse);

      // Mutacoes em item alheio devem lancar NotOwnerException e nao alterar o estado.
      expect(() => notifier.incrementQuantity('b'), throwsA(isA<NotOwnerException>()));
      expect(() => notifier.toggleBoughtStatus('b'), throwsA(isA<NotOwnerException>()));
      expect(() => notifier.removeItem('b'), throwsA(isA<NotOwnerException>()));
      expect(notifier.state.first.quantity, 1, reason: 'Estado nao pode mudar');
      expect(notifier.state.length, 1, reason: 'Item alheio nao pode ser removido');
    });

    test('todos VEEM itens de outras pessoas (inventario compartilhado)', () {
      final notifier = InventoryNotifier([
        const SupplyItem(id: 'meu', title: 'Meu', description: '', quantity: 1),
        const SupplyItem(id: 'alheio', title: 'Alheio', description: '', quantity: 1, ownerId: 'x'),
      ]);

      expect(notifier.state.length, 2, reason: 'A lista mostra itens de todos');
      final alheio = notifier.state.firstWhere((e) => e.id == 'alheio');
      expect(notifier.canModify(alheio), isFalse, reason: 'Visivel, mas somente leitura');
    });
  });
}
