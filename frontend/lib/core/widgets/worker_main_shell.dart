import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_names.dart';
import '../constants/app_strings.dart';
import '../../features/auth/presentation/cubit/app_session_cubit.dart';
import '../navigation/screen_refresh.dart';
import '../network/worker_realtime_service.dart';
import 'animated_bottom_nav_bar.dart';

class WorkerMainShell extends StatefulWidget {
  const WorkerMainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<WorkerMainShell> createState() => _WorkerMainShellState();
}

class _WorkerMainShellState extends State<WorkerMainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AppSessionCubit>().currentUser;
      if (user != null && user.id.isNotEmpty) {
        WorkerRealtimeService.instance.initForWorker(user.id);
      }
    });
  }

  /// Routes that logically belong to each tab index.
  ///  0 = Dashboard, 1 = Jobs, 2 = Wallet, 3 = Profile
  static const _tabRoutes = <int, List<String>>{
    0: [
      RouteNames.workerDashboard,
      RouteNames.workerEarnings,
      RouteNames.workerReliability,
      RouteNames.workerAvailability,
      RouteNames.workerIncoming,
      RouteNames.workerActiveJob,
      RouteNames.workerOtpEntry,
      RouteNames.workerAddParts,
      RouteNames.workerRating,
      RouteNames.workerNavigation,
      RouteNames.workerPriceEstimation,
      RouteNames.workerCooperative,
      RouteNames.workerWelfare,
    ],
    1: [
      RouteNames.workerJobs,
      RouteNames.workerJobDetail,
    ],
    2: [
      RouteNames.workerWallet,
    ],
    3: [
      RouteNames.workerProfileTab,
      RouteNames.workerProfile,
      RouteNames.workerRateSettings,
      RouteNames.sharedProfile,
      RouteNames.sharedEditProfile,
      RouteNames.sharedSettings,
      RouteNames.sharedNotifications,
      RouteNames.sharedOrderHistory,
      RouteNames.sharedSupportChat,
      RouteNames.sharedSupportTicket,
      RouteNames.sharedSos,
    ],
  };

  /// Derive tab index from the current route location.
  /// Falls back to [navigationShell.currentIndex] if no match found.
  int _resolveTabIndex(String location) {
    for (final entry in _tabRoutes.entries) {
      for (final route in entry.value) {
        // Strip path params (e.g. /worker/job/:id → /worker/job/)
        final pattern = route.replaceAll(RegExp(r':[^/]+'), '');
        if (location.startsWith(pattern)) return entry.key;
      }
    }
    return widget.navigationShell.currentIndex;
  }

  void _onTap(int index) {
    const tabRoots = [
      RouteNames.workerDashboard,
      RouteNames.workerJobs,
      RouteNames.workerWallet,
      RouteNames.workerProfileTab,
    ];
    if (index < 0 || index >= tabRoots.length) return;
    final target = tabRoots[index];
    ScreenRefresh.mark(target);

    // Root overlays (navigation map, etc.) — go clears them so tab switch works.
    final path = GoRouterState.of(context).uri.path;
    final coveringShell = path.contains('/navigation') ||
        path.contains('/active-job') ||
        path.contains('/otp') ||
        path.contains('/add-parts') ||
        path.contains('/price-estimation') ||
        path.contains('/rating');
    if (coveringShell) {
      context.go(target);
      return;
    }

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to route changes so the bottom nav updates for overlay routes too.
    final location = GoRouterState.of(context).uri.toString();
    final effectiveIndex = _resolveTabIndex(location);

    return BlocBuilder<AppSessionCubit, AppSessionState>(
      buildWhen: (prev, curr) => prev.locale != curr.locale,
      builder: (context, session) {
        final l10n = AppStrings(session.locale);
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: widget.navigationShell,
          bottomNavigationBar: AnimatedBottomNavBar(
            currentIndex: effectiveIndex,
            onTap: _onTap,
            items: [
              NavBarItem(
                icon: Icons.dashboard_outlined,
                activeIcon: Icons.dashboard_rounded,
                label: l10n.navHome,
              ),
              NavBarItem(
                icon: Icons.work_outline,
                activeIcon: Icons.work_rounded,
                label: l10n.navJobs,
              ),
              NavBarItem(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet_rounded,
                label: l10n.navWallet,
              ),
              NavBarItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person_rounded,
                label: l10n.navProfile,
              ),
            ],
          ),
        );
      },
    );
  }
}
