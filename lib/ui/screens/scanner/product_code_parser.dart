import 'dart:convert';

enum PlatformType {
  mercadoLivre,
  shopee,
  tiktok,
  unknown,
}

class ParsedProductCode {
  final String raw;
  final String? productId;
  final String? shopId;
  final String? formattedMlbId;
  final String? type;
  final PlatformType platform;
  final String? directUrl;

  const ParsedProductCode({
    required this.raw,
    this.productId,
    this.shopId,
    this.formattedMlbId,
    this.type,
    this.platform = PlatformType.unknown,
    this.directUrl,
  });

  bool get isMercadoLivre => platform == PlatformType.mercadoLivre;
  bool get isShopee => platform == PlatformType.shopee;
  bool get isTikTok => platform == PlatformType.tiktok;

  String get searchTerm => productId ?? raw;

  String get mlbProductUrl {
    final id = formattedMlbId ?? (productId != null ? 'MLB-$productId' : raw);
    return 'https://produto.mercadolivre.com.br/$id';
  }

  String get mlbSearchUrl {
    return 'https://lista.mercadolivre.com.br/${Uri.encodeComponent(searchTerm)}';
  }

  String get shopeeProductUrl {
    if (directUrl != null && directUrl!.toLowerCase().contains('shopee')) {
      return directUrl!;
    }
    if (shopId != null && productId != null) {
      return 'https://shopee.com.br/product/$shopId/$productId';
    }
    return 'https://shopee.com.br/search?keyword=${Uri.encodeComponent(productId ?? searchTerm)}';
  }

  String get shopeeSearchUrl {
    return 'https://shopee.com.br/search?keyword=${Uri.encodeComponent(searchTerm)}';
  }

  String get tiktokProductUrl {
    if (directUrl != null && directUrl!.toLowerCase().contains('tiktok')) {
      return directUrl!;
    }
    if (productId != null) {
      return 'https://shop.tiktok.com/view/product/$productId';
    }
    return 'https://www.tiktok.com/search?q=${Uri.encodeComponent(searchTerm)}';
  }

  String get tiktokSearchUrl {
    return 'https://www.tiktok.com/search?q=${Uri.encodeComponent(searchTerm)}';
  }

  String get googleSearchUrl {
    return 'https://www.google.com/search?q=${Uri.encodeComponent(searchTerm)}';
  }
}

