import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:common/ui/components/drawer/nav_drawer_view.dart';

import '../../../service/local_filament_stock_service.dart';

class LocalFilamentStockPage extends ConsumerWidget {
  const LocalFilamentStockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(localFilamentStockProvider);
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const NavigationDrawerWidget(),
      appBar: AppBar(
        title: const Text('Estoque de Filamentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar Carretel',
            onPressed: () => _openAddSpoolDialog(context, ref),
          ),
        ],
      ),
      body: stock.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum filamento no estoque',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cadastre seus carretéis para controlar o peso e consumo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _openAddSpoolDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Cadastrar Novo Carretel'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: stock.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final spool = stock[index];
                final progress = (spool.remainingWeightGrams / spool.initialWeightGrams)
                    .clamp(0.0, 1.0);
                final color = _parseColor(spool.colorHex);

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    spool.name.isNotEmpty
                                        ? spool.name
                                        : '${spool.vendor} ${spool.material}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${spool.material} • ${spool.vendor} • ${spool.diameterMm}mm',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Remover Carretel',
                              onPressed: () => _confirmDelete(context, ref, spool),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Restante: ${spool.remainingWeightGrams.toStringAsFixed(0)}g / ${spool.initialWeightGrams.toStringAsFixed(0)}g',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surface.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress < 0.2 ? Colors.orange : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Ajustar Peso'),
                              onPressed: () => _editWeightDialog(context, ref, spool),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: stock.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _openAddSpoolDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) {
        return Color(int.parse('0xFF$clean'));
      }
    } catch (_) {}
    return Colors.blueGrey;
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, LocalSpool spool) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Carretel'),
        content: Text('Deseja realmente remover o carretel "${spool.name}" do estoque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              ref.read(localFilamentStockProvider.notifier).removeSpool(spool.id);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _editWeightDialog(BuildContext context, WidgetRef ref, LocalSpool spool) {
    final controller =
        TextEditingController(text: spool.remainingWeightGrams.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajustar Peso Restante'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Peso restante (gramas)',
            suffixText: 'g',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= 0) {
                ref
                    .read(localFilamentStockProvider.notifier)
                    .updateRemainingWeight(spool.id, val);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _openAddSpoolDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _AddSpoolForm(),
    );
  }
}

class _AddSpoolForm extends ConsumerStatefulWidget {
  const _AddSpoolForm();

  @override
  ConsumerState<_AddSpoolForm> createState() => _AddSpoolFormState();
}

class _AddSpoolFormState extends ConsumerState<_AddSpoolForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _weightCtrl = TextEditingController(text: '1000');
  final _priceCtrl = TextEditingController();

  String _material = 'PLA';
  String _selectedColor = '#FF5733';

  final List<String> _materials = [
    'PLA',
    'PLA+',
    'PETG',
    'ABS',
    'ASA',
    'TPU',
    'Nylon',
    'PC',
  ];

  final List<String> _colorOptions = [
    '#FF0000', // Vermelho
    '#FF5733', // Laranja
    '#FFC300', // Amarelo
    '#2ECC71', // Verde
    '#3498DB', // Azul
    '#9B59B6', // Roxo
    '#FFFFFF', // Branco
    '#7F8C8D', // Cinza
    '#1A1A1A', // Preto
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cadastrar Novo Carretel',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome / Apelido (ex: PLA Preto Voolt)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Informe um nome' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _material,
                      decoration: const InputDecoration(
                        labelText: 'Material',
                        border: OutlineInputBorder(),
                      ),
                      items: _materials
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _material = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _vendorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fabricante',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Peso Inicial (g)',
                        border: OutlineInputBorder(),
                        suffixText: 'g',
                      ),
                      validator: (v) =>
                          v == null || double.tryParse(v) == null ? 'Inválido' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Preço Pago (R\$)',
                        border: OutlineInputBorder(),
                        prefixText: 'R\$ ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Cor do Filamento:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colorOptions.map((hex) {
                  final color = Color(int.parse('0xFF${hex.replaceAll('#', '')}'));
                  final isSelected = _selectedColor == hex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.cyanAccent : Colors.white24,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              size: 20,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saveSpool,
                child: const Text('Salvar Carretel no Estoque'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveSpool() {
    if (_formKey.currentState?.validate() != true) return;

    final weight = double.tryParse(_weightCtrl.text) ?? 1000.0;
    final price = double.tryParse(_priceCtrl.text) ?? 0.0;

    final newSpool = LocalSpool(
      id: '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}',
      name: _nameCtrl.text.trim(),
      material: _material,
      vendor: _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : 'Genérico',
      colorHex: _selectedColor,
      initialWeightGrams: weight,
      remainingWeightGrams: weight,
      diameterMm: 1.75,
      price: price,
    );

    ref.read(localFilamentStockProvider.notifier).addSpool(newSpool);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Text('Carretel "${newSpool.name}" adicionado com sucesso!'),
      ),
    );
  }
}
