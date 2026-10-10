/*
 * Copyright (c) 2023-2024. Patrick Schmidt.
 * All rights reserved.
 *
 * Personal, non-commercial customization: PrintDeck overview.
 */
import 'package:common/data/dto/machine/print_state_enum.dart';
import 'package:common/data/model/hive/machine.dart';
import 'package:common/network/jrpc_client_provider.dart';
import 'package:common/network/json_rpc_client.dart';
import 'package:common/service/app_router.dart';
import 'package:common/service/machine_service.dart';
import 'package:common/service/moonraker/printer_service.dart';
import 'package:common/service/selected_machine_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobileraker/routing/app_router.dart';
import 'package:common/ui/components/drawer/nav_drawer_view.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('PrintDeck'),
          centerTitle: false,
        ),
        body: const PrintDeckOverviewBody(),
        drawer: const NavigationDrawerWidget(),
      );
}

class PrintDeckOverviewBody extends ConsumerWidget {
  const PrintDeckOverviewBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(allMachinesProvider).when(
          data: (machines) {
            if (machines.isEmpty) {
              return _EmptyState(onAddPrinter: () => _addPrinter(ref));
            }

            return RefreshIndicator(
              onRefresh: () async {
                final _ = await ref.refresh(allMachinesProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _OverviewHeading(machineCount: machines.length),
                  const SizedBox(height: 12),
                  ...machines.map(
                      (machine) => _PrintDeckMachineCard(machine: machine)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _addPrinter(ref),
                    icon: const Icon(Icons.add),
                    label: Text('pages.overview.printdeck.add_printer'.tr()),
                  ),
                ],
              ),
            );
          },
          error: (error, stackTrace) =>
              _LoadError(onRetry: () => ref.invalidate(allMachinesProvider)),
          loading: () => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('pages.overview.printdeck.loading'.tr()),
              ],
            ),
          ),
        );
  }

  void _addPrinter(WidgetRef ref) {
    ref.read(goRouterProvider).pushNamed(AppRoute.printerAdd.name);
  }
}

class _OverviewHeading extends StatelessWidget {
  const _OverviewHeading({required this.machineCount});

  final int machineCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'pages.overview.printdeck.tagline'.tr(),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'pages.overview.printdeck.machines_count'
                .tr(args: [machineCount.toString()]),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PrintDeckMachineCard extends ConsumerWidget {
  const _PrintDeckMachineCard({required this.machine});

  final Machine machine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final connection = ref.watch(jrpcClientStateProvider(machine.uuid));
    final printerAsync = ref.watch(printerProvider(machine.uuid));
    final printer = printerAsync.valueOrNull;
    final isOnline = connection.valueOrNull == ClientState.connected;
    final printState = printer?.print.state;
    final isPrinting = printState == PrintState.printing;
    final isPaused = printState == PrintState.paused;
    final statusColor = !isOnline
        ? colors.error
        : (printState == PrintState.error ? colors.error : colors.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.print_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(machine.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      _StatusBadge(
                        label: isOnline
                            ? 'pages.overview.printdeck.online'.tr()
                            : 'pages.overview.printdeck.offline'.tr(),
                        color: statusColor,
                      ),
                    ],
                  ),
                ),
                if (connection.isLoading && !connection.hasValue)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (!isOnline)
                  Icon(Icons.wifi_off_rounded, color: colors.error),
              ],
            ),
            const SizedBox(height: 16),
            if (printer == null)
              Text(
                isOnline
                    ? 'pages.overview.printdeck.fetching_status'.tr()
                    : 'pages.overview.printdeck.no_connection'.tr(),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _printStateLabel(printState),
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: statusColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (isPrinting || isPaused)
                    Text(
                      '${(printer.printProgress.clamp(0.0, 1.0) * 100).round()}%',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                printer.print.filename.isEmpty
                    ? 'pages.overview.printdeck.no_job'.tr()
                    : printer.print.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (isPrinting || isPaused) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: printer.printProgress.clamp(0.0, 1.0).toDouble()),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (printer.extruders.isNotEmpty)
                    _TemperatureBadge(
                      icon: Icons.local_fire_department_outlined,
                      label: 'pages.overview.printdeck.nozzle'.tr(),
                      value: printer.extruder.temperature,
                    ),
                  if (printer.heaterBed != null)
                    _TemperatureBadge(
                      icon: Icons.grid_on_outlined,
                      label: 'pages.overview.printdeck.bed'.tr(),
                      value: printer.heaterBed!.temperature,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openControls(ref),
                    icon: const Icon(Icons.tune_rounded),
                    label: Text('pages.overview.printdeck.open_controls'.tr()),
                  ),
                ),
                if (isPrinting || isPaused) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: isPrinting
                        ? 'pages.overview.printdeck.pause_print'.tr()
                        : 'pages.overview.printdeck.resume_print'.tr(),
                    onPressed: !isOnline
                        ? null
                        : () {
                            final service =
                                ref.read(printerServiceProvider(machine.uuid));
                            if (isPrinting) {
                              service.pausePrint();
                            } else {
                              service.resumePrint();
                            }
                          },
                    icon: Icon(isPrinting
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                  ),
                ] else if (!isOnline) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'pages.overview.printdeck.reconnect'.tr(),
                    onPressed: () => ref
                        .read(jrpcClientProvider(machine.uuid))
                        .ensureConnection(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _printStateLabel(PrintState? state) {
    switch (state) {
      case PrintState.printing:
        return 'pages.overview.printdeck.printing'.tr();
      case PrintState.paused:
        return 'pages.overview.printdeck.paused'.tr();
      case PrintState.complete:
        return 'pages.overview.printdeck.complete'.tr();
      case PrintState.cancelled:
        return 'pages.overview.printdeck.cancelled'.tr();
      case PrintState.error:
        return 'pages.overview.printdeck.error'.tr();
      case PrintState.standby:
      case null:
        return 'pages.overview.printdeck.standby'.tr();
    }
  }

  Future<void> _openControls(WidgetRef ref) async {
    await ref.read(selectedMachineServiceProvider).selectMachine(machine);
    ref.read(goRouterProvider).pushNamed(AppRoute.dashBoard.name);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _TemperatureBadge extends StatelessWidget {
  const _TemperatureBadge(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 5),
            Text('$label ${value.round()}°C',
                style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddPrinter});

  final VoidCallback onAddPrinter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_disabled_rounded,
                size: 54, color: theme.colorScheme.secondary),
            const SizedBox(height: 16),
            Text('pages.overview.printdeck.empty_title'.tr(),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'pages.overview.printdeck.empty_message'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddPrinter,
              icon: const Icon(Icons.add),
              label: Text('pages.overview.printdeck.add_printer'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('pages.overview.printdeck.load_error'.tr(),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('pages.overview.printdeck.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
