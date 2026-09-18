import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_strings.dart';
import '../../features/auth/presentation/cubit/app_session_cubit.dart';
import '../navigation/customer_navigation.dart';
import '../navigation/screen_refresh.dart';
import '../network/customer_realtime_service.dart';
import 'animated_bottom_nav_bar.dart';

class CustomerMainShell extends StatefulWidget {
  const CustomerMainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<CustomerMainShell> createState() => _CustomerMainShellState();
}

class _CustomerMainShellState extends State<CustomerMainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AppSessionCubit>().currentUser;
      if (user != null && user.id.isNotEmpty) {
        CustomerRealtimeService.instance.initForCustomer(user.id);
      }
    });
  }

  void _onTap(int index) {
    if (index < 0 ||
        index >= CustomerNavigation.customerTabRoutes.length) {
      return;
    }
    final target = CustomerNavigation.customerTabRoutes[index];
    ScreenRefresh.mark(target);

    // Category/search overlays use rootNavigatorKey — goBranch alone leaves
    // them on top, so the UI looks stuck while the shell switches underneath.
    final path = GoRouterState.of(context).uri.path;
    final coveringShell = path.contains('/category-search') ||
        path.endsWith('/categories') ||
        path.contains('/categories/');
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
    return BlocBuilder<AppSessionCubit, AppSessionState>(
      buildWhen: (prev, curr) => prev.locale != curr.locale,
      builder: (context, session) {
        final l10n = AppStrings(session.locale);
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: widget.navigationShell,
          bottomNavigationBar: AnimatedBottomNavBar(
            currentIndex: widget.navigationShell.currentIndex,
            onTap: _onTap,
            items: [
              NavBarItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: l10n.navHome,
              ),
              NavBarItem(
                icon: Icons.search_outlined,
                activeIcon: Icons.search_rounded,
                label: l10n.navSearch,
              ),
              NavBarItem(
                icon: Icons.auto_awesome_outlined,
                activeIcon: Icons.auto_awesome,
                label: l10n.navAi,
                isAccent: true,
              ),
              NavBarItem(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
                label: l10n.navBookings,
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
