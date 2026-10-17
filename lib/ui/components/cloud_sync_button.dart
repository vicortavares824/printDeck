import 'package:common/service/selected_machine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CloudSyncButton extends HookConsumerWidget {
  const CloudSyncButton({
    super.key,
    this.cloudApiUrl = 'https://printdeck-cloud.onrender.com',
    this.apiKey = 'printdeck-V2Niche',
  });

  final String cloudApiUrl;
  final String apiKey;

  Future<void> _syncToCloud(BuildContext context, WidgetRef ref) async {
    if (cloudApiUrl.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
          content: Text('Configure a URL da Cloud API (cloudApiUrl)'),
        ),
      );
      return;
    }

    final machine = ref.read(selectedMachineProvider).valueOrNull;
    final printerId = machine?.name ?? 'sem-impressora';

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final base = cloudApiUrl.replaceAll(RegExp(r'/+$'), '');

      final response = await dio.post(
        '$base/api/telemetry',
        data: {
          'printer_id': printerId,
          'state': 'online',
          'progress': 0.0,
          'current_file': null,
          'nozzle_temp': 0.0,
          'bed_temp': 0.0,
          'filament': null,
        },
        options: Options(headers: {'x-api-key': apiKey}),
      );

      if (!context.mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Erro ao sincronizar com a nuvem: $e')),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);

    if (isLoading.value) {
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
      onPressed: () async {
        if (isLoading.value) return;
        isLoading.value = true;
        await _syncToCloud(context, ref);
        if (context.mounted) isLoading.value = false;
      },
    );
  }
}
