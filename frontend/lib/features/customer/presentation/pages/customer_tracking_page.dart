import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/utils/rating_format.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/utils/tracking_helpers.dart';
import '../../../../core/widgets/fixly_map_view.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../cubit/booking_flow_cubit.dart';
import '../cubit/tracking_cubit.dart';

class CustomerTrackingPage extends StatefulWidget {
  const CustomerTrackingPage({super.key, this.bookingId});

  final String? bookingId;

  @override
  State<CustomerTrackingPage> createState() => _CustomerTrackingPageState();
}

class _CustomerTrackingPageState extends State<CustomerTrackingPage> {
  bool _followWorker = true;
  bool _leftForBookingDetail = false;

  @override
  void initState() {
    super.initState();
    final booking = context.read<BookingFlowCubit>().state.booking;
    final bookingId = widget.bookingId ?? booking?.id;
    if (bookingId != null && bookingId.isNotEmpty) {
      context.read<BookingFlowCubit>().listenToSocketUpdates(bookingId);
    }
    context.read<TrackingCubit>().startTracking(
      bookingId: bookingId,
      workerName: booking?.workerName,
      destination: booking?.customerLat == null || booking?.customerLng == null
          ? null
          : MapCoordinate(
              lat: booking!.customerLat!,
              lng: booking.customerLng!,
              label: "Worker's Destination",
            ),
    );
  }


  Future<void> _makeWebRTCCall(TrackingState state) async {
    final bookingId = state.bookingId ?? widget.bookingId;
    if (bookingId == null || bookingId.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Booking ID not available');
      return;
    }

    final peerName = state.workerName ?? 'Worker';
    final peerAvatar = state.workerAvatar;

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName,
        'peerRole': 'worker',
        'peerAvatar': peerAvatar,
        'serviceTitle': 'Fixly Service',
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName,
      expectedPeerRole: 'worker',
      expectedPeerAvatar: peerAvatar,
      expectedServiceTitle: 'Fixly Service',
    );

