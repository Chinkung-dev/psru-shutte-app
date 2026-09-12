import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

double shuttleBearing(LatLng from, LatLng to) {
  final a = from.latitudeInRad;
  final b = to.latitudeInRad;
  final delta = to.longitudeInRad - from.longitudeInRad;
  return (math.atan2(
                math.sin(delta) * math.cos(b),
                math.cos(a) * math.sin(b) -
                    math.sin(a) * math.cos(b) * math.cos(delta),
              ) *
              180 /
              math.pi +
          360) %
      360;
}

double shortestHeadingDelta(double from, double to) =>
    (to - from + 180) % 360 - 180;

/// Uses accepted GPS fixes, never route/highlight geometry. Small displacements
/// accumulate from the last heading anchor so a slow vehicle can still turn.
class ShuttleHeadingTracker {
  LatLng? _anchor;
  LatLng? _lastFix;
  DateTime? _lastTime;
  double bearing = 0;

  double update(LatLng position, DateTime timestamp) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180) {
      return bearing;
    }
    final previousTime = _lastTime;
    if (previousTime != null && !timestamp.isAfter(previousTime)) {
      return bearing;
    }
    const distance = Distance();
    if (_lastFix != null && previousTime != null) {
      final seconds = timestamp.difference(previousTime).inMilliseconds / 1000;
      // A reconnect needs a fresh anchor rather than a heading across the gap.
      if (seconds > 30) {
        _anchor = _lastFix = position;
        _lastTime = timestamp;
        return bearing;
      }
      if (distance(_lastFix!, position) > math.max(15, seconds * 20)) {
        return bearing;
      }
    }
    _lastFix = position;
    _lastTime = timestamp;
    if (_anchor == null) {
      _anchor = position;
    } else if (distance(_anchor!, position) >= 4) {
      bearing = shuttleBearing(_anchor!, position);
      _anchor = position;
    }
    return bearing;
  }
}
