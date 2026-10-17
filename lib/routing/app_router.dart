/*
 * Copyright (c) 2023-2024. Patrick Schmidt.
 * All rights reserved.
 */
// ignore_for_file: prefer-match-file-name

import 'package:common/data/dto/files/gcode_file.dart';
import 'package:common/data/dto/files/generic_file.dart';
import 'package:common/data/model/hive/machine.dart';
import 'package:common/service/app_router.dart';
import 'package:common/service/machine_service.dart';
import 'package:common/service/setting_service.dart';
import 'package:common/ui/components/info_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_icons/flutter_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileraker/ui/components/app_version_text.dart';
import 'package:mobileraker/ui/screens/console/console_page.dart';
import 'package:mobileraker/ui/screens/dashboard/dashboard_page.dart';
import 'package:mobileraker/ui/screens/dev/dev_page.dart';
import 'package:mobileraker/ui/screens/files/details/config_file_details_page.dart';
import 'package:mobileraker/ui/screens/files/details/gcode_file_details_page.dart';
import 'package:mobileraker/ui/screens/files/details/image_file_page.dart';
import 'package:mobileraker/ui/screens/files/files_page.dart';
import 'package:mobileraker/ui/screens/fullcam/full_cam_page.dart';
import 'package:mobileraker/ui/screens/markdown/mark_down_page.dart';
import 'package:mobileraker/ui/screens/overview/overview_page.dart';
import 'package:mobileraker/ui/screens/paywall/paywall_page.dart';
import 'package:mobileraker/ui/screens/printers/add/printers_add_page.dart';
import 'package:mobileraker/ui/screens/printers/edit/printers_edit_page.dart';
import 'package:mobileraker/ui/screens/printers/import_export/printer_import_export_page.dart';
import 'package:mobileraker/ui/screens/qr_scanner/qr_scanner_page.dart';
import 'package:mobileraker/ui/screens/scanner/universal_product_scanner_page.dart';
import 'package:mobileraker/ui/screens/setting/imprint/imprint_view.dart';
import 'package:mobileraker/ui/screens/setting/setting_page.dart';
import 'package:mobileraker/ui/screens/spoolman/filament_detail_page.dart';
import 'package:mobileraker/ui/screens/spoolman/local_filament_stock_page.dart';
import 'package:mobileraker/ui/screens/spoolman/spool_detail_page.dart';
import 'package:mobileraker/ui/screens/spoolman/spoolman_page.dart';
import 'package:mobileraker/ui/screens/spoolman/vendor_detail_page.dart';
import 'package:mobileraker/ui/screens/tools/components/belt_tuner.dart';
import 'package:mobileraker_pro/spoolman/dto/filament.dart';
import 'package:mobileraker_pro/spoolman/dto/spool.dart';
import 'package:mobileraker_pro/spoolman/dto/vendor.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/screens/files/details/video_player_page.dart';
import '../ui/screens/tools/tool_page.dart';
import '../features/supply_hub/presentation/screens/supply_hub_page.dart';
import '../features/auth/presentation/screens/login_page.dart';
import '../features/auth/presentation/screens/register_page.dart';
import '../features/auth/presentation/screens/forgot_password_page.dart';
import '../features/auth/presentation/screens/profile_page.dart';

part 'app_router.g.dart';

enum AppRoute implements RouteDefinitionMixin {
  dashBoard,
  overview,
  printerEdit,
  fullCam,
  printerAdd,
  qrScanner,
  console,
  files,
  settings,
  imprint,
  gcodeDetail,
  configDetail,
  imageViewer,
  dev,
  faq,
  changelog,
  supportDev,
  videoPlayer,
  tool,
  beltTuner,
  spoolman,
  spoolman_vendorDetails,
  spoolman_spoolDetails,
  spoolman_filamentDetails,
  localStock,
  productScanner,
  printerImportExport,
  supplyHub,
  login,
  register,
  forgotPassword,
  profile;
}

