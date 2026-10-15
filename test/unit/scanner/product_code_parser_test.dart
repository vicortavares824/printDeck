import 'package:flutter_test/flutter_test.dart';
import 'package:mobileraker/ui/screens/scanner/product_code_parser.dart';

void main() {
  group('ProductCodeParser', () {
    test('parses Mercado Livre JSON QR code with id and t:lm', () {
      const qrCode = '{"id":"48214515581","t":"lm"}';
      final result = parseProductCode(qrCode);

      expect(result.productId, '48214515581');
      expect(result.formattedMlbId, 'MLB-48214515581');
      expect(result.type, 'lm');
      expect(result.isMercadoLivre, isTrue);
      expect(result.mlbProductUrl, 'https://produto.mercadolivre.com.br/MLB-48214515581');
      expect(result.searchTerm, '48214515581');
    });

    test('parses Mercado Livre JSON with numeric id', () {
      const qrCode = '{"id":48214515581,"t":"lm"}';
      final result = parseProductCode(qrCode);

      expect(result.productId, '48214515581');
      expect(result.formattedMlbId, 'MLB-48214515581');
      expect(result.isMercadoLivre, isTrue);
      expect(result.mlbProductUrl, 'https://produto.mercadolivre.com.br/MLB-48214515581');
    });

    test('parses JSON with MLB prefix in id', () {
      const qrCode = '{"id":"MLB48214515581"}';
      final result = parseProductCode(qrCode);

      expect(result.productId, 'MLB48214515581');
      expect(result.formattedMlbId, 'MLB-48214515581');
      expect(result.isMercadoLivre, isTrue);
      expect(result.mlbProductUrl, 'https://produto.mercadolivre.com.br/MLB-48214515581');
    });

    test('parses direct MLB code string', () {
      const code = 'MLB48214515581';
      final result = parseProductCode(code);

      expect(result.productId, '48214515581');
      expect(result.formattedMlbId, 'MLB-48214515581');
      expect(result.isMercadoLivre, isTrue);
      expect(result.mlbProductUrl, 'https://produto.mercadolivre.com.br/MLB-48214515581');
    });

    test('parses loose json-like string', () {
      const code = "{id:'48214515581', t:'lm'}";
      final result = parseProductCode(code);

      expect(result.productId, '48214515581');
      expect(result.formattedMlbId, 'MLB-48214515581');
      expect(result.isMercadoLivre, isTrue);
      expect(result.mlbProductUrl, 'https://produto.mercadolivre.com.br/MLB-48214515581');
    });

    test('parses Shopee JSON QR code with shopid and itemid', () {
      const qrCode = '{"shopid":123456789,"itemid":987654321}';
      final result = parseProductCode(qrCode);

      expect(result.isShopee, isTrue);
      expect(result.shopId, '123456789');
      expect(result.productId, '987654321');
      expect(result.shopeeProductUrl, 'https://shopee.com.br/product/123456789/987654321');
    });

    test('parses Shopee JSON QR code with id and t:sp', () {
      const qrCode = '{"id":"987654321","t":"sp"}';
      final result = parseProductCode(qrCode);

      expect(result.isShopee, isTrue);
      expect(result.productId, '987654321');
      expect(result.shopeeProductUrl, 'https://shopee.com.br/search?keyword=987654321');
    });

    test('parses Shopee direct URL', () {
      const url = 'https://shopee.com.br/product/123456789/987654321';
      final result = parseProductCode(url);

      expect(result.isShopee, isTrue);
      expect(result.shopId, '123456789');
      expect(result.productId, '987654321');
      expect(result.shopeeProductUrl, url);
    });

    test('parses TikTok Shop QR code with product_id and t:tt', () {
      const qrCode = '{"product_id":"1729384756123456789","t":"tt"}';
      final result = parseProductCode(qrCode);

      expect(result.isTikTok, isTrue);
      expect(result.productId, '1729384756123456789');
      expect(result.tiktokProductUrl, 'https://shop.tiktok.com/view/product/1729384756123456789');
    });

    test('parses TikTok Shop QR code with id and platform:tiktok', () {
      const qrCode = '{"id":"1729384756123456789","platform":"tiktok"}';
      final result = parseProductCode(qrCode);

      expect(result.isTikTok, isTrue);
      expect(result.productId, '1729384756123456789');
      expect(result.tiktokProductUrl, 'https://shop.tiktok.com/view/product/1729384756123456789');
    });

    test('parses TikTok direct URL', () {
      const url = 'https://shop.tiktok.com/view/product/1729384756123456789';
      final result = parseProductCode(url);

      expect(result.isTikTok, isTrue);
      expect(result.productId, '1729384756123456789');
      expect(result.tiktokProductUrl, url);
    });

    test('handles standard EAN barcode without product id', () {
      const ean = '7891234567890';
      final result = parseProductCode(ean);

      expect(result.productId, isNull);
      expect(result.formattedMlbId, isNull);
      expect(result.isMercadoLivre, isFalse);
      expect(result.isShopee, isFalse);
      expect(result.isTikTok, isFalse);
      expect(result.mlbSearchUrl, 'https://lista.mercadolivre.com.br/7891234567890');
      expect(result.searchTerm, '7891234567890');
    });
  });
}
