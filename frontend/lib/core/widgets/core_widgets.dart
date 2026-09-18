import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/router/route_names.dart';
import '../../features/auth/presentation/cubit/app_session_cubit.dart';
import '../../shared/models/models.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_x.dart';
import '../constants/app_strings.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.bottom,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.showBack,
    this.onBack,
    this.fallbackPath,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsets padding;

  /// When null, back shows only if *this* route can pop (not the root stack).
  final bool? showBack;
  final VoidCallback? onBack;
  final String? fallbackPath;

  bool _canPopThisRoute(BuildContext context) {
    if (showBack != null) return showBack!;
    return ModalRoute.of(context)?.canPop ?? false;
  }

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    if (fallbackPath != null && fallbackPath!.isNotEmpty) {
      context.go(fallbackPath!);
      return;
    }
    try {
      final from = GoRouterState.of(context).uri.queryParameters['from'];
      if (from == 'notifications') {
        context.go(RouteNames.sharedNotifications);
        return;
      }
    } catch (_) {}

    try {
      final isWorker =
          context.read<AppSessionCubit?>()?.currentUser?.role == UserRole.worker;
      context.go(
          isWorker ? RouteNames.workerDashboard : RouteNames.customerHome);
    } catch (_) {
      context.go(RouteNames.customerHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _canPopThisRoute(context);
    bool hasQueryFromNotif = false;
    try {
      hasQueryFromNotif =
          GoRouterState.of(context).uri.queryParameters['from'] != null;
    } catch (_) {}

    final canGoBack = canPop ||
        context.canPop() ||
        fallbackPath != null ||
        hasQueryFromNotif;

    final scaffold = Scaffold(
      appBar: title == null && titleWidget == null
          ? null
          : AppBar(
              title: titleWidget ?? (title != null ? Text(title!) : null),
              centerTitle: false,
              leading: leading ??
                  ((showBack ?? canGoBack)
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: context.l10n.goBack,
                          onPressed: () => _handleBack(context),
                        )
                      : null),
              automaticallyImplyLeading: false,
              actions: actions,
              bottom: bottom,
            ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: Padding(padding: padding, child: body),
      ),
    );

    if (!canGoBack) {
      return scaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack(context);
        }
      },
      child: scaffold,
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading && onPressed != null,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          child: loading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}

class SwipeActionButton extends StatefulWidget {
  const SwipeActionButton({
    required this.label,
    required this.onCompleted,
    super.key,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onCompleted;
  final bool enabled;

  @override
  State<SwipeActionButton> createState() => _SwipeActionButtonState();
}

class _SwipeActionButtonState extends State<SwipeActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<double>? _anim;
  double _drag = 0;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double target, {VoidCallback? onDone}) {
    _anim = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() => _drag = _anim!.value);
      });
    _animController.forward(from: 0).then((_) {
      onDone?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: widget.enabled
            ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
            : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDrag = (constraints.maxWidth - 52).clamp(0.0, double.infinity);
          final dragRatio = maxDrag > 0 ? (_drag / maxDrag).clamp(0.0, 1.0) : 0.0;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Progress fill behind the knob
              if (widget.enabled && _drag > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _drag + 52,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),

              // Centered prompt text (fades as user drags)
              Center(
                child: Opacity(
                  opacity: (1.0 - dragRatio * 1.5).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.enabled
                              ? (isDark ? Colors.white70 : const Color(0xFF334155))
                              : Colors.grey,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: widget.enabled
                            ? (isDark ? Colors.white38 : Colors.black26)
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),

              // Draggable Action Knob
              Positioned(
                left: _drag,
                child: GestureDetector(
                  onHorizontalDragUpdate: !widget.enabled || _isCompleted
                      ? null
                      : (details) {
                          setState(() {
                            _drag = (_drag + details.delta.dx).clamp(0.0, maxDrag);
                          });
                        },
                  onHorizontalDragEnd: !widget.enabled || _isCompleted
                      ? null
                      : (_) {
                          if (_drag >= maxDrag * 0.6) {
                            setState(() => _isCompleted = true);
                            _animateTo(maxDrag, onDone: () {
                              widget.onCompleted();
                            });
                          } else {
                            _animateTo(0.0);
                          }
                        },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: widget.enabled ? 0.35 : 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: !widget.enabled
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isCompleted
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.controller,
    super.key,
    this.label,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLength,
    this.focusNode,
    this.textInputAction,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final int? maxLength;
  final int maxLines;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          readOnly: readOnly,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          maxLength: maxLength,
          validator: validator,
          onChanged: onChanged,
          onTap: onTap,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            counterText: '',
            semanticCounterText: '',
          ),
        ),
      ],
    );
  }
}

class StepProgressHeader extends StatelessWidget {
  const StepProgressHeader({
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    super.key,
  });

  final int currentStep;
  final int totalSteps;
  final String title;

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $currentStep of $totalSteps',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: context.scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class GreetingAppBarTitle extends StatelessWidget {
  const GreetingAppBarTitle({required this.userName, super.key});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.timeGreeting(DateTime.now().hour),
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          userName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Branded pull-to-refresh — uses [ColorScheme.primary] and surface container.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    required this.onRefresh,
    required this.child,
    super.key,
    this.notificationPredicate,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Defaults to Flutter's depth-0 check. Use custom for [NestedScrollView].
  final ScrollNotificationPredicate? notificationPredicate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest,
      strokeWidth: 2.5,
      displacement: 48,
      edgeOffset: 12,
      notificationPredicate:
          notificationPredicate ?? defaultScrollNotificationPredicate,
      child: child,
    );
  }
}

/// Lets pull-to-refresh work when content shorter than viewport.
const ScrollPhysics appRefreshScrollPhysics = AlwaysScrollableScrollPhysics(
  parent: BouncingScrollPhysics(),
);
