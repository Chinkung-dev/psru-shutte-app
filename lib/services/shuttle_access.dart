import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// ใช้หลักเดียวกับหน้าคนขับ เพื่อให้สิทธิ์ตรงกับคีย์ที่ส่ง GPS
String shuttleDatabaseKey({
  required String documentId,
  required String name,
  required String number,
}) {
  var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) digits = name.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? documentId : 'shuttle_${digits.padLeft(2, '0')}';
}

class ShuttleAccess {
  static Future<void> requireAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('กรุณาเข้าสู่ระบบแอดมิน');
    final snapshot = await FirebaseDatabase.instance
        .ref('access/admins/$uid')
        .get();
    if (snapshot.value != true) {
      throw StateError('บัญชีนี้ยังไม่ได้รับสิทธิ์จัดการรถ กรุณาติดต่อผู้ดูแลระบบ');
    }
  }

  // ถอนสิทธิ์ก่อนแก้ข้อมูลข้ามฐานข้อมูล หากบันทึกล้มเหลวจะไม่เหลือสิทธิ์รถเดิม
  static Future<void> revokeDriver(String driverUid) async {
    final result = await FirebaseDatabase.instance
        .ref('shuttle_drivers')
        .runTransaction((value) {
          if (value == null) return Transaction.success(null);
          final assignments = Map<String, dynamic>.from(value as Map);
          assignments.removeWhere((key, uid) => uid == driverUid);
          return Transaction.success(assignments);
        });
    if (!result.committed) throw StateError('ไม่สามารถถอนสิทธิ์รถเดิมได้');
  }

  static Future<void> assignDriver({
    required String driverUid,
    required String documentId,
    required String name,
    required String number,
  }) async {
    final key = shuttleDatabaseKey(
      documentId: documentId,
      name: name,
      number: number,
    );
    final result = await FirebaseDatabase.instance
        .ref('shuttle_drivers/$key')
        .runTransaction((owner) {
          if (owner != null && owner != driverUid) return Transaction.abort();
          return Transaction.success(driverUid);
        });
    if (!result.committed) {
      throw StateError('รถคันนี้ได้รับการมอบหมายให้คนขับคนอื่นแล้ว');
    }
  }
}
