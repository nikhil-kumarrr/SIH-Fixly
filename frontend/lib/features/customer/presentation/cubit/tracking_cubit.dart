import 'dart:async';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/map_constants.dart';
import '../../../../core/network/live_tracking_socket.dart';
import '../../../../core/utils/tracking_helpers.dart';
import '../../../../core/location/app_location.dart';
import '../../../bookings/data/bookings_api_repository.dart';

part 'tracking_state.dart';

class TrackingCubit extends Cubit<TrackingState> {
  TrackingCubit({BookingsApiRepository? bookings})
    : _bookings = bookings ?? BookingsApiRepository(),
      super(const TrackingState());

  final BookingsApiRepository _bookings;
  final LiveTrackingSocket _socket = LiveTrackingSocket();
  StreamSubscription<MapCoordinate>? _socketSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _pollTimer;
  Timer? _animationTimer;
  int _startGeneration = 0;

  /// Latest GPS we are animating toward / have accepted.
  MapCoordinate? _acceptedTarget;
  /// Newer socket point waiting until current ease finishes.
  MapCoordinate? _queuedTarget;
  bool _animating = false;

  bool get _alive => !isClosed;

  void _safeEmit(TrackingState state) {
    if (!_alive) return;
    emit(state);
  }

  Future<void> startTracking({
    String? bookingId,
    String? workerName,
    MapCoordinate? destination,
  }) async {
    final gen = ++_startGeneration;
    _pollTimer?.cancel();
    _animationTimer?.cancel();
    _animating = false;
    _acceptedTarget = null;
    _queuedTarget = null;
    await _socketSubscription?.cancel();
    await _connectionSubscription?.cancel();
    if (!_alive || gen != _startGeneration) return;

    var target = destination;
    var name = workerName;
    String? serviceTitle;
    String? arrivalOtp;
    String? workerPhone;
    double? workerRating;
    String? workerAvatar;
    MapCoordinate? initialWorkerPos;

    if (bookingId != null) {
      try {
        final booking = await _bookings.getById(bookingId);
        if (!_alive || gen != _startGeneration) return;
        target ??= booking.customerLat == null || booking.customerLng == null
            ? null
            : MapCoordinate(
                lat: booking.customerLat!,
                lng: booking.customerLng!,
                label: 'Customer',
              );
        name ??= booking.workerName;
        serviceTitle = booking.serviceTitle;
        arrivalOtp = booking.arrivalOtp;
        workerRating = booking.workerRating;
        workerAvatar = booking.workerAvatar;

        try {
          initialWorkerPos = await _bookings.trackWorkerPosition(bookingId);
        } catch (_) {}
        if (!_alive || gen != _startGeneration) return;
      } catch (_) {}
    }

    if (!_alive || gen != _startGeneration) return;

    target ??= AppLocation.instance.coordinateOrNull ?? MapConstants.current;

    if (initialWorkerPos == null && target != null) {
      initialWorkerPos = MapCoordinate(
        lat: target.lat - 0.010,
        lng: target.lng - 0.009,
        label: 'Worker Departure',
      );
    }

    final initialHeading = (initialWorkerPos != null && target != null)
        ? TrackingHelpers.bearingDegrees(initialWorkerPos, target)
        : 0.0;

    final initialDistance = (initialWorkerPos != null && target != null)
        ? TrackingHelpers.distanceMeters(initialWorkerPos, target)
        : 1200.0;

    final initialEta = TrackingHelpers.estimateEtaMinutes(initialDistance);

    _acceptedTarget = initialWorkerPos;

    _safeEmit(
      TrackingState(
        isActive: bookingId != null,
        bookingId: bookingId,
        workerName: name,
        serviceTitle: serviceTitle,
        arrivalOtp: arrivalOtp,
        workerPhone: workerPhone,
        workerRating: workerRating,
        workerAvatar: workerAvatar,
        workerPosition: initialWorkerPos,
        startPosition: initialWorkerPos,
        customerPosition: target,
        workerHeading: initialHeading,
        distanceMeters: initialDistance,
        etaMinutes: initialEta,
        phase: initialDistance <= 200
            ? TrackingPhase.arrived
            : TrackingPhase.enRoute,
        isSocketConnected: false,
      ),
    );

    if (!_alive || gen != _startGeneration) return;
    if (bookingId == null) return;

    if (initialWorkerPos != null && target != null) {
      unawaited(_loadRoute(initialWorkerPos, target, gen));
    }

    _socket.connect(bookingId);
    _socketSubscription = _socket.positions.listen((pos) {
      if (!_alive || gen != _startGeneration) return;
      _lastSocketTime = DateTime.now();
      _onPosition(pos, source: _PosSource.socket);
    });
    _connectionSubscription = _socket.connectionState.listen((connected) {
      if (!_alive || gen != _startGeneration) return;
      _safeEmit(state.copyWith(isSocketConnected: connected));
    });

    // Poll only as cold fallback when socket is dead — never fight live GPS.
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!_alive || gen != _startGeneration) return;
      if (_socket.isConnected) return;
      final last = _lastSocketTime;
      if (last != null && DateTime.now().difference(last).inSeconds < 15) {
        return;
      }
      try {
        final position = await _bookings.trackWorkerPosition(bookingId);
        if (!_alive || gen != _startGeneration) return;
        if (position != null) {
          _onPosition(position, source: _PosSource.poll);
        }
      } catch (_) {}
    });
  }

  DateTime? _lastSocketTime;
  int _lastPositionTimestamp = 0;
  MapCoordinate? _routeFrom;
  bool _routeLoading = false;
  static const _rerouteAfterMeters = 120.0;

  Future<void> _loadRoute(
    MapCoordinate from,
    MapCoordinate to,
    int gen, {
    bool force = false,
  }) async {
    if (_routeLoading && !force) return;
    if (!force &&
        _routeFrom != null &&
        TrackingHelpers.distanceMeters(_routeFrom!, from) < _rerouteAfterMeters &&
        state.routeCoordinates.length >= 2) {
      return;
    }
    _routeLoading = true;
    try {
      final route = await _bookings.fetchDrivingRoute(from: from, to: to);
      if (!_alive || gen != _startGeneration) return;
      if (route.length >= 2) {
        _routeFrom = from;
        _safeEmit(state.copyWith(routeCoordinates: route));
      }
    } catch (e) {
      debugPrint('TrackingCubit._loadRoute: $e');
    } finally {
      _routeLoading = false;
    }
  }

  void _onPosition(MapCoordinate position, {required _PosSource source}) {
    if (!_alive) return;

    if (position.timestamp != null && position.timestamp! > 0) {
      if (position.timestamp! < _lastPositionTimestamp) {
        return;
      }
      _lastPositionTimestamp = position.timestamp!;
    }

    final dest = state.customerPosition;
    final displayed = state.workerPosition ?? _acceptedTarget;
    final reference = _acceptedTarget ?? displayed;

    // Poll has no timestamp — never yank bike behind live accepted GPS.
    if (source == _PosSource.poll && reference != null && dest != null) {
      final pollDist = TrackingHelpers.distanceMeters(position, dest);
      final acceptedDist = TrackingHelpers.distanceMeters(reference, dest);
      if (pollDist > acceptedDist + 20) return;
    }

    if (reference != null && dest != null) {
      final jump = TrackingHelpers.distanceMeters(reference, position);
      final refToDest = TrackingHelpers.distanceMeters(reference, dest);
      final newToDest = TrackingHelpers.distanceMeters(position, dest);
      final regressMeters = newToDest - refToDest;

      // Noise / stale sample moving away from customer — drop it.
      // Allow big corrections (tunnel GPS snap, etc.).
      if (regressMeters > 18 && jump < 90) {
        return;
      }
    }

    final heading = TrackingHelpers.resolveBikeHeading(
      position: position,
      previous: displayed,
      route: state.routeCoordinates,
      reportedHeading: position.heading,
    );
    final targetPos = position.copyWith(heading: heading);

    // Same pattern as worker nav: finish current ease, then apply newest point.
    if (_animating) {
      final queued = _queuedTarget;
      if (queued != null && dest != null) {
        final qDist = TrackingHelpers.distanceMeters(queued, dest);
        final nDist = TrackingHelpers.distanceMeters(targetPos, dest);
        // Keep the better (closer-to-customer) pending target.
        if (nDist <= qDist + 5) {
          _queuedTarget = targetPos;
        }
      } else {
        _queuedTarget = targetPos;
      }
      return;
    }

    _animateTo(targetPos);
  }

  void _animateTo(MapCoordinate targetPos) {
    if (!_alive) return;

    final dest = state.customerPosition;
    final previous = state.workerPosition ?? targetPos;
    _acceptedTarget = targetPos;
    _queuedTarget = null;

    final heading = TrackingHelpers.resolveBikeHeading(
      position: targetPos,
      previous: previous,
      route: state.routeCoordinates,
      reportedHeading: targetPos.heading,
    );
    final aimed = targetPos.copyWith(heading: heading);

    if (dest == null) {
      _safeEmit(
        state.copyWith(
          workerPosition: aimed,
          workerHeading: heading,
        ),
      );
      return;
    }

    final totalDist = TrackingHelpers.distanceMeters(aimed, dest);
    final eta = TrackingHelpers.estimateEtaMinutes(totalDist);
    final phase = totalDist <= 150
        ? TrackingPhase.arrived
        : totalDist <= 800
            ? TrackingPhase.nearby
            : TrackingPhase.enRoute;

    final jumpMeters = TrackingHelpers.distanceMeters(previous, aimed);
    if (jumpMeters < 1.5) {
      _safeEmit(
        state.copyWith(
          workerPosition: aimed,
          workerHeading: heading,
          distanceMeters: totalDist,
          etaMinutes: eta,
          phase: phase,
          isActive: phase != TrackingPhase.arrived,
        ),
      );
      unawaited(_loadRoute(aimed, dest, _startGeneration));
      _drainQueue();
      return;
    }

    _animationTimer?.cancel();
    _animating = true;
    final duration = TrackingHelpers.smoothMoveDuration(jumpMeters);
    const tickMs = 50;
    final totalTicks = math.max(1, (duration.inMilliseconds / tickMs).round());
    var tick = 0;
    _animationTimer = Timer.periodic(const Duration(milliseconds: tickMs), (
      timer,
    ) {
      if (!_alive) {
        timer.cancel();
        _animating = false;
        return;
      }
      tick++;
      final linear = (tick / totalTicks).clamp(0.0, 1.0);
      final progress = TrackingHelpers.easeInOut(linear);
      final current =
          TrackingHelpers.lerpCoordinate(previous, aimed, progress);
      final frameHeading = TrackingHelpers.resolveBikeHeading(
        position: current,
        previous: previous,
        route: state.routeCoordinates,
        reportedHeading: heading,
      );

      _safeEmit(
        state.copyWith(
          workerPosition: current.copyWith(heading: frameHeading),
          workerHeading: frameHeading,
          distanceMeters: totalDist,
          etaMinutes: eta,
          phase: phase,
          isActive: phase != TrackingPhase.arrived,
        ),
      );
      if (linear >= 1.0) {
        timer.cancel();
        _animating = false;
        _drainQueue();
      }
    });

    unawaited(_loadRoute(aimed, dest, _startGeneration));
  }

  void _drainQueue() {
    final next = _queuedTarget;
    if (next == null || !_alive) return;
    _queuedTarget = null;
    _animateTo(next);
  }

  void reset() {
    _startGeneration++;
    _pollTimer?.cancel();
    _animationTimer?.cancel();
    _animating = false;
    _acceptedTarget = null;
    _queuedTarget = null;
    _socketSubscription?.cancel();
    _connectionSubscription?.cancel();
    _socket.disconnect();
    _safeEmit(const TrackingState());
  }

  @override
  Future<void> close() {
    _startGeneration++;
    _pollTimer?.cancel();
    _animationTimer?.cancel();
    _animating = false;
    _socketSubscription?.cancel();
    _connectionSubscription?.cancel();
    _socket.dispose();
    return super.close();
  }
}

enum _PosSource { socket, poll }
