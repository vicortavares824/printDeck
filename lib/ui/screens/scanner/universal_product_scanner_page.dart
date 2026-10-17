import 'package:common/ui/components/drawer/nav_drawer_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../files/files_controller.dart';
import 'product_code_parser.dart';

enum AutoSearchTarget {
  ask,
  mercadoLivre,
  shopee,
  tiktok,
  google,
}

class UniversalProductScannerPage extends ConsumerStatefulWidget {
  const UniversalProductScannerPage({super.key});

  @override
  ConsumerState<UniversalProductScannerPage> createState() =>
      _UniversalProductScannerPageState();
}

class _UniversalProductScannerPageState
    extends ConsumerState<UniversalProductScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  String? _lastCode;
  AutoSearchTarget _autoTarget = AutoSearchTarget.mercadoLivre;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!.trim();
    if (raw.isEmpty || raw == _lastCode) return;

    setState(() {
      _isProcessing = true;
      _lastCode = raw;
    });

    _processCode(raw);
  }

  Future<void> _processCode(String code) async {
    final parsed = parseProductCode(code);

    // 1. Se a plataforma for explicitamente identificada pelo QR Code:
    if (parsed.isMercadoLivre) {
      if (_autoTarget == AutoSearchTarget.ask) {
        _showProductResultModal(parsed);
      } else {
        await _openUrl(parsed.mlbProductUrl);
        _resetScanner();
      }
      return;
    }

    if (parsed.isShopee) {
      if (_autoTarget == AutoSearchTarget.ask) {
        _showProductResultModal(parsed);
      } else {
        await _openUrl(parsed.shopeeProductUrl);
        _resetScanner();
      }
      return;
    }

    if (parsed.isTikTok) {
      if (_autoTarget == AutoSearchTarget.ask) {
        _showProductResultModal(parsed);
      } else {
        await _openUrl(parsed.tiktokProductUrl);
        _resetScanner();
      }
      return;
    }

    // 2. Se for uma URL direta genérica
    if (parsed.directUrl != null) {
      await _openUrl(parsed.directUrl!);
      _resetScanner();
      return;
    }

    // 3. Fallback baseado no alvo padrão configurado pelo usuário
    switch (_autoTarget) {
      case AutoSearchTarget.mercadoLivre:
        if (parsed.productId != null) {
          await _openUrl(parsed.mlbProductUrl);
        } else {
          await _openUrl(parsed.mlbSearchUrl);
        }
        _resetScanner();
        break;

      case AutoSearchTarget.shopee:
        await _openUrl(parsed.shopeeProductUrl);
        _resetScanner();
        break;

      case AutoSearchTarget.tiktok:
        await _openUrl(parsed.tiktokProductUrl);
        _resetScanner();
        break;

      case AutoSearchTarget.google:
        await _openUrl(parsed.googleSearchUrl);
        _resetScanner();
        break;

      case AutoSearchTarget.ask:
        _showProductResultModal(parsed);
        break;
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Não foi possível abrir o link: $url'),
          ),
        );
      }
    }
  }

  void _resetScanner() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastCode = null;
        });
      }
    });
  }

  void _showProductResultModal(ParsedProductCode parsed) {
    final hasId = parsed.productId != null;

    String platformBadgeText;
    Color platformBadgeColor;
    switch (parsed.platform) {
      case PlatformType.mercadoLivre:
        platformBadgeText = 'Mercado Livre detectado';
        platformBadgeColor = const Color(0xFFFFE600);
        break;
      case PlatformType.shopee:
        platformBadgeText = 'Shopee detectada';
        platformBadgeColor = Colors.deepOrangeAccent;
        break;
      case PlatformType.tiktok:
        platformBadgeText = 'TikTok Shop detectado';
        platformBadgeColor = const Color(0xFFFE2C55);
        break;
      case PlatformType.unknown:
        platformBadgeText = '';
        platformBadgeColor = Colors.transparent;
        break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasId ? 'Produto Identificado' : 'Código Identificado',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (platformBadgeText.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: platformBadgeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: platformBadgeColor),
                      ),
                      child: Text(
                        platformBadgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: platformBadgeColor,
                        ),
                      ),
                    ),
                  ],
                  if (parsed.productTitle != null) ...[
                    Text(
                      parsed.productTitle!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (parsed.itemId != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.tag, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            'Item ID: ${parsed.itemId}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (parsed.catalogId != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.inventory, color: Colors.cyanAccent, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            'Catálogo / UP ID: ${parsed.catalogId}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (!hasId && parsed.productTitle == null) ...[
                    SelectableText(
                      parsed.raw,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ] else ...[
                    if (parsed.shopId != null) ...[
                      Text(
                        'Shop ID: ${parsed.shopId}',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      'Código/URL: ${parsed.raw}',
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Botão Buscar no PrintDeck (Arquivos G-Code)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.primary,
                foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.search),
              label: Text(
                'Buscar G-Code no PrintDeck (${parsed.itemId ?? parsed.catalogId ?? parsed.searchTerm})',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                final query = parsed.itemId ?? parsed.catalogId ?? parsed.searchTerm;
                ref.read(isSearchingProvider.notifier).setSearching(true);
                ref.read(searchTextEditingControllerProvider).text = query;
                context.go('/files');
              },
            ),
            const SizedBox(height: 8),
            // Botão Mercado Livre
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFE600),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.shopping_bag, color: Colors.black),
              label: Text(
                hasId
                    ? 'Abrir no Mercado Livre (${parsed.itemId ?? parsed.catalogId ?? parsed.formattedMlbId ?? parsed.productId})'
                    : 'Pesquisar no Mercado Livre',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl(parsed.mlbProductUrl);
              },
            ),
            const SizedBox(height: 8),
            // Botão Shopee
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.shopping_cart, color: Colors.white),
              label: Text(
                parsed.shopId != null && hasId
                    ? 'Abrir Produto na Shopee'
                    : (hasId ? 'Abrir/Buscar ID na Shopee' : 'Pesquisar na Shopee'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl(parsed.shopeeProductUrl);
              },
            ),
            const SizedBox(height: 8),
            // Botão TikTok Shop
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFE2C55),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.music_note, color: Colors.white),
              label: Text(
                hasId ? 'Abrir no TikTok Shop (${parsed.productId})' : 'Pesquisar no TikTok',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl(parsed.tiktokProductUrl);
              },
            ),
            const SizedBox(height: 8),
            // Botão Google
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: Text(hasId ? 'Pesquisar ID no Google' : 'Pesquisar no Google'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl(parsed.googleSearchUrl);
              },
            ),
          ],
        ),
      ),
    ).whenComplete(_resetScanner);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const NavigationDrawerWidget(),
      appBar: AppBar(
        title: const Text('Verificar Produto / QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Lanterna',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            tooltip: 'Trocar Câmera',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Erro ao abrir a câmera: ${error.errorCode.name}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Verifique se a permissão de câmera foi concedida nas configurações do aparelho.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                        onPressed: () => _controller.start(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Moldura visual da mira
          Container(
            width: 270,
            height: 270,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.cyanAccent, width: 2.5),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          // Barra de seleção de Auto-Pesquisa no topo
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Auto-Abrir:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AutoSearchTarget>(
                        value: _autoTarget,
                        dropdownColor: Colors.grey[900],
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: AutoSearchTarget.mercadoLivre,
                            child: Text('🟡 Mercado Livre (Abrir ID / Buscar)'),
                          ),
                          DropdownMenuItem(
                            value: AutoSearchTarget.shopee,
                            child: Text('🟠 Shopee (Abrir ID / Buscar)'),
                          ),
                          DropdownMenuItem(
                            value: AutoSearchTarget.tiktok,
                            child: Text('🔴 TikTok Shop (Abrir ID / Buscar)'),
                          ),
                          DropdownMenuItem(
                            value: AutoSearchTarget.google,
                            child: Text('🔵 Google'),
                          ),
                          DropdownMenuItem(
                            value: AutoSearchTarget.ask,
                            child: Text('⚪ Perguntar sempre'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _autoTarget = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Mensagem informativa na parte inferior
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isProcessing
                  ? 'Processando e abrindo produto...'
                  : 'Aponte para o QR Code ou código. Abre direto pelo ID no Mercado Livre, Shopee ou TikTok!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
