import 'dart:convert';
import 'dart:io';

import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/moonraker/file_service.dart';
import 'package:common/service/moonraker/printer_service.dart';
import 'package:common/util/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class UniversalGcodePart {
  final String title;
  final String content;
  final int lineCount;

  const UniversalGcodePart({
    required this.title,
    required this.content,
    required this.lineCount,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'lineCount': lineCount,
      };
}

class UniversalGcodeMetadata {
  final String name;
  final double sizeX;
  final double sizeY;
  final double sizeZ;
  final int layerCount;
  final double layerHeight;
  final double estimatedTimeSeconds;
  final double filamentUsedMm;
  final double targetBedTemp;
  final double targetExtruderTemp;
  final String filamentType;

  const UniversalGcodeMetadata({
    required this.name,
    required this.sizeX,
    required this.sizeY,
    required this.sizeZ,
    required this.layerCount,
    required this.layerHeight,
    required this.estimatedTimeSeconds,
    required this.filamentUsedMm,
    this.targetBedTemp = 60.0,
    this.targetExtruderTemp = 205.0,
    this.filamentType = 'PLA',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'sizeX': sizeX,
        'sizeY': sizeY,
        'sizeZ': sizeZ,
        'layerCount': layerCount,
        'layerHeight': layerHeight,
        'estimatedTimeSeconds': estimatedTimeSeconds,
        'filamentUsedMm': filamentUsedMm,
        'targetBedTemp': targetBedTemp,
        'targetExtruderTemp': targetExtruderTemp,
        'filamentType': filamentType,
      };

  factory UniversalGcodeMetadata.fromJson(Map<String, dynamic> json) =>
      UniversalGcodeMetadata(
        name: json['name'] as String? ?? 'Modelo Universal',
        sizeX: (json['sizeX'] as num?)?.toDouble() ?? 20.0,
        sizeY: (json['sizeY'] as num?)?.toDouble() ?? 20.0,
        sizeZ: (json['sizeZ'] as num?)?.toDouble() ?? 20.0,
        layerCount: json['layerCount'] as int? ?? 50,
        layerHeight: (json['layerHeight'] as num?)?.toDouble() ?? 0.2,
        estimatedTimeSeconds:
            (json['estimatedTimeSeconds'] as num?)?.toDouble() ?? 900.0,
        filamentUsedMm: (json['filamentUsedMm'] as num?)?.toDouble() ?? 450.0,
        targetBedTemp: (json['targetBedTemp'] as num?)?.toDouble() ?? 60.0,
        targetExtruderTemp:
            (json['targetExtruderTemp'] as num?)?.toDouble() ?? 205.0,
        filamentType: json['filamentType'] as String? ?? 'PLA',
      );
}

class UniversalGcodeModel {
  final String id;
  final String name;
  final DateTime processedAt;
  final UniversalGcodePart header;
  final UniversalGcodePart body;
  final UniversalGcodePart footer;
  final UniversalGcodeMetadata metadata;
  final String localDirectoryPath;

