import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../app/theme/app_colors.dart';
import '../constants/map_constants.dart';
import '../constants/map_geo_utils.dart';
import '../utils/navigation_math.dart';
import '../utils/tracking_helpers.dart';

/// Mapbox map with route, worker progress, and service-area circle.
class FixlyMapView extends StatefulWidget {
  const FixlyMapView({
    super.key,
    this.height = 260,
    this.expand = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.center,
    this.zoom = MapConstants.defaultZoom,
    this.routeEnd,
    this.routeProgress,
    this.serviceRadiusKm,
    this.showDestinationPin = true,
    this.showStartPin = true,
    this.showUserLocation = false,
    this.routeStart,
    this.workerPosition,
    this.followWorker = false,
    this.cameraFollowMinIntervalMs = 0,
    this.routeCoordinates = const [],
    this.workerHeading,
    this.claimGestures = false,
    this.showZoomControls = true,
    this.showRecenterButton = false,
    this.show3DControl = true,
    this.showCompassButton = true,
    this.showMovementControls = false,
    this.showNavigationOption = true,
    this.isCustomerView = true,
    this.initial3D = false,
    this.isNavigating,
    this.onNavigationChanged,
    this.controlsBottomPadding = 12.0,
    this.onLocationChanged,
    this.onMapIdled,
    this.onMapTap,
  });

  final double height;
  final bool expand;
  final BorderRadius borderRadius;
  final MapCoordinate? center;
  final double zoom;
  final MapCoordinate? routeEnd;
  final double? routeProgress;
  final double? serviceRadiusKm;
  final bool showDestinationPin;
  final bool showStartPin;
  final bool showUserLocation;

  /// Trip start origin pin (defaults to [MapConstants.workerApproachStart]).
  final MapCoordinate? routeStart;

  /// Moving worker position (displayed with bike icon).
  final MapCoordinate? workerPosition;

  /// Automatically keep camera centered on moving worker.
  final bool followWorker;

  /// Min ms between follow-camera eases (0 = every move). Customer tracking
  /// uses ~450 to avoid overlapping easeTo thrash that looks like reverse.
  final int cameraFollowMinIntervalMs;

  final List<MapCoordinate> routeCoordinates;
  final double? workerHeading;

  /// Win gesture arena vs parent [ScrollView] so user can pan/zoom the map.
  final bool claimGestures;

  /// Show floating '+' and '-' zoom buttons.
  final bool showZoomControls;

  /// Show floating recenter button to return to [center].
  final bool showRecenterButton;

  /// Show 2D/3D perspective toggle button.
  final bool show3DControl;

  /// Show compass button to reset rotation north.
  final bool showCompassButton;

  /// Show directional movement pan D-pad buttons.
  final bool showMovementControls;

  /// Show "Start Navigation" button for turn-by-turn navigation.
  final bool showNavigationOption;

  /// Whether map is viewed from customer perspective (destination = "Your Location")
  /// or worker perspective (destination = "Destination", worker = "Your Location").
  final bool isCustomerView;

  /// Initial 3D tilted camera perspective.
  final bool initial3D;

  /// Controlled navigation active state.
  final bool? isNavigating;

  /// Callback when navigation state toggles.
  final ValueChanged<bool>? onNavigationChanged;

  /// Bottom padding for map control buttons.
  final double controlsBottomPadding;

  /// Callback when user moves the map / center coordinate (fires continuously during drag).
  final ValueChanged<MapCoordinate>? onLocationChanged;

  /// Callback fired ONCE after map becomes idle (user stopped dragging).
  final ValueChanged<MapCoordinate>? onMapIdled;

  /// Callback when user taps anywhere on the map with the tapped coordinate.
  final ValueChanged<MapCoordinate>? onMapTap;

  @override
  State<FixlyMapView> createState() => _FixlyMapViewState();
}

class _FixlyMapViewState extends State<FixlyMapView> {
  static const double _zoomFollowThreshold = 14.5;

  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineManager;
  PolygonAnnotationManager? _polygonManager;
  PointAnnotationManager? _pointManager;
  PolylineAnnotation? _routeLine;
  PolygonAnnotation? _areaPolygon;
  PointAnnotation? _destinationMarker;
  PointAnnotation? _workerMarker;
  PointAnnotation? _startMarker;
  PointAnnotation? _userMarker;
  Uint8List? _startImage;
  Uint8List? _destinationMarkerImage;
  Uint8List? _bikeImage;
  Uint8List? _userLocationImage;
  String? _mapError;
  Timer? _idleDebounce;
  bool _isDisposed = false;
  bool _isRefreshing = false;
  bool _refreshQueued = false;
  bool _is3D = false;
  bool _isNavigating = false;
  CameraViewportState? _initialViewport;
  DateTime? _lastCameraFollowAt;

  @override
  void initState() {
    super.initState();
    _is3D = widget.initial3D;
    _isNavigating = widget.isNavigating ?? false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _idleDebounce?.cancel();
    _polylineManager = null;
    _polygonManager = null;
    _pointManager = null;
    _mapboxMap = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FixlyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isNavigating != null && widget.isNavigating != _isNavigating) {
      if (widget.isNavigating!) {
        _startNavigation();
      } else {
        _stopNavigation();
      }
    }

    if (oldWidget.center?.lat != widget.center?.lat ||
        oldWidget.center?.lng != widget.center?.lng ||
        oldWidget.zoom != widget.zoom) {
      final newCenter = widget.center ?? MapConstants.current;
      if (newCenter != null) {
        _initialViewport = CameraViewportState(
          center: Point(coordinates: Position(newCenter.lng, newCenter.lat)),
          zoom: widget.zoom,
        );
      }
    }
    if (_mapboxMap == null) return;