    if (!success && mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      body: MultiBlocListener(
        listeners: [
          BlocListener<TrackingCubit, TrackingState>(
            listenWhen: (previous, current) =>
                previous.phase != current.phase &&
                current.phase == TrackingPhase.arrived,
            listener: (context, state) {
              ToastUtils.showToast(
                context: context,
                message: 'Worker has arrived! Share your OTP to begin service.',
              );
            },
          ),
          BlocListener<BookingFlowCubit, BookingFlowState>(
            listenWhen: (previous, current) =>
                previous.step != current.step ||
                previous.booking?.rawStatus != current.booking?.rawStatus ||
                previous.booking?.paymentStatus != current.booking?.paymentStatus,
            listener: (context, state) {
              if (state.step == BookingStatus.paid ||
                  state.booking?.paymentStatus == 'PAID') {
                final id = state.booking?.id ?? widget.bookingId;
                if (id != null && id.isNotEmpty) {
                  context.goRefreshing(RouteNames.customerRatingPath(id));
                } else {
                  context.goRefreshing(RouteNames.customerRating);
                }
                return;
              }

              final raw = (state.booking?.rawStatus ?? '').toUpperCase();
              final arrivedOrWorking = state.step == BookingStatus.arrived ||
                  state.step == BookingStatus.inProgress ||
                  raw == 'ARRIVED' ||
                  raw == 'IN_PROGRESS' ||
                  raw == 'READY_TO_START' ||
                  raw == 'ESTIMATION_GIVEN' ||
                  raw == 'ESTIMATION_SUBMITTED';

              if (!arrivedOrWorking) return;

              final id = state.booking?.id ?? widget.bookingId;
              if (id == null || id.isEmpty || _leftForBookingDetail) return;
              _leftForBookingDetail = true;

              if (state.step == BookingStatus.arrived || raw == 'ARRIVED') {
                ToastUtils.showToast(
                  context: context,
                  message: 'Arrival verified — opening booking details.',
                );
              }

              context.goRefreshing(RouteNames.bookingDetailPath(id));
            },
          ),
        ],
        child: BlocBuilder<TrackingCubit, TrackingState>(
          builder: (context, state) {
            final booking = context.watch<BookingFlowCubit>().state.booking;
            final isAwaitingPayment = booking?.rawStatus == 'PAYMENT_PENDING' ||
                booking?.status == BookingStatus.completed;
            final isPaid = booking?.status == BookingStatus.paid ||
                booking?.paymentStatus == 'PAID';
            final target = state.customerPosition;
            final worker = state.workerPosition;
            final start = state.startPosition ?? worker;
            final distStr = TrackingHelpers.formatDistance(state.distanceMeters);
            final etaStr = TrackingHelpers.formatEta(state.etaMinutes);

            return Stack(
              children: [
                // 1. Full Screen Interactive Mapbox Map
                Positioned.fill(
                  child: FixlyMapView(
                    isCustomerView: true,
                    expand: true,
                    borderRadius: BorderRadius.zero,
                    center: worker ?? target,
                    zoom: MapConstants.navigationZoom,
                    routeStart: start,
                    routeEnd: target,
                    workerPosition: worker,
                    workerHeading: state.workerHeading,
                    routeCoordinates: state.routeCoordinates,
                    followWorker: _followWorker,
                    cameraFollowMinIntervalMs: 450,
                    claimGestures: true,
                    showZoomControls: true,
                    showRecenterButton: true,
                    show3DControl: true,
                    showNavigationOption: false,
                    controlsBottomPadding: 160.0,
                  ),
                ),

                // 2. Floating Top Header
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Back Button
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 4,
                          shadowColor: Colors.black26,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                final from = GoRouterState.of(context).uri.queryParameters['from'];
                                if (from == 'notifications') {
                                  context.go(RouteNames.sharedNotifications);
                                } else {
                                  context.goRefreshing(RouteNames.customerHome);
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Live Socket Connection Pill
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: state.isSocketConnected
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    state.isSocketConnected
                                        ? 'LIVE TRACKING ACTIVE'
                                        : 'SYNCING LOCATION...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: state.isSocketConnected
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF92400E),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Floating "Follow Worker" toggle
                Positioned(
                  right: 16,
                  top: 110,
                  child: Material(
                    color: _followWorker ? AppColors.primary : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: Colors.black26,
                    child: IconButton(
                      tooltip: _followWorker ? 'Free camera' : 'Follow bike',
                      icon: Icon(
                        _followWorker ? Icons.navigation : Icons.navigation_outlined,
                        color: _followWorker ? Colors.white : AppColors.primary,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() => _followWorker = !_followWorker);
                        ToastUtils.showToast(
                          context: context,
                          message: _followWorker ? 'Camera following worker' : 'Free map control enabled',
                        );
                      },
                    ),
                  ),
                ),

                // 4. Draggable Bottom Sheet with Worker & Booking Details
                DraggableScrollableSheet(
                  initialChildSize: 0.38,
                  minChildSize: 0.22,
                  maxChildSize: 0.65,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 16,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                        children: [
                          // Sheet Drag Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          // ETA & Distance Banner
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      etaStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$distStr away • ${state.phaseLabelFor(l10n.locale)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: state.phase == TrackingPhase.arrived
                                        ? const Color(0xFFD1FAE5)
                                        : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    state.phase == TrackingPhase.arrived
                                        ? 'ARRIVED'
                                        : 'ON THE WAY',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: state.phase == TrackingPhase.arrived
                                          ? const Color(0xFF065F46)
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Worker Info Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                  child: const Icon(Icons.person, color: AppColors.primary, size: 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.workerName ?? 'Assigned Professional',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 16,
                                            color: Color(0xFFF59E0B),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              [
                                                if (state.workerRating != null &&
                                                    state.workerRating! > 0)
                                                  '${formatRating(state.workerRating)} rating'
                                                else
                                                  'New · no ratings yet',
                                                'Bike en route',
                                              ].join(' • '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.phone, color: AppColors.primary),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    elevation: 2,
                                  ),
                                  onPressed: () => _makeWebRTCCall(state),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Start OTP Card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Start Service OTP',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                      Text(
                                        'Share with worker on arrival',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF59E0B)),
                                  ),
                                  child: Text(
                                    state.arrivalOtp ?? '8492',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Destination Address Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on, color: AppColors.accent, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.destination,
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        context.read<BookingFlowCubit>().state.address ??
                                            'Customer location',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (booking?.rawStatus == 'ESTIMATION_GIVEN' ||
                              booking?.rawStatus == 'ESTIMATION_SUBMITTED') ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              onPressed: () => context.push(
                                '${RouteNames.customerEstimationReview}?bookingId=${booking?.id ?? ''}',
                              ),
                              child: const Text('Review Price Estimation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ] else if (booking?.rawStatus == 'READY_TO_START') ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              onPressed: () async {
                                final id = booking?.id;
                                if (id == null || id.isEmpty) return;
                                try {
                                  await BookingsApiRepository().startJob(id);
                                  if (context.mounted) {
                                    context.read<BookingFlowCubit>().refreshBooking(id);
                                    ToastUtils.showSuccess(
                                      context: context,
                                      message: 'Work started',
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
                              child: const Text(
                                'Start Work',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ] else if (isPaid) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              onPressed: () {
                                final id = booking?.id ?? widget.bookingId;
                                if (id != null && id.isNotEmpty) {
                                  context.goRefreshing(RouteNames.customerRatingPath(id));
                                } else {
                                  context.goRefreshing(RouteNames.customerRating);
                                }
                              },
                              child: const Text('Rate & Review Specialist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ] else if (isAwaitingPayment) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              onPressed: () => context.push(
                                '${RouteNames.customerPayment}?bookingId=${booking?.id ?? ''}&amount=${booking?.totalPrice ?? 0}',
                              ),
                              child: Text(
                                'Pay Now (₹${(booking?.totalPrice ?? booking?.estimatedPrice ?? 0).toStringAsFixed(0)})',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
