import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Marks a destination so kept-alive / shell screens reload after auto-nav.
class ScreenRefresh {
  ScreenRefresh._();

  static final ValueNotifier<int> version = ValueNotifier(0);
  static final Set<String> _pending = <String>{};

  static String normalize(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static String _prefixOf(String ownedRoute) {
    final raw =
        ownedRoute.contains(':') ? ownedRoute.split('/:').first : ownedRoute;
    return normalize(raw);
  }

  static void mark(String location) {
    final path = normalize(location);
    if (path.isEmpty) return;
    _pending.add(path);
    version.value++;
  }

  /// Consume any pending marks owned by [ownedRoutes]. Returns true if any hit.
  static bool consumeForScreen(List<String> ownedRoutes) {
    if (_pending.isEmpty || ownedRoutes.isEmpty) return false;
    final prefixes = ownedRoutes.map(_prefixOf).toList(growable: false);
    var hit = false;
    for (final pending in _pending.toList(growable: false)) {
      for (final prefix in prefixes) {
        if (pending == prefix || pending.startsWith('$prefix/')) {
          _pending.remove(pending);
          hit = true;
          break;
        }
      }
    }
    return hit;
  }
}

extension GoRefreshing on BuildContext {
  /// Auto-nav: mark destination for refresh, then [go].
  void goRefreshing(String location) {
    ScreenRefresh.mark(location);
    go(location);
  }

  /// Auto-nav: mark destination for refresh, then [push].
  Future<T?> pushRefreshing<T extends Object?>(String location) {
    ScreenRefresh.mark(location);
    return push<T>(location);
  }
}

/// Listen for [ScreenRefresh] marks aimed at this screen.
mixin RefreshWhenNavigatedTo<T extends StatefulWidget> on State<T> {
  /// Exact paths or templates this screen owns (e.g. `/customer/orders`).
  List<String> get refreshRoutePaths;

  void onScreenRefresh();

  bool _refreshListenerAttached = false;
  bool _readyForNavRefresh = false;

  @override
  void initState() {
    super.initState();
    // Cold mount loads in subclass — drop pending mark to avoid double fetch.
    ScreenRefresh.consumeForScreen(refreshRoutePaths);
    ScreenRefresh.version.addListener(_onRefreshSignal);
    _refreshListenerAttached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyForNavRefresh = true;
    });
  }

  @override
  void dispose() {
    if (_refreshListenerAttached) {
      ScreenRefresh.version.removeListener(_onRefreshSignal);
    }
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted || !_readyForNavRefresh) return;
    if (ScreenRefresh.consumeForScreen(refreshRoutePaths)) {
      onScreenRefresh();
    }
  }
}