    final workerMoved =
        oldWidget.workerPosition?.lat != widget.workerPosition?.lat ||
        oldWidget.workerPosition?.lng != widget.workerPosition?.lng ||
        oldWidget.workerHeading != widget.workerHeading;

    if (workerMoved && widget.workerPosition != null) {
      _onWorkerMoved(widget.workerPosition!);
    }

    final roleChanged = oldWidget.isCustomerView != widget.isCustomerView;
    if (roleChanged) {
      _destinationMarkerImage = null;
    }

    final changed =
        roleChanged ||
        oldWidget.routeProgress != widget.routeProgress ||
        oldWidget.serviceRadiusKm != widget.serviceRadiusKm ||
        oldWidget.routeEnd != widget.routeEnd ||
        oldWidget.routeStart?.lat != widget.routeStart?.lat ||
        oldWidget.routeStart?.lng != widget.routeStart?.lng ||
        oldWidget.routeCoordinates != widget.routeCoordinates ||
        oldWidget.center?.lat != widget.center?.lat ||
        oldWidget.center?.lng != widget.center?.lng ||
        oldWidget.showDestinationPin != widget.showDestinationPin ||
        oldWidget.showStartPin != widget.showStartPin ||
        oldWidget.showUserLocation != widget.showUserLocation ||
        oldWidget.followWorker != widget.followWorker;