ParsedProductCode parseProductCode(String raw) {
  final trimmed = raw.trim();

  // 1. Se for uma URL direta da internet
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final lower = trimmed.toLowerCase();
    if (lower.contains('mercadolivre.com') || lower.contains('mercadolibre.com')) {
      final mlbMatch = RegExp(r'MLB-?(\d+)', caseSensitive: false).firstMatch(trimmed);
      final id = mlbMatch?.group(1);
      return ParsedProductCode(
        raw: trimmed,
        productId: id,
        formattedMlbId: id != null ? 'MLB-$id' : null,
        platform: PlatformType.mercadoLivre,
        directUrl: trimmed,
      );
    } else if (lower.contains('shopee.com')) {
      // Exemplo: shopee.com.br/product/123/456 ou -i.123.456
      final shopeeMatch = RegExp(r'(?:product/|-i\.)(\d+)[/.]([\d]+)').firstMatch(trimmed);
      final sId = shopeeMatch?.group(1);
      final pId = shopeeMatch?.group(2);
      return ParsedProductCode(
        raw: trimmed,
        productId: pId,
        shopId: sId,
        platform: PlatformType.shopee,
        directUrl: trimmed,
      );
    } else if (lower.contains('tiktok.com')) {
      final ttMatch = RegExp(r'(?:product/|product_id=)(\d+)').firstMatch(trimmed);
      final id = ttMatch?.group(1);
      return ParsedProductCode(
        raw: trimmed,
        productId: id,
        platform: PlatformType.tiktok,
        directUrl: trimmed,
      );
    }
    return ParsedProductCode(raw: trimmed, directUrl: trimmed);
  }

  // 2. Tentar decodificar como JSON (ex: {"id":"...","t":"lm"} ou {"shopid":...,"itemid":...} ou {"product_id":"...","t":"tt"})
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      dynamic findKey(List<String> candidates) {
        for (final entry in decoded.entries) {
          final keyNorm = entry.key.toString().replaceAll('_', '').toLowerCase();
          for (final c in candidates) {
            if (keyNorm == c.replaceAll('_', '').toLowerCase()) {
              return entry.value;
            }
          }
        }
        return null;
      }

      final dynamic rawId = findKey(['id', 'itemId', 'productId']);
      final dynamic rawShopId = findKey(['shopId']);
      final dynamic rawType = findKey(['t', 'type', 'platform', 'sp']);
      final dynamic rawUrl = findKey(['url', 'link', 'deeplink', 'fallbackUrl']);

      final idStr = rawId?.toString().trim();
      final shopIdStr = rawShopId?.toString().trim();
      final typeStr = rawType?.toString().trim().toLowerCase();
      final urlStr = rawUrl?.toString().trim();

      // Determinar plataforma
      PlatformType platform = PlatformType.unknown;
      if (typeStr == 'lm' ||
          typeStr == 'ml' ||
          typeStr == 'mercadolivre' ||
          (idStr != null && idStr.toUpperCase().startsWith('ML'))) {
        platform = PlatformType.mercadoLivre;
      } else if (typeStr == 'sp' ||
          typeStr == 'shopee' ||
          shopIdStr != null ||
          (urlStr != null && urlStr.toLowerCase().contains('shopee'))) {
        platform = PlatformType.shopee;
      } else if (typeStr == 'tt' ||
          typeStr == 'tiktok' ||
          typeStr == 'tiktokshop' ||
          (urlStr != null && urlStr.toLowerCase().contains('tiktok'))) {
        platform = PlatformType.tiktok;
      }

      if (idStr != null || shopIdStr != null || urlStr != null) {
        return ParsedProductCode(
          raw: trimmed,
          productId: idStr,
          shopId: shopIdStr,
          formattedMlbId: idStr != null ? _formatMlbId(idStr) : null,
          type: typeStr,
          platform: platform,
          directUrl: urlStr,
        );
      }
    }
  } catch (_) {
    // Caso JSON estrito falhe, tentar via Regex
  }

  // 3. Regex fallback para JSON solto / aspas simples
  final idMatch = RegExp(r'''["']?(?:id|item_?id|product_?id)["']?\s*:\s*["']?([a-zA-Z0-9_-]+)["']?''', caseSensitive: false).firstMatch(trimmed);
  final shopMatch = RegExp(r'''["']?shop_?id["']?\s*:\s*["']?([a-zA-Z0-9_-]+)["']?''', caseSensitive: false).firstMatch(trimmed);
  final typeMatch = RegExp(r'''["']?(?:t|type|platform)["']?\s*:\s*["']?([a-zA-Z0-9_-]+)["']?''', caseSensitive: false).firstMatch(trimmed);

  if (idMatch != null || shopMatch != null) {
    final idStr = idMatch?.group(1);
    final shopIdStr = shopMatch?.group(1);
    final typeStr = typeMatch?.group(1)?.toLowerCase();

    PlatformType platform = PlatformType.unknown;
    if (typeStr == 'lm' ||
        typeStr == 'ml' ||
        typeStr == 'mercadolivre' ||
        (idStr != null && idStr.toUpperCase().startsWith('ML'))) {
      platform = PlatformType.mercadoLivre;
    } else if (typeStr == 'sp' || typeStr == 'shopee' || shopIdStr != null) {
      platform = PlatformType.shopee;
    } else if (typeStr == 'tt' || typeStr == 'tiktok') {
      platform = PlatformType.tiktok;
    }

    return ParsedProductCode(
      raw: trimmed,
      productId: idStr,
      shopId: shopIdStr,
      formattedMlbId: idStr != null ? _formatMlbId(idStr) : null,
      type: typeStr,
      platform: platform,
    );
  }

  // 4. Código direto do Mercado Livre (ex: MLB-48214515581 ou MLB48214515581)
  final mlbMatch = RegExp(r'^MLB-?(\d+)$', caseSensitive: false).firstMatch(trimmed);
  if (mlbMatch != null) {
    final digits = mlbMatch.group(1)!;
    return ParsedProductCode(
      raw: trimmed,
      productId: digits,
      formattedMlbId: 'MLB-$digits',
      platform: PlatformType.mercadoLivre,
    );
  }

  // Código genérico (código de barras EAN, GTIN ou texto livre)
  return ParsedProductCode(raw: trimmed);
}

String _formatMlbId(String idStr) {
  final upper = idStr.toUpperCase();
  if (upper.startsWith('MLB-')) {
    return 'MLB-${idStr.substring(4)}';
  } else if (upper.startsWith('MLB')) {
    return 'MLB-${idStr.substring(3)}';
  } else if (RegExp(r'^[A-Z]{3}-?\d+$', caseSensitive: false).hasMatch(idStr)) {
    return idStr;
  }
  return 'MLB-$idStr';
}
