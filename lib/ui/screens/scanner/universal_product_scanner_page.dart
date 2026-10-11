import 'package:common/ui/components/drawer/nav_drawer_view.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum AutoSearchTarget {
  ask,
  mercadoLivre,
  shopee,
  google,
}

class UniversalProductScannerPage extends StatefulWidget {
  const UniversalProductScannerPage({super.key});

  @override
  State<UniversalProductScannerPage> createState() =>
      _UniversalProductScannerPageState();
}

class _UniversalProductScannerPageState
    extends State<UniversalProductScannerPage> {
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
    // 1. Se for URL direta (ex: link do Mercado Livre, Shopee ou qualquer site)
    if (code.startsWith('http://') || code.startsWith('https://')) {
      await _openUrl(code);
      _resetScanner();
      return;
    }

    // 2. Se for código de barras (EAN/UPC) e a auto-pesquisa estiver ligada:
    switch (_autoTarget) {
      case AutoSearchTarget.mercadoLivre:
        final url = 'https://lista.mercadolivre.com.br/${Uri.encodeComponent(code)}';
        await _openUrl(url);
        _resetScanner();
        break;

      case AutoSearchTarget.shopee:
        final url = 'https://shopee.com.br/search?keyword=${Uri.encodeComponent(code)}';
        await _openUrl(url);
        _resetScanner();
        break;

      case AutoSearchTarget.google:
        final url = 'https://www.google.com/search?q=${Uri.encodeComponent(code)}';
        await _openUrl(url);
        _resetScanner();
        break;

      case AutoSearchTarget.ask:
        _showProductResultModal(code);
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

  void _showProductResultModal(String code) {
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
                    'Código Identificado',
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
              child: SelectableText(
                code,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.shopping_bag, color: Colors.yellow),
              label: const Text('Pesquisar no Mercado Livre'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl('https://lista.mercadolivre.com.br/${Uri.encodeComponent(code)}');
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              icon: const Icon(Icons.shopping_cart, color: Colors.white),
              label: const Text('Pesquisar na Shopee'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl('https://shopee.com.br/search?keyword=${Uri.encodeComponent(code)}');
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Pesquisar no Google'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl('https://www.google.com/search?q=${Uri.encodeComponent(code)}');
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
        title: const Text('Verificador Automático'),
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
                            child: Text('🟡 Mercado Livre'),
                          ),
                          DropdownMenuItem(
                            value: AutoSearchTarget.shopee,
                            child: Text('🟠 Shopee'),
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
                  : 'Aponte para o código. Ele pesquisa automaticamente no app/site!',
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
