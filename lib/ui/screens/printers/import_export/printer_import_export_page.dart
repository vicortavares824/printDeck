import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/machine_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../service/printer_import_export_service.dart';

class PrinterImportExportPage extends ConsumerStatefulWidget {
  const PrinterImportExportPage({super.key});

  @override
  ConsumerState<PrinterImportExportPage> createState() =>
      _PrinterImportExportPageState();
}

class _PrinterImportExportPageState
    extends ConsumerState<PrinterImportExportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _importJsonController = TextEditingController();
  final PrinterImportExportService _service =
      const PrinterImportExportService();

  List<ImportablePrinter> _parsedPrinters = [];
  String? _parseError;
  bool _isImporting = false;

  // Seleções para exportação (uuid -> bool)
  final Set<String> _selectedUuidsToExport = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _importJsonController.dispose();
    super.dispose();
  }

  void _onJsonChanged(String text, List<Machine> existing) {
    if (text.trim().isEmpty) {
      setState(() {
        _parsedPrinters = [];
        _parseError = null;
      });
      return;
    }

    try {
      final parsed = _service.parsePrintersFromJson(
        text,
        existingMachines: existing,
      );
      setState(() {
        _parsedPrinters = parsed;
        _parseError = parsed.isEmpty
            ? 'Nenhuma impressora válida encontrada no JSON informado.'
            : null;
      });
    } catch (e) {
      setState(() {
        _parsedPrinters = [];
        _parseError = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _pasteFromClipboard(List<Machine> existing) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _importJsonController.text = data.text!;
      _onJsonChanged(data.text!, existing);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A área de transferência está vazia.'),
          ),
        );
      }
    }
  }

  void _loadSampleJson(List<Machine> existing) {
    const sample = '''[
  {
    "name": "Ender 3 V2",
    "ip": "192.168.1.50"
  },
  {
    "name": "Voron 2.4",
    "ip": "192.168.1.100:7125",
    "apiKey": "sua_chave_opcional"
  }
]''';
    _importJsonController.text = sample;
    _onJsonChanged(sample, existing);
  }

  Future<void> _performImport() async {
    final toImport = _parsedPrinters.where((p) => p.isSelected).toList();
    if (toImport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Nenhuma impressora selecionada para importar.'),
        ),
      );
      return;
    }

    setState(() => _isImporting = true);

    int successCount = 0;
    final machineService = ref.read(machineServiceProvider);

    try {
      for (final p in toImport) {
        final machine = p.toMachine();
        await machineService.addMachine(machine);
        successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              '$successCount impressora(s) importada(s) com sucesso!',
            ),
          ),
        );
        setState(() {
          _importJsonController.clear();
          _parsedPrinters = [];
          _parseError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Erro ao importar impressoras: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allMachinesAsync = ref.watch(allMachinesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar / Exportar Impressoras'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.download_for_offline_outlined), text: 'Importar JSON'),
            Tab(icon: Icon(Icons.upload_file_outlined), text: 'Exportar JSON'),
          ],
        ),
      ),
      body: allMachinesAsync.when(
        loading: () => const Center(
          child: SpinKitWave(color: Colors.cyanAccent, size: 30),
        ),
        error: (err, stack) => Center(child: Text('Erro: $err')),
        data: (machines) {
          // Inicializa lista de exportação com todas selecionadas se estiver vazia
          if (_selectedUuidsToExport.isEmpty && machines.isNotEmpty) {
            _selectedUuidsToExport.addAll(machines.map((m) => m.uuid));
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildImportTab(theme, machines),
              _buildExportTab(theme, machines),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // TAB DE IMPORTAÇÃO
  // ==========================================
  Widget _buildImportTab(ThemeData theme, List<Machine> existing) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.cyanAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Importar impressoras por IP via JSON',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cole abaixo uma lista de impressoras em formato JSON. '
                    'Você pode informar apenas o IP ou portas customizadas.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.content_paste, size: 16),
                        label: const Text('Colar da Área de Transferência'),
                        onPressed: () => _pasteFromClipboard(existing),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.code, size: 16),
                        label: const Text('Exemplo de JSON'),
                        onPressed: () => _loadSampleJson(existing),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _importJsonController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Conteúdo JSON',
              hintText: '[\n  {\n    "name": "Ender 3",\n    "ip": "192.168.1.50"\n  }\n]',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _importJsonController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _importJsonController.clear();
                        _onJsonChanged('', existing);
                      },
                    )
                  : null,
            ),
            onChanged: (val) => _onJsonChanged(val, existing),
          ),
          if (_parseError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _parseError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_parsedPrinters.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_parsedPrinters.length} impressora(s) identificada(s):',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final allSelected = _parsedPrinters.every((p) => p.isSelected);
                    setState(() {
                      for (final p in _parsedPrinters) {
                        p.isSelected = !allSelected;
                      }
                    });
                  },
                  child: Text(
                    _parsedPrinters.every((p) => p.isSelected)
                        ? 'Desmarcar Todas'
                        : 'Selecionar Todas',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _parsedPrinters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final p = _parsedPrinters[idx];
                final isDuplicate = p.existingMatchName != null;

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isDuplicate
                          ? Colors.orangeAccent.withOpacity(0.5)
                          : Colors.white12,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: p.isSelected,
                    onChanged: (val) {
                      setState(() => p.isSelected = val ?? false);
                    },
                    secondary: Icon(
                      Icons.print,
                      color: isDuplicate ? Colors.orangeAccent : Colors.cyanAccent,
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IP / Host: ${p.httpUri.host}${p.httpUri.hasPort && p.httpUri.port != 80 && p.httpUri.port != 443 ? ':${p.httpUri.port}' : ''}'),
                        if (p.apiKey != null && p.apiKey!.isNotEmpty)
                          Text('API Key: ••••••••', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        if (isDuplicate)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orangeAccent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Já cadastrada no app: "${p.existingMatchName}"',
                                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              icon: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_task),
              label: Text(
                _isImporting
                    ? 'Importando impressoras...'
                    : 'Importar ${_parsedPrinters.where((p) => p.isSelected).length} Impressora(s)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: _isImporting ? null : _performImport,
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // TAB DE EXPORTAÇÃO
  // ==========================================
  Widget _buildExportTab(ThemeData theme, List<Machine> machines) {
    if (machines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.print_disabled, size: 56, color: theme.colorScheme.onSurface.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                'Nenhuma impressora cadastrada para exportar',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final selectedMachines = machines
        .where((m) => _selectedUuidsToExport.contains(m.uuid))
        .toList();
    final exportedJson = _service.exportPrintersToJson(selectedMachines);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.file_upload_outlined, color: Colors.cyanAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Exportar impressoras em JSON',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Selecione as impressoras que deseja incluir no arquivo JSON gerado.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Selecione as impressoras:',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...machines.map((m) {
            final isChecked = _selectedUuidsToExport.contains(m.uuid);
            final host = m.httpUri.host;
            final port = m.httpUri.hasPort && m.httpUri.port != 80 && m.httpUri.port != 443
                ? ':${m.httpUri.port}'
                : '';

            return CheckboxListTile(
              dense: true,
              value: isChecked,
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('IP: $host$port'),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedUuidsToExport.add(m.uuid);
                  } else {
                    _selectedUuidsToExport.remove(m.uuid);
                  }
                });
              },
            );
          }),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'JSON Gerado (${selectedMachines.length} impressora(s)):',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copiar JSON',
                onPressed: selectedMachines.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: exportedJson));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.green,
                            content: Text('JSON copiado para a área de transferência!'),
                          ),
                        );
                      },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                selectedMachines.isEmpty
                    ? '// Nenhuma impressora selecionada'
                    : exportedJson,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.lightGreenAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            icon: const Icon(Icons.copy),
            label: Text(
              'Copiar JSON (${selectedMachines.length} impressoras)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: selectedMachines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: exportedJson));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.green,
                        content: Text('JSON copiado com sucesso! Você pode colá-lo em outro celular ou backup.'),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}
