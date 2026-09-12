import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ตำแหน่งสำหรับแสดงระหว่างรอ GPS เท่านั้น ไม่ใช่พิกัดสดสำหรับเรียกรถ
class StudentLocationCache {
  static String _key(String uid) => 'student_location_v1_$uid';

  static LatLng? read(SharedPreferences prefs, String uid, DateTime now) {
    try {
      final raw = prefs.getString(_key(uid));
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final age = now.difference(DateTime.fromMillisecondsSinceEpoch(data['time'] as int));
      if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180 ||
          age.isNegative || age >= const Duration(minutes: 5)) {
        return null;
      }
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    SharedPreferences prefs, String uid, LatLng location, DateTime now,
  ) async {
    await prefs.setString(_key(uid), jsonEncode({
      'lat': location.latitude,
      'lng': location.longitude,
      'time': now.millisecondsSinceEpoch,
    }));
  }
}
