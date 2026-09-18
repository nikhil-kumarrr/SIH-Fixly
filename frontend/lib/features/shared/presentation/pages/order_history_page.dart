import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/network/customer_realtime_service.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../../bookings/data/bookings_api_repository.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key, this.showBack = true});

  final bool showBack;

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage>
    with RefreshWhenNavigatedTo {
  final _bookings = BookingsApiRepository();
  late Future<List<Booking>> _ordersFuture;
  List<Booking> _orders = const [];
  int _selectedFilter = 0; // 0: All, 1: Ongoing, 2: Completed
  Timer? _navPollTimer;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  @override
  List<String> get refreshRoutePaths => [
        RouteNames.customerOrders,
        RouteNames.sharedOrderHistory,
      ];

  @override
  void onScreenRefresh() {
    unawaited(_onRefresh());
  }

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindRealtime());
  }

  @override
  void dispose() {
    _navPollTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<List<Booking>> _fetchOrders() async {
    final list = await _bookings.history(forceNetwork: true);
    if (mounted) {
      setState(() => _orders = list);
      _syncNavPoll();
      _bindRealtime();
    }
    return list;
  }

  Future<void> _onRefresh() async {
    final next = _fetchOrders();
    setState(() {
      _ordersFuture = next;
    });
    try {
      await next;
    } catch (_) {
      // Error stays on [_ordersFuture] for FutureBuilder; don't rethrow to zone.
    }
  }

  bool _needsNavWatch(List<Booking> orders, {required bool isWorker}) {
    if (isWorker) return false;
    return orders.any(
      (o) =>
          (o.status == BookingStatus.accepted ||
              o.status == BookingStatus.arrived) &&
          !o.workerHasStartedNavigation,
    );
  }

  void _bindRealtime() {
    if (!mounted) return;
    final role =
        context.read<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    if (role == UserRole.worker) {
      _statusSub?.cancel();
      _statusSub = null;
      return;
    }

    final userId = context.read<AppSessionCubit>().currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      CustomerRealtimeService.instance.initForCustomer(userId);
    }

    // Track first pending booking room (socket room); polling covers the rest.
    final pending = _orders.where(
      (o) =>
          (o.status == BookingStatus.accepted ||
              o.status == BookingStatus.arrived) &&
          !o.workerHasStartedNavigation,
    );
    if (pending.isNotEmpty) {
      CustomerRealtimeService.instance.trackBooking(pending.first.id);
    }

    _statusSub?.cancel();
    _statusSub =
        CustomerRealtimeService.instance.bookingStatusStream.listen((map) {
      final eventId = map['bookingId']?.toString();
      final canonical = map['canonicalBookingId']?.toString();
      final navStarted = map['workerNavigationStarted'] == true ||
          map['workerNavigationStartedAt'] != null;
      final touchesWatching = _orders.any(
        (o) =>
            o.id == eventId ||
            o.displayId == eventId ||
            o.id == canonical ||
            o.displayId == canonical,
      );
      if (!touchesWatching && !navStarted) return;
      unawaited(_pollNavigationFlags(forceIds: {
        if (eventId != null && eventId.isNotEmpty) eventId,
        if (canonical != null && canonical.isNotEmpty) canonical,
      }));
    });
  }

  void _syncNavPoll() {
    if (!mounted) return;
    final role =
        context.read<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    final isWorker = role == UserRole.worker;
    _navPollTimer?.cancel();
    _navPollTimer = null;
    if (!_needsNavWatch(_orders, isWorker: isWorker)) return;
    unawaited(_pollNavigationFlags());
    _navPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pollNavigationFlags());
    });
  }

  Future<void> _pollNavigationFlags({Set<String> forceIds = const {}}) async {
    if (!mounted || _orders.isEmpty) return;
    final pending = _orders
        .where(
          (o) =>
              forceIds.contains(o.id) ||
              forceIds.contains(o.displayId) ||
              ((o.status == BookingStatus.accepted ||
                      o.status == BookingStatus.arrived) &&
                  !o.workerHasStartedNavigation),
        )
        .toList();
    if (pending.isEmpty) {
      _navPollTimer?.cancel();
      _navPollTimer = null;
      return;
    }

    var changed = false;
    final next = List<Booking>.from(_orders);
    for (final order in pending) {
      try {
        final fresh = await _bookings.getById(
          order.id,
          serviceTitle: order.serviceTitle,
          forceNetwork: true,
        );
        final idx = next.indexWhere((o) => o.id == order.id);
        if (idx < 0) continue;
        if (fresh.workerHasStartedNavigation !=
                next[idx].workerHasStartedNavigation ||
            fresh.status != next[idx].status ||
            fresh.workerNavigationStartedAt !=
                next[idx].workerNavigationStartedAt) {
          next[idx] = fresh;
          changed = true;
        }
      } catch (_) {}
    }
    if (!mounted || !changed) return;
    setState(() => _orders = next);
    _syncNavPoll();
    _bindRealtime();
  }

  List<Booking> _filterOrders(List<Booking> orders, {required bool isWorker}) {
    switch (_selectedFilter) {
      case 1:
        return orders
            .where(
              (o) =>
                  o.needsReview(isWorker: isWorker) ||
                  o.isAwaitingPayment ||
                  o.status == BookingStatus.searching ||
                  o.status == BookingStatus.accepted ||
                  o.status == BookingStatus.arrived ||
                  o.status == BookingStatus.inProgress,
            )
            .toList();
      case 2:
        return orders
            .where(
              (o) =>
                  !o.needsReview(isWorker: isWorker) &&
                  !o.isAwaitingPayment &&
                  (o.status == BookingStatus.completed ||
                      o.status == BookingStatus.paid ||
                      o.status == BookingStatus.cancelled),
            )
            .toList();
      default:
        return orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = context.watch<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    final isWorker = userRole == UserRole.worker;
    final pageTitle = isWorker ? 'Job History' : context.l10n.orderHistory;

    return AppScaffold(
      title: pageTitle,
      showBack: widget.showBack,
      body: AppRefreshIndicator(
        onRefresh: _onRefresh,
        child: FutureBuilder<List<Booking>>(
          future: _ordersFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return ListView(
                physics: appRefreshScrollPhysics,
                children: const [
                  SizedBox(height: 140),
                  Center(
                    child: CircularProgressIndicator(),
                  ),
                ],
              );
            }

            if (snap.hasError) {
              final scheme = Theme.of(context).colorScheme;
              return ListView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: scheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      isWorker ? 'Failed to load jobs' : 'Failed to load order history',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      snap.error.toString().replaceAll('ApiException: ', ''),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }

            final allOrders =
                _orders.isNotEmpty ? _orders : (snap.data ?? const []);
            if (allOrders.isEmpty) {
              return _buildEmptyState(context, isWorker, isFiltered: false);
            }

            final filteredOrders = _filterOrders(allOrders, isWorker: isWorker);

            return Column(
              children: [
                _buildFilterBar(allOrders, isWorker: isWorker),
                Expanded(
                  child: filteredOrders.isEmpty
                      ? _buildEmptyState(context, isWorker, isFiltered: true)
                      : ListView.builder(
                          physics: appRefreshScrollPhysics,
                          padding: const EdgeInsets.only(top: 6, bottom: 24),
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            return _buildOrderCard(
                              context,
                              filteredOrders[index],
                              isWorker,
                              index,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterBar(List<Booking> allOrders, {required bool isWorker}) {
    final ongoingCount = allOrders
        .where(
          (o) =>
              o.needsReview(isWorker: isWorker) ||
              o.isAwaitingPayment ||
              o.status == BookingStatus.searching ||
              o.status == BookingStatus.accepted ||
              o.status == BookingStatus.arrived ||
              o.status == BookingStatus.inProgress,
        )
        .length;

    final completedCount = allOrders
        .where(
          (o) =>
              !o.needsReview(isWorker: isWorker) &&
              !o.isAwaitingPayment &&
              (o.status == BookingStatus.completed ||
                  o.status == BookingStatus.paid),
        )
        .length;

    final filters = [
      'All (${allOrders.length})',
      'Ongoing ($ongoingCount)',
      'Completed ($completedCount)',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(filters.length, (idx) {
            final isSelected = _selectedFilter == idx;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filters[idx]),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedFilter = idx),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.onSurface,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
                showCheckmark: false,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isWorker, {required bool isFiltered}) {
    final scheme = Theme.of(context).colorScheme;

    String title;
    String subtitle;
    IconData icon;

    if (isFiltered) {
      if (_selectedFilter == 1) {
        title = isWorker ? 'No ongoing jobs' : 'No ongoing bookings';
        subtitle = isWorker
            ? 'Active jobs assigned to you will appear here.'
            : 'You do not have any active service requests right now.';
        icon = Icons.pending_actions_rounded;
      } else {
        title = isWorker ? 'No completed jobs' : 'No completed bookings';
        subtitle = isWorker
            ? 'Completed service jobs will appear here.'
            : 'Your past completed services will show up here.';
        icon = Icons.check_circle_outline_rounded;
      }
    } else {
      title = isWorker ? 'No jobs yet' : context.l10n.noOrdersYet;
      subtitle = isWorker
          ? 'Jobs assigned to you will appear here. Keep your availability online!'
          : 'Your completed and ongoing bookings will show up here.';
      icon = Icons.receipt_long_rounded;
    }

    return ListView(
      physics: appRefreshScrollPhysics,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
        if (!isWorker && !isFiltered) ...[
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => context.go(RouteNames.customerHome),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Explore Services'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderCard(BuildContext context, Booking order, bool isWorker, int index) {
    final scheme = Theme.of(context).colorScheme;
    final status = order.isCancelled && order.cancelledByWorker
        ? _StatusBadgeConfig(
            label: isWorker ? 'Declined' : 'Cancelled by Worker',
            color: const Color(0xFFDC2626),
            bgColor: const Color(0xFFFEE2E2),
            icon: Icons.cancel_rounded,
          )
        : order.needsReview(isWorker: isWorker)
            ? const _StatusBadgeConfig(
                label: 'Review Pending',
                color: Color(0xFFD97706),
                bgColor: Color(0xFFFEF3C7),
                icon: Icons.rate_review_rounded,
              )
            : _getStatusBadge(
                order.status,
                isWorker: isWorker,
                rawStatus: order.rawStatus,
                paymentStatus: order.paymentStatus,
              );
    final catColor = _categoryColor(order.serviceCategory);
    final catIcon = _categoryIcon(order.serviceCategory);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(RouteNames.bookingDetailPath(order.id)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row: Icon + Category/ID + Status Badge
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(catIcon, color: catColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (order.serviceCategory != null && order.serviceCategory!.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    localizeCategory(
                                      order.serviceCategory,
                                      context.l10n.locale,
                                    ).toUpperCase(),
                                    style: TextStyle(
                                      color: catColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (order.displayId != null && order.displayId!.isNotEmpty) ...[
                                if (order.serviceCategory != null && order.serviceCategory!.isNotEmpty)
                                  Text(
                                    ' • ',
                                    style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
                                  ),
                                Flexible(
                                  child: Text(
                                    order.displayId!,
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(order.scheduledAt ?? order.createdAt),
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: status.bgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: status.color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, size: 12, color: status.color),
                          const SizedBox(width: 4),
                          Text(
                            status.label,
                            style: TextStyle(
                              color: status.color,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Service Title
                Text(
                  order.serviceTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 10),

                // Who's working / Customer row
                _buildPersonRow(context, order, isWorker),

                // Address row
                if (order.address != null && order.address!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 10),

                // Footer: Price + Quick Action Button
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isWorker ? 'Earnings estimate' : 'Total estimate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '₹${order.totalPrice.toStringAsFixed(0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              if (order.paymentStatus != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: _buildPaymentStatusChip(order.paymentStatus!),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _buildQuickActionButton(context, order, isWorker),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).appListEnter(context, index: index, id: order.id);
  }

  Widget _buildPersonRow(BuildContext context, Booking order, bool isWorker) {
    final scheme = Theme.of(context).colorScheme;

    if (isWorker) {
      // Worker view: Customer details
      final name = order.customerName?.isNotEmpty == true ? order.customerName! : 'Customer';
      final phone = order.customerPhone;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey),
                  ),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (phone != null && phone.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_rounded, size: 13, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      // Customer view: Worker details + Arrival OTP if applicable
      final hasWorker = order.workerName?.isNotEmpty == true;
      final workerName = hasWorker ? order.workerName! : 'Assigning professional...';
      final showOtp = order.arrivalOtp != null &&
          !order.isAwaitingPayment &&
          order.status != BookingStatus.completed &&
          order.status != BookingStatus.paid &&
          !order.isCancelled;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: hasWorker
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              child: Icon(
                hasWorker ? Icons.engineering_rounded : Icons.search_rounded,
                size: 16,
                color: hasWorker ? AppColors.accent : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasWorker ? 'Assigned Professional' : 'Professional Status',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey),
                  ),
                  Text(
                    workerName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasWorker ? null : Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showOtp)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.key_rounded, size: 12, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      'OTP: ${order.arrivalOtp}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildQuickActionButton(BuildContext context, Booking order, bool isWorker) {
    if (order.isCancelled) {
      return Text(
        order.cancelledByWorker
            ? (isWorker ? 'You declined this job' : 'Cancelled by worker')
            : 'Order cancelled',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.red.shade700,
        ),
      );
    }

    if (!isWorker && order.isAwaitingPayment) {
      final amount = order.totalPrice;
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: () => context.push(
          '${RouteNames.customerPayment}?bookingId=${order.id}&amount=$amount',
        ),
        icon: const Icon(Icons.payments_rounded, size: 14),
        label: Text(
          amount > 0 ? 'Pay Now (₹${amount.toInt()})' : 'Pay Now',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (order.needsReview(isWorker: isWorker)) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD97706),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: () {
          if (isWorker) {
            context.push(
              RouteNames.workerRatingPath(
                order.id,
                customerId: order.customerId,
              ),
            );
          } else {
            context.push(RouteNames.customerRatingPath(order.id));
          }
        },
        icon: const Icon(Icons.rate_review_rounded, size: 14),
        label: Text(
          isWorker ? 'Rate Customer' : 'Give Review',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }

    final isOngoing = order.status == BookingStatus.accepted ||
        order.status == BookingStatus.arrived ||
        order.status == BookingStatus.inProgress;

    if (isOngoing) {
      if (isWorker) {
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () async {
            try {
              await BookingsApiRepository().startNavigation(order.id);
            } catch (_) {
              // Map still opens; GPS unlock is backup.
            }
            if (!context.mounted) return;
            context.push(
              '${RouteNames.workerNavigation}?bookingId=${order.id}',
            );
          },
          icon: const Icon(Icons.navigation_rounded, size: 14),
          label: const Text(
            'Navigate',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );
      }

      // Customer: Track only after worker starts navigation.
      if (order.workerHasStartedNavigation) {
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () => context.push(
            '${RouteNames.customerTracking}?bookingId=${order.id}',
          ),
          icon: const Icon(Icons.radar_rounded, size: 14),
          label: const Text(
            'Track',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );
      }

      if (order.status == BookingStatus.accepted ||
          order.status == BookingStatus.arrived) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFFD97706)),
                ),
              ),
              SizedBox(width: 6),
              Text(
                'Waiting…',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
        );
      }
    }

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => context.push(RouteNames.bookingDetailPath(order.id)),
      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
      label: const Text(
        'Details',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPaymentStatusChip(String paymentStatus) {
    final isPaid = paymentStatus.toLowerCase().contains('paid') ||
        paymentStatus.toLowerCase().contains('completed') ||
        paymentStatus.toLowerCase().contains('success');

    final color = isPaid ? const Color(0xFF059669) : const Color(0xFFD97706);
    final bgColor = isPaid ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7);
    final label = isPaid ? 'Paid' : 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Date unavailable';
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isYesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;
    final timeStr = DateFormat('h:mm a').format(dt);

    if (isToday) return 'Today, $timeStr';
    if (isYesterday) return 'Yesterday, $timeStr';
    return DateFormat('d MMM yyyy, h:mm a').format(dt);
  }
}

class _StatusBadgeConfig {
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _StatusBadgeConfig({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });
}

_StatusBadgeConfig _getStatusBadge(
  BookingStatus status, {
  required bool isWorker,
  String? rawStatus,
  String? paymentStatus,
}) {
  final raw = (rawStatus ?? '').toUpperCase();
  final pay = (paymentStatus ?? '').toUpperCase();
  final isPaid =
      status == BookingStatus.paid || pay == 'PAID' || raw == 'PAID' || raw == 'PAYMENT_PAID';
  final isAwaitingPayment = !isPaid &&
      (raw == 'PAYMENT_PENDING' ||
          raw == 'AWAITING_PAYMENT' ||
          (status == BookingStatus.completed &&
              raw != 'COMPLETED' &&
              pay != 'PAID'));

  if (isAwaitingPayment) {
    return const _StatusBadgeConfig(
      label: 'Payment Pending',
      color: Color(0xFFD97706),
      bgColor: Color(0xFFFEF3C7),
      icon: Icons.payments_outlined,
    );
  }

  switch (status) {
    case BookingStatus.searching:
    case BookingStatus.draft:
      return _StatusBadgeConfig(
        label: isWorker ? 'New Request' : 'Waiting for Worker',
        color: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        icon: Icons.hourglass_top_rounded,
      );
    case BookingStatus.accepted:
      return _StatusBadgeConfig(
        label: isWorker ? 'Accepted' : 'Worker Assigned',
        color: const Color(0xFF2563EB),
        bgColor: const Color(0xFFEFF6FF),
        icon: Icons.person_pin_circle_rounded,
      );
    case BookingStatus.arrived:
      return _StatusBadgeConfig(
        label: isWorker ? 'You Arrived' : 'Worker Arrived',
        color: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF5F3FF),
        icon: Icons.location_on_rounded,
      );
    case BookingStatus.inProgress:
      return const _StatusBadgeConfig(
        label: 'In Progress',
        color: Color(0xFF0284C7),
        bgColor: Color(0xFFE0F2FE),
        icon: Icons.construction_rounded,
      );
    case BookingStatus.completed:
    case BookingStatus.rating:
      return const _StatusBadgeConfig(
        label: 'Completed',
        color: Color(0xFF059669),
        bgColor: Color(0xFFECFDF5),
        icon: Icons.check_circle_rounded,
      );
    case BookingStatus.paid:
      return const _StatusBadgeConfig(
        label: 'Paid',
        color: Color(0xFF059669),
        bgColor: Color(0xFFECFDF5),
        icon: Icons.verified_rounded,
      );
    case BookingStatus.cancelled:
      return const _StatusBadgeConfig(
        label: 'Cancelled',
        color: Color(0xFFDC2626),
        bgColor: Color(0xFFFEE2E2),
        icon: Icons.cancel_rounded,
      );
  }
}

IconData _categoryIcon(String? category) {
  if (category == null) return Icons.handyman_rounded;
  final c = category.toLowerCase();
  if (c.contains('elect')) return Icons.bolt_rounded;
  if (c.contains('plumb')) return Icons.plumbing_rounded;
  if (c.contains('tech') || c.contains('appliance') || c.contains('geyser')) {
    return Icons.build_rounded;
  }
  if (c.contains('care') || c.contains('nurse')) return Icons.favorite_rounded;
  if (c.contains('clean')) return Icons.cleaning_services_rounded;
  if (c.contains('paint')) return Icons.format_paint_rounded;
  if (c.contains('carpen')) return Icons.carpenter_rounded;
  return Icons.handyman_rounded;
}

Color _categoryColor(String? category) {
  if (category == null) return AppColors.primary;
  final c = category.toLowerCase();
  if (c.contains('elect')) return const Color(0xFFEAB308);
  if (c.contains('plumb')) return const Color(0xFF0284C7);
  if (c.contains('tech') || c.contains('appliance')) return const Color(0xFF6366F1);
  if (c.contains('care') || c.contains('nurse')) return const Color(0xFFEC4899);
  if (c.contains('clean')) return const Color(0xFF10B981);
  if (c.contains('paint')) return const Color(0xFF8B5CF6);
  return AppColors.primary;
}
