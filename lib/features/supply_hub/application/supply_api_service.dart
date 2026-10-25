import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/models/supply_item.dart';

/// Resultado de um push: quantos itens foram aceitos e quais foram recusados
/// por autorizacao (tentativa de alterar item de outro dono sem ser admin).
class PushResult {
  const PushResult({required this.synced, required this.forbidden});
  final int synced;
  final List<String> forbidden;
}

/// Servico responsavel por sincronizar o almoxarifado (Supply Hub)
/// com a Cloud API da PrintDeck.
class SupplyApiService {
  static const String _baseUrl = 'https://printdeck-cloud.onrender.com';
  static const String _apiKey = 'printdeck-V2Niche';

  /// Chave sob a qual o ID do dispositivo e persistido na box de settings do Hive.
  static const String _deviceIdKey = 'supply_hub_device_id';

  /// Chave sob a qual o codigo de admin verificado e persistido (para reenviar
  /// o header x-admin-code nas proximas operacoes). Guardado so localmente neste
  /// dispositivo; a validacao real e sempre no backend.
  static const String _adminCodeKey = 'supply_hub_admin_code';

  static String? _cachedDeviceId;

  /// ID unico e estavel deste dispositivo. Gerado uma unica vez por instalacao
  /// e persistido no Hive (box settingsbox, ja aberta no startup do app).
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

  /// Codigo de admin verificado e persistido neste dispositivo (null se nao for
  /// admin). Quando presente, e enviado no header x-admin-code.
  static String? get adminCode {
    final box = Hive.box('settingsbox');
    final code = box.get(_adminCodeKey) as String?;
    return (code == null || code.isEmpty) ? null : code;
  }

  /// Indica se este dispositivo tem acesso de admin.
  static bool get isAdmin => adminCode != null;

  /// Persiste (ou limpa, se null) o codigo de admin verificado.
  static void setAdminCode(String? code) {
    final box = Hive.box('settingsbox');
    if (code == null || code.isEmpty) {
      box.delete(_adminCodeKey);
    } else {
      box.put(_adminCodeKey, code);
    }
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'x-api-key': _apiKey,
        'Content-Type': 'application/json',
      },
    ),
  );

  /// Monta os headers de uma requisicao, incluindo o x-admin-code quando admin.
  Map<String, dynamic> _headers() {
    final code = adminCode;
    return {if (code != null) 'x-admin-code': code};
  }

  /// Executa [action] com uma nova tentativa automatica caso a primeira
  /// falhe por timeout/conexao (cobre o cold start do Render).
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final isColdStart = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (!isColdStart) rethrow;
      return await action();
    }
  }

  /// Verifica um codigo de admin no backend. Em sucesso, persiste e retorna true.
  Future<bool> verifyAdminCode(String code) async {
    try {
      final response = await _withRetry(
        () => _dio.post(
          '/api/supply/admin/verify',
          options: Options(headers: {'x-admin-code': code}),
        ),
      );
      final ok = response.statusCode == 200;
      if (ok) setAdminCode(code);
      return ok;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return false;
      rethrow;
    }
  }

  /// Remove o acesso de admin deste dispositivo.
  void logoutAdmin() => setAdminCode(null);

  /// Envia a lista local de itens para a nuvem (upsert por item_id no inventario
  /// compartilhado). Retorna quais itens foram recusados por autorizacao.
  Future<PushResult> pushItems(List<SupplyItem> items) async {
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

    final response = await _withRetry(
      () => _dio.post(
        '/api/supply/sync',
        data: payload,
        options: Options(headers: _headers()),
      ),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Falha ao enviar itens para a nuvem: ${response.statusCode}');
    }

    final data = response.data;
    final synced = (data is Map && data['synced'] is int) ? data['synced'] as int : items.length;
    final forbidden = (data is Map && data['forbidden'] is List)
        ? (data['forbidden'] as List).map((e) => e.toString()).toList()
        : <String>[];
    return PushResult(synced: synced, forbidden: forbidden);
  }

  /// Baixa todo o inventario compartilhado da nuvem.
  Future<List<SupplyItem>> pullItems() async {
    final response = await _withRetry(
      () => _dio.get('/api/supply/items', queryParameters: {'device_id': deviceId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar itens da nuvem: ${response.statusCode}');
    }

    final List<dynamic> data = response.data;
    return data.map((json) => _fromJson(json as Map<String, dynamic>)).toList();
  }

  SupplyItem _fromJson(Map<String, dynamic> json) {
    return SupplyItem(
      id: json['item_id'] ?? json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      quantity: (json['quantity'] ?? 1).toInt(),
      isBought: json['is_bought'] ?? false,
      ownerId: json['owner_id'] as String?,
    );
  }

  /// Deleta um item do inventario compartilhado. Lanca [ForbiddenException]
  /// quando o backend recusa (403) por o dispositivo nao ser dono nem admin.
  Future<void> deleteItem(String itemId) async {
    try {
      final response = await _withRetry(
        () => _dio.delete(
          '/api/supply/items/$itemId',
          queryParameters: {'device_id': deviceId},
          options: Options(headers: _headers()),
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('Falha ao deletar item na nuvem: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ForbiddenException('Sem permissao para excluir este item.');
      }
      rethrow;
    }
  }
}

/// Erro de autorizacao: o dispositivo nao e dono do item nem admin.
class ForbiddenException implements Exception {
  ForbiddenException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Provider do servico de API do almoxarifado.
final supplyApiServiceProvider = Provider((ref) => SupplyApiService());
