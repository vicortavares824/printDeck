import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class CloudSyncButton extends StatefulWidget {
  const CloudSyncButton({
    super.key,
    this.backendUrl = 'http://10.0.2.2:8000', // 10.0.2.2 para emulador Android ou IP do PC para celular
  });

  final String backendUrl;

  @override
  State<CloudSyncButton> createState() => _CloudSyncButtonState();
}

class _CloudSyncButtonState extends State<CloudSyncButton> {
  bool _isLoading = false;

  Future<void> _syncToCloud() async {
    setState(() => _isLoading = true);

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      // Chama o endpoint de sincronização no backend local
      final response = await dio.post('${widget.backendUrl}/api/cloud/sync');

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Sincronizado com a nuvem com sucesso!')),
              ],
            ),
          ),
        );
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Erro ao sincronizar: $e')),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Sincronizar com a Nuvem',
      icon: const Icon(Icons.cloud_upload_outlined),
      onPressed: _syncToCloud,
    );
  }
}
