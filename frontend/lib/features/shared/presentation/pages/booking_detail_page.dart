import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/customer_realtime_service.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/rating_format.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../payments/services/razorpay_checkout_service.dart';

class BookingDetailPage extends StatefulWidget {
  const BookingDetailPage({required this.bookingId, super.key});

  final String bookingId;

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage>
    with RefreshWhenNavigatedTo {
  final BookingsApiRepository _bookings = BookingsApiRepository();
  Booking? _booking;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<bool>? _connSub;

  @override
  List<String> get refreshRoutePaths => [RouteNames.bookingDetail];

  @override
  void onScreenRefresh() {
    unawaited(_load());
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load(initial: true));
  }

  @override
  void dispose() {
    _stopLive();
    super.dispose();
  }

  bool _isTerminal(Booking b) {
    if (b.isCancelled) return true;
    final raw = (b.rawStatus ?? '').toUpperCase();
    if (raw == 'CANCELLED' || raw == 'PAID') return true;
    return b.status == BookingStatus.paid || b.status == BookingStatus.rating;
  }

  bool _eventMatches(Map<String, dynamic> map, Booking booking) {
    final eventId = map['bookingId']?.toString();
    final canonical = map['canonicalBookingId']?.toString();
    return eventId == booking.id ||
        canonical == booking.id ||
        eventId == booking.displayId ||
        canonical == booking.displayId;
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final booking = await _bookings.getById(
        widget.bookingId,
        serviceTitle: _booking?.serviceTitle ?? 'Service',
        forceNetwork: true,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
        _error = null;
      });
      _bindLive();
    } catch (e) {
      if (!mounted) return;
      if (initial || _booking == null) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshBooking() async {
    final current = _booking;
    if (_refreshing || current == null) return;
    _refreshing = true;
    try {
      final updated = await _bookings.getById(
        current.id,
        serviceTitle: current.serviceTitle,
        forceNetwork: true,
      );
      if (!mounted) return;
      final changed = updated.status != current.status ||
          updated.rawStatus != current.rawStatus ||
          updated.workerHasStartedNavigation !=
              current.workerHasStartedNavigation ||
          updated.workerNavigationStartedAt !=
              current.workerNavigationStartedAt ||
          updated.paymentStatus != current.paymentStatus ||
          updated.arrivalOtp != current.arrivalOtp ||
          updated.workerName != current.workerName ||
          updated.workerId != current.workerId ||
          updated.jobStartedAt != current.jobStartedAt ||
          updated.jobCompletedAt != current.jobCompletedAt ||
          updated.workerEstimation != current.workerEstimation ||
          updated.totalAmount != current.totalAmount ||
          updated.extraPartsTotal != current.extraPartsTotal;
      if (!changed) return;
      setState(() => _booking = updated);
      if (_isTerminal(updated)) {
        _stopLive();
      }
    } catch (_) {
      // Next socket event / poll tick retries.
    } finally {
      _refreshing = false;
    }
  }

  void _stopLive() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusSub?.cancel();
    _statusSub = null;
    _connSub?.cancel();
    _connSub = null;
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshBooking());
    });
  }

  void _bindLive() {
    _stopLive();
    final booking = _booking;
    if (booking == null || !mounted) return;
    if (_isTerminal(booking)) return;

    final role =
        context.read<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    final userId = context.read<AppSessionCubit>().currentUser?.id;

    if (role == UserRole.worker) {
      if (userId != null && userId.isNotEmpty) {
        WorkerRealtimeService.instance.initForWorker(userId);
      }
      WorkerRealtimeService.instance.trackBooking(booking.id);

      _statusSub =
          WorkerRealtimeService.instance.bookingStatusStream.listen((map) {
        if (_booking == null || !_eventMatches(map, _booking!)) return;
        unawaited(_refreshBooking());
      });

      _startPoll();
      _connSub =
          WorkerRealtimeService.instance.connectionStream.listen((connected) {
        if (!mounted || _booking == null) return;
        if (connected) {
          WorkerRealtimeService.instance.trackBooking(_booking!.id);
          unawaited(_refreshBooking());
        }
        if (_pollTimer == null) _startPoll();
      });
      return;
    }

    if (userId != null && userId.isNotEmpty) {
      CustomerRealtimeService.instance.initForCustomer(userId);
    }
    CustomerRealtimeService.instance.trackBooking(booking.id);

    // Socket → instant full-screen refresh
    _statusSub =
        CustomerRealtimeService.instance.bookingStatusStream.listen((map) {
      if (_booking == null || !_eventMatches(map, _booking!)) return;
      unawaited(_refreshBooking());
    });

    // Poll every 5s as backup when socket down / silent
    _startPoll();
    _connSub =
        CustomerRealtimeService.instance.connectionStream.listen((connected) {
      if (!mounted || _booking == null) return;
      if (connected) {
        CustomerRealtimeService.instance.trackBooking(_booking!.id);
        unawaited(_refreshBooking());
      }
      // Keep 5s poll running either way — covers "connected but no events".
      if (_pollTimer == null) _startPoll();
    });
  }

  void _retry() => unawaited(_load(initial: _booking == null));

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Booking Details',
      padding: EdgeInsets.zero,
      showBack: true,
      body: _loading && _booking == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _booking == null
              ? _ErrorState(onRetry: _retry)
              : _BookingDetails(
                  booking: _booking!,
                  onRefresh: _refreshBooking,
                ),
    );
  }
}

