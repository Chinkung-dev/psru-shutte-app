import 'package:flutter_test/flutter_test.dart';
import 'package:psru_shuttle_app/services/shuttle_access.dart';

void main() {
  group('การทดสอบฟังก์ชัน shuttleDatabaseKey สำหรับ Realtime Database', () {
    test('แปลงชื่อและหมายเลขรถ shuttle#01 และ SH#01 เป็นคีย์มาตรฐาน shuttle_01', () {
      final key = shuttleDatabaseKey(
        documentId: 'doc_01',
        name: 'shuttle#01',
        number: 'SH#01',
      );
      expect(key, 'shuttle_01');
    });

    test('แปลงชื่อและหมายเลขรถ shuttle#05 และ SH#05 เป็นคีย์มาตรฐาน shuttle_05', () {
      final key = shuttleDatabaseKey(
        documentId: 'doc_05',
        name: 'shuttle#05',
        number: 'SH#05',
      );
      expect(key, 'shuttle_05');
    });

    test('แปลงรูปแบบตัวเลขเดี่ยว เช่น 2 เป็น shuttle_02', () {
      final key = shuttleDatabaseKey(
        documentId: 'doc_02',
        name: 'รถรับส่ง 2',
        number: '2',
      );
      expect(key, 'shuttle_02');
    });

    test('ใช้ documentId เมื่อไม่มีตัวเลขในชื่อหรือหมายเลข', () {
      final key = shuttleDatabaseKey(
        documentId: 'custom_doc_id',
        name: 'shuttle',
        number: 'none',
      );
      expect(key, 'custom_doc_id');
    });

    test('ตรวจสอบการสร้างคีย์มาตรฐานสำหรับรถทั้ง 5 คัน', () {
      for (int i = 1; i <= 5; i++) {
        final padded = i.toString().padLeft(2, '0');
        final keyFromName = shuttleDatabaseKey(
          documentId: 'fallback_$i',
          name: 'shuttle#$padded',
          number: '',
        );
        final keyFromNumber = shuttleDatabaseKey(
          documentId: 'fallback_$i',
          name: '',
          number: 'SH#$padded',
        );
        expect(keyFromName, 'shuttle_$padded');
        expect(keyFromNumber, 'shuttle_$padded');
      }
    });
  });
}
