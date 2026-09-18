import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/network/live_tracking_socket.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/utils/tracking_helpers.dart';
import '../../../../core/widgets/fixly_map_view.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';

class WorkerNavigationPage extends StatefulWidget {
  const WorkerNavigationPage({super.key, this.bookingId});

  final String? bookingId;

  @override
  State<WorkerNavigationPage> createState() => _WorkerNavigationPageState();
}

class _WorkerNavigationPageState extends State<WorkerNavigationPage> {
  final _bookings = BookingsApiRepository();
  final _socket = LiveTrackingSocket();

  WorkerJob? _job;
  MapCoordinate? _workerPosition;
  MapCoordinate? _startPosition;
  MapCoordinate? _destination;
  double? _workerHeading;
  List<MapCoordinate> _route = const [];
  MapCoordinate? _routeFrom;
  bool _routeLoading = false;
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _moveAnimTimer;

  bool _followWorker = true;
  bool _loading = true;
  bool _navigationStarted = false;
  bool _startNavApiSent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNavigation();
  }

  @override
  void dispose() {
    _moveAnimTimer?.cancel();
    _gpsSubscription?.cancel();
    _socket.disconnect();
    _socket.dispose();
    super.dispose();
  }

  Future<void> _loadNavigation() async {
    try {
      final job = widget.bookingId == null
          ? null
          : await _bookings.workerJobById(widget.bookingId!);

      final current = AppLocation.instance.coordinateOrNull;
      final destination =
          job == null || job.customerLat == null || job.customerLng == null
              ? (current != null
                  ? MapCoordinate(lat: current.lat + 0.012, lng: current.lng + 0.010, label: "Worker's Destination")
                  : MapConstants.current)
              : MapCoordinate(
                  lat: job.customerLat!,
                  lng: job.customerLng!,
                  label: "Worker's Destination",
                );

      // Determine initial worker departure location
      final workerStart = current ??
          (destination != null
              ? MapCoordinate(lat: destination.lat - 0.012, lng: destination.lng - 0.010, label: 'Worker Departure')
              : MapConstants.workerApproachStart);

      final initialHeading = (workerStart != null && destination != null)
          ? TrackingHelpers.bearingDegrees(workerStart, destination)
          : 0.0;

      if (!mounted) return;
      setState(() {
        _job = job;
        _workerPosition = workerStart;
        _startPosition = workerStart;
        _destination = destination;
        _workerHeading = initialHeading;
        _loading = false;
        _error = destination == null ? 'Waiting for location permission' : null;
      });

      // Unlock customer Track as soon as worker opens navigation screen.
      unawaited(_notifyNavigationStarted());

      await _loadRoute();

      // Connect to Socket.IO room for this booking so worker can broadcast location
      if (widget.bookingId != null) {
        _socket.connect(widget.bookingId!);

        // Broadcast initial location
        if (workerStart != null) {
          _broadcastLocation(workerStart, initialHeading);
        }
      }

      // Automatically start live GPS streaming
      await _startLiveGpsTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startLiveGpsTracking() async {
    await _gpsSubscription?.cancel();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      );

      _gpsSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen((Position position) {
        final prev = _workerPosition;
        final nextCoord = MapCoordinate(
          lat: position.latitude,
          lng: position.longitude,
        );

        final heading = TrackingHelpers.resolveBikeHeading(
          position: nextCoord,
          previous: prev,
          route: _route,
          reportedHeading: position.heading > 0 ? position.heading : null,
        );

        final updatedWorker = nextCoord.copyWith(heading: heading);
        if (!mounted) return;

        _animateWorkerTo(updatedWorker, heading);
        _broadcastLocation(updatedWorker, heading);
        unawaited(_loadRoute(from: updatedWorker));
      });
    } catch (e) {
      debugPrint('Error starting live GPS stream: $e');
    }
  }

  void _animateWorkerTo(MapCoordinate target, double heading) {
    final previous = _workerPosition ?? target;
    final jump = TrackingHelpers.distanceMeters(previous, target);
    if (jump < 1.5) {
      setState(() {
        _workerPosition = target;
        _workerHeading = heading;
        _navigationStarted = true;
      });
      return;
    }

    _moveAnimTimer?.cancel();
    final duration = TrackingHelpers.smoothMoveDuration(jump);
    const tickMs = 50;
    final totalTicks = math.max(1, (duration.inMilliseconds / tickMs).round());
    var tick = 0;
    _moveAnimTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick++;
      final linear = (tick / totalTicks).clamp(0.0, 1.0);
      final progress = TrackingHelpers.easeInOut(linear);
      final current = TrackingHelpers.lerpCoordinate(previous, target, progress);
      final frameHeading = TrackingHelpers.resolveBikeHeading(
        position: current,
        previous: previous,
        route: _route,
        reportedHeading: heading,
      );
      setState(() {
        _workerPosition = current.copyWith(heading: frameHeading);
        _workerHeading = frameHeading;
        _navigationStarted = true;
      });
      if (linear >= 1.0) timer.cancel();
    });
  }

  Future<void> _loadRoute({MapCoordinate? from}) async {
    final origin = from ?? _workerPosition;
    final to = _destination;
    if (origin == null || to == null || !MapConstants.hasToken) return;
    if (_routeLoading) return;
    if (_routeFrom != null &&
        _route.length >= 2 &&
        TrackingHelpers.distanceMeters(_routeFrom!, origin) < 120) {
      return;
    }
    _routeLoading = true;
    try {
      final route = await _bookings.fetchDrivingRoute(from: origin, to: to);
      if (mounted && route.length >= 2) {
        setState(() {
          _route = route;
          _routeFrom = origin;
        });
      }
    } catch (e) {
      debugPrint('WorkerNavigation._loadRoute: $e');
    } finally {
      _routeLoading = false;
    }
  }

  void _broadcastLocation(MapCoordinate pos, double heading) {
    final bookingId = widget.bookingId;
    if (bookingId == null) return;
    _socket.emitWorkerLocation(
      bookingId: bookingId,
      lat: pos.lat,
      lng: pos.lng,
      heading: heading,
    );
  }


  Future<void> _notifyNavigationStarted() async {
    if (_startNavApiSent) return;
    final bookingId = _job?.id ?? widget.bookingId;
    if (bookingId == null || bookingId.isEmpty) return;
    _startNavApiSent = true;
    try {
      await _bookings.startNavigation(bookingId);
    } catch (e) {
      _startNavApiSent = false;
      debugPrint('startNavigation API failed: $e');
      if (mounted) {
        ToastUtils.showToast(
          context: context,
          message: 'Navigation sync failed — keep GPS on; Track unlocks on live location',
        );
      }
    }
  }

  Future<void> _makeWebRTCCall() async {
    final bookingId = _job?.id ?? widget.bookingId;
    if (bookingId == null || bookingId.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Booking ID not available');
      return;
    }

    final customerName = _job?.customerName ?? 'Customer';

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': customerName,
        'peerRole': 'customer',
        'serviceTitle': _job?.title ?? 'Fixly Service',
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: customerName,
      expectedPeerRole: 'customer',
      expectedServiceTitle: _job?.title ?? 'Fixly Service',
    );

    if (!success && mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  void _showArrivalDialog() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter Customer Start OTP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask customer for the 4-digit OTP shown on their live tracking screen.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final otp = controller.text.trim();
                if (otp.length == 4 && widget.bookingId != null) {
                  Navigator.pop(ctx);
                  try {
                    await _bookings.verifyArrivalOtp(bookingId: widget.bookingId!, otp: otp);
                    if (mounted) {
                      ToastUtils.showToast(context: context, message: 'OTP verified! Arrived at customer.');
                      context.go(RouteNames.workerActiveJob);
                    }
                  } catch (e) {
                    if (mounted) {
                      ToastUtils.showToast(context: context, message: e.toString());
                    }
                  }
                }
              },
              child: const Text('Verify Arrival', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destination = _destination;
    final worker = _workerPosition;
    final start = _startPosition ?? worker;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navigation)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final distanceMeters = (worker != null && destination != null)
        ? TrackingHelpers.distanceMeters(worker, destination)
        : 1500.0;
    final distStr = TrackingHelpers.formatDistance(distanceMeters);
    final etaStr = TrackingHelpers.formatEta(TrackingHelpers.estimateEtaMinutes(distanceMeters));

    return PopScope(
      // Block edge-swipe / system back from dumping worker off the map.
      canPop: false,
      child: Scaffold(
      body: Stack(
        children: [
          // 1. Full Screen Interactive Navigation Map
          Positioned.fill(
            child: destination == null
                ? Center(child: Text(_error ?? 'Customer location unavailable'))
                : FixlyMapView(
                    isCustomerView: false,
                    expand: true,
                    borderRadius: BorderRadius.zero,
                    center: worker ?? destination,
                    zoom: MapConstants.navigationZoom,
                    routeStart: start,
                    routeEnd: destination,
                    workerPosition: worker,
                    workerHeading: _workerHeading,
                    routeCoordinates: _route,
                    followWorker: _followWorker,
                    // Smooth slide with GPS; leave zoom free for pinch / +/-.
                    cameraFollowMinIntervalMs: 320,
                    claimGestures: true,
                    showZoomControls: true,
                    showRecenterButton: true,
                    show3DControl: true,
                    showNavigationOption: true,
                    controlsBottomPadding: 160.0,
                    onNavigationChanged: (started) {
                      if (!started) return;
                      if (!mounted) return;
                      setState(() => _navigationStarted = true);
                      unawaited(_notifyNavigationStarted());
                    },
                  ),
          ),

          // 2. Turn-by-Turn HUD Top Card
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.navigation, color: Color(0xFF38BDF8), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _navigationStarted ? 'GPS Active • En Route' : 'Navigation Ready',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$distStr • $etaStr',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.gps_fixed, color: Color(0xFF10B981), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'REAL GPS',
                                  style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Follow Camera Toggle
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
                  _followWorker ? Icons.my_location : Icons.location_searching,
                  color: _followWorker ? Colors.white : AppColors.primary,
                  size: 22,
                ),
                onPressed: () => setState(() => _followWorker = !_followWorker),
              ),
            ),
          ),

          // 4. Bottom Card with Customer Details & Arrival Action
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.accent, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _job?.customerName ?? 'Customer',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                _job?.address ?? destination?.label ?? 'Customer Location',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: AppColors.primary),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFEFF6FF),
                          ),
                          onPressed: _makeWebRTCCall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _showArrivalDialog,
                      child: const Text('I Have Arrived', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
