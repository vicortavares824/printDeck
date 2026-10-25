import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:common/ui/components/drawer/nav_drawer_view.dart';

import '../../application/inventory_notifier.dart';
import '../../domain/models/supply_item.dart';
import '../widgets/supply_item_card.dart';
import 'add_supply_item_page.dart';

class SupplyHubPage extends ConsumerStatefulWidget {
  const SupplyHubPage({super.key});

  @override
  ConsumerState<SupplyHubPage> createState() => _SupplyHubPageState();
}

class _SupplyHubPageState extends ConsumerState<SupplyHubPage> {
  bool _isSyncing = false;

  Future<void> _syncFromCloud() async {
    setState(() => _isSyncing = true);
    try {
      await ref.read(inventoryNotifierProvider.notifier).pullFromCloud();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Almoxarifado sincronizado com a nuvem!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao sincronizar com a nuvem: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _openAdminDialog() async {
    final notifier = ref.read(inventoryNotifierProvider.notifier);

    if (notifier.isAdmin) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sair do modo administrador'),
          content: const Text(
            'Voce voltara a editar apenas os itens que criou. Deseja sair?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sair'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        notifier.logoutAdmin();
        if (mounted) setState(() {});
      }
      return;
    }

    final controller = TextEditingController();
    var loading = false;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Acesso administrador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Digite o codigo de administrador para poder editar e excluir '
                'qualquer item do almoxarifado compartilhado.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Codigo de administrador',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) => Navigator.of(ctx).maybePop(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.isEmpty) {
                        setLocal(() => error = 'Informe o codigo.');
                        return;
                      }
                      setLocal(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        final granted = await notifier.loginAsAdmin(code);
                        if (!granted) {
                          setLocal(() {
                            loading = false;
                            error = 'Codigo invalido.';
                          });
                          return;
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setLocal(() {
                          loading = false;
                          error = 'Falha ao verificar: $e';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Entrar'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo administrador ativado.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromCloud();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems = ref.watch(pendingSupplyItemsProvider);
    final boughtItems = ref.watch(boughtSupplyItemsProvider);
    final theme = Theme.of(context);
    final isAdmin = ref.read(inventoryNotifierProvider.notifier).isAdmin;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const NavigationDrawerWidget(),
        appBar: AppBar(
          title: const Text('SupplyHub - Almoxarifado'),
          actions: [
            IconButton(
              icon: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                color: isAdmin ? Colors.amber : null,
              ),
              onPressed: _openAdminDialog,
              tooltip: isAdmin ? 'Administrador (tocar para sair)' : 'Entrar como administrador',
            ),
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync),
              onPressed: _isSyncing ? null : _syncFromCloud,
              tooltip: 'Sincronizar com a nuvem',
            ),
          ],
          bottom: TabBar(
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                icon: const Icon(Icons.shopping_cart_outlined),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('A Comprar / Salvos'),
                    if (pendingItems.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge.count(
                        count: pendingItems.length,
                        backgroundColor: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                icon: const Icon(Icons.check_circle_outline),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Comprados'),
                    if (boughtItems.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge.count(
                        count: boughtItems.length,
                        backgroundColor: theme.colorScheme.secondary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ItemsListTab(
              items: pendingItems,
              emptyIcon: Icons.shopping_basket_outlined,
              emptyTitle: 'Nenhum item pendente',
              emptySubtitle: 'Sua lista de compras do almoxarifado esta vazia.',
              showAddButton: true,
            ),
            _ItemsListTab(
              items: boughtItems,
              emptyIcon: Icons.task_alt_outlined,
              emptyTitle: 'Nenhum item comprado ainda',
              emptySubtitle: 'Marque os itens como "Comprado" na aba anterior para arquiva-los aqui.',
              showAddButton: false,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AddSupplyItemPage(),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Novo Item'),
        ),
      ),
    );
  }
}

class _ItemsListTab extends StatelessWidget {
  const _ItemsListTab({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.showAddButton,
  });

  final List<SupplyItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                emptyIcon,
                size: 64,
                color: theme.colorScheme.onSurface.withOpacity(0.35),
              ),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                emptySubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
              if (showAddButton) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AddSupplyItemPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Cadastrar Primeiro Item'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return SupplyItemCard(item: item);
      },
    );
  }
}
