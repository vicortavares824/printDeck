import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';

/// Serviço responsável por sincronizar o almoxarifado (Supply Hub)
/// com a Cloud API da PrintDeck.
class SupplyApiService {
  static const String _baseUrl = 'https://printdeck-cloud.onrender.com';
  static const String _apiKey = 'printdeck-V2Niche';

  /// Chave sob a qual o ID do dispositivo é persistido na box de settings do Hive.
  static const String _deviceIdKey = 'supply_hub_device_id';

  /// Cache em memória para evitar leituras repetidas do Hive dentro da sessão.
  static String? _cachedDeviceId;

  /// ID único e estável deste dispositivo. Gerado uma única vez por instalação
  /// e persistido no Hive (box `settingsbox`, já aberta no startup do app), de
  /// forma que o mesmo `device_id` seja reutilizado entre reinicializações.
  /// Sem isso, a nuvem "esqueceria" os itens a cada abertura do app, pois o
  /// `device_id` mudaria.
  static String get deviceId {
    final cached = _cachedDeviceId;
    if (cached != null) return cached;

    final box = Hive.box('settingsbox');
    var id = box.get(_deviceIdKey) as String?;
    if (id == null || id.isEmpty) {
      id = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      box.put(_deviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      // O Render (plano free) hiberna o serviço após inatividade e pode levar
      // de 30 a 60s para acordar no primeiro acesso (cold start). Timeouts
      // generosos evitam o "receive timeout" nesse cenário.
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'x-api-key': _apiKey,
        'Content-Type': 'application/json',
      },
    ),
  );

  /// Executa [action] com uma nova tentativa automática caso a primeira
  /// falhe por timeout/conexão. Isso cobre o cold start do Render: a primeira
  /// chamada "acorda" o servidor e a segunda já responde rápido.
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final isColdStart = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (!isColdStart) rethrow;
      // Segunda tentativa: o servidor já deve ter acordado.
      return await action();
    }
  }

  /// Envia a lista local de itens para a nuvem (substitui os itens remotos deste dispositivo).
  Future<void> pushItems(List<SupplyItem> items) async {
    final payload = {
      'device_id': deviceId,
      'items': items.map((item) => {
            'item_id': item.id,
            'title': item.title,
            'description': item.description,
            'quantity': item.quantity.toDouble(),
            'is_bought': item.isBought,
          }).toList(),
    };

    final response = await _withRetry(() => _dio.post('/api/supply/sync', data: payload));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Falha ao enviar itens para a nuvem: ${response.statusCode}');
    }
  }

  /// Baixa os itens da nuvem para este dispositivo.
  Future<List<SupplyItem>> pullItems() async {
    final response = await _withRetry(
      () => _dio.get('/api/supply/items', queryParameters: {'device_id': deviceId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar itens da nuvem: ${response.statusCode}');
    }

    final List<dynamic> data = response.data;
    return data.map((json) => _fromJson(json)).toList();
  }

  SupplyItem _fromJson(Map<String, dynamic> json) {
    return SupplyItem(
      id: json['item_id'] ?? json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      quantity: (json['quantity'] ?? 1).toInt(),
      isBought: json['is_bought'] ?? false,
    );
  }

  /// Deleta um item da nuvem.
  Future<void> deleteItem(String itemId) async {
    final response = await _withRetry(
      () => _dio.delete(
        '/api/supply/items/$itemId',
        queryParameters: {'device_id': deviceId},
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Falha ao deletar item na nuvem: ${response.statusCode}');
    }
  }
}

/// Provider do serviço de API do almoxarifado.
final supplyApiServiceProvider = Provider((ref) => SupplyApiService());
