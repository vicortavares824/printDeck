import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:common/ui/components/drawer/nav_drawer_view.dart';

import '../../application/inventory_notifier.dart';
import '../../domain/models/supply_item.dart';
import '../widgets/supply_item_card.dart';
import 'add_supply_item_page.dart';

class SupplyHubPage extends ConsumerWidget {
  const SupplyHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingItems = ref.watch(pendingSupplyItemsProvider);
    final boughtItems = ref.watch(boughtSupplyItemsProvider);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const NavigationDrawerWidget(),
        appBar: AppBar(
          title: const Text('SupplyHub • Almoxarifado'),
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
            // Aba 1: A Comprar / Salvos
            _ItemsListTab(
              items: pendingItems,
              emptyIcon: Icons.shopping_basket_outlined,
              emptyTitle: 'Nenhum item pendente',
              emptySubtitle: 'Sua lista de compras do almoxarifado está vazia.',
              showAddButton: true,
            ),

            // Aba 2: Comprados
            _ItemsListTab(
              items: boughtItems,
              emptyIcon: Icons.task_alt_outlined,
              emptyTitle: 'Nenhum item comprado ainda',
              emptySubtitle: 'Marque os itens como "Comprado" na aba anterior para arquivá-los aqui.',
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
