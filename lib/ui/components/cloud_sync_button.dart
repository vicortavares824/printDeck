import 'package:common/data/dto/machine/print_state_enum.dart';
import 'package:common/data/dto/machine/printer.dart';
import 'package:common/data/dto/server/klipper.dart';
import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/machine_service.dart';
import 'package:common/service/moonraker/klippy_service.dart';
import 'package:common/service/moonraker/printer_service.dart';
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

  /// Mapeia o estado de impressão do Klipper para a string esperada pela Cloud API.
  String _mapPrintState(PrintState state) {
    switch (state) {
      case PrintState.printing:
        return 'printing';
      case PrintState.paused:
        return 'paused';
      case PrintState.standby:
        return 'idle';
      case PrintState.complete:
        return 'complete';
      case PrintState.cancelled:
      case PrintState.error:
        return 'error';
    }
  }

  /// Monta o payload de telemetria de uma máquina a partir do estado ao vivo.
  ///
  /// Se a máquina não estiver conectada (klippy != ready) ou o [printer] for
  /// nulo, envia um payload 'offline' com valores zerados.
  Map<String, dynamic> _buildPayload(Machine machine, Printer? printer) {
    if (printer == null) {
      return {
        'printer_id': machine.name,
        'state': 'offline',
        'progress': 0.0,
        'current_file': null,
        'nozzle_temp': 0.0,
        'bed_temp': 0.0,
        'filament': null,
      };
    }

    final filename = printer.print.filename;
    return {
      'printer_id': machine.name,
      'state': _mapPrintState(printer.print.state),
      'progress': printer.printProgress,
      'current_file': filename.isEmpty ? null : filename,
      'nozzle_temp': printer.extruder.temperature,
      'bed_temp': printer.heaterBed?.temperature ?? 0.0,
      'filament': null,
    };
  }

  /// Envia a telemetria de uma única máquina, preservando o tratamento de
  /// cold start do Render (1 retry em caso de timeout/erro de conexão).
  Future<void> _postTelemetry(Dio dio, String base, Map<String, dynamic> payload) async {
    final options = Options(headers: {'x-api-key': apiKey});
    Response response;
    try {
      response = await dio.post('$base/api/telemetry', data: payload, options: options);
    } on DioException catch (e) {
      // Cold start: tenta uma segunda vez, pois a primeira já "acordou" o servidor.
      final isColdStart = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError;
      if (!isColdStart) rethrow;
      response = await dio.post('$base/api/telemetry', data: payload, options: options);
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Status ${response.statusCode}');
    }
  }

  Future<void> _syncAllToCloud(BuildContext context, WidgetRef ref) async {
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

    List<Machine> machines;
    try {
      machines = await ref.read(allMachinesProvider.future);
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
              Expanded(child: Text('Erro ao carregar máquinas: $e')),
            ],
          ),
        ),
      );
      return;
    }

    if (machines.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
          content: Text('Nenhuma máquina cadastrada para sincronizar'),
        ),
      );
      return;
    }

    final dio = Dio(
      BaseOptions(
        // O Render (plano free) hiberna e pode levar de 30 a 60s para
        // acordar no primeiro acesso (cold start). Timeouts generosos
        // evitam o "receive timeout" nesse cenário.
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    final base = cloudApiUrl.replaceAll(RegExp(r'/+$'), '');

    // Envia todas as máquinas de forma resiliente: uma falha não aborta as demais.
    final results = await Future.wait(
      machines.map((machine) async {
        try {
          // Tenta ler o estado real da máquina. Se estiver offline/sem dados
          // (klippy != ready ou printer em erro/loading), envia 'offline'.
          Printer? printer;
          final klippyState = ref.read(klipperProvider(machine.uuid)).valueOrNull?.klippyState;
          if (klippyState == KlipperState.ready) {
            printer = ref.read(printerProvider(machine.uuid)).valueOrNull;
          }

          await _postTelemetry(dio, base, _buildPayload(machine, printer));
          return true;
        } catch (_) {
          return false;
        }
      }),
    );

    final total = results.length;
    final success = results.where((ok) => ok).length;
    final failed = total - success;

    if (!context.mounted) return;

    if (failed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('$success/$total máquinas sincronizadas')),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$success/$total máquinas sincronizadas ($failed com falha)'),
              ),
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
      tooltip: 'Sincronizar todas as impressoras com a Nuvem',
      icon: const Icon(Icons.cloud_sync_outlined),
      onPressed: () async {
        if (isLoading.value) return;
        isLoading.value = true;
        await _syncAllToCloud(context, ref);
        if (context.mounted) isLoading.value = false;
      },
    );
  }
}
