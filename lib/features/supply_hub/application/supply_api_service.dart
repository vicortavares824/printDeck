import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';

/// Serviço responsável por sincronizar o almoxarifado (Supply Hub)
/// com a Cloud API da PrintDeck.
class SupplyApiService {
  static const String _baseUrl = 'https://printdeck-cloud.onrender.com';
  static const String _apiKey = 'printdeck-V2Niche';

  /// ID único deste dispositivo. Gerado uma vez por instalação.
  /// Em produção, considere persistir isso em SharedPreferences.
  static final String deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'x-api-key': _apiKey,
        'Content-Type': 'application/json',
      },
    ),
  );

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

    final response = await _dio.post('/api/supply/sync', data: payload);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Falha ao enviar itens para a nuvem: ${response.statusCode}');
    }
  }

  /// Baixa os itens da nuvem para este dispositivo.
  Future<List<SupplyItem>> pullItems() async {
    final response = await _dio.get('/api/supply/items', queryParameters: {'device_id': deviceId});

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
    final response = await _dio.delete(
      '/api/supply/items/$itemId',
      queryParameters: {'device_id': deviceId},
    );
    if (response.statusCode != 200) {
      throw Exception('Falha ao deletar item na nuvem: ${response.statusCode}');
    }
  }
}

/// Provider do serviço de API do almoxarifado.
final supplyApiServiceProvider = Provider((ref) => SupplyApiService());
