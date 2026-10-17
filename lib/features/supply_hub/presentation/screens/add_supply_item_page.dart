import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../application/inventory_notifier.dart';

class AddSupplyItemPage extends ConsumerStatefulWidget {
  const AddSupplyItemPage({super.key});

  @override
  ConsumerState<AddSupplyItemPage> createState() => _AddSupplyItemPageState();
}

class _AddSupplyItemPageState extends ConsumerState<AddSupplyItemPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController();

  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _quantityController.text = '$_quantity';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _updateQuantity(int newQuantity) {
    if (newQuantity < 1) return;
    setState(() {
      _quantity = newQuantity;
      _quantityController.text = '$_quantity';
    });
  }

  void _onQuantityFieldChanged(String val) {
    final parsed = int.tryParse(val);
    if (parsed != null && parsed >= 1) {
      setState(() {
        _quantity = parsed;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    try {
      ref.read(inventoryNotifierProvider.notifier).addItem(
            title: title,
            description: description,
            quantity: _quantity,
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$title" adicionado com sucesso!'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar item: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Item de Suprimento'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Informação do cabeçalho
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Se o item já existir no catálogo, sua quantidade será incrementada automaticamente.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Campo Título
                TextFormField(
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Título do Item *',
                    hintText: 'Ex: Bico Nozzle Brass 0.4mm, Álcool Isopropílico',
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, informe o título do item.';
                    }
                    if (value.trim().length < 2) {
                      return 'O título deve ter pelo menos 2 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Campo Descrição
                TextFormField(
                  controller: _descriptionController,
                  textInputAction: TextInputAction.done,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Descrição / Observações',
                    hintText: 'Ex: Rosca M6 para hotend V6, comprar pacote com 5 unidades.',
                    prefixIcon: Icon(Icons.description_outlined),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                // Controle Numérico de Quantidade
                Text(
                  'Quantidade Inicial',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Botão Decrementar
                    IconButton.filledTonal(
                      onPressed: _quantity > 1
                          ? () => _updateQuantity(_quantity - 1)
                          : null,
                      icon: const Icon(Icons.remove),
                      tooltip: 'Diminuir',
                    ),
                    const SizedBox(width: 12),

                    // Campo de entrada direta de quantidade
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        onChanged: _onQuantityFieldChanged,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Inválido';
                          }
                          final parsed = int.tryParse(value);
                          if (parsed == null || parsed < 1) {
                            return 'Mín. 1';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Botão Incrementar
                    IconButton.filledTonal(
                      onPressed: () => _updateQuantity(_quantity + 1),
                      icon: const Icon(Icons.add),
                      tooltip: 'Aumentar',
                    ),
                    const Spacer(),

                    // Chips de atalho rápido (+5, +10)
                    Wrap(
                      spacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('+5'),
                          onPressed: () => _updateQuantity(_quantity + 5),
                        ),
                        ActionChip(
                          label: const Text('+10'),
                          onPressed: () => _updateQuantity(_quantity + 10),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Botão de Submissão
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(
                    'Salvar no Almoxarifado',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
