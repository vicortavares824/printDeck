import 'dart:convert';

import 'package:common/data/model/hive/machine.dart';
import 'package:common/util/misc.dart';

class ImportablePrinter {
  final String name;
  final String rawIpOrUrl;
  final Uri httpUri;
  final Uri wsUri;
  final String? apiKey;
  final bool trustUntrustedCertificate;
  final int timeout;
  final String? existingMatchName;

  bool isSelected;

  ImportablePrinter({
    required this.name,
    required this.rawIpOrUrl,
    required this.httpUri,
    required this.wsUri,
    this.apiKey,
    this.trustUntrustedCertificate = false,
    this.timeout = 5,
    this.existingMatchName,
    this.isSelected = true,
  });

  Machine toMachine() {
    return Machine(
      name: name,
      httpUri: httpUri,
      wsUri: wsUri,
      apiKey: apiKey,
      trustUntrustedCertificate: trustUntrustedCertificate,
      timeout: timeout,
    );
  }
}

class PrinterImportExportService {
  const PrinterImportExportService();

  /// Exporta a lista de impressoras para uma string JSON formatada.
  String exportPrintersToJson(List<Machine> machines) {
    final list = machines.map((m) {
      final host = m.httpUri.host;
      final port = m.httpUri.hasPort && m.httpUri.port != 80 && m.httpUri.port != 443
          ? ':${m.httpUri.port}'
          : '';
      final ip = '$host$port';

      final map = <String, dynamic>{
        'name': m.name,
        'ip': ip,
        'httpUrl': m.httpUri.toString(),
        'wsUrl': m.wsUri.toString(),
        if (m.apiKey != null && m.apiKey!.isNotEmpty) 'apiKey': m.apiKey,
        if (m.trustUntrustedCertificate) 'trustUntrustedCertificate': true,
        if (m.timeout != 5) 'timeout': m.timeout,
      };
      return map;
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Faz o parse de JSON em múltiplos formatos (array de objetos, array de strings,
  /// objeto único ou envelope {"printers": [...]}) e retorna a lista de impressoras prontas para importar.
  List<ImportablePrinter> parsePrintersFromJson(
    String jsonText, {
    List<Machine> existingMachines = const [],
  }) {
    final trimmed = jsonText.trim();
    if (trimmed.isEmpty) return [];

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw FormatException('Formato JSON inválido: $e');
    }

    List<dynamic> items = [];
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      if (decoded.containsKey('printers') && decoded['printers'] is List) {
        items = decoded['printers'] as List;
      } else if (decoded.containsKey('machines') && decoded['machines'] is List) {
        items = decoded['machines'] as List;
      } else if (decoded.containsKey('data') && decoded['data'] is List) {
        items = decoded['data'] as List;
      } else {
        // Objeto único de impressora
        items = [decoded];
      }
    } else {
      throw const FormatException('O JSON deve ser uma lista de impressoras ou um objeto.');
    }

    final result = <ImportablePrinter>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      String? rawIp;
      String? name;
      String? apiKey;
      String? explicitWsUrl;
      String? explicitHttpUrl;
      bool trustCert = false;
      int timeout = 5;

      if (item is String) {
        rawIp = item.trim();
      } else if (item is Map) {
        final dynamic rawIpVal = item['ip'] ??
            item['host'] ??
            item['address'] ??
            item['url'] ??
            item['httpUrl'] ??
            item['http_url'];

        if (rawIpVal != null) {
          rawIp = rawIpVal.toString().trim();
        }

        final dynamic rawName = item['name'] ?? item['printer_name'] ?? item['title'];
        if (rawName != null) {
          name = rawName.toString().trim();
        }

        final dynamic rawKey = item['apiKey'] ?? item['api_key'] ?? item['key'];
        if (rawKey != null) {
          apiKey = rawKey.toString().trim();
        }

        if (item.containsKey('wsUrl')) explicitWsUrl = item['wsUrl']?.toString();
        if (item.containsKey('ws_url')) explicitWsUrl = item['ws_url']?.toString();
        if (item.containsKey('httpUrl')) explicitHttpUrl = item['httpUrl']?.toString();
        if (item.containsKey('http_url')) explicitHttpUrl = item['http_url']?.toString();

        if (item['trustUntrustedCertificate'] == true || item['trust_ssl'] == true) {
          trustCert = true;
        }

        if (item['timeout'] is int) {
          timeout = item['timeout'] as int;
        }
      }

      if (rawIp == null || rawIp.isEmpty) {
        continue;
      }

      final httpUri = explicitHttpUrl != null
          ? Uri.tryParse(explicitHttpUrl) ?? buildMoonrakerHttpUri(rawIp)
          : buildMoonrakerHttpUri(rawIp);

      final wsUri = explicitWsUrl != null
          ? Uri.tryParse(explicitWsUrl) ?? buildMoonrakerWebSocketUri(rawIp)
          : buildMoonrakerWebSocketUri(rawIp);

      if (httpUri == null || wsUri == null) {
        continue;
      }

      final finalName = (name != null && name.isNotEmpty)
          ? name
          : 'Impressora ${httpUri.host}${httpUri.hasPort && httpUri.port != 80 && httpUri.port != 443 ? ':${httpUri.port}' : ''}';

      String? matchName;
      for (final ex in existingMachines) {
        if (ex.httpUri.host == httpUri.host && ex.httpUri.port == httpUri.port) {
          matchName = ex.name;
          break;
        }
      }

      result.add(ImportablePrinter(
        name: finalName,
        rawIpOrUrl: rawIp,
        httpUri: httpUri,
        wsUri: wsUri,
        apiKey: apiKey,
        trustUntrustedCertificate: trustCert,
        timeout: timeout,
        existingMatchName: matchName,
        isSelected: true,
      ));
    }

    return result;
  }
}