    if (changed) {
      _refreshAnnotations(fitCamera: false);
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _startImage = await _loadAsset('assets/icons/start.png');
    _destinationMarkerImage = await _createDestinationMarkerImage(
      isCustomerView: widget.isCustomerView,
    );
    _bikeImage = await _loadAsset('assets/icons/bike_marker.png');
    _userLocationImage = await _createUserLocationPuckImage();

    if (widget.showUserLocation) {
      try {
        await mapboxMap.location.updateSettings(
          LocationComponentSettings(enabled: true, pulsingEnabled: true),
        );
      } catch (e) {
        debugPrint('FixlyMapView locationComponent error: $e');
      }
    }

    try {
      await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
      await mapboxMap.logo.updateSettings(
        LogoSettings(marginBottom: 8, marginLeft: 8),
      );
      await mapboxMap.attribution.updateSettings(
        AttributionSettings(marginBottom: 8, marginRight: 8),
      );
      await mapboxMap.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          doubleTapToZoomInEnabled: true,
          doubleTouchToZoomOutEnabled: true,
          quickZoomEnabled: true,
          pitchEnabled: true,
          rotateEnabled: true,
        ),
      );
    } catch (e) {
      debugPrint('FixlyMapView mapbox settings error: $e');
    }

    // Safe resilient annotation manager initialization
    Future<void> initManagers() async {
      try {
        _polylineManager ??= await mapboxMap.annotations
            .createPolylineAnnotationManager();
      } catch (e) {
        debugPrint('FixlyMapView polylineManager init: $e');
      }
      try {
        _polygonManager ??= await mapboxMap.annotations
            .createPolygonAnnotationManager();
      } catch (e) {
        debugPrint('FixlyMapView polygonManager init: $e');
      }
      try {
        _pointManager ??= await mapboxMap.annotations
            .createPointAnnotationManager();
        // iconRotate relative to map north (not viewport) so 3D camera bearing
        // does not double-rotate the bike.
        await _pointManager?.setIconRotationAlignment(
          IconRotationAlignment.MAP,
        );
      } catch (e) {
        debugPrint('FixlyMapView pointManager init: $e');
      }
    }

    await initManagers();

    // If initial attempt missed due to channel binding / hot-restart, retry once after short delay
    if (_pointManager == null || _polylineManager == null) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_isDisposed && _mapboxMap == mapboxMap) {
        await initManagers();
      }
    }

    try {
      await _refreshAnnotations();
    } catch (e) {
      debugPrint('FixlyMapView refreshAnnotations error: $e');
    }
  }

  Future<Uint8List?> _loadAsset(String path) async {
    try {
      final data = await DefaultAssetBundle.of(context).load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _createDestinationMarkerImage({
    bool isCustomerView = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const double width = 64.0;
    const double height = 76.0;

    // Soft drop shadow at the ground touchpoint
    final shadowPaint = Paint()
      ..color = const Color(0x38000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(width / 2, height - 6),
        width: 22,
        height: 8,
      ),
      shadowPaint,
    );

    // Modern pin body pointing downward to (width / 2, height - 8)
    final path = Path();
    path.moveTo(width / 2, height - 8);
    path.cubicTo(
      width / 2 - 16,
      height - 28,
      width / 2 - 22,
      height - 42,
      width / 2 - 22,
      28,
    );
    path.arcToPoint(
      const Offset(width / 2 + 22, 28),
      radius: const Radius.circular(22),
    );
    path.cubicTo(
      width / 2 + 22,
      height - 42,
      width / 2 + 16,
      height - 28,
      width / 2,
      height - 8,
    );
    path.close();

    // Customer view: Primary Blue ("Your Location")
    // Worker view: Accent Coral/Red-Orange ("Destination")
    final pinColor = isCustomerView
        ? const Color(0xFF2563EB)
        : const Color(0xFFEA580C);
    final pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, pinPaint);

    // Crisp White Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawPath(path, borderPaint);

    // Inner White Disc
    final innerDiscPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(width / 2, 28), 10, innerDiscPaint);

    // Inner Focal Dot
    final innerDotColor = isCustomerView
        ? const Color(0xFF1D4ED8)
        : const Color(0xFFC2410C);
    final innerDotPaint = Paint()
      ..color = innerDotColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(width / 2, 28), 5.5, innerDotPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createUserLocationPuckImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 64.0;

    // Outer glow / pulse circle
    final outerPaint = Paint()
      ..color = const Color(0x332563EB)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), 26, outerPaint);

    // White ring
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), 15, borderPaint);

    // Inner bright blue dot
    final innerPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), 11, innerPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _onCameraChanged() {
    if (widget.onLocationChanged == null && widget.onMapIdled == null) return;
    _idleDebounce?.cancel();
    // Only fire onLocationChanged during drag (continuous updates).
    if (widget.onLocationChanged != null) {
      _idleDebounce = Timer(
        const Duration(milliseconds: 350),
        _notifyLocationChanged,
      );
    }
  }

  void _onMapIdle() {
    _idleDebounce?.cancel();
    if (widget.show3DControl && _mapboxMap != null) {
      _mapboxMap!
          .getCameraState()
          .then((camera) {
            final is3D = camera.pitch > 25.0;
            if (is3D != _is3D && mounted) {
              setState(() => _is3D = is3D);
            }
          })
          .catchError((_) {});
    }
    // Fire onMapIdled ONCE when map becomes idle.
    if (widget.onMapIdled != null) {
      _notifyMapIdled();
    } else if (widget.onLocationChanged != null) {
      // Legacy: fallback for callers that only use onLocationChanged.
      _notifyLocationChanged();
    }
  }

  Future<void> _notifyLocationChanged() async {
    final map = _mapboxMap;
    if (map == null || !mounted || widget.onLocationChanged == null) return;
    try {
      final camera = await map.getCameraState();
      final lat = camera.center.coordinates.lat.toDouble();
      final lng = camera.center.coordinates.lng.toDouble();
      widget.onLocationChanged!(MapCoordinate(lat: lat, lng: lng));
    } catch (e) {
      debugPrint('FixlyMapView _notifyLocationChanged error: $e');
    }
  }

  Future<void> _notifyMapIdled() async {
    final map = _mapboxMap;
    if (map == null || !mounted || widget.onMapIdled == null) return;
    try {
      final camera = await map.getCameraState();
      final lat = camera.center.coordinates.lat.toDouble();
      final lng = camera.center.coordinates.lng.toDouble();
      widget.onMapIdled!(MapCoordinate(lat: lat, lng: lng));
    } catch (e) {
      debugPrint('FixlyMapView _notifyMapIdled error: $e');
    }
  }

  Future<void> _zoomIn() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      await mapboxMap.easeTo(
        CameraOptions(zoom: (camera.zoom + 1.2).clamp(2.0, 20.0)),
        MapAnimationOptions(duration: 300),
      );
    } catch (e) {
      debugPrint('FixlyMapView zoomIn error: $e');
    }
  }

  Future<void> _zoomOut() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      await mapboxMap.easeTo(
        CameraOptions(zoom: (camera.zoom - 1.2).clamp(2.0, 20.0)),
        MapAnimationOptions(duration: 300),
      );
    } catch (e) {
      debugPrint('FixlyMapView zoomOut error: $e');
    }
  }

  Future<void> _recenter() async {
    final mapboxMap = _mapboxMap;
    final target =
        widget.workerPosition ?? widget.center ?? MapConstants.current;
    if (mapboxMap == null || target == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      final heading = widget.workerHeading ?? target.heading ?? 0.0;
      final lookAhead = _lookAheadMeters(camera.zoom, navigating: _isNavigating);
      final center = (_isNavigating && heading != 0.0)
          ? _calculateLookAheadCoordinate(target, heading, lookAhead)
          : target;
      await mapboxMap.easeTo(
        CameraOptions(
          center: Point(coordinates: Position(center.lng, center.lat)),
          // Keep worker's chosen zoom; only nudge pitch/bearing for nav.
          pitch: _isNavigating ? 58.0 : (_is3D ? 60.0 : camera.pitch),
          bearing: _isNavigating ? heading : camera.bearing,
        ),
        MapAnimationOptions(duration: 400),
      );
    } catch (e) {
      debugPrint('FixlyMapView recenter error: $e');
    }
  }

  Future<void> _toggle3D() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      final isCurrently3D = camera.pitch > 25.0;
      final targetPitch = isCurrently3D ? 0.0 : 60.0;
      final next3D = !isCurrently3D;

      final heading =
          widget.workerHeading ??
          widget.workerPosition?.heading ??
          camera.bearing;

      await mapboxMap.easeTo(
        CameraOptions(
          center: camera.center,
          zoom: next3D ? math.max(camera.zoom, 15.5) : camera.zoom,
          bearing: next3D && heading != 0.0 ? heading : camera.bearing,
          pitch: targetPitch,
        ),
        MapAnimationOptions(duration: 450),
      );
      if (mounted) setState(() => _is3D = next3D);
    } catch (e) {
      debugPrint('FixlyMapView toggle3D error: $e');
    }
  }

  Future<void> _resetBearing() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      await mapboxMap.easeTo(
        CameraOptions(
          center: camera.center,
          zoom: camera.zoom,
          bearing: 0.0,
          pitch: camera.pitch,
        ),
        MapAnimationOptions(duration: 350),
      );
    } catch (e) {
      debugPrint('FixlyMapView resetBearing error: $e');
    }
  }

  Future<void> _panByDirection(double dx, double dy) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final camera = await mapboxMap.getCameraState();
      final currentLat = camera.center.coordinates.lat.toDouble();
      final currentLng = camera.center.coordinates.lng.toDouble();
      final zoom = camera.zoom;
      final step = (0.003 * math.pow(2, 14.5 - zoom)).clamp(0.0002, 0.05);
      final latRad = currentLat * math.pi / 180.0;
      final cosLat = math.cos(latRad).abs().clamp(0.01, 1.0);
      final newLat = (currentLat + dy * step).clamp(-85.0, 85.0);
      final newLng =
          ((currentLng + dx * (step / cosLat) + 180.0) % 360.0) - 180.0;
      await mapboxMap.easeTo(
        CameraOptions(center: Point(coordinates: Position(newLng, newLat))),
        MapAnimationOptions(duration: 200),
      );
    } catch (e) {
      debugPrint('FixlyMapView pan error: $e');
    }
  }

  /// Bike faces travel direction along the blue route when available.
  double _bikeRotation(MapCoordinate worker) {
    final along = TrackingHelpers.headingAlongRoute(
      worker,
      widget.routeCoordinates,
    );
    if (along != null) return along;
    return TrackingHelpers.normalizeHeading(
      widget.workerHeading ??
          worker.heading ??
          (widget.routeEnd != null
              ? NavigationMath.bearingDegrees(worker, widget.routeEnd!)
              : 0.0),
    );
  }

  MapCoordinate _calculateLookAheadCoordinate(
    MapCoordinate pos,
    double headingDegrees,
    double distanceMeters,
  ) {
    const earthRadius = 6371000.0;
    final rad = headingDegrees * math.pi / 180.0;
    final dLat =
        (distanceMeters * math.cos(rad)) / earthRadius * (180.0 / math.pi);
    final cosLat = math.cos(pos.lat * math.pi / 180.0);
    final safeCos = cosLat.abs() < 0.001 ? 0.001 : cosLat;
    final dLng =
        (distanceMeters * math.sin(rad)) /
        (earthRadius * safeCos) *
        (180.0 / math.pi);
    return MapCoordinate(
      lat: (pos.lat + dLat).clamp(-85.0, 85.0),
      lng: ((pos.lng + dLng + 180.0) % 360.0) - 180.0,
      heading: headingDegrees,
    );
  }

  Future<void> _onWorkerMoved(MapCoordinate worker) async {
    final map = _mapboxMap;
    if (map == null || _isDisposed) return;

    // Immediately update live worker pin geometry & rotation
    if (_workerMarker != null && _pointManager != null) {
      final rotation = _bikeRotation(worker);
      try {
        _workerMarker!
          ..geometry = Point(coordinates: Position(worker.lng, worker.lat))
          ..iconRotate = rotation;
        await _pointManager!.update(_workerMarker!);
      } catch (_) {}
    }

    if (_isNavigating && mounted) {
      setState(() {});
    }

    try {
      final camera = await map.getCameraState();
      final currentZoom = camera.zoom;

      // Follow at any zoom when navigating / followWorker — never force zoom.
      if (!widget.followWorker &&
          !_isNavigating &&
          currentZoom < _zoomFollowThreshold) {
        return;
      }

      final minInterval = widget.cameraFollowMinIntervalMs;
      if (minInterval > 0) {
        final now = DateTime.now();
        final last = _lastCameraFollowAt;
        if (last != null &&
            now.difference(last).inMilliseconds < minInterval) {
          return;
        }
        _lastCameraFollowAt = now;
      }

      final heading = widget.workerHeading ?? worker.heading ?? camera.bearing;
      final targetPitch = _isNavigating ? 58.0 : (_is3D ? 60.0 : camera.pitch);
      final targetBearing = _isNavigating ? heading : camera.bearing;
      final lookAhead = _lookAheadMeters(currentZoom, navigating: _isNavigating);

      // Offset camera forward so worker sees road ahead at their chosen zoom.
      final targetCoord = (targetPitch > 20.0 && heading != 0.0)
          ? _calculateLookAheadCoordinate(worker, heading, lookAhead)
          : worker;

      // Omit zoom — preserve whatever worker set with pinch / +/- buttons.
      await map.easeTo(
        CameraOptions(
          center: Point(
            coordinates: Position(targetCoord.lng, targetCoord.lat),
          ),
          pitch: targetPitch,
          bearing: targetBearing,
        ),
        MapAnimationOptions(duration: minInterval > 0 ? minInterval : 400),
      );
    } catch (e) {
      debugPrint('FixlyMapView _onWorkerMoved camera error: $e');
    }
  }

  /// Look-ahead grows when zoomed in so forward road stays on screen.
  double _lookAheadMeters(double zoom, {required bool navigating}) {
    if (!navigating) return 28.0;
    return (45.0 * math.pow(2, zoom - 17.5)).clamp(25.0, 200.0).toDouble();
  }

  Future<void> _startNavigation() async {
    final map = _mapboxMap;
    if (map == null || _isDisposed) return;

    final targetWorker =
        widget.workerPosition ??
        widget.routeStart ??
        widget.center ??
        MapConstants.current;
    if (targetWorker == null) return;

    setState(() {
      _isNavigating = true;
      _is3D = true;
    });
    widget.onNavigationChanged?.call(true);

    try {
      final heading =
          widget.workerHeading ??
          targetWorker.heading ??
          (widget.routeEnd != null
              ? NavigationMath.bearingDegrees(targetWorker, widget.routeEnd!)
              : 0.0);

      const targetZoom = 17.8;
      const targetPitch = 58.0;

      final targetCoord = heading != 0.0
          ? _calculateLookAheadCoordinate(targetWorker, heading, 45.0)
          : targetWorker;

      await map.easeTo(
        CameraOptions(
          center: Point(
            coordinates: Position(targetCoord.lng, targetCoord.lat),
          ),
          zoom: targetZoom,
          pitch: targetPitch,
          bearing: heading,
        ),
        MapAnimationOptions(duration: 650),
      );
    } catch (e) {
      debugPrint('FixlyMapView _startNavigation error: $e');
    }
  }

  Future<void> _stopNavigation() async {
    setState(() => _isNavigating = false);
    widget.onNavigationChanged?.call(false);
    await _fitCamera();
  }

  _ManeuverInfo _getCurrentManeuver() {
    final destination = widget.routeEnd ?? widget.center;
    final worker = widget.workerPosition ?? widget.routeStart ?? widget.center;

    if (destination == null || worker == null) {
      return const _ManeuverInfo(
        icon: Icons.navigation_rounded,
        title: 'Navigating route',
        subtitle: 'Follow highlighted path',
        distanceToManeuver: 0,
      );
    }

    final totalDist = TrackingHelpers.distanceMeters(worker, destination);
    final distStr = TrackingHelpers.formatDistance(totalDist);
    final etaStr = TrackingHelpers.formatEta(
      TrackingHelpers.estimateEtaMinutes(totalDist),
    );

    if (totalDist <= 35.0) {
      return _ManeuverInfo(
        icon: Icons.sports_score_rounded,
        title: 'You have arrived!',
        subtitle: widget.isCustomerView
            ? 'Worker has arrived at your location'
            : 'Arrived at customer destination',
        distanceToManeuver: totalDist,
      );
    }

    final coords = widget.routeCoordinates;
    if (coords.length >= 3) {
      int closestIdx = 0;
      double minD = double.infinity;
      for (int i = 0; i < coords.length; i++) {
        final d = TrackingHelpers.distanceMeters(worker, coords[i]);
        if (d < minD) {
          minD = d;
          closestIdx = i;
        }
      }

      for (int i = closestIdx + 1; i < coords.length - 1; i++) {
        final b1 = NavigationMath.bearingDegrees(coords[i - 1], coords[i]);
        final b2 = NavigationMath.bearingDegrees(coords[i], coords[i + 1]);
        var diff = (b2 - b1) % 360.0;
        if (diff > 180.0) diff -= 360.0;
        if (diff < -180.0) diff += 360.0;

        if (diff.abs() >= 20.0) {
          double distToTurn = TrackingHelpers.distanceMeters(
            worker,
            coords[closestIdx],
          );
          for (int j = closestIdx; j < i; j++) {
            distToTurn += TrackingHelpers.distanceMeters(
              coords[j],
              coords[j + 1],
            );
          }

          final IconData turnIcon;
          final String turnName;
          if (diff > 45) {
            turnIcon = Icons.turn_right_rounded;
            turnName = 'Turn right';
          } else if (diff > 15) {
            turnIcon = Icons.turn_slight_right_rounded;
            turnName = 'Slight right';
          } else if (diff < -45) {
            turnIcon = Icons.turn_left_rounded;
            turnName = 'Turn left';
          } else {
            turnIcon = Icons.turn_slight_left_rounded;
            turnName = 'Slight left';
          }

          final formattedDistToTurn = TrackingHelpers.formatDistance(
            distToTurn,
          );
          return _ManeuverInfo(
            icon: turnIcon,
            title: 'In $formattedDistToTurn, $turnName',
            subtitle: '$distStr remaining • $etaStr',
            distanceToManeuver: distToTurn,
          );
        }
      }
    }

    return _ManeuverInfo(
      icon: Icons.straight_rounded,
      title:
          'Head toward ${widget.isCustomerView ? "Your Location" : "Destination"}',
      subtitle: '$distStr • $etaStr',
      distanceToManeuver: totalDist,
    );
  }

  Widget _buildNavigationHUD() {
    final maneuver = _getCurrentManeuver();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(maneuver.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  maneuver.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  maneuver.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _stopNavigation,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartNavigationButton() {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        onTap: _startNavigation,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.navigation_rounded,
                color: Color(0xFF38BDF8),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Start Navigation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshAnnotations({bool fitCamera = true}) async {
    if (_isDisposed || !mounted || _mapboxMap == null) return;

    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }
    _isRefreshing = true;

    try {
      final polylineManager = _polylineManager;
      final polygonManager = _polygonManager;
      final pointManager = _pointManager;
      if (polylineManager == null ||
          polygonManager == null ||
          pointManager == null) {
        return;
      }

      final destination =
          widget.routeEnd ?? widget.center ?? MapConstants.current;
      if (destination == null) {
        return;
      }
      final start =
          widget.routeStart ??
          (widget.routeEnd != null ? MapConstants.workerApproachStart : null);
      final worker =
          widget.workerPosition ??
          (widget.routeEnd == null || start == null
              ? null
              : MapConstants.lerpRoute(
                  start,
                  widget.routeEnd!,
                  widget.routeProgress ?? 0,
                ));

      if (widget.serviceRadiusKm != null) {
        final polygon = MapGeoUtils.geodesicCirclePolygon(
          lat: destination.lat,
          lng: destination.lng,
          radiusKm: widget.serviceRadiusKm!,
        );
        final areaOptions = PolygonAnnotationOptions(
          geometry: polygon,
          fillColor: AppColors.primary.withValues(alpha: 0.18).toARGB32(),
          fillOutlineColor: AppColors.primary
              .withValues(alpha: 0.85)
              .toARGB32(),
          fillOpacity: 0.75,
        );
        try {
          if (_areaPolygon == null) {
            _areaPolygon = await polygonManager.create(areaOptions);
          } else {
            _areaPolygon!
              ..geometry = areaOptions.geometry
              ..fillColor = areaOptions.fillColor
              ..fillOutlineColor = areaOptions.fillOutlineColor
              ..fillOpacity = areaOptions.fillOpacity;
            await polygonManager.update(_areaPolygon!);
          }
        } catch (_) {
          _areaPolygon = null;
        }
      } else if (_areaPolygon != null) {
        try {
          await polygonManager.delete(_areaPolygon!);
        } catch (_) {}
        _areaPolygon = null;
      }

      if (widget.routeCoordinates.length >= 2) {
        final coordinates = widget.routeCoordinates;
        final route = LineString(
          coordinates: coordinates
              .map((coordinate) => Position(coordinate.lng, coordinate.lat))
              .toList(),
        );
        final routeOptions = PolylineAnnotationOptions(
          geometry: route,
          lineColor: AppColors.primary.toARGB32(),
          lineWidth: 5,
          lineOpacity: 0.95,
          lineJoin: LineJoin.ROUND,
          lineBorderColor: Colors.white.toARGB32(),
          lineBorderWidth: 1.5,
        );
        try {
          if (_routeLine == null) {
            _routeLine = await polylineManager.create(routeOptions);
          } else {
            _routeLine!
              ..geometry = routeOptions.geometry
              ..lineColor = routeOptions.lineColor
              ..lineWidth = routeOptions.lineWidth;
            await polylineManager.update(_routeLine!);
          }
        } catch (_) {
          _routeLine = null;
        }
      } else if (_routeLine != null) {
        try {
          await polylineManager.delete(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }

      if (widget.showDestinationPin) {
        final rawLabel = destination.label?.trim();
        final String destinationLabel;
        if (widget.isCustomerView) {
          if (rawLabel == null ||
              rawLabel.isEmpty ||
              rawLabel.toLowerCase() == 'destination' ||
              rawLabel.toLowerCase() == 'customer' ||
              rawLabel.toLowerCase().contains("worker's destination")) {
            destinationLabel = "Your Location";
          } else {
            destinationLabel = rawLabel;
          }
        } else {
          if (rawLabel == null ||
              rawLabel.isEmpty ||
              rawLabel.toLowerCase() == 'your location' ||
              rawLabel.toLowerCase().contains("worker's destination")) {
            destinationLabel = "Destination";
          } else {
            destinationLabel = rawLabel;
          }
        }

        final destinationOptions = PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(destination.lng, destination.lat),
          ),
          image: _destinationMarkerImage,
          iconSize: 0.9,
          iconAnchor: IconAnchor.BOTTOM,
          textField: destinationLabel,
          textSize: 12,
          textColor: AppColors.onSurface.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textOffset: [0, 0.6],
          textAnchor: TextAnchor.TOP,
        );
        try {
          if (_destinationMarker == null) {
            _destinationMarker = await pointManager.create(destinationOptions);
          } else {
            _destinationMarker!
              ..geometry = destinationOptions.geometry
              ..image = destinationOptions.image
              ..textField = destinationOptions.textField;
            await pointManager.update(_destinationMarker!);
          }
        } catch (_) {
          _destinationMarker = null;
        }
      } else if (_destinationMarker != null) {
        try {
          await pointManager.delete(_destinationMarker!);
        } catch (_) {}
        _destinationMarker = null;
      }

      // Only render start marker if distinct from worker bike and enabled
      final isStartDistinct =
          widget.showStartPin &&
          start != null &&
          (worker == null ||
              (start.lat - worker.lat).abs() > 0.0001 ||
              (start.lng - worker.lng).abs() > 0.0001);

      if (isStartDistinct) {
        final startOptions = PointAnnotationOptions(
          geometry: Point(coordinates: Position(start.lng, start.lat)),
          image: _startImage,
          iconImage: _startImage == null ? 'marker-15' : null,
          iconSize: 0.7,
          iconAnchor: IconAnchor.BOTTOM,
          textField: start.label ?? 'Start',
          textSize: 11,
          textColor: AppColors.onSurface.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 1.5,
          textOffset: [0, 0.8],
          textAnchor: TextAnchor.TOP,
        );
        try {
          if (_startMarker == null) {
            _startMarker = await pointManager.create(startOptions);
          } else {
            _startMarker!
              ..geometry = startOptions.geometry
              ..image = startOptions.image
              ..textField = startOptions.textField;
            await pointManager.update(_startMarker!);
          }
        } catch (_) {
          _startMarker = null;
        }
      } else if (_startMarker != null) {
        try {
          await pointManager.delete(_startMarker!);
        } catch (_) {}
        _startMarker = null;
      }

      if (widget.showUserLocation) {
        _userLocationImage ??= await _createUserLocationPuckImage();
        final userOptions = PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(destination.lng, destination.lat),
          ),
          image: _userLocationImage,
          iconSize: 0.8,
          iconAnchor: IconAnchor.CENTER,
        );
        try {
          if (_userMarker == null) {
            _userMarker = await pointManager.create(userOptions);
          } else {
            _userMarker!
              ..geometry = userOptions.geometry
              ..image = userOptions.image;
            await pointManager.update(_userMarker!);
          }
        } catch (_) {
          _userMarker = null;
        }
      } else if (_userMarker != null) {
        try {
          await pointManager.delete(_userMarker!);
        } catch (_) {}
        _userMarker = null;
      }

      if (worker != null) {
        final rotation = _bikeRotation(worker);

        final String workerLabel;
        if (widget.isCustomerView) {
          workerLabel = worker.label ?? 'Worker';
        } else {
          workerLabel = 'Your Location';
        }

        final workerOptions = PointAnnotationOptions(
          geometry: Point(coordinates: Position(worker.lng, worker.lat)),
          image: _bikeImage,
          iconImage: _bikeImage == null ? 'car-15' : null,
          iconSize: 0.85,
          iconColor: _bikeImage == null ? AppColors.primary.toARGB32() : null,
          iconRotate: rotation,
          iconAnchor: IconAnchor.CENTER,
          textField: workerLabel,
          textSize: 12,
          textColor: AppColors.primary.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 1.5,
          textOffset: [0, 1.2],
          textAnchor: TextAnchor.TOP,
        );
        try {
          if (_workerMarker == null) {
            _workerMarker = await pointManager.create(workerOptions);
          } else {
            _workerMarker!
              ..geometry = workerOptions.geometry
              ..image = workerOptions.image
              ..iconRotate = workerOptions.iconRotate
              ..textField = workerOptions.textField;
            await pointManager.update(_workerMarker!);
          }
        } catch (_) {
          _workerMarker = null;
        }

        if (widget.followWorker && _mapboxMap != null && !_isNavigating) {
          try {
            await _mapboxMap!.easeTo(
              CameraOptions(
                center: Point(coordinates: Position(worker.lng, worker.lat)),
              ),
              MapAnimationOptions(duration: 250),
            );
          } catch (_) {}
        }
      } else if (_workerMarker != null) {
        try {
          await pointManager.delete(_workerMarker!);
        } catch (_) {}
        _workerMarker = null;
      }

      if (fitCamera && !_isNavigating) await _fitCamera();
    } catch (e) {
      debugPrint('FixlyMapView _refreshAnnotations error: $e');
    } finally {
      _isRefreshing = false;
      if (_refreshQueued && !_isDisposed && mounted) {
        _refreshQueued = false;
        Future.microtask(() => _refreshAnnotations(fitCamera: false));
      }
    }
  }

  Future<void> _fitCamera() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final center = widget.center ?? MapConstants.current;
    if (center == null) return;

    final points = MapGeoUtils.cameraPoints(
      center: center,
      routeStart: widget.routeStart ?? MapConstants.workerApproachStart,
      routeEnd: widget.routeEnd,
      routeProgress: widget.routeProgress,
      serviceRadiusKm: widget.serviceRadiusKm,
      routeCoordinates: widget.routeCoordinates,
    );

    if (points.length <= 1) {
      await mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(center.lng, center.lat)),
          zoom: widget.zoom,
          pitch: _is3D ? 60.0 : 0.0,
        ),
      );
      return;
    }

    final camera = await mapboxMap.cameraForCoordinatesPadding(
      points,
      CameraOptions(pitch: _is3D ? 60.0 : 0.0),
      MbxEdgeInsets(top: 56, left: 40, bottom: 56, right: 40),
      widget.routeEnd != null ? 15.5 : 13.5,
      null,
    );
    await mapboxMap.setCamera(camera);
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center ?? MapConstants.current;
    if (center == null) {
      final placeholder = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: widget.borderRadius,
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_searching, color: AppColors.primary),
              SizedBox(height: 8),
              Text('Waiting for location…'),
            ],
          ),
        ),
      );
      if (widget.expand) {
        return placeholder;
      }
      return SizedBox(height: widget.height, child: placeholder);
    }

    _initialViewport ??= CameraViewportState(
      center: Point(coordinates: Position(center.lng, center.lat)),
      zoom: widget.zoom,
    );

    final mapCore = MapConstants.hasToken && _mapError == null
        ? MapWidget(
            key: const ValueKey('fixly-map-canvas'),
            styleUri: MapboxStyles.STANDARD,
            
            textureView: true,
            gestureRecognizers: widget.claimGestures
                ? <Factory<OneSequenceGestureRecognizer>>{
                    Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
                  }
                : null,
            viewport: _initialViewport,
            onMapCreated: _onMapCreated,
            onCameraChangeListener: (_) => _onCameraChanged(),
            onMapIdleListener: (_) => _onMapIdle(),
            // ignore: deprecated_member_use
            onTapListener: widget.onMapTap != null
                ? (gestureContext) {
                    final lat = gestureContext.point.coordinates.lat.toDouble();
                    final lng = gestureContext.point.coordinates.lng.toDouble();
                    widget.onMapTap!(MapCoordinate(lat: lat, lng: lng));
                  }
                : null,
            onMapLoadErrorListener: (event) {
              if (!mounted) return;
              setState(() => _mapError = event.message);
            },
          )
        : _MapPreviewFallback(
            center: center,
            routeEnd: widget.routeEnd,
            routeProgress: widget.routeProgress,
            serviceRadiusKm: widget.serviceRadiusKm,
            showDestinationPin: widget.showDestinationPin,
            message:
                _mapError ??
                (MapConstants.hasToken ? null : 'Add ACCESS_TOKEN for Mapbox'),
          );

    final mapChild = Stack(
      fit: StackFit.expand,
      children: [
        mapCore,
        // Fallback center pin only if destination annotation marker not yet created
        if (widget.showDestinationPin &&
            widget.routeEnd == null &&
            _destinationMarker == null &&
            _mapError == null &&
            MapConstants.hasToken)
          // Turn-by-Turn Guidance HUD when active
          if (_isNavigating && MapConstants.hasToken && _mapError == null)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: SafeArea(bottom: false, child: _buildNavigationHUD()),
            ),

        // Start Navigation Floating Pill Button
        if (widget.showNavigationOption &&
            !_isNavigating &&
            (widget.routeEnd != null || widget.routeCoordinates.isNotEmpty) &&
            MapConstants.hasToken &&
            _mapError == null)
          Positioned(
            left: 12,
            bottom: widget.showMovementControls
                ? null
                : widget.controlsBottomPadding,
            top: widget.showMovementControls ? 12 : null,
            child: SafeArea(
              bottom: false,
              top: widget.showMovementControls,
              child: _buildStartNavigationButton(),
            ),
          ),

        if (widget.showMovementControls &&
            MapConstants.hasToken &&
            _mapError == null)
          Positioned(
            left: 12,
            bottom: widget.controlsBottomPadding,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapMiniArrowBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: 'Pan North',
                    onTap: () => _panByDirection(0, 1),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapMiniArrowBtn(
                        icon: Icons.keyboard_arrow_left_rounded,
                        tooltip: 'Pan West',
                        onTap: () => _panByDirection(-1, 0),
                      ),
                      _MapMiniArrowBtn(
                        icon: Icons.adjust_rounded,
                        tooltip: 'Recenter',
                        size: 26,
                        iconSize: 15,
                        color: AppColors.primary,
                        onTap: _recenter,
                      ),
                      _MapMiniArrowBtn(
                        icon: Icons.keyboard_arrow_right_rounded,
                        tooltip: 'Pan East',
                        onTap: () => _panByDirection(1, 0),
                      ),
                    ],
                  ),
                  _MapMiniArrowBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: 'Pan South',
                    onTap: () => _panByDirection(0, -1),
                  ),
                ],
              ),
            ),
          ),
        if ((widget.showZoomControls ||
                widget.showRecenterButton ||
                widget.show3DControl ||
                widget.showCompassButton) &&
            MapConstants.hasToken &&
            _mapError == null)
          Positioned(
            right: 12,
            bottom: widget.controlsBottomPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.show3DControl) ...[
                  Material(
                    color: _is3D ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    elevation: 3,
                    shadowColor: Colors.black.withValues(alpha: 0.2),
                    child: _MapControlBtn(
                      tooltip: _is3D ? '2D Map View' : '3D Perspective View',
                      onTap: _toggle3D,
                      customChild: Text(
                        _is3D ? '2D' : '3D',
                        style: TextStyle(
                          color: _is3D ? Colors.white : AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.showCompassButton) ...[
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    elevation: 3,
                    shadowColor: Colors.black.withValues(alpha: 0.2),
                    child: _MapControlBtn(
                      icon: Icons.navigation_rounded,
                      tooltip: 'Reset North',
                      onTap: _resetBearing,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.showRecenterButton) ...[
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    elevation: 3,
                    shadowColor: Colors.black.withValues(alpha: 0.2),
                    child: _MapControlBtn(
                      icon: Icons.my_location_rounded,
                      tooltip: 'My location',
                      onTap: _recenter,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.showZoomControls)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MapControlBtn(
                          icon: Icons.add_rounded,
                          tooltip: 'Zoom in',
                          onTap: _zoomIn,
                        ),
                        Container(
                          width: 24,
                          height: 1,
                          color: Colors.grey.withValues(alpha: 0.25),
                        ),
                        _MapControlBtn(
                          icon: Icons.remove_rounded,
                          tooltip: 'Zoom out',
                          onTap: _zoomOut,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: widget.borderRadius, child: mapChild),
    );

    if (widget.expand) {
      return content;
    }
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: content,
    );
  }
}

class _MapPreviewFallback extends StatelessWidget {
  const _MapPreviewFallback({
    required this.center,
    this.routeEnd,
    this.routeProgress,
    this.serviceRadiusKm,
    this.showDestinationPin = true,
    this.message,
  });

  final MapCoordinate center;
  final MapCoordinate? routeEnd;
  final double? routeProgress;
  final double? serviceRadiusKm;
  final bool showDestinationPin;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _MapGridPainter(
              center: center,
              routeEnd: routeEnd,
              routeProgress: routeProgress,
              serviceRadiusKm: serviceRadiusKm,
              showDestinationPin: showDestinationPin,
            ),
          ),
          if (message != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    message!,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  _MapGridPainter({
    required this.center,
    this.routeEnd,
    this.routeProgress,
    this.serviceRadiusKm,
    this.showDestinationPin = true,
  });

  final MapCoordinate center;
  final MapCoordinate? routeEnd;
  final double? routeProgress;
  final double? serviceRadiusKm;
  final bool showDestinationPin;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dest = Offset(size.width * 0.62, size.height * 0.58);
    final workerStart = Offset(size.width * 0.28, size.height * 0.34);
    final workerEnd = routeEnd == null
        ? workerStart
        : Offset(
            workerStart.dx + (dest.dx - workerStart.dx) * (routeProgress ?? 0),
            workerStart.dy + (dest.dy - workerStart.dy) * (routeProgress ?? 0),
          );

    if (serviceRadiusKm != null) {
      final radius = serviceRadiusKm! * 8;
      canvas.drawCircle(
        dest,
        radius,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        dest,
        radius,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    if (routeEnd != null) {
      canvas.drawLine(
        workerStart,
        dest,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      _drawPin(canvas, workerEnd, AppColors.primary);
    }

    if (showDestinationPin) {
      _drawPin(canvas, dest, AppColors.accent);
    }
  }

  void _drawPin(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, 10, Paint()..color = color);
    canvas.drawCircle(
      point,
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) {
    return oldDelegate.routeProgress != routeProgress ||
        oldDelegate.serviceRadiusKm != serviceRadiusKm;
  }
}

class _MapControlBtn extends StatelessWidget {
  const _MapControlBtn({
    required this.onTap,
    this.icon,
    this.customChild,
    this.tooltip,
  });

  final IconData? icon;
  final Widget? customChild;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child:
                  customChild ??
                  Icon(icon, size: 20, color: AppColors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapMiniArrowBtn extends StatelessWidget {
  const _MapMiniArrowBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 28,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Tooltip(
          message: tooltip ?? '',
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: color ?? AppColors.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManeuverInfo {
  const _ManeuverInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.distanceToManeuver,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double distanceToManeuver;
}
