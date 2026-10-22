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
  bool _hasEstablishedHeading = false;

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
        _hasEstablishedHeading = false;
        return bearing;
      }
      if (distance(_lastFix!, position) > math.max(15, seconds * 20)) {
        return bearing;
      }

      final stepDist = distance(_lastFix!, position);
      final speed = seconds > 0 ? (stepDist / seconds) : 0.0;

      // เมื่อรถจอดนิ่งหรือเคลื่อนที่ช้ามากตามสัญญาณรบกวน GPS (ความเร็วต่ำกว่า 0.8 ม./วินาที หรือประมาณ 2.8 กม./ชม.)
      // ให้คงทิศทางเดิมไว้เสมอ ไม่เปลี่ยนทิศทาง และอัปเดตแองเคอร์ตามตำแหน่งปัจจุบันเพื่อป้องกันการสะสม drift
      if (_hasEstablishedHeading && speed < 0.8) {
        _lastFix = position;
        _lastTime = timestamp;
        _anchor = position;
        return bearing;
      }
    }

    _lastFix = position;
    _lastTime = timestamp;

    if (_anchor == null) {
      _anchor = position;
      return bearing;
    }

    final distFromAnchor = distance(_anchor!, position);

    if (!_hasEstablishedHeading) {
      if (distFromAnchor >= 4) {
        bearing = shuttleBearing(_anchor!, position);
        _hasEstablishedHeading = true;
        _anchor = position;
      }
      return bearing;
    }

    final candidateBearing = shuttleBearing(_anchor!, position);
    final delta = shortestHeadingDelta(bearing, candidateBearing).abs();

    // กำหนดเกณฑ์ระยะทางขั้นต่ำตามมุมการเลี้ยว:
    // 1. ทางตรงหรือโค้งเล็กน้อย (delta <= 60 องศา): ต้องการระยะสะสมอย่างน้อย 4 เมตร
    // 2. เลี้ยวทางแยก (60 องศา < delta <= 110 องศา): ต้องการระยะสะสมอย่างน้อย 8 เมตร
    // 3. ทิศตรงข้ามหรือกลับรถ (delta > 110 องศา): ต้องการระยะสะสมอย่างน้อย 14 เมตร
    // เพื่อป้องกัน GPS Jitter ขณะรถจอดนิ่งส่งผลให้ตัวรถกลับหลังไปมา
    final double requiredDist = delta <= 60.0
        ? 4.0
        : (delta <= 110.0 ? 8.0 : 14.0);

    if (distFromAnchor >= requiredDist) {
      bearing = candidateBearing;
      _anchor = position;
    }

    return bearing;
  }
}
