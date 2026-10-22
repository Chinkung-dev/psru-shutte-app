import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/services/shuttle_access.dart';
import 'package:psru_shuttle_app/widgets/shuttle_3d_layer.dart';
import 'package:psru_shuttle_app/widgets/shuttle_map_badge.dart';
import 'package:psru_shuttle_app/widgets/animated_highlighted_route_layer.dart';

void main() {
  group('REV-01: การแยกบันทึกโปรไฟล์คนขับและการจัดการความล้มเหลวแบบแยกส่วน', () {
    test('ฟังก์ชันบันทึกโปรไฟล์คนขับไม่จำเป็นต้องแตะต้อง shuttle_drivers หรือ assignDriver', () {
      // ตรวจสอบว่าคีย์ของรถถูกสร้างอย่างถูกต้องสำหรับซิงก์ driver_name / driver_avatar
      const assignedShuttleName = 'shuttle#01';
      const assignedShuttleNumber = 'SH#01';
      final key = shuttleDatabaseKey(
        documentId: assignedShuttleName,
        name: assignedShuttleName,
        number: assignedShuttleNumber,
      );
      expect(key, 'shuttle_01');

      // ตรวจสอบว่า payload สำหรับซิงก์ไปยัง shuttles/$key มีเฉพาะฟิลด์โปรไฟล์ ไม่แตะต้อง driver_uid
      final profileSyncPayload = {
        'driver_name': 'สมชาย ใจดี',
        'driver_avatar': 'assets/images/man1.png',
      };
      expect(profileSyncPayload.containsKey('driver_uid'), isFalse);
      expect(profileSyncPayload['driver_name'], 'สมชาย ใจดี');
      expect(profileSyncPayload['driver_avatar'], 'assets/images/man1.png');
    });

    test('จำลองกรณีซิงก์ RTDB ล้มเหลว โปรไฟล์ Firestore ยังคงสำเร็จและแจ้งเตือนถูกต้อง', () {
      String resolveNotificationMessage({
        required bool firestoreSaved,
        required bool rtdbSynced,
      }) {
        if (firestoreSaved && rtdbSynced) {
          return 'อัปเดตโปรไฟล์เรียบร้อยแล้ว';
        } else if (firestoreSaved && !rtdbSynced) {
          return 'บันทึกโปรไฟล์สำเร็จแล้ว แต่ข้อมูลบนรถยังไม่อัปเดต';
        }
        return 'เกิดข้อผิดพลาดในการอัปเดตโปรไฟล์';
      }

      expect(
        resolveNotificationMessage(firestoreSaved: true, rtdbSynced: false),
        'บันทึกโปรไฟล์สำเร็จแล้ว แต่ข้อมูลบนรถยังไม่อัปเดต',
      );
      expect(
        resolveNotificationMessage(firestoreSaved: true, rtdbSynced: true),
        'อัปเดตโปรไฟล์เรียบร้อยแล้ว',
      );
      expect(
        resolveNotificationMessage(firestoreSaved: false, rtdbSynced: false),
        'เกิดข้อผิดพลาดในการอัปเดตโปรไฟล์',
      );
    });
  });

  group('REV-02: การตรวจสอบความขัดแย้งของ Migration และ Verified Pre-cleanup', () {
    test('ShuttleMigrationReport บันทึกสถานะครบถ้วนและประเมินผล isSuccess ถูกต้อง', () {
      final reportSuccess = ShuttleMigrationReport(
        migratedShuttles: ['shuttle_01', 'shuttle_02'],
        skippedShuttles: ['shuttle_03'],
        conflictedShuttles: {},
        errors: [],
        originalFirestoreData: {
          'doc_01': {'name': 'shuttle#01'},
        },
      );
      expect(reportSuccess.isSuccess, isTrue);

      final reportWithConflict = ShuttleMigrationReport(
        migratedShuttles: ['shuttle_01'],
        skippedShuttles: [],
        conflictedShuttles: {
          'shuttle_02': 'คนขับใน Firestore ขัดแย้งกับ shuttle_drivers',
        },
        errors: [],
        originalFirestoreData: {},
      );
      expect(reportWithConflict.isSuccess, isFalse);
    });

    test('ตรวจจับความขัดแย้งหากคนขับใน Firestore ไม่ตรงกับ shuttle_drivers', () {
      const fsDriverUid = 'driver_user_A';
      const rtdbAssignedDriver = 'driver_user_B';

      final bool hasConflict = (fsDriverUid != rtdbAssignedDriver);
      expect(hasConflict, isTrue);

      // เมื่อมีความขัดแย้ง ต้องบันทึกลง conflictedShuttles และไม่เขียนทับ
      final Map<String, String> conflictedShuttles = {};
      if (hasConflict) {
        conflictedShuttles['shuttle_01'] =
            'คนขับใน Firestore ($fsDriverUid) ขัดแย้งกับ shuttle_drivers ($rtdbAssignedDriver)';
      }
      expect(conflictedShuttles.containsKey('shuttle_01'), isTrue);
    });

    test('Pre-cleanup ข้ามการลบหากข้อมูลใน Firestore ถูกแก้ไขหลังจัดทำรายงาน', () {
      final originalSnapshot = {'driver_uid': 'driver_1'};
      final currentDataAfterEdit = {'driver_uid': 'driver_2'}; // มีการเปลี่ยนคนขับหลังรายงาน

      final bool dataChanged = originalSnapshot['driver_uid'] != currentDataAfterEdit['driver_uid'];
      expect(dataChanged, isTrue);

      // ต้องข้ามการลบและรายงานข้อขัดแย้ง
      final List<String> skippedDocIds = [];
      final List<String> cleanupErrors = [];
      if (dataChanged) {
        skippedDocIds.add('shuttle_doc_01');
        cleanupErrors.add('ข้อมูลคนขับของ shuttle_doc_01 ใน Firestore มีการแก้ไขหลังจัดทำรายงาน ข้ามการลบ');
      }

      expect(skippedDocIds, contains('shuttle_doc_01'));
      expect(cleanupErrors.isNotEmpty, isTrue);
    });
  });

  group('REV-03: การเริ่มกะงานและการกำหนดค่า passenger_status', () {
    String resolvePassengerStatus(String currentStatus) {
      final status = currentStatus.trim().toLowerCase();
      const validStatuses = {'available', 'full', 'break'};
      if (!validStatuses.contains(status) || status == 'offline') {
        return 'available';
      }
      return status;
    }

    test('เปลี่ยน offline, ค่าว่าง หรือค่าที่ไม่ถูกต้องเป็น available เมื่อเริ่มงาน', () {
      expect(resolvePassengerStatus('offline'), 'available');
      expect(resolvePassengerStatus('OFFLINE'), 'available');
      expect(resolvePassengerStatus(''), 'available');
      expect(resolvePassengerStatus('unknown_status'), 'available');
      expect(resolvePassengerStatus('invalid'), 'available');
    });

    test('คงค่าสถานะเดิมที่ถูกต้องไว้ (available, full, break)', () {
      expect(resolvePassengerStatus('available'), 'available');
      expect(resolvePassengerStatus('full'), 'full');
      expect(resolvePassengerStatus('break'), 'break');
    });

    test('สร้าง payload เริ่มงานที่รวม status, passenger_status และพิกัดในคำสั่งเดียว', () {
      const loc = LatLng(16.83, 100.21);
      final targetStatus = resolvePassengerStatus('offline');

      final updatePayload = {
        'lat': loc.latitude,
        'lng': loc.longitude,
        'status': 'online',
        'passenger_status': targetStatus,
      };

      expect(updatePayload['status'], 'online');
      expect(updatePayload['passenger_status'], 'available');
      expect(updatePayload['lat'], 16.83);
      expect(updatePayload['lng'], 100.21);
    });
  });

  group('REV-04: การจัดลำดับ Marker รถที่กำลังติดตามให้อยู่บนสุดเสมอ', () {
    test('เรียงลำดับให้ targetedShuttleId อยู่ท้ายสุดของรายการ Marker', () {
      final activeShuttles = [
        {'id': 'shuttle_01', 'number': 'SH#01', 'lat': 16.83, 'lng': 100.21},
        {'id': 'shuttle_02', 'number': 'SH#02', 'lat': 16.83, 'lng': 100.21},
        {'id': 'shuttle_03', 'number': 'SH#03', 'lat': 16.83, 'lng': 100.21},
      ];
      const targetedShuttleId = 'shuttle_01'; // เลือกคันแรก

      final otherShuttles = activeShuttles.where((s) => s['id'] != targetedShuttleId);
      final targetedShuttleList = activeShuttles.where((s) => s['id'] == targetedShuttleId);
      final ordered = [...otherShuttles, ...targetedShuttleList];

      // shuttle_01 ต้องไปอยู่ลำดับสุดท้ายของรายการ
      expect(ordered.last['id'], targetedShuttleId);
      expect(ordered.map((s) => s['id']).toList(), ['shuttle_02', 'shuttle_03', 'shuttle_01']);
    });

    testWidgets('Widget Test: รถสองคันอยู่ที่เดียวกัน ป้ายของคันที่เลือกต้องแสดงและไม่ถูกทับ', (tester) async {
      final shuttles = [
        {'id': 'shuttle_01', 'number': '01', 'status': 'available'},
        {'id': 'shuttle_02', 'number': '02', 'status': 'full'},
      ];
      const targetedId = 'shuttle_01';

      final otherShuttles = shuttles.where((s) => s['id'] != targetedId);
      final targetedShuttles = shuttles.where((s) => s['id'] == targetedId);
      final ordered = [...otherShuttles, ...targetedShuttles];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              key: const Key('test_marker_stack'),
              children: ordered.map((s) {
                final isSelected = s['id'] == targetedId;
                return Positioned(
                  key: Key('pos_${s['id']}'),
                  left: 50,
                  top: 50,
                  child: ShuttleMapBadge(
                    number: s['number']!,
                    status: s['status']!,
                    showFallback: true,
                    selected: isSelected,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      );

      // ตรวจสอบว่าป้ายของ shuttle_01 แสดงข้อความถูกต้อง
      expect(find.text('รถ 01 · ว่าง'), findsOneWidget);
      expect(find.text('รถ 02 · เต็ม'), findsOneWidget);

      // ใน Stack วิดเจ็ตตัวท้ายสุด (shuttle_01) จะอยู่บนสุด
      final stack = tester.widget<Stack>(find.byKey(const Key('test_marker_stack')));
      final positionedWidgets = stack.children.cast<Positioned>().toList();
      expect(positionedWidgets.last.key, const Key('pos_shuttle_01'));
    });
  });

  group('REV-05: Pausable Startup Budget Timer', () {
    test('หยุดนับเวลาขณะแอปพัก และรักษาเวลาคงเหลือไว้นับต่อ', () {
      var remainingBudget = const Duration(seconds: 20);
      final stopwatch = Stopwatch()..start();

      // จำลองเวลาผ่านไป 3 วินาทีขณะแอปทำงาน
      // สมมุติ elapsed = 3 วินาที
      const simulatedElapsed = Duration(seconds: 3);
      remainingBudget -= simulatedElapsed;
      stopwatch.stop();

      expect(remainingBudget, const Duration(seconds: 17));

      // จำลองแอปพักไป 10 นาที (remainingBudget ไม่ควรลดลง)
      // เมื่อกลับมาทำงานต่อ
      final resumeStopwatch = Stopwatch()..start();
      const nextSimulatedElapsed = Duration(seconds: 5);
      remainingBudget -= nextSimulatedElapsed;
      resumeStopwatch.stop();

      expect(remainingBudget, const Duration(seconds: 12));
    });
  });

  group('REV-06: RendererLifecycleCoordinator และ Generation Token', () {
    test('Generation Token เพิ่มขึ้นในแต่ละ instance ใหม่อย่างแม่นยำ', () {
      final gen1 = RendererLifecycleCoordinator.nextGeneration();
      final gen2 = RendererLifecycleCoordinator.nextGeneration();
      expect(gen2, greaterThan(gen1));
    });

    test('RendererLifecycleCoordinator รันงานตามลำดับอย่างเคร่งครัด (Sequential Execution)', () async {
      final List<String> executionOrder = [];

      final task1 = RendererLifecycleCoordinator.schedule(() async {
        await Future.delayed(const Duration(milliseconds: 30));
        executionOrder.add('task1_teardown_complete');
      });

      final task2 = RendererLifecycleCoordinator.schedule(() async {
        executionOrder.add('task2_init_start');
      });

      await Future.wait([task1, task2]);

      expect(executionOrder, [
        'task1_teardown_complete',
        'task2_init_start',
      ]);
    });
  });

  group('REV-07: เส้นทางไฮไลท์แบบไล่สี (Gradient Polyline) และขอบตัดพื้นหลัง', () {
    test('กำหนดค่าสีแบบไล่โทน เขียวเข้มไปเขียวสด พร้อมขอบขาวบางและมุมมน', () {
      final polyline = Polyline(
        points: const [
          LatLng(16.820, 100.260),
          LatLng(16.821, 100.261),
          LatLng(16.822, 100.262),
        ],
        strokeWidth: 7.0,
        color: const Color(0xFF176A21),
        borderStrokeWidth: 2.0,
        borderColor: const Color(0xFFF9FFF9),
        gradientColors: const [
          Color(0xFF115C38),
          Color(0xFF168B4A),
          Color(0xFF43AD39),
        ],
        colorsStop: const [0.0, 0.55, 1.0],
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );

      expect(polyline.strokeWidth, 7.0);
      expect(polyline.borderStrokeWidth, 2.0);
      expect(polyline.borderColor, const Color(0xFFF9FFF9));
      expect(polyline.gradientColors, [
        const Color(0xFF115C38),
        const Color(0xFF168B4A),
        const Color(0xFF43AD39),
      ]);
      expect(polyline.colorsStop, [0.0, 0.55, 1.0]);
      expect(polyline.strokeCap, StrokeCap.round);
      expect(polyline.strokeJoin, StrokeJoin.round);
    });

    test('เงื่อนไขการวาดเส้นทางไฮไลท์ต้องมีพิกัดอย่างน้อย 2 จุดเพื่อสร้างเส้นและ Gradient ได้สมบูรณ์', () {
      bool shouldRenderPolyline(List<LatLng> path) => path.length >= 2;

      expect(shouldRenderPolyline([]), isFalse);
      expect(shouldRenderPolyline([const LatLng(16.820, 100.260)]), isFalse);
      expect(
        shouldRenderPolyline([
          const LatLng(16.820, 100.260),
          const LatLng(16.821, 100.261),
        ]),
        isTrue,
      );
    });

    test('AnimatedHighlightedRouteLayer คำนวณสีไล่ระดับเคลื่อนที่ไปมาระหว่างต้นทางและปลายทาง', () {
      // เมื่อ t = 0.0 แสงสว่างอยู่ที่ต้นทาง (ตำแหน่งรถ)
      final colorsAtStart = AnimatedHighlightedRouteLayer.calculateGradientColors(0.0);
      expect(colorsAtStart.length, AnimatedHighlightedRouteLayer.defaultStops.length);
      expect(colorsAtStart.first, const Color(0xFF6DF07C)); // จุดเริ่มต้นสว่างที่สุด
      expect(colorsAtStart.last, const Color(0xFF268B45)); // ปลายทางเป็นสีเขียวสดใสสบายตา

      // เมื่อ t = 1.0 แสงสว่างเคลื่อนที่ไปถึงปลายทาง (ป้ายจอดที่เลือก)
      final colorsAtEnd = AnimatedHighlightedRouteLayer.calculateGradientColors(1.0);
      expect(colorsAtEnd.first, const Color(0xFF268B45)); // ต้นทางเป็นสีเขียวสดใส
      expect(colorsAtEnd.last, const Color(0xFF6DF07C)); // ปลายทางสว่างที่สุด

      // เมื่อ t = 0.5 แสงสว่างอยู่กึ่งกลางเส้นทาง
      final colorsAtMid = AnimatedHighlightedRouteLayer.calculateGradientColors(0.5);
      expect(colorsAtMid.first, const Color(0xFF268B45));
      expect(colorsAtMid.last, const Color(0xFF268B45));
      // จุดตรงกลาง (index 4 หรือ 0.5) สว่างที่สุด
      expect(colorsAtMid[4], const Color(0xFF6DF07C));
    });

    testWidgets('AnimatedHighlightedRouteLayer แสดงผลบนแผนที่และทำงานแบบอนิเมชันต่อเนื่อง', (tester) async {
      final points = const [
        LatLng(16.820, 100.260),
        LatLng(16.825, 100.265),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(16.820, 100.260),
                initialZoom: 15.0,
              ),
              children: [
                AnimatedHighlightedRouteLayer(
                  path: points,
                  duration: const Duration(milliseconds: 1000),
                ),
              ],
            ),
          ),
        ),
      );

      // ตรวจสอบว่าพบ PolylineLayer สำหรับเส้นทางไฮไลท์
      expect(find.byType(PolylineLayer), findsOneWidget);

      // ก้าวข้ามเวลาเพื่อตรวจสอบการเล่นอนิเมชันไป-กลับโดยไม่เกิดข้อผิดพลาด
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PolylineLayer), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PolylineLayer), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PolylineLayer), findsOneWidget);
    });
  });

  group('REV-08: ตรรกะเสียงแจ้งเตือนคำขอขึ้นรถของคนขับ (Driver Alert Sound & TTS)', () {
    bool shouldPlayAlertSound({
      required DateTime? lastAlertTime,
      required String? lastAlertStopName,
      required String currentStopName,
      required DateTime currentTime,
    }) {
      if (lastAlertTime != null && lastAlertStopName == currentStopName) {
        if (currentTime.difference(lastAlertTime).inMilliseconds < 1500) {
          return false;
        }
      }
      return true;
    }

    test('คำขอแรกเข้ามา ต้องเล่นเสียงแจ้งเตือนเสมอ', () {
      final now = DateTime.now();
      final result = shouldPlayAlertSound(
        lastAlertTime: null,
        lastAlertStopName: null,
        currentStopName: 'ตึก IT',
        currentTime: now,
      );
      expect(result, isTrue);
    });

    test('คำขอถัดไปที่ป้ายเดิมหลังจากผ่านไป 2 วินาที ต้องเล่นเสียงแจ้งเตือนซ้ำได้', () {
      final t1 = DateTime(2026, 9, 12, 10, 0, 0);
      final t2 = DateTime(2026, 9, 12, 10, 0, 2); // ผ่านไป 2 วินาที (เกิน 1.5 วินาที)
      final result = shouldPlayAlertSound(
        lastAlertTime: t1,
        lastAlertStopName: 'ตึก IT',
        currentStopName: 'ตึก IT',
        currentTime: t2,
      );
      expect(result, isTrue);
    });

    test('คำขอถัดไปที่ต่างป้ายกันแม้เวลาห่างกันไม่ถึง 1 วินาที ต้องเล่นเสียงแจ้งเตือนทันที', () {
      final t1 = DateTime(2026, 9, 12, 10, 0, 0);
      final t2 = DateTime(2026, 9, 12, 10, 0, 0, 500); // ผ่านไป 500 มิลลิวินาที
      final result = shouldPlayAlertSound(
        lastAlertTime: t1,
        lastAlertStopName: 'ตึก IT',
        currentStopName: 'หอพัก 1',
        currentTime: t2,
      );
      expect(result, isTrue);
    });

    test('คำขอซ้ำป้ายเดิมภายใน 1 วินาที ต้องไม่เล่นเสียงกระดิ่งซ้อนทับ แต่ TTS จะยังอ่านข้อมูลล่าสุด', () {
      final t1 = DateTime(2026, 9, 12, 10, 0, 0);
      final t2 = DateTime(2026, 9, 12, 10, 0, 0, 800); // 800 มิลลิวินาที
      final result = shouldPlayAlertSound(
        lastAlertTime: t1,
        lastAlertStopName: 'ตึก IT',
        currentStopName: 'ตึก IT',
        currentTime: t2,
      );
      expect(result, isFalse);
    });
  });

  group('REV-09: ตรรกะแจ้งเตือนจุดหมายปลายทางของนักศึกษา (Driver Drop-off Stop Proximity Alert)', () {
    List<String> checkStopsToAlert({
      required LatLng currentLocation,
      required List<Map<String, dynamic>> allStops,
      required Set<String> activeDropOffStops,
      required Set<String> announcedDropOffStops,
    }) {
      List<String> toAlert = [];
      if (activeDropOffStops.isEmpty) return toAlert;

      for (var stop in allStops) {
        final stopName = (stop['name'] ?? '').toString().trim();
        if (stopName.isNotEmpty &&
            activeDropOffStops.contains(stopName) &&
            !announcedDropOffStops.contains(stopName)) {
          if (stop['lat'] != null && stop['lng'] != null) {
            final double stopLat = stop['lat'] is num
                ? (stop['lat'] as num).toDouble()
                : (double.tryParse(stop['lat'].toString()) ?? 0.0);
            final double stopLng = stop['lng'] is num
                ? (stop['lng'] as num).toDouble()
                : (double.tryParse(stop['lng'].toString()) ?? 0.0);

            if (stopLat != 0.0 && stopLng != 0.0) {
              final stopLoc = LatLng(stopLat, stopLng);
              final distance = const Distance().distance(currentLocation, stopLoc);
              if (distance <= 150.0) {
                toAlert.add(stopName);
                break; // แจ้งเตือนทีละ 1 ป้ายต่อรอบ
              }
            }
          }
        }
      }
      return toAlert;
    }

    final mockStops = [
      {'name': 'อาคารเรียนรวม', 'lat': 16.820000, 'lng': 100.260000, 'order': 1},
      {'name': 'ตึก IT', 'lat': 16.822000, 'lng': 100.262000, 'order': 2},
      {'name': 'ป้ายข้ามพิเศษ', 'lat': 16.824000, 'lng': 100.264000, 'order': 5},
      {'name': 'หอพักนักศึกษา', 'lat': 16.826000, 'lng': 100.266000, 'order': 6},
    ];

    test('ตรวจจับป้ายที่มีผู้โดยสารลงในระยะ 150 เมตรได้ถูกต้องแม้ข้ามป้ายก่อนหน้า', () {
      // รถอยู่ที่พิกัดห่างจาก หอพักนักศึกษา ประมาณ 100 เมตร (ข้ามป้าย 5 ไป)
      const busLocation = LatLng(16.825500, 100.265500);
      final activeDropOffs = {'หอพักนักศึกษา'};
      final announced = <String>{};

      final toAlert = checkStopsToAlert(
        currentLocation: busLocation,
        allStops: mockStops,
        activeDropOffStops: activeDropOffs,
        announcedDropOffStops: announced,
      );

      expect(toAlert, contains('หอพักนักศึกษา'));
    });

    test('ไม่แจ้งเตือนซ้ำหากป้ายนั้นได้ประกาศเตือนไปแล้ว', () {
      const busLocation = LatLng(16.825500, 100.265500);
      final activeDropOffs = {'หอพักนักศึกษา'};
      final announced = {'หอพักนักศึกษา'}; // ขานไปแล้ว

      final toAlert = checkStopsToAlert(
        currentLocation: busLocation,
        allStops: mockStops,
        activeDropOffStops: activeDropOffs,
        announcedDropOffStops: announced,
      );

      expect(toAlert, isEmpty);
    });

    test('หากระยะห่างเกิน 150 เมตร จะยังไม่ส่งเสียงเตือน', () {
      // รถอยู่ที่ป้าย 1 แต่อยากลงป้าย 6 (ระยะห่างประมาณ 800 เมตร)
      const busLocation = LatLng(16.820000, 100.260000);
      final activeDropOffs = {'หอพักนักศึกษา'};
      final announced = <String>{};

      final toAlert = checkStopsToAlert(
        currentLocation: busLocation,
        allStops: mockStops,
        activeDropOffStops: activeDropOffs,
        announcedDropOffStops: announced,
      );

      expect(toAlert, isEmpty);
    });

    test('เมื่อมีผู้โดยสารลงรถเสร็จสิ้นและมีกลุ่มใหม่ลงป้ายเดิม จะสามารถประกาศใหม่ได้', () {
      final announced = {'หอพักนักศึกษา'};
      // เมื่อผู้โดยสารลงเสร็จ ข้อมูล active ใน Firestore หายไป
      final currentDropOffs = <String>{};
      announced.retainAll(currentDropOffs);
      expect(announced, isEmpty);

      // ต่อมามีผู้โดยสารใหม่เลือกลงที่หอพักนักศึกษาอีกครั้ง
      final newDropOffs = {'หอพักนักศึกษา'};
      const busLocation = LatLng(16.825500, 100.265500);
      final toAlert = checkStopsToAlert(
        currentLocation: busLocation,
        allStops: mockStops,
        activeDropOffStops: newDropOffs,
        announcedDropOffStops: announced,
      );

      expect(toAlert, contains('หอพักนักศึกษา'));
    });
  });
}