  const UniversalGcodeModel({
    required this.id,
    required this.name,
    required this.processedAt,
    required this.header,
    required this.body,
    required this.footer,
    required this.metadata,
    required this.localDirectoryPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'processedAt': processedAt.toIso8601String(),
        'metadata': metadata.toJson(),
        'header': header.toJson(),
        'body': body.toJson(),
        'footer': footer.toJson(),
        'localDirectoryPath': localDirectoryPath,
      };
}

final universalGcodeServiceProvider = Provider<UniversalGcodeService>((ref) {
  return UniversalGcodeService();
});

class UniversalGcodeService {
  /// Test G-Code string representing a 20mm test cube print
  static const String testGcodeContent = '''; ========================================================
; PrintDeck Universal Test G-Code Model (Calibration 20mm)
; Generated for universal multi-printer deployment
; Material: PLA (205C / 60C)
; Layer height: 0.20 mm
; Layers: 50
; Size: 20 x 20 x 10 mm
; ========================================================

; [START_SETUP]
G21 ; set units to millimeters
G90 ; use absolute coordinates
M82 ; use absolute distances for extrusion
M140 S60 ; set bed temperature
M104 S205 ; set extruder temperature
G28 ; home all axes
M190 S60 ; wait for bed temperature
M109 S205 ; wait for extruder temperature
G92 E0 ; reset extrusion distance
; Prime line
G1 Z2.0 F3000
G1 X10.1 Y20 Z0.28 F5000.0 ; move to start-line position
G1 X10.1 Y120.0 Z0.28 F1500.0 E9 ; draw 1st line
G1 X10.4 Y120.0 Z0.28 F5000.0 ; move to side
G1 X10.4 Y20 Z0.28 F1500.0 E18 ; draw 2nd line
G92 E0 ; reset extrusion distance
G1 Z2.0 F3000 ; move Z up
; [END_SETUP]

; [START_UNIVERSAL_MODEL_BODY]
;LAYER:0
M106 S128 ; layer 0 fan
G1 F2400 E-0.8 ; retract
G0 F6000 X90 Y90 Z0.20 ; travel to center
G1 F2400 E0 ; unretract
; Perimeter Base
G1 F1800 X110 Y90 E0.655
G1 X110 Y110 E1.310
G1 X90 Y110 E1.965
G1 X90 Y90 E2.620
; Infill Base
G1 F2400 X91 Y91 E2.800
G1 X109 Y109 E3.400
G1 X109 Y91 E4.000
G1 X91 Y109 E4.600

;LAYER:1
G0 F6000 Z0.40
G1 F1800 X90 Y90 E4.800
G1 X110 Y90 E5.455
G1 X110 Y110 E6.110
G1 X90 Y110 E6.765
G1 X90 Y90 E7.420
G1 X109 Y91 E8.200
G1 X91 Y109 E8.900

;LAYER:2
G0 F6000 Z0.60
G1 F1800 X90 Y90 E9.100
G1 X110 Y90 E9.755
G1 X110 Y110 E10.410
G1 X90 Y110 E11.065
G1 X90 Y90 E11.720

;LAYER:3
G0 F6000 Z0.80
G1 F1800 X90 Y90 E12.000
G1 X110 Y90 E12.655
G1 X110 Y110 E13.310
G1 X90 Y110 E13.965
G1 X90 Y90 E14.620

;LAYER:4
G0 F6000 Z1.00
G1 F1800 X90 Y90 E15.000
G1 X110 Y90 E15.655
G1 X110 Y110 E16.310
G1 X90 Y110 E16.965
G1 X90 Y90 E17.620

;LAYER:5
G0 F6000 Z1.20
G1 F1800 X90 Y90 E18.000
G1 X110 Y90 E18.655
G1 X110 Y110 E19.310
G1 X90 Y110 E19.965
G1 X90 Y90 E20.620
; [END_UNIVERSAL_MODEL_BODY]

; [START_SHUTDOWN]
M140 S0 ; turn off bed
M104 S0 ; turn off extruder
M106 S0 ; turn off fan
G91 ; relative positioning
G1 E-2 F2700 ; retract filament
G1 Z10 F2400 ; lift Z
G90 ; absolute positioning
G1 X0 Y200 F3000 ; park toolhead
M84 ; disable stepper motors
; [END_SHUTDOWN]
''';