@riverpod
Future<String> initialRoute(InitialRouteRef ref) async {
  ref.keepAlive();
  SettingService settingService = ref.watch(settingServiceProvider);

  if (!settingService.readBool(AppSettingKeys.overviewIsHomescreen)) {
    return '/';
  }
  int printerCnt = await ref.watch(allMachinesProvider.selectAsync((data) => data.length));

  if (printerCnt > 1) {
    return '/overview';
  }
  return '/';
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter goRouterImpl(GoRouterRef ref) {
  final authStream = FirebaseAuth.instance.authStateChanges();
  final refreshListenable = GoRouterRefreshStream(authStream);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: ref.watch(initialRouteProvider).requireValue,
    debugLogDiagnostics: false,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final location = state.location;
      final isLoggingIn = location == '/login';
      final isRegistering = location == '/register';
      final isResettingPassword = location == '/forgot-password';
      final isAuthRoute = isLoggingIn || isRegistering || isResettingPassword;

      // Se deslogado, permite apenas rotas públicas de autenticação; caso contrário, vai para o login
      if (user == null) {
        return isAuthRoute ? null : '/login';
      }

      // Se logado e tentar acessar rotas de autenticação (login, cadastro), redireciona para a home
      if (isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.dashBoard.name,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: '/overview',
        name: AppRoute.overview.name,
        builder: (context, state) => const OverviewPage(),
      ),
      GoRoute(
        path: '/qrScanner',
        name: AppRoute.qrScanner.name,
        builder: (context, state) => const QrScannerPage(),
      ),
      GoRoute(
        path: '/fullcam',
        name: AppRoute.fullCam.name,
        builder: (context, state) {
          Map<String, dynamic> b = state.extra as Map<String, dynamic>;
          return FullCamPage(b['machine'], b['selectedCam']);
        },
      ),
      GoRoute(
        path: '/printer',
        builder: (_, __) => const SizedBox(),
        routes: [
          GoRoute(
            path: 'edit',
            name: AppRoute.printerEdit.name,
            builder: (context, state) {
              return PrinterEditPage(machine: state.extra! as Machine);
            },
          ),
          GoRoute(
            path: 'add',
            name: AppRoute.printerAdd.name,
            builder: (context, state) =>
                // TestPage(),
                const PrinterAddPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/files',
        name: AppRoute.files.name,
        builder: (context, state) => const FilesPage(),
        routes: [
          GoRoute(
            path: 'gcode-details',
            name: AppRoute.gcodeDetail.name,
            builder: (context, state) => GCodeFileDetailPage(gcodeFile: state.extra! as GCodeFile),
          ),
          GoRoute(
            path: 'config-details',
            name: AppRoute.configDetail.name,
            builder: (context, state) => ConfigFileDetailPage(file: state.extra! as GenericFile),
          ),
          GoRoute(
            path: 'video-player',
            name: AppRoute.videoPlayer.name,
            builder: (context, state) => VideoPlayerPage(state.extra! as GenericFile),
          ),
          GoRoute(
            path: 'image-viewer',
            name: AppRoute.imageViewer.name,
            builder: (context, state) => ImageFilePage(state.extra! as GenericFile),
          ),
        ],
      ),
      GoRoute(
        path: '/setting',
        name: AppRoute.settings.name,
        builder: (context, state) => const SettingPage(),
      ),
      GoRoute(
        path: '/imprint',
        name: AppRoute.imprint.name,
        builder: (context, state) => const ImprintPage(),
      ),
      GoRoute(
        path: '/console',
        name: AppRoute.console.name,
        builder: (context, state) => const ConsolePage(),
      ),
      GoRoute(
        path: '/faq',
        name: AppRoute.faq.name,
        builder: (context, state) => MarkDownPage(
          title: tr('pages.faq.title'),
          mdRoot: Uri.parse(
            'https://raw.githubusercontent.com/Clon1998/mobileraker/master/docs/faq.md',
          ),
          mdHuman: Uri.parse(
            'https://github.com/Clon1998/mobileraker/blob/master/docs/faq.md',
          ),
        ),
      ),
      GoRoute(
        path: '/changelog',
        name: AppRoute.changelog.name,
        builder: (context, state) => MarkDownPage(
          title: tr('pages.changelog.title'),
          mdRoot: Uri.parse(
            'https://raw.githubusercontent.com/Clon1998/mobileraker/master/docs/changelog.md',
          ),
          mdHuman: Uri.parse(
            'https://github.com/Clon1998/mobileraker/blob/master/docs/changelog.md',
          ),
          topWidget: InfoCard(
            leading: const Icon(FlutterIcons.code_fork_faw),
            title: const Text('components.app_version_display.installed_version').tr(),
            body: const AppVersionText(prefix: 'Mobileraker'),
          ),
        ),
      ),
      GoRoute(
        path: '/paywall',
        name: AppRoute.supportDev.name,
        builder: (context, state) => const PaywallPage(),
      ),
      GoRoute(
        path: '/dev',
        name: AppRoute.dev.name,
        builder: (context, state) => DevPage(),
      ),
      GoRoute(
        path: '/tool',
        name: AppRoute.tool.name,
        builder: (context, state) => const ToolPage(),
        routes: [
          GoRoute(
            path: 'belt-tuner',
            name: AppRoute.beltTuner.name,
            builder: (context, state) => const BeltTuner(),
          ),
        ],
      ),
      GoRoute(
        path: '/spoolman',
        name: AppRoute.spoolman.name,
        builder: (context, state) => const SpoolmanPage(),
        routes: [
          GoRoute(
            path: 'spool-details',
            name: AppRoute.spoolman_spoolDetails.name,
            builder: (context, state) => switch (state.extra) {
              [String machineUUID, Spool spool] => SpoolDetailPage(spool: spool, machineUUID: machineUUID),
              _ => throw ArgumentError('Invalid state.extra for spool-details route'),
            },
          ),
          GoRoute(
            path: 'filament-details',
            name: AppRoute.spoolman_filamentDetails.name,
            builder: (context, state) => switch (state.extra) {
              [String machineUUID, Filament filament] =>
                FilamentDetailPage(filament: filament, machineUUID: machineUUID),
              _ => throw ArgumentError('Invalid state.extra for spool-details route'),
            },
          ),
          GoRoute(
            path: 'vendor-details',
            name: AppRoute.spoolman_vendorDetails.name,
            builder: (context, state) => switch (state.extra) {
              [String machineUUID, Vendor vendor] => VendorDetailPage(vendor: vendor, machineUUID: machineUUID),
              _ => throw ArgumentError('Invalid state.extra for spool-details route'),
            },
          ),
        ],
      ),
      GoRoute(
        path: '/stock',
        name: AppRoute.localStock.name,
        builder: (context, state) => const LocalFilamentStockPage(),
      ),
      GoRoute(
        path: '/product-scanner',
        name: AppRoute.productScanner.name,
        builder: (context, state) => const UniversalProductScannerPage(),
      ),
      GoRoute(
        path: '/printer/import-export',
        name: AppRoute.printerImportExport.name,
        builder: (context, state) => const PrinterImportExportPage(),
      ),
      GoRoute(
        path: '/supply-hub',
        name: AppRoute.supplyHub.name,
        builder: (context, state) => const SupplyHubPage(),
      ),
      GoRoute(
        path: '/login',
        name: AppRoute.login.name,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: AppRoute.register.name,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: AppRoute.forgotPassword.name,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/profile',
        name: AppRoute.profile.name,
        builder: (context, state) => const ProfilePage(),
      ),
    ],
    // errorBuilder: (context, state) => const NotFoundScreen(),
  );
}
