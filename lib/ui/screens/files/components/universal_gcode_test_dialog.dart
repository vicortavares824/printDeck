import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/machine_service.dart';
import 'package:common/service/moonraker/file_service.dart';
import 'package:common/service/moonraker/printer_service.dart';
import 'package:common/service/selected_machine_service.dart';
import 'package:common/ui/components/error_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../service/gcode/universal_gcode_service.dart';

class UniversalGcodeTestDialog extends ConsumerStatefulWidget {
  const UniversalGcodeTestDialog({super.key});

  @override
  ConsumerState<UniversalGcodeTestDialog> createState() =>
      _UniversalGcodeTestDialogState();
}

class _UniversalGcodeTestDialogState
    extends ConsumerState<UniversalGcodeTestDialog> {
  bool _isProcessing = false;
  UniversalGcodeModel? _processedModel;
  String? _processError;

  Machine? _targetMachine;
  bool _isUploading = false;
  bool _startPrintImmediately = false;
  String? _uploadSuccessMessage;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    // Iniciar processamento automaticamente ao abrir o diálogo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processTestGcode();
    });
  }

  Future<void> _processTestGcode() async {
    setState(() {
      _isProcessing = true;
      _processError = null;
      _uploadSuccessMessage = null;
      _uploadError = null;
    });

    try {
      final gcodeService = ref.read(universalGcodeServiceProvider);
      final model = await gcodeService.processAndSaveGcode(
        modelName: 'teste_cubo_universal_printdeck',
      );

      final selectedMachine =
          ref.read(selectedMachineProvider).valueOrNull;
      final allMachines = await ref.read(allMachinesProvider.future);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processedModel = model;
          _targetMachine = selectedMachine ?? allMachines.firstOrNull;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processError = e.toString();
        });
      }
    }
  }

  Future<void> _sendToTargetPrinter() async {
    if (_processedModel == null || _targetMachine == null) return;

    setState(() {
      _isUploading = true;
      _uploadError = null;
      _uploadSuccessMessage = null;
    });

    try {
      final gcodeService = ref.read(universalGcodeServiceProvider);
      final fileService = ref.read(fileServiceProvider(_targetMachine!.uuid));
      final printerService =
          ref.read(printerServiceProvider(_targetMachine!.uuid));

      await gcodeService.sendToPrinter(
        model: _processedModel!,
        targetMachine: _targetMachine!,
        fileService: fileService,
        printerService: printerService,
        startPrintImmediately: _startPrintImmediately,
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadSuccessMessage = _startPrintImmediately
              ? 'Modelo adaptado, enviado e impressão iniciada na impressora "${_targetMachine!.name}"!'
              : 'Modelo adaptado e salvo com sucesso na impressora "${_targetMachine!.name}" (gcodes/${_processedModel!.name}.gcode)!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = 'Erro ao enviar para ${_targetMachine!.name}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allMachinesAsync = ref.watch(allMachinesProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.science, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'G-Code Universal de Teste',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isProcessing) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Carregando, processando e salvando em estruturas locais...',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else if (_processError != null) ...[
                ErrorCard(
                  title: const Text('Falha no Processamento'),
                  body: Text(_processError!),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                  onPressed: _processTestGcode,
                ),
              ] else if (_processedModel != null) ...[
                // Card de Sucesso do Processamento Local
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Processado e Salvo Localmente',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Modelo: ${_processedModel!.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Dimensões: ${_processedModel!.metadata.sizeX} x ${_processedModel!.metadata.sizeY} x ${_processedModel!.metadata.sizeZ} mm (${_processedModel!.metadata.layerCount} camadas)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Material: ${_processedModel!.metadata.filamentType} (Bico: ${_processedModel!.metadata.targetExtruderTemp.toInt()}°C, Base: ${_processedModel!.metadata.targetBedTemp.toInt()}°C)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Lista de Partes Locais Estruturadas
                Text(
                  'Partes Estruturadas (Compatibilidade Universal):',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                _PartTile(
                  icon: Icons.title,
                  title: _processedModel!.header.title,
                  detail: '${_processedModel!.header.lineCount} linhas de setup e aquecimento',
                ),
                _PartTile(
                  icon: Icons.view_in_ar,
                  title: _processedModel!.body.title,
                  detail: '${_processedModel!.body.lineCount} linhas de geometria pura (toolpaths)',
                ),
                _PartTile(
                  icon: Icons.power_settings_new,
                  title: _processedModel!.footer.title,
                  detail: '${_processedModel!.footer.lineCount} linhas de desligamento seguro',
                ),
                _PartTile(
                  icon: Icons.folder_special,
                  title: 'Armazenamento Local',
                  detail: _processedModel!.localDirectoryPath,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Seção de Envio Universal para Qualquer Impressora
                Row(
                  children: [
                    Icon(Icons.print, color: theme.colorScheme.secondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Executar em Qualquer Impressora:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                allMachinesAsync.when(
                  data: (machines) {
                    if (machines.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Nenhuma impressora cadastrada no aplicativo.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    // Se targetMachine ainda não foi escolhida ou não está na lista
                    if (_targetMachine == null || !machines.any((m) => m.uuid == _targetMachine!.uuid)) {
                      _targetMachine = machines.first;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Machine>(
                              value: machines.firstWhere(
                                (m) => m.uuid == _targetMachine!.uuid,
                                orElse: () => machines.first,
                              ),
                              isExpanded: true,
                              items: machines.map((machine) {
                                return DropdownMenuItem<Machine>(
                                  value: machine,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.precision_manufacturing, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${machine.name} (${machine.httpUri.host.isNotEmpty ? machine.httpUri.host : machine.wsUri.host})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _targetMachine = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Iniciar impressão automaticamente após envio',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: _startPrintImmediately,
                          onChanged: (v) => setState(() => _startPrintImmediately = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 8),
                        if (_uploadSuccessMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Text(
                              _uploadSuccessMessage!,
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_uploadError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Text(
                              _uploadError!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(
                            _isUploading
                                ? 'Enviando e Adaptando...'
                                : 'Enviar para ${_targetMachine?.name ?? 'Impressora'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isUploading ? null : _sendToTargetPrinter,
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Text('Erro ao carregar impressoras: $e'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _PartTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _PartTile({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
