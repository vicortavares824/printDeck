import 'package:common/data/model/hive/machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileraker/service/printer_import_export_service.dart';

void main() {
  const service = PrinterImportExportService();

  group('PrinterImportExportService', () {
    test('exports machines to valid JSON', () {
      final machines = [
        Machine(
          name: 'Ender 3 V2',
          httpUri: Uri.parse('http://192.168.1.50'),
          wsUri: Uri.parse('ws://192.168.1.50/websocket'),
          apiKey: 'secret_key',
        ),
        Machine(
          name: 'Voron 2.4',
          httpUri: Uri.parse('http://192.168.1.100:7125'),
          wsUri: Uri.parse('ws://192.168.1.100:7125/websocket'),
        ),
      ];

      final jsonString = service.exportPrintersToJson(machines);
      expect(jsonString, contains('"name": "Ender 3 V2"'));
      expect(jsonString, contains('"ip": "192.168.1.50"'));
      expect(jsonString, contains('"apiKey": "secret_key"'));
      expect(jsonString, contains('"name": "Voron 2.4"'));
      expect(jsonString, contains('"ip": "192.168.1.100:7125"'));
    });

    test('parses array of printer objects with ip', () {
      const jsonText = '''
      [
        {
          "name": "Ender 3",
          "ip": "192.168.1.50"
        },
        {
          "name": "Voron 2.4",
          "ip": "192.168.1.100:7125",
          "apiKey": "abc123xyz"
        }
      ]
      ''';

      final list = service.parsePrintersFromJson(jsonText);
      expect(list.length, 2);

      expect(list[0].name, 'Ender 3');
      expect(list[0].httpUri.toString(), 'http://192.168.1.50');
      expect(list[0].wsUri.toString(), 'ws://192.168.1.50/websocket');
      expect(list[0].apiKey, isNull);

      expect(list[1].name, 'Voron 2.4');
      expect(list[1].httpUri.toString(), 'http://192.168.1.100:7125');
      expect(list[1].wsUri.toString(), 'ws://192.168.1.100:7125/websocket');
      expect(list[1].apiKey, 'abc123xyz');
    });

    test('parses array of plain IP strings', () {
      const jsonText = '["192.168.1.50", "192.168.1.100:7125"]';
      final list = service.parsePrintersFromJson(jsonText);
      expect(list.length, 2);
      expect(list[0].httpUri.host, '192.168.1.50');
      expect(list[1].httpUri.host, '192.168.1.100');
      expect(list[1].httpUri.port, 7125);
    });

    test('parses envelope object with printers key', () {
      const jsonText = '''
      {
        "printers": [
          { "name": "Lab Printer", "ip": "10.0.0.15" }
        ]
      }
      ''';
      final list = service.parsePrintersFromJson(jsonText);
      expect(list.length, 1);
      expect(list[0].name, 'Lab Printer');
      expect(list[0].httpUri.host, '10.0.0.15');
    });

    test('detects existing printer by IP/host', () {
      final existing = [
        Machine(
          name: 'Old Ender',
          httpUri: Uri.parse('http://192.168.1.50'),
          wsUri: Uri.parse('ws://192.168.1.50/websocket'),
        ),
      ];

      const jsonText = '[{"name": "New Ender", "ip": "192.168.1.50"}]';
      final list = service.parsePrintersFromJson(jsonText, existingMachines: existing);
      expect(list.length, 1);
      expect(list[0].existingMatchName, 'Old Ender');
    });
  });
}
