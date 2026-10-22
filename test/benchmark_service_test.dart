import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/services/benchmark_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ระบบทดสอบจริงแบบใหม่ 2 ช่วง (Pick-up ETA & Destination ETA)', () {
    late BenchmarkService bm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      bm = BenchmarkService.instance;
      await bm.resetAll();
      bm.startRecording();
    });

    tearDown(() {
      bm.stopRecording();
    });

    test('คำนวณระยะทางแบบ Forward Loop และสมการ ETA ได้ถูกต้อง', () {
      final sampleStops = [
        {'order': 1, 'name': 'ป้าย 1 ประตูหน้า', 'lat': 16.8200, 'lng': 100.2600},
        {'order': 2, 'name': 'ป้าย 2 อาคารเรียน', 'lat': 16.8220, 'lng': 100.2620},
        {'order': 3, 'name': 'ป้าย 3 หอพัก', 'lat': 16.8240, 'lng': 100.2640},
      ];

      final dist = BenchmarkService.calculateForwardRouteDistance(
        currentLoc: const LatLng(16.8190, 100.2590),
        targetStopOrder: 3,
        lastPassedStopOrder: 1,
        currentTargetStopOrder: 2,
        busStops: sampleStops,
      );
      expect(dist, greaterThan(0));

      final etaSec = BenchmarkService.calculateModelEtaSeconds(
        routeDistanceMeters: 700.0,
        stopsAhead: 2,
      );
      // v = 7.0 m/s -> 700/7 = 100s, dwell = 2 * 12s = 24s -> 124s
      expect(etaSec, equals(124.0));
    });

    test('การบันทึกคำขอของนักศึกษาช่วงที่ 1 (Pick-up ETA) และคำนวณ MAE/RMSE ถูกต้อง', () {
      // 1. นักศึกษากดเรียกรถ
      bm.recordStudentRequestCreated(
        requestId: 'req_001',
        stopName: 'ป้าย 3 หอพัก',
        stopOrder: 3,
        distanceMeters: 600.0,
        predictedEtaSeconds: 100.0,
      );

      expect(bm.currentRound.studentRideRequests.length, equals(1));
      final req = bm.currentRound.studentRideRequests.first;
      expect(req.requestId, equals('req_001'));
      expect(req.boardedTime, isNull);

      // 2. รถมาถึงป้าย 3 -> นักศึกษาขึ้นรถ (markBoarded)
      bm.recordStopArrival(3);

      expect(req.boardedTime, isNotNull);
      expect(req.actualWaitSeconds, isNotNull);
      expect(req.errorSeconds, isNotNull);
      expect(bm.currentRound.pickUpMAE, greaterThanOrEqualTo(0.0));
      expect(bm.currentRound.pickUpRMSE, greaterThanOrEqualTo(0.0));
    });

    test('การเดินทางช่วงที่ 2 (Destination ETA) เริ่มต้นอัตโนมัติเมื่อขึ้นรถและจบลงเมื่อถึงจุดหมาย', () {
      // 1. สร้างคำขอ
      bm.recordStudentRequestCreated(
        requestId: 'req_002',
        stopName: 'ป้าย 1 ประตูหน้า',
        stopOrder: 1,
        distanceMeters: 500.0,
        predictedEtaSeconds: 80.0,
      );

      // 2. รถถึงป้าย 1 -> นักศึกษาขึ้นรถ และระบบจะเริ่มบันทึก Destination trip
      bm.recordStopArrival(1);

      expect(bm.currentRound.destinationTrips.length, equals(1));
      final trip = bm.currentRound.destinationTrips.first;
      expect(trip.pickupStopOrder, equals(1));
      expect(trip.destinationStopOrder, greaterThan(1));
      expect(trip.initialPredictedDestinationEtaSeconds, greaterThan(0));
      expect(trip.arrivedTime, isNull);

      // 3. รถแล่นไปถึงป้ายปลายทางของนักศึกษา
      bm.recordStopArrival(trip.destinationStopOrder);

      expect(trip.arrivedTime, isNotNull);
      expect(trip.actualTravelSeconds, isNotNull);
      expect(trip.errorSeconds, isNotNull);

      // ตรวจสอบสถิติช่วงที่ 2
      expect(bm.currentRound.destinationMAE, greaterThanOrEqualTo(0.0));
      expect(bm.currentRound.destinationRMSE, greaterThanOrEqualTo(0.0));

      // ตรวจสอบสถิติรวมตลอดวงจร (Overall Real ETA)
      expect(bm.currentRound.allRealEtaErrors.length, equals(2));
      expect(bm.currentRound.overallRealEtaMAE, greaterThanOrEqualTo(0.0));
      expect(bm.currentRound.overallRealEtaRMSE, greaterThanOrEqualTo(0.0));
    });

    test('การข้ามป้าย (Bypass) จะไม่นำข้อมูลป้ายที่ถูกข้ามมาคิดความคลาดเคลื่อน', () {
      bm.recordStudentRequestCreated(
        requestId: 'req_005',
        stopName: 'ป้าย 5 สาขาวิศวกรรม',
        stopOrder: 5,
        distanceMeters: 400.0,
        predictedEtaSeconds: 70.0,
      );

      // จำลองการข้ามป้าย 5 (Conditional Bypass)
      bm.recordStopSkipped(5);

      final req = bm.currentRound.studentRideRequests.first;
      expect(req.isSkipped, isTrue);
      expect(bm.currentRound.skippedStops.contains(5), isTrue);
      // ป้ายที่ถูกข้ามจะไม่ถูกนำมาคำนวณใน studentRequestErrors
      expect(bm.currentRound.studentRequestErrors, isEmpty);
    });

    test('การสร้างข้อความตารางที่ 2 และส่งออกไฟล์ CSV มีรูปแบบใหม่ครบถ้วน', () {
      // จำลองข้อมูล 1 รายการ
      bm.recordStudentRequestCreated(
        requestId: 'req_test',
        stopName: 'ป้าย 2',
        stopOrder: 2,
        distanceMeters: 300.0,
        predictedEtaSeconds: 50.0,
      );
      bm.recordStopArrival(2);

      final summaryText = bm.generateTable2SummaryText();
      expect(summaryText.contains('ช่วงที่ 1: เวลารถมารับ ณ จุดรอรถ (Pick-up ETA)'), isTrue);
      expect(summaryText.contains('ช่วงที่ 2: เวลาเดินทางบนรถจนถึงจุดหมาย (Destination ETA)'), isTrue);
      expect(summaryText.contains('ภาพรวมตลอดวงจรการเดินทางจริง (Overall Real ETA)'), isTrue);

      final csvRounds = bm.exportRoundsSummaryCSV();
      expect(csvRounds.contains('PickUp_MAE_s'), isTrue);
      expect(csvRounds.contains('Dest_MAE_s'), isTrue);
      expect(csvRounds.contains('Overall_Real_MAE_s'), isTrue);

      final csvDest = bm.exportDestinationTripsCSV();
      expect(csvDest.contains('PickupStopOrder'), isTrue);
      expect(csvDest.contains('DestStopOrder'), isTrue);
    });

    test('simulateCompleteRoundData จำลองข้อมูลครบ 1 รอบ ทั้ง 2 ช่วง ได้อย่างสมบูรณ์', () {
      bm.simulateCompleteRoundData();

      expect(bm.currentRound.mapMatchingErrors.length, equals(30));
      expect(bm.currentRound.latencyValues.length, equals(20));
      expect(bm.currentRound.dispatchRecords.isNotEmpty, isTrue);
      expect(bm.currentRound.studentRideRequests.isNotEmpty, isTrue);
      expect(bm.currentRound.destinationTrips.isNotEmpty, isTrue);

      // ตรวจสอบว่าคำนวณ MAE และ RMSE ทั้ง 2 ช่วงได้สำเร็จ
      expect(bm.currentRound.pickUpMAE, greaterThan(0.0));
      expect(bm.currentRound.pickUpRMSE, greaterThan(0.0));
      expect(bm.currentRound.destinationMAE, greaterThan(0.0));
      expect(bm.currentRound.destinationRMSE, greaterThan(0.0));
      expect(bm.currentRound.overallRealEtaMAE, greaterThan(0.0));
      expect(bm.currentRound.overallRealEtaRMSE, greaterThan(0.0));
    });
  });
}
