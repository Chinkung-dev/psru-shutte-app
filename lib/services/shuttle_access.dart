import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// แปลงชื่อหรือหมายเลขรถให้เป็นคีย์มาตรฐานของ Realtime Database (เช่น shuttle_01 ถึง shuttle_05)
String shuttleDatabaseKey({
  required String documentId,
  required String name,
  required String number,
}) {
  var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) digits = name.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? documentId : 'shuttle_${digits.padLeft(2, '0')}';
}

// รายงานผลการตรวจสอบและการย้ายข้อมูลจาก Firestore ไปยัง Realtime Database
class ShuttleMigrationReport {
  final List<String> migratedShuttles;
  final List<String> skippedShuttles;
  final Map<String, String> conflictedShuttles;
  final List<String> errors;
  final Map<String, Map<String, dynamic>> originalFirestoreData;

  ShuttleMigrationReport({
    required this.migratedShuttles,
    required this.skippedShuttles,
    required this.conflictedShuttles,
    required this.errors,
    required this.originalFirestoreData,
  });

  bool get isSuccess => conflictedShuttles.isEmpty && errors.isEmpty;
}

class ShuttleAccess {
  // ตรวจสอบและสร้างข้อมูลรถเริ่มต้นใน Realtime Database ให้ครบตามมาตรฐาน shuttle_01 ถึง shuttle_05
  // โดยไม่มีการลบข้อมูลเดิมใน Firestore เพื่อป้องกันข้อมูลสูญหายตาม REV-02
  static Future<void> ensureDefaultShuttles([int targetCount = 5]) async {
    try {
      final rtdbRef = FirebaseDatabase.instance.ref('shuttles');
      final driversRef = FirebaseDatabase.instance.ref('shuttle_drivers');
      final snapshot = await rtdbRef.get();
      final driversSnapshot = await driversRef.get();

      Map<String, dynamic> existing = {};
      if (snapshot.exists && snapshot.value is Map) {
        existing = Map<String, dynamic>.from(snapshot.value as Map);
      }

      Map<String, dynamic> existingDrivers = {};
      if (driversSnapshot.exists && driversSnapshot.value is Map) {
        existingDrivers = Map<String, dynamic>.from(driversSnapshot.value as Map);
      }

      for (int i = 1; i <= targetCount; i++) {
        final padNum = i.toString().padLeft(2, '0');
        final key = 'shuttle_$padNum';
        final targetName = 'shuttle#$padNum';
        final targetNumber = 'SH#$padNum';

        if (!existing.containsKey(key)) {
          // หาก shuttle_drivers มีการผูกคนขับไว้เดิม ให้รักษาคนขับนั้นไว้ ไม่เซ็ตเป็น null
          final assignedDriverUid = existingDrivers[key]?.toString();

          // สร้างโหนดรถใหม่ใน Realtime Database
          await rtdbRef.child(key).set({
            'name': targetName,
            'number': targetNumber,
            'status': 'offline',
            'passenger_status': 'offline',
            'lat': 16.82753,
            'lng': 100.20686,
            'driver_uid': (assignedDriverUid != null && assignedDriverUid.isNotEmpty)
                ? assignedDriverUid
                : null,
            'driver_name': null,
            'driver_avatar': null,
            'capacity_percent': 0,
            'last_updated': ServerValue.timestamp,
          });
        } else {
          // อัปเดตชื่อและหมายเลขให้ได้มาตรฐานหากยังไม่ถูกต้อง
          final item = Map<String, dynamic>.from(existing[key] as Map);
          final curName = (item['name'] ?? '').toString();
          final curNumber = (item['number'] ?? '').toString();
          if (curName != targetName || curNumber != targetNumber) {
            await rtdbRef.child(key).update({
              'name': targetName,
              'number': targetNumber,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('เกิดข้อผิดพลาดในการตรวจสอบหรือสร้างข้อมูลรถใน RTDB: $e');
    }
  }

  // ระบบ Migration ย้ายข้อมูลจาก Firestore ไป RTDB อย่างปลอดภัยตาม REV-02
  static Future<ShuttleMigrationReport> migrateFirestoreShuttlesToRtdb() async {
    await requireAdmin();

    final List<String> migratedShuttles = [];
    final List<String> skippedShuttles = [];
    final Map<String, String> conflictedShuttles = {};
    final List<String> errors = [];
    final Map<String, Map<String, dynamic>> originalFirestoreData = {};

    try {
      // 1. อ่านข้อมูลจากทุกแหล่ง
      final fsSnapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      final rtdbShuttlesSnap = await FirebaseDatabase.instance.ref('shuttles').get();
      final rtdbDriversSnap = await FirebaseDatabase.instance.ref('shuttle_drivers').get();

      final Map<String, dynamic> rtdbShuttles = (rtdbShuttlesSnap.exists && rtdbShuttlesSnap.value is Map)
          ? Map<String, dynamic>.from(rtdbShuttlesSnap.value as Map)
          : {};

      final Map<String, dynamic> rtdbDrivers = (rtdbDriversSnap.exists && rtdbDriversSnap.value is Map)
          ? Map<String, dynamic>.from(rtdbDriversSnap.value as Map)
          : {};

      // รวบรวมข้อมูลคนขับจากคอลเล็กชัน users
      final Map<String, Map<String, dynamic>> driverUsers = {};
      for (final doc in usersSnapshot.docs) {
        driverUsers[doc.id] = doc.data();
      }

      final Map<String, Object?> atomicUpdates = {};

      for (final doc in fsSnapshot.docs) {
        final data = doc.data();
        originalFirestoreData[doc.id] = Map<String, dynamic>.from(data);

        final docName = (data['name'] ?? '').toString().trim();
        final docNumber = (data['number'] ?? '').toString().trim();
        final key = shuttleDatabaseKey(documentId: doc.id, name: docName, number: docNumber);

        // หา driverUid จากเอกสาร Firestore หรือจาก users
        String? fsDriverUid = (data['driver_uid'] ?? data['driverUid'])?.toString().trim();
        if (fsDriverUid == null || fsDriverUid.isEmpty) {
          for (final entry in driverUsers.entries) {
            final uData = entry.value;
            final uName = (uData['shuttle_name'] ?? uData['shuttleName'] ?? '').toString().trim();
            final uNumber = (uData['shuttle_number'] ?? uData['shuttleNumber'] ?? '').toString().trim();
            if ((uName.isNotEmpty && uName == docName) || (uNumber.isNotEmpty && uNumber == docNumber)) {
              fsDriverUid = entry.key;
              break;
            }
          }
        }

        final rtdbCurrentDriver = rtdbShuttles[key]?['driver_uid']?.toString();
        final rtdbAssignedDriver = rtdbDrivers[key]?.toString();

        // ตรวจสอบความขัดแย้งของคนขับ
        final bool hasFsDriver = fsDriverUid != null && fsDriverUid.isNotEmpty;
        final bool hasRtdbAssigned = rtdbAssignedDriver != null && rtdbAssignedDriver.isNotEmpty;
        final bool hasRtdbCurrent = rtdbCurrentDriver != null && rtdbCurrentDriver.isNotEmpty;

        if (hasFsDriver && hasRtdbAssigned && fsDriverUid != rtdbAssignedDriver) {
          conflictedShuttles[key] =
              'คนขับใน Firestore ($fsDriverUid) ขัดแย้งกับ shuttle_drivers ($rtdbAssignedDriver)';
          continue;
        }

        if (hasRtdbCurrent && hasRtdbAssigned && rtdbCurrentDriver != rtdbAssignedDriver) {
          conflictedShuttles[key] =
              'driver_uid ในโหนด shuttles ($rtdbCurrentDriver) ขัดแย้งกับ shuttle_drivers ($rtdbAssignedDriver)';
          continue;
        }

        // ตรวจสอบข้อมูลคนขับที่จะย้าย
        final targetDriverUid = hasFsDriver ? fsDriverUid : rtdbAssignedDriver;
        Map<String, dynamic>? driverProfile;
        if (targetDriverUid != null && targetDriverUid.isNotEmpty) {
          driverProfile = driverUsers[targetDriverUid];
        }

        final driverName = driverProfile?['name']?.toString() ??
            (data['driver_name'] ?? data['driverName'])?.toString();
        final driverAvatar = driverProfile?['avatar']?.toString() ??
            data['driver_avatar']?.toString() ??
            'assets/images/man1.png';

        // รักษาพิกัดและสถานะสดที่มีอยู่ใน RTDB
        final existingItem = rtdbShuttles[key] as Map?;
        final existingLat = existingItem?['lat'] ?? data['lat'] ?? 16.82753;
        final existingLng = existingItem?['lng'] ?? data['lng'] ?? 100.20686;
        final existingStatus = existingItem?['status'] ?? 'offline';
        final existingPStatus = existingItem?['passenger_status'] ?? 'offline';

        bool needUpdate = false;

        if (existingItem == null) {
          needUpdate = true;
          atomicUpdates['shuttles/$key'] = {
            'name': docName.isNotEmpty ? docName : 'shuttle#${key.replaceAll(RegExp(r'[^0-9]'), '')}',
            'number': docNumber.isNotEmpty ? docNumber : 'SH#${key.replaceAll(RegExp(r'[^0-9]'), '')}',
            'status': existingStatus,
            'passenger_status': existingPStatus,
            'lat': existingLat,
            'lng': existingLng,
            'driver_uid': targetDriverUid,
            'driver_name': driverName,
            'driver_avatar': driverAvatar,
            'capacity_percent': existingItem?['capacity_percent'] ?? 0,
            'last_updated': ServerValue.timestamp,
          };
        } else {
          if (targetDriverUid != null && targetDriverUid.isNotEmpty && rtdbCurrentDriver != targetDriverUid) {
            atomicUpdates['shuttles/$key/driver_uid'] = targetDriverUid;
            atomicUpdates['shuttles/$key/driver_name'] = driverName;
            atomicUpdates['shuttles/$key/driver_avatar'] = driverAvatar;
            needUpdate = true;
          }
        }

        if (targetDriverUid != null && targetDriverUid.isNotEmpty && rtdbAssignedDriver != targetDriverUid) {
          atomicUpdates['shuttle_drivers/$key'] = targetDriverUid;
          needUpdate = true;
        }

        if (needUpdate) {
          migratedShuttles.add(key);
        } else {
          skippedShuttles.add(key);
        }
      }

      // ดำเนินการเขียนแบบ Atomic ใน RTDB พร้อมตรวจสอบข้อมูลไม่ให้ถูกเขียนทับระหว่างทาง
      if (atomicUpdates.isNotEmpty) {
        // ตรวจสอบความถูกต้องของ shuttle_drivers อีกครั้งก่อนอัปเดต (Optimistic concurrency check)
        final recheckDrivers = await FirebaseDatabase.instance.ref('shuttle_drivers').get();
        final Map<String, dynamic> currentDrivers = (recheckDrivers.exists && recheckDrivers.value is Map)
            ? Map<String, dynamic>.from(recheckDrivers.value as Map)
            : {};

        for (final key in conflictedShuttles.keys) {
          atomicUpdates.remove('shuttles/$key');
          atomicUpdates.remove('shuttle_drivers/$key');
        }

        for (final entry in atomicUpdates.entries) {
          if (entry.key.startsWith('shuttle_drivers/')) {
            final k = entry.key.replaceFirst('shuttle_drivers/', '');
            final previousExpected = rtdbDrivers[k]?.toString();
            final currentActual = currentDrivers[k]?.toString();
            if (previousExpected != currentActual) {
              throw StateError('ข้อมูลการผูกคนขับของ $k มีการเปลี่ยนแปลงระหว่างดำเนินการ');
            }
          }
        }

        await FirebaseDatabase.instance.ref().update(atomicUpdates);
      }
    } catch (e) {
      errors.add('เกิดข้อผิดพลาดระหว่าง Migration: $e');
    }

    return ShuttleMigrationReport(
      migratedShuttles: migratedShuttles,
      skippedShuttles: skippedShuttles,
      conflictedShuttles: conflictedShuttles,
      errors: errors,
      originalFirestoreData: originalFirestoreData,
    );
  }

  // ทำความสะอาดเอกสารใน Firestore เฉพาะที่ยืนยันแล้วว่าย้ายข้อมูลสำเร็จและตรงกับข้อมูลล่าสุดตาม REV-02
  static Future<Map<String, dynamic>> cleanMigratedFirestoreShuttles({
    required ShuttleMigrationReport report,
  }) async {
    await requireAdmin();

    final List<String> deletedDocIds = [];
    final List<String> skippedDocIds = [];
    final List<String> cleanupErrors = [];

    try {
      final fsSnapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      final rtdbShuttlesSnap = await FirebaseDatabase.instance.ref('shuttles').get();
      final rtdbDriversSnap = await FirebaseDatabase.instance.ref('shuttle_drivers').get();

      final Map<String, dynamic> rtdbShuttles = (rtdbShuttlesSnap.exists && rtdbShuttlesSnap.value is Map)
          ? Map<String, dynamic>.from(rtdbShuttlesSnap.value as Map)
          : {};
      final Map<String, dynamic> rtdbDrivers = (rtdbDriversSnap.exists && rtdbDriversSnap.value is Map)
          ? Map<String, dynamic>.from(rtdbDriversSnap.value as Map)
          : {};

      for (final doc in fsSnapshot.docs) {
        final docId = doc.id;
        final currentData = doc.data();
        final docName = (currentData['name'] ?? '').toString().trim();
        final docNumber = (currentData['number'] ?? '').toString().trim();
        final key = shuttleDatabaseKey(documentId: docId, name: docName, number: docNumber);

        // หากคีย์นี้มีข้อขัดแย้งในรายงาน หรือไม่ได้อยู่ในรายการที่ย้ายสำเร็จ ให้ข้ามการลบ
        if (report.conflictedShuttles.containsKey(key) || !report.migratedShuttles.contains(key)) {
          skippedDocIds.add(docId);
          continue;
        }

        // ตรวจสอบซ้ำ (Re-verify) ว่าข้อมูลใน Firestore ยังคงตรงกับ snapshot ตอนทำรายงานหรือไม่
        final snapshotData = report.originalFirestoreData[docId];
        if (snapshotData != null) {
          final snapDriver = (snapshotData['driver_uid'] ?? snapshotData['driverUid'])?.toString();
          final curDriver = (currentData['driver_uid'] ?? currentData['driverUid'])?.toString();
          if (snapDriver != curDriver) {
            skippedDocIds.add(docId);
            cleanupErrors.add('ข้อมูลคนขับของ $docId ใน Firestore มีการแก้ไขหลังจัดทำรายงาน ข้ามการลบ');
            continue;
          }
        }

        // ตรวจสอบว่าใน RTDB มีข้อมูลรถคันนี้และผูกคนขับเรียบร้อยแล้วจริง
        if (!rtdbShuttles.containsKey(key)) {
          skippedDocIds.add(docId);
          cleanupErrors.add('ไม่พบโหนดรถ $key ใน RTDB ข้ามการลบ');
          continue;
        }

        final expectedDriver = (currentData['driver_uid'] ?? currentData['driverUid'])?.toString();
        if (expectedDriver != null && expectedDriver.isNotEmpty) {
          final rtdbDriver = rtdbDrivers[key]?.toString();
          if (rtdbDriver != expectedDriver) {
            skippedDocIds.add(docId);
            cleanupErrors.add('คนขับใน RTDB ของ $key ไม่ตรงกับ Firestore ข้ามการลบ');
            continue;
          }
        }

        // เมื่อตรวจสอบยืนยันข้อมูลล่าสุดครบถ้วนแล้ว จึงลบเอกสาร
        await doc.reference.delete();
        deletedDocIds.add(docId);
      }
    } catch (e) {
      cleanupErrors.add('เกิดข้อผิดพลาดในการทำความสะอาด Firestore: $e');
    }

    return {
      'deletedDocIds': deletedDocIds,
      'skippedDocIds': skippedDocIds,
      'errors': cleanupErrors,
    };
  }

  // ดึงรายการรถทั้งหมดที่ยังไม่มีคนขับ หรือเป็นรถของคนขับคนปัจจุบัน (จาก Realtime Database)
  static Future<List<Map<String, dynamic>>> getAvailableShuttles({
    String? currentDriverUid,
  }) async {
    await ensureDefaultShuttles(5);

    final rtdbRef = FirebaseDatabase.instance.ref('shuttles');
    final snapshot = await rtdbRef.get();
    if (!snapshot.exists || snapshot.value is! Map) return [];

    final shuttlesMap = Map<String, dynamic>.from(snapshot.value as Map);
    final List<Map<String, dynamic>> result = [];

    for (final entry in shuttlesMap.entries) {
      final key = entry.key.toString();
      final data = Map<String, dynamic>.from(entry.value as Map);
      final name = (data['name'] ?? key).toString();
      final number = (data['number'] ?? '').toString();
      final driverUid = data['driver_uid'] as String?;

      final isAvailable = driverUid == null ||
          driverUid.isEmpty ||
          (currentDriverUid != null && driverUid == currentDriverUid);

      if (isAvailable) {
        result.add({
          'id': key,
          'key': key,
          'name': name,
          'number': number,
          'driver_uid': driverUid,
          'status': data['status'] ?? 'offline',
          'passenger_status': data['passenger_status'] ?? 'offline',
        });
      }
    }

    result.sort((a, b) {
      final numA = int.tryParse(
              (a['number'] ?? a['name']).toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      final numB = int.tryParse(
              (b['number'] ?? b['name']).toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      return numA.compareTo(numB);
    });

    return result;
  }

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

  // ถอนสิทธิ์คนขับออกจากรถใน Realtime Database
  static Future<void> revokeDriver(String driverUid) async {
    // 1. ลบออกจาก shuttle_drivers
    final result = await FirebaseDatabase.instance
        .ref('shuttle_drivers')
        .runTransaction((value) {
      if (value == null) return Transaction.success(null);
      final assignments = Map<String, dynamic>.from(value as Map);
      assignments.removeWhere((key, uid) => uid == driverUid);
      return Transaction.success(assignments);
    });
    if (!result.committed) throw StateError('ไม่สามารถถอนสิทธิ์รถเดิมได้');

    // 2. ล้างข้อมูลคนขับในโหนด shuttles
    try {
      final snapshot = await FirebaseDatabase.instance.ref('shuttles').get();
      if (snapshot.exists && snapshot.value is Map) {
        final shuttles = Map<String, dynamic>.from(snapshot.value as Map);
        for (final entry in shuttles.entries) {
          final val = Map<String, dynamic>.from(entry.value as Map);
          if (val['driver_uid'] == driverUid) {
            await FirebaseDatabase.instance.ref('shuttles/${entry.key}').update({
              'driver_uid': null,
              'driver_name': null,
              'status': 'offline',
              'passenger_status': 'offline',
            });
          }
        }
      }
    } catch (_) {}
  }

  // ปลดการผูกรถตามชื่อรถ
  static Future<void> unassignShuttleByName(String shuttleName) async {
    final digits = shuttleName.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final key = 'shuttle_${digits.padLeft(2, '0')}';
    await unassignShuttleByKey(key);
  }

  // ปลดการผูกรถตามคีย์ RTDB (เช่น shuttle_01)
  static Future<void> unassignShuttleByKey(String key) async {
    try {
      await FirebaseDatabase.instance.ref('shuttle_drivers/$key').remove();
      await FirebaseDatabase.instance.ref('shuttles/$key').update({
        'driver_uid': null,
        'driver_name': null,
        'status': 'offline',
        'passenger_status': 'offline',
      });
    } catch (_) {}
  }

  // มอบหมายคนขับให้กับรถใน Realtime Database
  static Future<void> assignDriver({
    required String driverUid,
    String? documentId,
    String? name,
    String? number,
    String? shuttleName,
    String? shuttleNumber,
    String? driverName,
    String? driverAvatar,
  }) async {
    final effectiveName = shuttleName ?? name ?? '';
    final effectiveNumber = shuttleNumber ?? number ?? '';
    final effectiveDocId = documentId ?? effectiveName;

    final key = shuttleDatabaseKey(
      documentId: effectiveDocId,
      name: effectiveName,
      number: effectiveNumber,
    );

    // 1. ตรวจสอบสิทธิ์และบันทึกผู้ครอบครองใน shuttle_drivers/$key
    final result = await FirebaseDatabase.instance
        .ref('shuttle_drivers/$key')
        .runTransaction((owner) {
      if (owner != null && owner != driverUid) return Transaction.abort();
      return Transaction.success(driverUid);
    });
    if (!result.committed) {
      throw StateError('รถคันนี้ได้รับการมอบหมายให้คนขับคนอื่นแล้ว');
    }

    // 2. อัปเดตข้อมูลคนขับลงในโหนด shuttles/$key โดยตรง
    await FirebaseDatabase.instance.ref('shuttles/$key').update({
      'driver_uid': driverUid,
      ...?driverName != null ? {'driver_name': driverName} : null,
      'driver_avatar': driverAvatar ?? 'assets/images/man1.png',
      if (effectiveName.isNotEmpty) 'name': effectiveName,
      if (effectiveNumber.isNotEmpty) 'number': effectiveNumber,
    });
  }
}
