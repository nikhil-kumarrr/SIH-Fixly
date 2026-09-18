import 'dart:math' as math;

import '../constants/map_constants.dart';

abstract final class NavigationMath {
  static double bearingDegrees(MapCoordinate from, MapCoordinate to) {
    final lat1 = from.lat * math.pi / 180;
    final lat2 = to.lat * math.pi / 180;
    final deltaLng = (to.lng - from.lng) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// The bike artwork points North (0° up), so rotation matches bearing directly.
  static double bikeIconRotation(MapCoordinate from, MapCoordinate to) =>
      bearingDegrees(from, to);

  /// Heading along road polyline toward destination (avoids flipped GPS / crow-flies).
  static double? headingAlongRoute(
    MapCoordinate position,
    List<MapCoordinate> route, {
    int lookAheadPoints = 3,
  }) {
    if (route.length < 2) return null;
    var closestIdx = 0;
    var minDist = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = distanceMeters(position, route[i]);
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }
    final aheadIdx =
        closestIdx + lookAheadPoints < route.length
            ? closestIdx + lookAheadPoints
            : route.length - 1;
    if (aheadIdx <= closestIdx) {
      if (closestIdx > 0) {
        return bearingDegrees(route[closestIdx - 1], route[closestIdx]);
      }
      return null;
    }
    return bearingDegrees(route[closestIdx], route[aheadIdx]);
  }

  static double distanceMeters(MapCoordinate from, MapCoordinate to) {
    const radius = 6371000.0;
    final lat1 = from.lat * math.pi / 180;
    final lat2 = to.lat * math.pi / 180;
    final dLat = (to.lat - from.lat) * math.pi / 180;
    final dLng = (to.lng - from.lng) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
