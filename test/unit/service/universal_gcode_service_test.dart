import 'dart:io';

import 'package:common/data/model/hive/machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileraker/service/gcode/universal_gcode_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../test_utils.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    final tempDir = Directory.systemTemp.createTempSync('printdeck_test_');
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  setUpAll(() {
    setupTestLogger();
  });

  group('UniversalGcodeService', () {
    late UniversalGcodeService service;

    setUp(() {
      service = UniversalGcodeService();
    });

    test('processes test G-Code and extracts structured parts and metadata',
        () async {
      final model = await service.processAndSaveGcode(
        modelName: 'teste_cubo_universal',
      );

      expect(model.name, 'teste_cubo_universal');
      expect(model.header.lineCount, greaterThan(0));
      expect(model.body.lineCount, greaterThan(0));
      expect(model.footer.lineCount, greaterThan(0));

      expect(model.metadata.sizeX, greaterThanOrEqualTo(20.0));
      expect(model.metadata.sizeY, greaterThanOrEqualTo(20.0));
      expect(model.metadata.layerCount, greaterThanOrEqualTo(5));
      expect(model.metadata.targetBedTemp, 60.0);
      expect(model.metadata.targetExtruderTemp, 205.0);

      // Verify that local files were created in the structured directory
      final dir = Directory(model.localDirectoryPath);
      expect(await dir.exists(), isTrue);
      expect(await File('${dir.path}/header.gcode').exists(), isTrue);
      expect(await File('${dir.path}/body.gcode').exists(), isTrue);
      expect(await File('${dir.path}/footer.gcode').exists(), isTrue);
      expect(await File('${dir.path}/metadata.json').exists(), isTrue);
    });

    test('adapts universal G-Code for a target printer', () async {
      final model = await service.processAndSaveGcode(
        modelName: 'teste_cubo_universal',
      );

      final machine = Machine(
        name: 'Ender 3 V2 Pro',
        wsUri: Uri.parse('ws://192.168.1.50/websocket'),
        httpUri: Uri.parse('http://192.168.1.50'),
      )..uuid = 'test-printer-uuid-123';

      final adaptedGcode = service.generateAdaptedGcodeForPrinter(
        model: model,
        targetMachine: machine,
        customBedTemp: 65.0,
        customExtruderTemp: 210.0,
      );

      expect(adaptedGcode, contains('Ender 3 V2 Pro'));
      expect(adaptedGcode, contains('test-printer-uuid-123'));
      expect(adaptedGcode, contains('M140 S65'));
      expect(adaptedGcode, contains('M104 S210'));
      expect(adaptedGcode, contains('; --- UNIVERSAL MODEL BODY ---'));
      expect(adaptedGcode, contains('; --- UNIVERSAL ADAPTED END FOR Ender 3 V2 Pro ---'));
    });
  });
}
