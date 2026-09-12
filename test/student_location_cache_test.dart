import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/services/student_location_cache.dart';

void main() {
  test('คืนหมุดล่าสุดหลังโหลดใหม่ เฉพาะบัญชีเดิมและข้อมูลที่ยังไม่หมดอายุ', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.utc(2026, 9, 12);
    const position = LatLng(16.83, 100.21);
    await StudentLocationCache.save(prefs, 'student-a', position, now);
    await prefs.reload();
    expect(StudentLocationCache.read(prefs, 'student-a', now.add(const Duration(seconds: 20))), position);
    expect(StudentLocationCache.read(prefs, 'student-b', now), isNull);
    expect(StudentLocationCache.read(prefs, 'student-a', now.add(const Duration(minutes: 6))), isNull);
    expect(StudentLocationCache.read(prefs, 'student-a', now.subtract(const Duration(seconds: 1))), isNull);
    await prefs.setString('student_location_v1_student-a', '{broken');
    expect(StudentLocationCache.read(prefs, 'student-a', now), isNull);
  });
}