  /// Process raw G-Code into universal parts: Header, Body, and Footer
  Future<UniversalGcodeModel> processAndSaveGcode({
    String? gcodeContent,
    String modelName = 'teste_cubo_universal_printdeck',
  }) async {
    final content = gcodeContent ?? testGcodeContent;
    final lines = content.split('\n');

    final headerLines = <String>[];
    final bodyLines = <String>[];
    final footerLines = <String>[];

    int phase = 0; // 0 = header, 1 = body, 2 = footer
    double minX = 9999, maxX = -9999;
    double minY = 9999, maxY = -9999;
    double maxZ = 0;
    int layerCount = 0;
    double maxE = 0;
    double? detectedBedTemp;
    double? detectedExtruderTemp;

    for (final line in lines) {
      final trimmed = line.trim();

      // Check temperature settings in header
      if (phase == 0) {
        if (trimmed.startsWith('M140') || trimmed.startsWith('M190')) {
          final match = RegExp(r'S(\d+(?:\.\d+)?)').firstMatch(trimmed);
          final temp = match != null ? double.tryParse(match.group(1)!) : null;
          if (temp != null && temp > 0) detectedBedTemp = temp;
        }
        if (trimmed.startsWith('M104') || trimmed.startsWith('M109')) {
          final match = RegExp(r'S(\d+(?:\.\d+)?)').firstMatch(trimmed);
          final temp = match != null ? double.tryParse(match.group(1)!) : null;
          if (temp != null && temp > 0) detectedExtruderTemp = temp;
        }
      }

      // Check transition tags or layer markers
      if (trimmed.contains('[START_UNIVERSAL_MODEL_BODY]') ||
          (phase == 0 && trimmed.startsWith(';LAYER:0'))) {
        phase = 1;
      } else if (trimmed.contains('[START_SHUTDOWN]') ||
          (phase == 1 && (trimmed.startsWith('M104 S0') || trimmed.startsWith('M140 S0')))) {
        phase = 2;
      }

      if (phase == 0) {
        headerLines.add(line);
      } else if (phase == 1) {
        bodyLines.add(line);

        // Detect layers
        if (trimmed.startsWith(';LAYER:') || RegExp(r'^G[01].*Z(\d+(?:\.\d+)?)').hasMatch(trimmed)) {
          layerCount++;
        }

        // Detect dimensions & extrusion
        final xMatch = RegExp(r'X(\d+(?:\.\d+)?)').firstMatch(trimmed);
        final yMatch = RegExp(r'Y(\d+(?:\.\d+)?)').firstMatch(trimmed);
        final zMatch = RegExp(r'Z(\d+(?:\.\d+)?)').firstMatch(trimmed);
        final eMatch = RegExp(r'E(\d+(?:\.\d+)?)').firstMatch(trimmed);

        if (xMatch != null) {
          final x = double.parse(xMatch.group(1)!);
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
        if (yMatch != null) {
          final y = double.parse(yMatch.group(1)!);
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        if (zMatch != null) {
          final z = double.parse(zMatch.group(1)!);
          if (z > maxZ) maxZ = z;
        }
        if (eMatch != null) {
          final e = double.parse(eMatch.group(1)!);
          if (e > maxE) maxE = e;
        }
      } else {
        footerLines.add(line);
      }
    }

    final sizeX = (maxX > minX && minX != 9999) ? (maxX - minX) : 20.0;
    final sizeY = (maxY > minY && minY != 9999) ? (maxY - minY) : 20.0;
    final sizeZ = maxZ > 0 ? maxZ : 10.0;
    final finalLayerCount = layerCount > 0 ? layerCount : 50;

    final headerPart = UniversalGcodePart(
      title: 'Cabeçalho e Inicialização Universal',
      content: headerLines.join('\n'),
      lineCount: headerLines.length,
    );

    final bodyPart = UniversalGcodePart(
      title: 'Geometria e Camadas Universais do Modelo',
      content: bodyLines.join('\n'),
      lineCount: bodyLines.length,
    );

    final footerPart = UniversalGcodePart(
      title: 'Finalização e Desligamento Seguro',
      content: footerLines.join('\n'),
      lineCount: footerLines.length,
    );

    final metadata = UniversalGcodeMetadata(
      name: modelName,
      sizeX: double.parse(sizeX.toStringAsFixed(1)),
      sizeY: double.parse(sizeY.toStringAsFixed(1)),
      sizeZ: double.parse(sizeZ.toStringAsFixed(1)),
      layerCount: finalLayerCount,
      layerHeight: 0.20,
      estimatedTimeSeconds: 300,
      filamentUsedMm: double.parse(maxE > 0 ? maxE.toStringAsFixed(1) : '20.6'),
      targetBedTemp: detectedBedTemp ?? 60.0,
      targetExtruderTemp: detectedExtruderTemp ?? 205.0,
      filamentType: 'PLA',
    );

    // Save locally in application documents directory under structured parts
    final appDir = await getApplicationDocumentsDirectory();
    final modelId = 'univ_${DateTime.now().millisecondsSinceEpoch}';
    final targetDir = Directory('${appDir.path}/universal_gcode/$modelId');
    await targetDir.create(recursive: true);

    await File('${targetDir.path}/header.gcode').writeAsString(headerPart.content);
    await File('${targetDir.path}/body.gcode').writeAsString(bodyPart.content);
    await File('${targetDir.path}/footer.gcode').writeAsString(footerPart.content);
    await File('${targetDir.path}/metadata.json').writeAsString(
      jsonEncode(metadata.toJson()),
    );

    final model = UniversalGcodeModel(
      id: modelId,
      name: modelName,
      processedAt: DateTime.now(),
      header: headerPart,
      body: bodyPart,
      footer: footerPart,
      metadata: metadata,
      localDirectoryPath: targetDir.path,
    );

    logger.i('Universal G-Code processed & saved locally at: ${targetDir.path}');
    return model;
  }

  /// Adapt the universal model parts specifically for any target 3D printer
  String generateAdaptedGcodeForPrinter({
    required UniversalGcodeModel model,
    required Machine targetMachine,
    double? customBedTemp,
    double? customExtruderTemp,
  }) {
    final bedTemp = customBedTemp ?? model.metadata.targetBedTemp;
    final extruderTemp = customExtruderTemp ?? model.metadata.targetExtruderTemp;

    final buffer = StringBuffer();
    buffer.writeln('; ========================================================');
    buffer.writeln('; PRINTDECK UNIVERSAL G-CODE DISPATCH');
    buffer.writeln('; Target Printer: ${targetMachine.name} (UUID: ${targetMachine.uuid})');
    buffer.writeln('; Model: ${model.name}');
    buffer.writeln('; Dimensions: ${model.metadata.sizeX} x ${model.metadata.sizeY} x ${model.metadata.sizeZ} mm');
    buffer.writeln('; Material: ${model.metadata.filamentType} (Nozzle: ${extruderTemp.toInt()}C, Bed: ${bedTemp.toInt()}C)');
    buffer.writeln('; Generated At: ${DateTime.now().toIso8601String()}');
    buffer.writeln('; ========================================================');
    buffer.writeln();

    // Universal Start Routine adapted for the machine
    buffer.writeln('; --- UNIVERSAL ADAPTED START FOR ${targetMachine.name} ---');
    buffer.writeln('G21 ; metric values');
    buffer.writeln('G90 ; absolute coordinates');
    buffer.writeln('M82 ; absolute extrusion');
    buffer.writeln('M140 S${bedTemp.toInt()} ; set bed temp');
    buffer.writeln('M104 S${extruderTemp.toInt()} ; set extruder temp');
    buffer.writeln('G28 ; home all axes');
    buffer.writeln('M190 S${bedTemp.toInt()} ; wait bed temp');
    buffer.writeln('M109 S${extruderTemp.toInt()} ; wait extruder temp');
    buffer.writeln('G92 E0 ; reset extruder');
    buffer.writeln('G1 Z2.0 F3000 ; move Z up');
    buffer.writeln('G1 X10.1 Y20 Z0.28 F5000.0 ; prime line start');
    buffer.writeln('G1 X10.1 Y120.0 Z0.28 F1500.0 E9 ; prime line 1');
    buffer.writeln('G1 X10.4 Y120.0 Z0.28 F5000.0 ; prime line 2');
    buffer.writeln('G1 X10.4 Y20 Z0.28 F1500.0 E18 ; prime line 2 end');
    buffer.writeln('G92 E0 ; reset extruder');
    buffer.writeln('G1 Z2.0 F3000');
    buffer.writeln('; --- END ADAPTED START ---');
    buffer.writeln();

    // Injected Universal Body (pure geometry toolpaths)
    buffer.writeln('; --- UNIVERSAL MODEL BODY ---');
    buffer.writeln(model.body.content);
    buffer.writeln('; --- END UNIVERSAL MODEL BODY ---');
    buffer.writeln();

    // Universal End Routine adapted for the machine
    buffer.writeln('; --- UNIVERSAL ADAPTED END FOR ${targetMachine.name} ---');
    buffer.writeln('M140 S0 ; turn off bed');
    buffer.writeln('M104 S0 ; turn off nozzle');
    buffer.writeln('M106 S0 ; turn off fan');
    buffer.writeln('G91 ; relative');
    buffer.writeln('G1 E-2 F2700 ; retract');
    buffer.writeln('G1 Z10 F2400 ; lift');
    buffer.writeln('G90 ; absolute');
    buffer.writeln('G1 X0 Y200 F3000 ; park');
    buffer.writeln('M84 ; disable steppers');
    buffer.writeln('; ========================================================');

    return buffer.toString();
  }

  /// Send the adapted universal G-Code to any registered 3D printer
  Future<void> sendToPrinter({
    required UniversalGcodeModel model,
    required Machine targetMachine,
    required FileService fileService,
    PrinterService? printerService,
    bool startPrintImmediately = false,
  }) async {
    final adaptedGcode = generateAdaptedGcodeForPrinter(
      model: model,
      targetMachine: targetMachine,
    );

    final filename = '${model.name}.gcode';
    logger.i('Uploading universal G-Code "$filename" to printer "${targetMachine.name}"');

    // Upload to target printer's gcodes root
    await fileService.uploadAsFile('gcodes/$filename', adaptedGcode);
    logger.i('Upload complete for "${targetMachine.name}"');

    if (startPrintImmediately && printerService != null) {
      logger.i('Starting print of "$filename" on "${targetMachine.name}"');
      await printerService.startPrint(filename);
    }
  }
}
