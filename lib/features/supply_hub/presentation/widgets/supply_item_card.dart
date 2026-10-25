import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../application/inventory_notifier.dart';
import '../../domain/models/supply_item.dart';

class SupplyItemCard extends ConsumerWidget {
  const SupplyItemCard({
    required this.item,
    super.key,
  });

  final SupplyItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(inventoryNotifierProvider.notifier);

    final isBought = item.isBought;
    // Somente o dono do item (ou um admin) pode editar/excluir. Itens de outras
    // pessoas aparecem para todos, mas em modo somente leitura.
    final canEdit = notifier.canModify(item);

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isBought
              ? theme.colorScheme.outlineVariant.withOpacity(0.4)
              : theme.colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: isBought
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: isBought
                              ? theme.colorScheme.onSurface.withOpacity(0.55)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
                          ),
                        ),
                      ],
                      if (!canEdit) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Somente leitura (item de outra pessoa)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (canEdit)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: theme.colorScheme.error.withOpacity(0.7),
                    ),
                    tooltip: 'Remover Item',
                    onPressed: () async {
                      try {
                        await notifier.removeItemWithCloud(item.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Item "${item.title}" removido.'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Nao foi possivel remover: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        splashRadius: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Diminuir Quantidade',
                        onPressed: (canEdit && item.quantity > 1)
                            ? () => notifier.decrementQuantity(item.id)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${item.quantity}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        splashRadius: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Aumentar Quantidade',
                        onPressed: canEdit
                            ? () => notifier.incrementQuantity(item.id)
                            : null,
                      ),
                    ],
                  ),
                ),
                if (!isBought)
                  FilledButton.tonalIcon(
                    onPressed: canEdit
                        ? () => notifier.toggleBoughtStatus(item.id)
                        : null,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Comprado'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: canEdit
                        ? () => notifier.toggleBoughtStatus(item.id)
                        : null,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('De novo'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
