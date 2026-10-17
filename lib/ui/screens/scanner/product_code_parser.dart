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
  final String? itemId;
  final String? catalogId;
  final String? productTitle;
  final String? shopId;
  final String? formattedMlbId;
  final String? type;
  final PlatformType platform;
  final String? directUrl;

  const ParsedProductCode({
    required this.raw,
    this.productId,
    this.itemId,
    this.catalogId,
    this.productTitle,
    this.shopId,
    this.formattedMlbId,
    this.type,
    this.platform = PlatformType.unknown,
    this.directUrl,
  });

  bool get isMercadoLivre => platform == PlatformType.mercadoLivre;
  bool get isShopee => platform == PlatformType.shopee;
  bool get isTikTok => platform == PlatformType.tiktok;

  String get searchTerm => productTitle ?? itemId ?? catalogId ?? productId ?? raw;

  String get mlbProductUrl {
    if (catalogId != null && itemId == null) {
      final clean = catalogId!.replaceAll('-', '');
      return 'https://www.mercadolivre.com.br/p/$clean';
    }
    if (formattedMlbId != null) {
      return 'https://produto.mercadolivre.com.br/$formattedMlbId';
    }
    if (directUrl != null && (directUrl!.toLowerCase().contains('mercadolivre.com') || directUrl!.toLowerCase().contains('mercadolibre.com'))) {
      return directUrl!;
    }
    final id = formattedMlbId ?? (productId != null ? (productId!.toUpperCase().startsWith('MLB') ? productId! : 'MLB-$productId') : raw);
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
      String? extractedItemId;
      String? extractedCatalogId;
      String? extractedTitle;

      // a) Procurar item_id em parâmetros de busca (ex: pdp_filters=item_id:MLB4790249909 ou item_id=MLB... ou item_id:123...)
      final itemIdParamMatch = RegExp(r'(?:item_id|itemid|item)[:=]([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
      if (itemIdParamMatch != null) {
        extractedItemId = itemIdParamMatch.group(1);
      }

      // b) Procurar catálogo ou UP ID (ex: /up/MLBU4127265954 ou /p/MLB123456 ou /up/1234)
      final catalogMatch = RegExp(r'/(?:up|p)/([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
      if (catalogMatch != null) {
        extractedCatalogId = catalogMatch.group(1);
      }

      // c) Tentar extrair título amigável a partir do slug do caminho
      try {
        final uri = Uri.parse(trimmed);
        for (final seg in uri.pathSegments) {
          if (seg.contains('-') && !seg.toUpperCase().startsWith('MLB') && seg != 'up' && seg != 'p') {
            extractedTitle = seg
                .split('-')
                .where((w) => w.isNotEmpty)
                .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join(' ');
            break;
          }
        }
      } catch (_) {}

      // d) Se não achou itemId específico pelo param, verificar padrão MLB-123456789 no slug
      if (extractedItemId == null) {
        final mlbDirectMatch = RegExp(r'(MLB-?\d+)', caseSensitive: false).firstMatch(trimmed);
        if (mlbDirectMatch != null && mlbDirectMatch.group(1) != extractedCatalogId) {
          extractedItemId = mlbDirectMatch.group(1);
        }
      }

      // Determinar o primaryId
      final primaryId = extractedItemId ?? extractedCatalogId;
      final digitsMatch = primaryId != null ? RegExp(r'\d+').firstMatch(primaryId) : null;
      final productId = digitsMatch?.group(0) ?? primaryId;

      return ParsedProductCode(
        raw: trimmed,
        productId: productId,
        itemId: extractedItemId,
        catalogId: extractedCatalogId,
        productTitle: extractedTitle,
        formattedMlbId: primaryId != null ? _formatMlbId(primaryId) : null,
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
        itemId: pId,
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
        itemId: id,
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
      Object? findKey(List<String> candidates) {
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

      final rawId = findKey(['id', 'itemId', 'productId', 'catalogId']);
      final rawShopId = findKey(['shopId']);
      final rawType = findKey(['t', 'type', 'platform', 'sp']);
      final rawUrl = findKey(['url', 'link', 'deeplink', 'fallbackUrl']);

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
        final isCatalog = idStr != null && idStr.toUpperCase().startsWith('MLBU');
        return ParsedProductCode(
          raw: trimmed,
          productId: idStr,
          itemId: (platform == PlatformType.mercadoLivre && !isCatalog) ? idStr : null,
          catalogId: isCatalog ? idStr : null,
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

  // 3. String com prefixo explícito de identificador (ex: "item_id: MLB4790249909" ou "item_id:MLBU4127265954" ou "item_id=...")
  final itemIdPrefixMatch = RegExp(r'^(?:item_?id|pdp_filters=item_?id)[:=\s]+([a-zA-Z0-9_-]+)$', caseSensitive: false).firstMatch(trimmed);
  if (itemIdPrefixMatch != null) {
    final id = itemIdPrefixMatch.group(1)!;
    final isCatalog = id.toUpperCase().startsWith('MLBU');
    final digits = RegExp(r'\d+').firstMatch(id)?.group(0);
    return ParsedProductCode(
      raw: trimmed,
      productId: digits ?? id,
      itemId: !isCatalog ? id : null,
      catalogId: isCatalog ? id : null,
      formattedMlbId: _formatMlbId(id),
      platform: PlatformType.mercadoLivre,
    );
  }

  // 4. Regex fallback para JSON solto / aspas simples
  final idMatch = RegExp(r'''["']?(?:id|item_?id|product_?id|catalog_?id)["']?\s*:\s*["']?([a-zA-Z0-9_-]+)["']?''', caseSensitive: false).firstMatch(trimmed);
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

    final isCatalog = idStr != null && idStr.toUpperCase().startsWith('MLBU');

    return ParsedProductCode(
      raw: trimmed,
      productId: idStr,
      itemId: (platform == PlatformType.mercadoLivre && !isCatalog) ? idStr : null,
      catalogId: isCatalog ? idStr : null,
      shopId: shopIdStr,
      formattedMlbId: idStr != null ? _formatMlbId(idStr) : null,
      type: typeStr,
      platform: platform,
    );
  }

  // 5. Código direto do Mercado Livre (ex: MLB-48214515581, MLB48214515581, MLBU4127265954, MLBU-4127265954)
  final mlbMatch = RegExp(r'^(MLB[Uu]?)-?(\d+)$', caseSensitive: false).firstMatch(trimmed);
  if (mlbMatch != null) {
    final prefix = mlbMatch.group(1)!.toUpperCase();
    final digits = mlbMatch.group(2)!;
    final isCatalog = prefix.startsWith('MLBU');
    return ParsedProductCode(
      raw: trimmed,
      productId: digits,
      itemId: !isCatalog ? '$prefix$digits' : null,
      catalogId: isCatalog ? '$prefix$digits' : null,
      formattedMlbId: '$prefix-$digits',
      platform: PlatformType.mercadoLivre,
    );
  }

  // Código genérico (código de barras EAN, GTIN ou texto livre)
  return ParsedProductCode(raw: trimmed);
}

String _formatMlbId(String idStr) {
  final upper = idStr.toUpperCase();
  if (upper.startsWith('MLBU-')) {
    return 'MLBU-${idStr.substring(5)}';
  } else if (upper.startsWith('MLBU')) {
    return 'MLBU-${idStr.substring(4)}';
  } else if (upper.startsWith('MLB-')) {
    return 'MLB-${idStr.substring(4)}';
  } else if (upper.startsWith('MLB')) {
    return 'MLB-${idStr.substring(3)}';
  } else if (RegExp(r'^[A-Z]{3,4}-?\d+$', caseSensitive: false).hasMatch(idStr)) {
    return idStr;
  }
  return 'MLB-$idStr';
}