class _BookingDetails extends StatelessWidget {
  const _BookingDetails({
    required this.booking,
    this.onRefresh,
  });

  final Booking booking;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    final isWorker = role == UserRole.worker;

    return RefreshIndicator(
      onRefresh: () async {
        await onRefresh?.call();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 1. Hero Header Card (Category, Title, Status, Schedule)
          _HeroHeaderCard(booking: booking, isWorker: isWorker),
          const SizedBox(height: 16),

          if (booking.status == BookingStatus.accepted ||
              booking.status == BookingStatus.arrived ||
              booking.status == BookingStatus.inProgress) ...[
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await BookingsApiRepository().triggerSos(booking.id);
                  if (context.mounted) {
                    ToastUtils.showSuccess(
                      context: context,
                      message: 'SOS alert sent for this booking',
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ToastUtils.showError(
                      context: context,
                      message: e.toString(),
                    );
                  }
                }
              },
              icon: const Icon(Icons.sos_rounded, color: Colors.red),
              label: const Text(
                'Trigger in-job SOS alert',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 2. Who's Working / Customer Info (Role-adaptive)
          _RoleAdaptivePartyCard(booking: booking, isWorker: isWorker),
          const SizedBox(height: 16),

          // 3. Arrival OTP Card (Customer view when worker accepted/arrived)
          if (!isWorker &&
              booking.arrivalOtp != null &&
              booking.arrivalOtp!.isNotEmpty &&
              (booking.status == BookingStatus.accepted ||
                  booking.status == BookingStatus.arrived ||
                  booking.status == BookingStatus.inProgress)) ...[
            _ArrivalOtpCard(otp: booking.arrivalOtp!),
            const SizedBox(height: 16),
          ],

          // 4. Job Details & Work Scope (What's the work)
          _JobScopeCard(booking: booking),
          const SizedBox(height: 16),

          // 5. Uploaded Media Evidence (Big 2-column Grid with full-screen tap)
          if (booking.problemPhotos.isNotEmpty || booking.problemVideos.isNotEmpty) ...[
            _UploadedMediaGridCard(booking: booking),
            const SizedBox(height: 16),
          ],

          // 6. Booking Progress Stepper
          _BookingProgressCard(booking: booking),
          const SizedBox(height: 16),

          // 7. Payment Summary & Pricing
          _PaymentSummaryCard(booking: booking, isWorker: isWorker),
          const SizedBox(height: 24),

          // 8. Actions (Role and status specific)
          _StatusActions(booking: booking, onRefresh: onRefresh),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Hero Header Card
// ---------------------------------------------------------------------------
class _HeroHeaderCard extends StatelessWidget {
  const _HeroHeaderCard({
    required this.booking,
    required this.isWorker,
  });

  final Booking booking;
  final bool isWorker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = booking.cancelledByWorker && !isWorker
        ? const _StatusBadgeConfig(
            label: 'Cancelled by Worker',
            color: Color(0xFFDC2626),
            bgColor: Color(0xFFFEE2E2),
            icon: Icons.cancel_rounded,
          )
        : booking.needsReview(isWorker: isWorker)
            ? const _StatusBadgeConfig(
                label: 'Review Pending',
                color: Color(0xFFD97706),
                bgColor: Color(0xFFFEF3C7),
                icon: Icons.rate_review_rounded,
              )
            : _getStatusBadge(
                booking.status,
                isWorker: isWorker,
                rawStatus: booking.rawStatus,
                paymentStatus: booking.paymentStatus,
              );
    final catColor = _categoryColor(booking.serviceCategory);
    final catIcon = _categoryIcon(booking.serviceCategory);
    final catLabel = () {
      final localized =
          localizeCategory(booking.serviceCategory, context.l10n.locale);
      return localized.isNotEmpty ? localized : 'Service';
    }();
    final scheduled = booking.scheduledAt;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Optional service image banner
          if (booking.serviceImage != null && booking.serviceImage!.isNotEmpty)
            Stack(
              children: [
                Image.network(
                  booking.serviceImage!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: catColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(catIcon, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              catLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _StatusBadgeWidget(badge: status),
                    ],
                  ),
                ),
              ],
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row if no service image banner
                if (booking.serviceImage == null || booking.serviceImage!.isEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(catIcon, size: 14, color: catColor),
                            const SizedBox(width: 6),
                            Text(
                              catLabel,
                              style: TextStyle(
                                color: catColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _StatusBadgeWidget(badge: status),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Title
                Text(
                  booking.serviceTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Booking ID with copy button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.displayId == null
                            ? 'Booking #${booking.id}'
                            : '${booking.displayId} • ${booking.id.length > 8 ? booking.id.substring(booking.id.length - 8) : booking.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: booking.displayId ?? booking.id));
                        ToastUtils.showToast(
                          context: context,
                          message: 'Booking ID copied to clipboard',
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Scheduled Time
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scheduled Time',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            scheduled != null
                                ? DateFormat('d MMM, h:mm a').format(scheduled)
                                : 'Immediate / As soon as available',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Role Adaptive Party Card (Who's Working / Customer Site)
// ---------------------------------------------------------------------------
class _RoleAdaptivePartyCard extends StatelessWidget {
  const _RoleAdaptivePartyCard({
    required this.booking,
    required this.isWorker,
  });

  final Booking booking;
  final bool isWorker;

  Future<void> _callCustomerViaWebRtc(BuildContext context) async {
    final bookingId = booking.id;
    if (bookingId.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Booking ID not available');
      return;
    }
    final peerName = booking.customerName ?? 'Customer';
    final peerAvatar = booking.customerAvatar;
    final serviceTitle = booking.serviceTitle;

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName,
        'peerRole': 'customer',
        'peerAvatar': peerAvatar,
        'serviceTitle': serviceTitle,
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName,
      expectedPeerRole: 'customer',
      expectedPeerAvatar: peerAvatar,
      expectedServiceTitle: serviceTitle,
    );

    if (!success && context.mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  Future<void> _callWorkerViaWebRtc(BuildContext context) async {
    final bookingId = booking.id;
    if (bookingId.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Booking ID not available');
      return;
    }
    final peerName = booking.workerName ?? 'Worker';
    final peerAvatar = booking.workerAvatar;
    final serviceTitle = booking.serviceTitle;

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName,
        'peerRole': 'worker',
        'peerAvatar': peerAvatar,
        'serviceTitle': serviceTitle,
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName,
      expectedPeerRole: 'worker',
      expectedPeerAvatar: peerAvatar,
      expectedServiceTitle: serviceTitle,
    );

    if (!success && context.mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  Future<void> _openLocationInMaps(BuildContext context) async {
    if (booking.customerLat != null && booking.customerLng != null) {
      final lat = booking.customerLat;
      final lng = booking.customerLng;
      final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (booking.address != null && booking.address!.isNotEmpty) {
      final encoded = Uri.encodeComponent(booking.address!);
      final url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (context.mounted) {
      ToastUtils.showToast(context: context, message: 'Address location unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isWorker) {
      // Worker view: Show Customer info & Site address
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Customer & Service Site',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Customer Name and Quick Call
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    (booking.customerName ?? 'C')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.customerName ?? 'Valued Customer',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        booking.customerPhone ?? 'Phone on file',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                    onPressed: () => _callCustomerViaWebRtc(context),
                    icon: const Icon(Icons.call_rounded, size: 16),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),

            if (booking.address != null && booking.address!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Address',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          booking.address!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openLocationInMaps(context),
                    icon: const Icon(Icons.directions_rounded, size: 16),
                    label: const Text('Map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Customer view: Show Assigned Professional or Matching Radar
    final hasWorker = booking.workerName != null && booking.workerName!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handyman_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Service Professional',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (hasWorker) ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: AppColors.primary.withValues(alpha: 0.1),
                    child: booking.workerAvatar != null &&
                            booking.workerAvatar!.isNotEmpty
                        ? Image.network(
                            booking.workerAvatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                booking.workerName![0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              booking.workerName![0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              booking.workerName!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Color(0xFF0284C7),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 12, color: Color(0xFFD97706)),
                                const SizedBox(width: 2),
                                Text(
                                  formatRating(booking.workerRating),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Fixly Verified Partner',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _callWorkerViaWebRtc(context),
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: const Text('Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Searching State / Matching
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Matching with nearby professional',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Available workers are reviewing your request. You\'ll receive an instant update.',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF92400E).withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (booking.address != null && booking.address!.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Service Address',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        booking.address!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Arrival OTP Card (High visual emphasis for customer security)
// ---------------------------------------------------------------------------
class _ArrivalOtpCard extends StatelessWidget {
  const _ArrivalOtpCard({required this.otp});

  final String otp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'START OF WORK OTP',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Share this code when worker arrives',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                tooltip: 'Copy OTP',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: otp));
                  ToastUtils.showToast(
                    context: context,
                    message: 'Arrival OTP copied to clipboard',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: otp.split('').map((char) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 38,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    char,
                    style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Job Scope Card (What's the work)
// ---------------------------------------------------------------------------
class _JobScopeCard extends StatelessWidget {
  const _JobScopeCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDesc = booking.problemDescription != null &&
        booking.problemDescription!.trim().isNotEmpty;
    final hasIncluded = booking.whatsIncluded.isNotEmpty;
    final hasParts = booking.addOns.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Job Scope & Description',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Problem Description
          if (hasDesc) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.8),
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reported Problem Description:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    booking.problemDescription!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Text(
              'No custom problem description provided.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // What's included in service
          if (hasIncluded) ...[
            Text(
              'What\'s Included in this Service:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in booking.whatsIncluded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Color(0xFF059669),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Extra parts added
          if (hasParts) ...[
            if (hasIncluded) const SizedBox(height: 14),
            Text(
              'Additional Parts & Materials:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final part in booking.addOns)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${part.title} (x${part.quantity})',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '₹${(part.price * part.quantity).toStringAsFixed(0)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
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
  }
}

// ---------------------------------------------------------------------------
// 5. Big Media Grid (Photos & Videos with full-screen tap)
// ---------------------------------------------------------------------------
class _UploadedMediaGridCard extends StatelessWidget {
  const _UploadedMediaGridCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = booking.problemPhotos;
    final videos = booking.problemVideos;
    final totalMedia = photos.length + videos.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.perm_media_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Problem Photos & Videos ($totalMedia)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap any item to preview in full screen',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 14),

          // 2-Column Responsive Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalMedia,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final isPhoto = index < photos.length;
              if (isPhoto) {
                final photoUrl = photos[index];
                final photoIndex = index + 1;
                return _PhotoGridItem(
                  url: photoUrl,
                  title: 'Photo $photoIndex of ${photos.length}',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullScreenImageViewer(
                          imageUrl: photoUrl,
                          title: 'Photo $photoIndex of ${photos.length}',
                        ),
                      ),
                    );
                  },
                );
              } else {
                final videoIndex = index - photos.length;
                final videoUrl = videos[videoIndex];
                final displayIndex = videoIndex + 1;
                return _VideoGridItem(
                  videoUrl: videoUrl,
                  title: 'Video $displayIndex of ${videos.length}',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _FullScreenVideoPlayer(
                          videoUrl: videoUrl,
                          title: 'Video $displayIndex of ${videos.length}',
                        ),
                      ),
                    );
                  },
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PhotoGridItem extends StatelessWidget {
  const _PhotoGridItem({
    required this.url,
    required this.title,
    required this.onTap,
  });

  final String url;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMediaImage(url),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.photo_camera_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Photo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoGridItem extends StatelessWidget {
  const _VideoGridItem({
    required this.videoUrl,
    required this.title,
    required this.onTap,
  });

  final String videoUrl;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF334155),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // Dark gradient backdrop
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                ),
              ),
            ),

            // Subtle pattern icon
            const Center(
              child: Icon(
                Icons.videocam_rounded,
                size: 48,
                color: Color(0xFF334155),
              ),
            ),

            // Centered Play Button
            Center(
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),

            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: Colors.black54,
                child: const Row(
                  children: [
                    Icon(Icons.videocam_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Tap to play',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildMediaImage(String pathOrUrl, {BoxFit fit = BoxFit.cover}) {
  if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
    return Image.network(
      pathOrUrl,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36),
      ),
    );
  } else {
    final file = File(pathOrUrl);
    return Image.file(
      file,
      fit: fit,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fullscreen Image Viewer
// ---------------------------------------------------------------------------
class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.title,
  });

  final String imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: _buildMediaImage(imageUrl, fit: BoxFit.contain),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Colors.black87,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pinch_rounded, color: Colors.white60, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Pinch to zoom • Double-tap to inspect',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fullscreen Interactive Video Player
// ---------------------------------------------------------------------------
class _FullScreenVideoPlayer extends StatefulWidget {
  const _FullScreenVideoPlayer({
    required this.videoUrl,
    required this.title,
  });

  final String videoUrl;
  final String title;

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final isNetwork = widget.videoUrl.startsWith('http://') ||
          widget.videoUrl.startsWith('https://');
      VideoPlayerController controller;

      if (isNetwork) {
        controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      } else {
        final file = File(widget.videoUrl);
        if (!await file.exists()) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Video file does not exist on device.';
            });
          }
          return;
        }
        controller = VideoPlayerController.file(file);
      }

      _controller = controller;
      await controller.initialize();
      controller.addListener(_onControllerUpdate);
      await controller.setLooping(true);
      await controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _scheduleHideControls();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Could not load video: $e';
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _scheduleHideControls();
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        controller.play();
        _scheduleHideControls();
      }
    });
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;

    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
              onPressed: _toggleMute,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 54),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage ?? 'Unable to play video',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : !_isInitialized || controller == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text('Buffering video...', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : GestureDetector(
                      onTap: _toggleControls,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),

                          // Play/Pause Overlay Button
                          if (_showControls)
                            AnimatedOpacity(
                              opacity: _showControls ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white30, width: 1.5),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    controller.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 38,
                                  ),
                                  onPressed: _togglePlayPause,
                                ),
                              ),
                            ),

                          // Bottom Progress & Timestamp Controls
                          if (_showControls)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                color: Colors.black87,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        activeTrackColor: AppColors.primary,
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: Colors.white,
                                      ),
                                      child: Slider(
                                        value: controller.value.position.inMilliseconds
                                            .clamp(0, controller.value.duration.inMilliseconds)
                                            .toDouble(),
                                        min: 0,
                                        max: controller.value.duration.inMilliseconds.toDouble(),
                                        onChanged: (val) {
                                          controller.seekTo(Duration(milliseconds: val.toInt()));
                                        },
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(controller.value.position),
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                        Text(
                                          _formatDuration(controller.value.duration),
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Booking Progress Stepper Card
// ---------------------------------------------------------------------------
class _BookingProgressCard extends StatelessWidget {
  const _BookingProgressCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = (booking.rawStatus ?? '').toUpperCase();
    final isPaid = booking.status == BookingStatus.paid ||
        (booking.paymentStatus ?? '').toUpperCase() == 'PAID' ||
        raw == 'PAID' ||
        raw == 'PAYMENT_PAID';
    final isAwaitingPayment = !isPaid &&
        (raw == 'PAYMENT_PENDING' ||
            raw == 'AWAITING_PAYMENT' ||
            (booking.status == BookingStatus.completed &&
                raw != 'COMPLETED' &&
                (booking.paymentStatus ?? '').toUpperCase() != 'PAID'));
    final workStarted = booking.jobStartedAt != null ||
        booking.status == BookingStatus.inProgress ||
        isAwaitingPayment ||
        isPaid;
    final arrivedOrLater = booking.status == BookingStatus.arrived ||
        booking.status == BookingStatus.inProgress ||
        isAwaitingPayment ||
        isPaid;

    final steps = [
      _ProgressStep(
        title: 'Booking Placed',
        subtitle: booking.createdAt != null
            ? DateFormat('d MMM, h:mm a').format(booking.createdAt!)
            : 'Order received',
        isDone: booking.createdAt != null,
        isActive: booking.status == BookingStatus.draft ||
            booking.status == BookingStatus.searching,
      ),
      _ProgressStep(
        title: 'Professional Assigned',
        subtitle: booking.workerName != null
            ? '${booking.workerName} assigned'
            : 'Matching nearby technician',
        isDone: booking.workerName != null &&
            booking.status != BookingStatus.searching &&
            booking.status != BookingStatus.draft,
        isActive: booking.status == BookingStatus.accepted,
      ),
      _ProgressStep(
        title: 'Technician Arrived',
        subtitle: 'At customer location',
        isDone: arrivedOrLater,
        isActive: booking.status == BookingStatus.arrived && !isAwaitingPayment,
      ),
      _ProgressStep(
        title: 'Work In Progress',
        subtitle: booking.jobStartedAt != null
            ? DateFormat('h:mm a').format(booking.jobStartedAt!)
            : 'Service execution',
        isDone: workStarted,
        isActive: booking.status == BookingStatus.inProgress,
      ),
      _ProgressStep(
        title: isPaid
            ? 'Paid & Complete'
            : (isAwaitingPayment ? 'Awaiting Payment' : 'Completed & Invoiced'),
        subtitle: isPaid
            ? (booking.jobCompletedAt != null
                ? DateFormat('d MMM, h:mm a').format(booking.jobCompletedAt!)
                : 'Payment received')
            : (isAwaitingPayment
                ? 'Invoice ready — pay to finish'
                : 'Not finished yet'),
        // Only tick when customer actually paid — not on PAYMENT_PENDING.
        isDone: isPaid,
        isActive: isAwaitingPayment,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.linear_scale_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Booking Timeline',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          for (int i = 0; i < steps.length; i++) ...[
            _ProgressStepRow(
              step: steps[i],
              isLast: i == steps.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressStep {
  final String title;
  final String subtitle;
  final bool isDone;
  final bool isActive;

  const _ProgressStep({
    required this.title,
    required this.subtitle,
    required this.isDone,
    required this.isActive,
  });
}

class _ProgressStepRow extends StatelessWidget {
  const _ProgressStepRow({
    required this.step,
    required this.isLast,
  });

  final _ProgressStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicatorColor = step.isDone
        ? const Color(0xFF059669)
        : step.isActive
            ? AppColors.primary
            : theme.hintColor.withValues(alpha: 0.3);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: step.isDone
                      ? const Color(0xFF059669)
                      : step.isActive
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: indicatorColor,
                    width: step.isActive ? 2 : 1.5,
                  ),
                ),
                child: Center(
                  child: step.isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : step.isActive
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: step.isDone
                        ? const Color(0xFF059669).withValues(alpha: 0.4)
                        : theme.dividerColor.withValues(alpha: 0.4),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: step.isDone || step.isActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: step.isDone || step.isActive
                          ? null
                          : theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Payment Summary & Pricing
// ---------------------------------------------------------------------------
class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.booking,
    this.isWorker = false,
  });

  final Booking booking;
  final bool isWorker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid = booking.status == BookingStatus.paid ||
        (booking.paymentStatus != null &&
            booking.paymentStatus!.toUpperCase() == 'PAID');
    final platform = booking.platformFee ?? booking.invoice?.platformFee ?? 0.0;
    final customerTotal =
        booking.totalAmount ?? booking.invoice?.totalAmount ?? booking.totalPrice;
    final workerTakeHome = booking.workerPayout;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isWorker ? 'Payout Breakdown' : 'Payment Breakdown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPaid ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaid ? Icons.check_circle_rounded : Icons.pending_rounded,
                        size: 12,
                        color: isPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isPaid ? 'PAID' : 'PAYMENT PENDING',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _ChargeRow(
            label: 'Base Service Fee',
            amount: booking.workerEstimation != null &&
                    booking.workerEstimation!.lockedBaseFee > 0
                ? booking.workerEstimation!.lockedBaseFee
                : (booking.invoice?.baseServiceFee ??
                    booking.baseServiceFee ??
                    booking.estimatedPrice),
          ),
          if ((booking.extraPartsTotal ?? 0) > 0 ||
              (booking.workerEstimation?.partsEstimate ?? 0) > 0 ||
              booking.addOns.isNotEmpty) ...[
            _ChargeRow(
              label: 'Extra Parts & Materials',
              amount: booking.workerEstimation?.partsEstimate ??
                  booking.extraPartsTotal ??
                  booking.addOns.fold<double>(
                    0.0,
                    (sum, a) => sum + (a.price * a.quantity),
                  ),
            ),
            for (final part in booking.addOns)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '• ${part.title} (x${part.quantity})',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                    Text(
                      '₹${(part.price * part.quantity).toStringAsFixed(0)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
          ],
          if ((booking.workerEstimation?.serviceCharge ?? 0) > 0)
            _ChargeRow(
              label: 'Service charge (extra work)',
              amount: booking.workerEstimation!.serviceCharge,
            ),
          if ((booking.urgentFee ?? 0) > 0)
            _ChargeRow(
              label: 'Emergency / Urgent Fee',
              amount: booking.urgentFee,
            ),
          if (platform > 0)
            _ChargeRow(
              label: isWorker
                  ? 'Platform fee (deducted)'
                  : 'Platform & Safety Fee',
              amount: isWorker ? -platform : platform,
            ),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          _ChargeRow(
            label: isWorker ? 'Your Payout' : 'Total Amount',
            amount: isWorker ? workerTakeHome : customerTotal,
            emphasize: true,
          ),
          if (isWorker && platform > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Customer paid ₹${customerTotal.toStringAsFixed(0)} · platform fee ₹${platform.toStringAsFixed(0)} deducted',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontSize: 11),
            ),
          ],

          if (booking.paymentMethod != null && booking.paymentMethod!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Method',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
                Text(
                  booking.paymentMethod!,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double? amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    if (amount == null && !emphasize) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final value = amount ?? 0;
    final isDeduction = value < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
              fontSize: emphasize ? 15 : 13,
            ),
          ),
          Text(
            isDeduction
                ? '-₹${value.abs().toStringAsFixed(0)}'
                : '₹${value.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: emphasize
                  ? AppColors.primary
                  : (isDeduction ? const Color(0xFFDC2626) : null),
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              fontSize: emphasize ? 17 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Role and Status Actions
// ---------------------------------------------------------------------------
class _StatusActions extends StatefulWidget {
  const _StatusActions({required this.booking, this.onRefresh});

  final Booking booking;
  final Future<void> Function()? onRefresh;

  @override
  State<_StatusActions> createState() => _StatusActionsState();
}

class _StatusActionsState extends State<_StatusActions> {
  final RazorpayCheckoutService _razorpay = RazorpayCheckoutService();
  final BookingsApiRepository _bookings = BookingsApiRepository();
  bool _isPaying = false;

  Booking get _booking => widget.booking;

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  Future<void> _handlePayment() async {
    final booking = _booking;
    final currentUser = context.read<AppSessionCubit>().currentUser;
    final amount = booking.totalAmount ?? booking.invoice?.totalAmount ?? booking.totalPrice;
    final raw = (booking.rawStatus ?? '').toUpperCase();
    const inProgressMsg =
        'The service is currently in progress. You cannot make a payment while the worker is actively working. Please wait until the worker completes the service.';

    if (booking.status == BookingStatus.inProgress || raw == 'IN_PROGRESS') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Payment unavailable'),
          content: const Text(inProgressMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (amount <= 0) {
      ToastUtils.showToast(context: context, message: 'Invalid payment amount');
      return;
    }

    setState(() => _isPaying = true);
    try {
      final verified = await _razorpay.processPayment(
        bookingId: booking.id,
        amountRupees: amount,
        description: '${booking.serviceTitle} payment',
        customerName: currentUser?.name ?? booking.customerName,
        email: currentUser?.email,
        phone: currentUser?.phone ?? booking.customerPhone,
      );

      if (!mounted) return;
      setState(() => _isPaying = false);

      if (verified) {
        ToastUtils.showToast(context: context, message: 'Payment successful!');
        widget.onRefresh?.call();
        context.goRefreshing(RouteNames.customerRatingPath(booking.id));
      } else {
        ToastUtils.showToast(context: context, message: 'Payment verification failed');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      final msg = e.message;
      if (msg.toLowerCase().contains('in progress') ||
          msg.toLowerCase().contains('actively working')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Payment unavailable'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ToastUtils.showError(context: context, message: msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      final msg = ApiException.fromError(e);
      ToastUtils.showError(context: context, message: msg);
    }
  }

  void _showEditBookingDialog(BuildContext context) {
    final descCtrl = TextEditingController(text: widget.booking.problemDescription ?? '');
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Problem Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Updating your problem description helps professionals understand the job requirements accurately.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Problem Description',
                  border: OutlineInputBorder(),
                  hintText: 'Describe the issue...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await BookingsApiRepository().updateBooking(
                  bookingId: widget.booking.id,
                  problemDescription: descCtrl.text.trim(),
                );
                if (context.mounted) {
                  ToastUtils.showToast(
                    context: context,
                    message: 'Booking details updated successfully!',
                  );
                  widget.onRefresh?.call();
                }
              } catch (e) {
                if (context.mounted) {
                  ToastUtils.showToast(
                    context: context,
                    message: 'Failed to update: $e',
                  );
                }
              }
            },
            child: const Text('Save & Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    final role = context.watch<AppSessionCubit>().currentUser?.role ?? UserRole.customer;
    final isWorker = role == UserRole.worker;
    final isPaid = booking.status == BookingStatus.paid ||
        (booking.paymentStatus != null &&
            booking.paymentStatus!.toUpperCase() == 'PAID');
    final amount = booking.totalAmount ?? booking.invoice?.totalAmount ?? booking.totalPrice;

    switch (booking.status) {
      case BookingStatus.cancelled:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.cancelledByWorker
                          ? 'Order cancelled by worker'
                          : 'Order cancelled',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (booking.cancelReason ?? booking.declineReason)
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? 'Reason: ${booking.cancelReason ?? booking.declineReason}'
                          : 'No further action needed on this booking.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case BookingStatus.searching:
      case BookingStatus.draft:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              label: 'Edit Problem Details',
              onPressed: () => _showEditBookingDialog(context),
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Cancel Booking Request',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Cancel Booking?'),
                    content: const Text(
                      'Are you sure you want to cancel this booking request?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('No, keep it'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Yes, cancel'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await BookingsApiRepository().cancel(booking.id);
                  if (context.mounted) context.pop();
                }
              },
            ),
          ],
        );

      case BookingStatus.accepted:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWorker)
              PrimaryButton(
                label: 'Open Navigation Map',
                onPressed: () async {
                  try {
                    await _bookings.startNavigation(booking.id);
                  } catch (_) {
                    // Map still opens; GPS unlock is backup.
                  }
                  if (!context.mounted) return;
                  context.push(
                    '${RouteNames.workerNavigation}?bookingId=${booking.id}',
                  );
                },
              )
            else if (booking.workerHasStartedNavigation)
              PrimaryButton(
                label: 'Track Worker Live',
                onPressed: () => context.push(
                  '${RouteNames.customerTracking}?bookingId=${booking.id}',
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFFD97706)),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Waiting for worker to start navigation…',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isWorker) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Edit Problem Details',
                onPressed: () => _showEditBookingDialog(context),
              ),
            ],
          ],
        );

      case BookingStatus.arrived:
        final raw = (booking.rawStatus ?? '').toUpperCase();
        final hasEstimation =
            raw == 'ESTIMATION_GIVEN' || raw == 'ESTIMATION_SUBMITTED';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isWorker && hasEstimation) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, color: Color(0xFF059669)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Worker sent a rough estimation for your review.',
                        style: TextStyle(
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PrimaryButton(
                label: 'Review Rough Estimation',
                onPressed: () => context.push(
                  '${RouteNames.customerEstimationReview}?bookingId=${booking.id}',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isWorker && !hasEstimation)
              PrimaryButton(
                label: 'Create Rough Estimation',
                onPressed: () => context.push(
                  '${RouteNames.workerPriceEstimation}?bookingId=${booking.id}',
                ),
              )
            else if (isWorker && hasEstimation)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Text(
                  'Waiting for customer to accept your rough estimation…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              )
            else if (!isWorker && booking.workerHasStartedNavigation)
              SecondaryButton(
                label: 'Track Worker Live',
                onPressed: () => context.push(
                  '${RouteNames.customerTracking}?bookingId=${booking.id}',
                ),
              ),
            if (isWorker) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'View Job Location on Map',
                onPressed: () => context.push(
                  '${RouteNames.workerNavigation}?bookingId=${booking.id}',
                ),
              ),
            ],
          ],
        );

      case BookingStatus.inProgress:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.construction_rounded, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text(
                    'Work is currently in progress...',
                    style: TextStyle(
                      color: Color(0xFF0369A1),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (!isWorker && !isPaid) ...[
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Pay Now (₹${amount.toInt()})',
                loading: _isPaying,
                onPressed: _isPaying ? null : () => _handlePayment(),
              ),
            ],
            if (isWorker) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'View Navigation Map',
                onPressed: () => context.push('${RouteNames.workerNavigation}?bookingId=${booking.id}'),
              ),
            ],
          ],
        );

      case BookingStatus.completed:
      case BookingStatus.rating:
      case BookingStatus.paid:
        if (booking.needsReview(isWorker: isWorker)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: isWorker ? 'Rate Customer' : 'Give Review',
                onPressed: () {
                  if (isWorker) {
                    context.push(
                      RouteNames.workerRatingPath(
                        booking.id,
                        customerId: booking.customerId,
                      ),
                    );
                  } else {
                    context.goRefreshing(RouteNames.customerRatingPath(booking.id));
                  }
                },
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Continue without review',
                onPressed: () {
                  if (isWorker) {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(RouteNames.workerJobs);
                    }
                    return;
                  }
                  context.push(
                    RouteNames.customerInvoice.replaceFirst(':id', booking.id),
                  );
                },
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              label: isPaid
                  ? 'View Invoice & Receipt'
                  : 'Pay Now (₹${amount.toInt()})',
              loading: _isPaying,
              onPressed: _isPaying
                  ? null
                  : () {
                      if (!isPaid) {
                        _handlePayment();
                        return;
                      }
                      context.push(
                        RouteNames.customerInvoice.replaceFirst(':id', booking.id),
                      );
                    },
            ),
          ],
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers & Components
// ---------------------------------------------------------------------------
class _StatusBadgeWidget extends StatelessWidget {
  const _StatusBadgeWidget({required this.badge});

  final _StatusBadgeConfig badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badge.bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badge.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 13, color: badge.color),
          const SizedBox(width: 5),
          Text(
            badge.label,
            style: TextStyle(
              color: badge.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
      label: 'Awaiting Payment',
      color: Color(0xFFD97706),
      bgColor: Color(0xFFFEF3C7),
      icon: Icons.payments_outlined,
    );
  }

  switch (status) {
    case BookingStatus.searching:
    case BookingStatus.draft:
      return _StatusBadgeConfig(
        label: isWorker ? 'New Request' : 'Searching for Worker',
        color: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        icon: Icons.hourglass_top_rounded,
      );
    case BookingStatus.accepted:
      return _StatusBadgeConfig(
        label: isWorker ? 'Job Accepted' : 'Worker Assigned',
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
      return _StatusBadgeConfig(
        label: isWorker ? 'Declined' : 'Cancelled',
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load booking details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check your network connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SecondaryButton(label: 'Try Again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
