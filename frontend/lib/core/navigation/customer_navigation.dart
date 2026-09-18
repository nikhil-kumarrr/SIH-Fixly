import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/router/route_names.dart';
import 'screen_refresh.dart';

/// Global reactive dispatcher to inject queries into the AI chat interface immediately.
class AiHelperQueryDispatcher {
  static final ValueNotifier<String?> pendingQuery = ValueNotifier<String?>(null);

  static void dispatch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    pendingQuery.value = null; // reset to ensure listeners trigger even on duplicate queries
    pendingQuery.value = clean;
  }
}

/// Global tab switching helper that works from any context, including rootNavigatorKey.
class CustomerTabSwitcher {
  static void switchToAiTab({BuildContext? context, String? query}) {
    if (query != null && query.trim().isNotEmpty) {
      AiHelperQueryDispatcher.dispatch(query.trim());
    }
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ctx.goCustomerTab(2, extra: query);
    }
  }
}

extension CustomerNavigation on BuildContext {
  static const customerTabRoutes = [
    RouteNames.customerHome,
    RouteNames.customerSearch,
    RouteNames.customerAiHelper,
    RouteNames.customerOrders,
    RouteNames.customerProfileTab,
  ];

  StatefulNavigationShellState? get _customerShell {
    try {
      return StatefulNavigationShell.of(this);
    } catch (_) {
      return null;
    }
  }

  /// Switch customer bottom-nav tab without corrupting the shell stack.
  void goCustomerTab(int index, {Object? extra}) {
    if (index < 0 || index >= customerTabRoutes.length) return;
    final target = customerTabRoutes[index];
    ScreenRefresh.mark(target);

    String? currentPath;
    try {
      currentPath = GoRouterState.of(this).uri.path;
    } catch (_) {
      try {
        currentPath = GoRouter.of(this).routerDelegate.currentConfiguration.uri.path;
      } catch (_) {
        currentPath = null;
      }
    }

    final coveringShell = currentPath != null &&
        (currentPath.contains('/category-search') ||
            currentPath.endsWith('/categories') ||
            currentPath.contains('/categories/'));

    final targetUri = (index == 2 && extra is String && extra.isNotEmpty)
        ? '$target?q=${Uri.encodeComponent(extra)}'
        : target;

    if (coveringShell) {
      try {
        go(targetUri, extra: extra);
      } catch (_) {
        GoRouter.of(this).go(targetUri, extra: extra);
      }
      return;
    }

    final shell = _customerShell;
    if (shell != null && extra == null) {
      shell.goBranch(
        index,
        initialLocation: index == shell.currentIndex,
      );
      return;
    }

    try {
      go(targetUri, extra: extra);
    } catch (_) {
      GoRouter.of(this).go(targetUri, extra: extra);
    }
  }

  /// Open filtered services for a category with a back button.
  void openCategorySearch(String categoryId) {
    final path = RouteNames.customerCategorySearchPath(categoryId);
    final location = GoRouterState.of(this).uri.toString();
    if (location.contains('/categories')) {
      pushReplacement(path);
      return;
    }
    push(path);
  }
}
