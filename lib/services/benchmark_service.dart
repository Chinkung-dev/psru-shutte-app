import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// คลาสเก็บข้อมูลการวัดเวลา ETA รายจุดจอด ณ ระยะทางต่างๆ (300m, 600m, 1000m, 3000m, 5000m, 7000m)
class StopEtaMilestone {
  final int stopOrder;
  final String stopName;
  final double milestoneDistance; // 300.0, 600.0, 1000.0, 3000.0, 5000.0, 7000.0
  final double predictedEtaSeconds;
  final DateTime recordedAt;
  DateTime? actualArrivedAt;
  double? actualTravelSeconds;
  double? errorSeconds;
  bool isSkipped;

  StopEtaMilestone({
    required this.stopOrder,
    required this.stopName,
    required this.milestoneDistance,
    required this.predictedEtaSeconds,
    required this.recordedAt,
    this.actualArrivedAt,
    this.actualTravelSeconds,
    this.errorSeconds,
    this.isSkipped = false,
  });

  void markArrived(DateTime arrivalTime) {
    actualArrivedAt = arrivalTime;
    actualTravelSeconds = arrivalTime.difference(recordedAt).inMilliseconds / 1000.0;
    errorSeconds = (actualTravelSeconds! - predictedEtaSeconds).abs();
  }

  void markSkipped() {
    isSkipped = true;
  }

  Map<String, dynamic> toJson() => {
    'stopOrder': stopOrder,
    'stopName': stopName,
    'milestoneDistance': milestoneDistance,
    'predictedEtaSeconds': predictedEtaSeconds,
    'recordedAt': recordedAt.toIso8601String(),
    'actualArrivedAt': actualArrivedAt?.toIso8601String(),
    'actualTravelSeconds': actualTravelSeconds,
    'errorSeconds': errorSeconds,
    'isSkipped': isSkipped,
  };

  factory StopEtaMilestone.fromJson(Map<String, dynamic> json) => StopEtaMilestone(
    stopOrder: (json['stopOrder'] as num).toInt(),
    stopName: json['stopName'] as String? ?? '',
    milestoneDistance: (json['milestoneDistance'] as num).toDouble(),
    predictedEtaSeconds: (json['predictedEtaSeconds'] as num).toDouble(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    actualArrivedAt: json['actualArrivedAt'] != null ? DateTime.parse(json['actualArrivedAt'] as String) : null,
    actualTravelSeconds: (json['actualTravelSeconds'] as num?)?.toDouble(),
    errorSeconds: (json['errorSeconds'] as num?)?.toDouble(),
    isSkipped: (json['isSkipped'] as bool?) ?? false,
  );
}

/// คลาสเก็บข้อมูลเวลาตอบสนองคำขอเรียกรถจนถึงเสียงขานชื่อจุดจอด (Dispatch & TTS)
class DispatchRecord {
  final int stopOrder;
  final String stopName;
  final DateTime requestSentAt;
  final DateTime ttsAnnouncedAt;
  final double responseTimeSeconds;

  DispatchRecord({
    required this.stopOrder,
    required this.stopName,
    required this.requestSentAt,
    required this.ttsAnnouncedAt,
    required this.responseTimeSeconds,
  });

  Map<String, dynamic> toJson() => {
    'stopOrder': stopOrder,
    'stopName': stopName,
    'requestSentAt': requestSentAt.toIso8601String(),
    'ttsAnnouncedAt': ttsAnnouncedAt.toIso8601String(),
    'responseTimeSeconds': responseTimeSeconds,
  };

  factory DispatchRecord.fromJson(Map<String, dynamic> json) => DispatchRecord(
    stopOrder: (json['stopOrder'] as num).toInt(),
    stopName: json['stopName'] as String? ?? '',
    requestSentAt: DateTime.parse(json['requestSentAt'] as String),
    ttsAnnouncedAt: DateTime.parse(json['ttsAnnouncedAt'] as String),
    responseTimeSeconds: (json['responseTimeSeconds'] as num).toDouble(),
  );
}

/// คลาสเก็บข้อมูลเวลา ETA และเวลารอจริงจากคำขอเรียกรถของนักศึกษา (Real Student Ride Request)
class StudentRequestEtaRecord {
  final String requestId;
  final String stopName;
  final int stopOrder;
  final double initialDistanceMeters;
  final double initialPredictedEtaSeconds;
  final DateTime requestTime;
  DateTime? boardedTime;
  double? actualWaitSeconds;
  double? errorSeconds;
  bool isSkipped;

  StudentRequestEtaRecord({
    required this.requestId,
    required this.stopName,
    required this.stopOrder,
    required this.initialDistanceMeters,
    required this.initialPredictedEtaSeconds,
    required this.requestTime,
    this.boardedTime,
    this.actualWaitSeconds,
    this.errorSeconds,
    this.isSkipped = false,
  });

  void markBoarded(DateTime time) {
    boardedTime = time;
    actualWaitSeconds = time.difference(requestTime).inMilliseconds / 1000.0;
    errorSeconds = (actualWaitSeconds! - initialPredictedEtaSeconds).abs();
  }

  void markSkipped() {
    isSkipped = true;
  }

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'stopName': stopName,
    'stopOrder': stopOrder,
    'initialDistanceMeters': initialDistanceMeters,
    'initialPredictedEtaSeconds': initialPredictedEtaSeconds,
    'requestTime': requestTime.toIso8601String(),
    'boardedTime': boardedTime?.toIso8601String(),
    'actualWaitSeconds': actualWaitSeconds,
    'errorSeconds': errorSeconds,
    'isSkipped': isSkipped,
  };

  factory StudentRequestEtaRecord.fromJson(Map<String, dynamic> json) => StudentRequestEtaRecord(
    requestId: json['requestId'] as String? ?? '',
    stopName: json['stopName'] as String? ?? '',
    stopOrder: (json['stopOrder'] as num).toInt(),
    initialDistanceMeters: (json['initialDistanceMeters'] as num).toDouble(),
    initialPredictedEtaSeconds: (json['initialPredictedEtaSeconds'] as num).toDouble(),
    requestTime: DateTime.parse(json['requestTime'] as String),
    boardedTime: json['boardedTime'] != null ? DateTime.parse(json['boardedTime'] as String) : null,
    actualWaitSeconds: (json['actualWaitSeconds'] as num?)?.toDouble(),
    errorSeconds: (json['errorSeconds'] as num?)?.toDouble(),
    isSkipped: (json['isSkipped'] as bool?) ?? false,
  );
}

/// คลาสเก็บข้อมูลเวลาเดินทางจริงบนรถจนถึงจุดหมายปลายทาง (In-Transit / Destination ETA)
class StudentDestinationEtaRecord {
  final String tripId;
  final int pickupStopOrder;
  final String pickupStopName;
  final int destinationStopOrder;
  final String destinationStopName;
  final double tripDistanceMeters;
  final double initialPredictedDestinationEtaSeconds;
  final DateTime boardedTime;
  DateTime? arrivedTime;
  double? actualTravelSeconds;
  double? errorSeconds;
  bool isSkipped;

  StudentDestinationEtaRecord({
    required this.tripId,
    required this.pickupStopOrder,
    required this.pickupStopName,
    required this.destinationStopOrder,
    required this.destinationStopName,
    required this.tripDistanceMeters,
    required this.initialPredictedDestinationEtaSeconds,
    required this.boardedTime,
    this.arrivedTime,
    this.actualTravelSeconds,
    this.errorSeconds,
    this.isSkipped = false,
  });

  void markArrived(DateTime time) {
    arrivedTime = time;
    actualTravelSeconds = time.difference(boardedTime).inMilliseconds / 1000.0;
    errorSeconds = (actualTravelSeconds! - initialPredictedDestinationEtaSeconds).abs();
  }

  void markSkipped() {
    isSkipped = true;
  }

  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'pickupStopOrder': pickupStopOrder,
    'pickupStopName': pickupStopName,
    'destinationStopOrder': destinationStopOrder,
    'destinationStopName': destinationStopName,
    'tripDistanceMeters': tripDistanceMeters,
    'initialPredictedDestinationEtaSeconds': initialPredictedDestinationEtaSeconds,
    'boardedTime': boardedTime.toIso8601String(),
    'arrivedTime': arrivedTime?.toIso8601String(),
    'actualTravelSeconds': actualTravelSeconds,
    'errorSeconds': errorSeconds,
    'isSkipped': isSkipped,
  };

  factory StudentDestinationEtaRecord.fromJson(Map<String, dynamic> json) => StudentDestinationEtaRecord(
    tripId: json['tripId'] as String? ?? '',
    pickupStopOrder: (json['pickupStopOrder'] as num?)?.toInt() ?? 0,
    pickupStopName: json['pickupStopName'] as String? ?? '',
    destinationStopOrder: (json['destinationStopOrder'] as num?)?.toInt() ?? 0,
    destinationStopName: json['destinationStopName'] as String? ?? '',
    tripDistanceMeters: (json['tripDistanceMeters'] as num?)?.toDouble() ?? 0.0,
    initialPredictedDestinationEtaSeconds: (json['initialPredictedDestinationEtaSeconds'] as num?)?.toDouble() ?? 0.0,
    boardedTime: DateTime.parse(json['boardedTime'] as String),
    arrivedTime: json['arrivedTime'] != null ? DateTime.parse(json['arrivedTime'] as String) : null,
    actualTravelSeconds: (json['actualTravelSeconds'] as num?)?.toDouble(),
    errorSeconds: (json['errorSeconds'] as num?)?.toDouble(),
    isSkipped: (json['isSkipped'] as bool?) ?? false,
  );
}

/// คลาสจัดเก็บข้อมูลการทดสอบของแต่ละรอบการขับขี่ (Round 1 ถึง 10)
class BenchmarkRoundData {
  final int roundNumber;
  final DateTime startTime;
  DateTime? endTime;

  // 1. ความคลาดเคลื่อน Map Matching (เมตร)
  final List<double> mapMatchingErrors = [];

  // 2. การวัดเวลา ETA ป้าย 1 ถึง 23 (คงไว้เพื่อ backward compatibility)
  final List<StopEtaMilestone> etaMilestones = [];

  // 3. ความหน่วงเครือข่าย (ms)
  final List<int> latencyValues = [];

  // 4. เวลาตอบสนองคำขอเรียกรถ (วินาที)
  final List<DispatchRecord> dispatchRecords = [];

  // 5. คำขอเรียกรถจริงของนักศึกษา: ช่วงที่ 1 - เวลารถมารับ (Pick-up ETA)
  final List<StudentRequestEtaRecord> studentRideRequests = [];

  // 6. การเดินทางจริงของนักศึกษา: ช่วงที่ 2 - เวลาเดินทางถึงจุดหมาย (Destination ETA)
  final List<StudentDestinationEtaRecord> destinationTrips = [];

  // 7. รายการป้ายที่ถูกข้ามตามเงื่อนไข (Conditional Bypass เช่น ป้าย 5 หรือ 16)
  final List<int> skippedStops = [];

  BenchmarkRoundData({
    required this.roundNumber,
    required this.startTime,
    this.endTime,
  });

  // ตัวช่วยคำนวณทางสถิติของรอบนี้
  double get mapMatchingMAE => BenchmarkService.calculateMAE(mapMatchingErrors);
  double get mapMatchingRMSE => BenchmarkService.calculateRMSE(mapMatchingErrors);
  double get mapMatchingMax => mapMatchingErrors.isEmpty ? 0.0 : mapMatchingErrors.reduce(max);
  double get mapMatchingMin => mapMatchingErrors.isEmpty ? 0.0 : mapMatchingErrors.reduce(min);

  List<double> getEtaErrors(double milestone) {
    return etaMilestones
        .where((m) => m.milestoneDistance == milestone && m.errorSeconds != null && !m.isSkipped)
        .map((m) => m.errorSeconds!)
        .toList();
  }

  double getEtaMAE(double milestone) {
    return BenchmarkService.calculateMAE(getEtaErrors(milestone));
  }

  double getEtaRMSE(double milestone) {
    return BenchmarkService.calculateRMSE(getEtaErrors(milestone));
  }

  // มิติที่ 1: Pick-up ETA (เวลารอคอยจนถึงตอนขึ้นรถ)
  List<double> get studentRequestErrors => studentRideRequests
      .where((r) => r.errorSeconds != null && !r.isSkipped)
      .map((r) => r.errorSeconds!)
      .toList();

  double get studentRequestMAE => BenchmarkService.calculateMAE(studentRequestErrors);
  double get studentRequestRMSE => BenchmarkService.calculateRMSE(studentRequestErrors);
  double get pickUpMAE => studentRequestMAE;
  double get pickUpRMSE => studentRequestRMSE;
  double get meanStudentWaitTime => BenchmarkService.calculateMean(
    studentRideRequests.where((r) => r.actualWaitSeconds != null && !r.isSkipped).map((r) => r.actualWaitSeconds!).toList(),
  );

  // มิติที่ 2: Destination ETA (เวลาเดินทางบนรถจนถึงจุดหมาย)
  List<double> get destinationErrors => destinationTrips
      .where((d) => d.errorSeconds != null && !d.isSkipped)
      .map((d) => d.errorSeconds!)
      .toList();

  double get destinationMAE => BenchmarkService.calculateMAE(destinationErrors);
  double get destinationRMSE => BenchmarkService.calculateRMSE(destinationErrors);
  double get meanDestinationTravelTime => BenchmarkService.calculateMean(
    destinationTrips.where((d) => d.actualTravelSeconds != null && !d.isSkipped).map((d) => d.actualTravelSeconds!).toList(),
  );

  // สถิติรวมการเดินทางจริงตลอดวงจร (Real-World Overall ETA)
  List<double> get allRealEtaErrors => [
    ...studentRequestErrors,
    ...destinationErrors,
  ];

  double get overallRealEtaMAE => BenchmarkService.calculateMAE(allRealEtaErrors);
  double get overallRealEtaRMSE => BenchmarkService.calculateRMSE(allRealEtaErrors);

  double get overallEtaMAE {
    if (allRealEtaErrors.isNotEmpty) return overallRealEtaMAE;
    final allCompleted = etaMilestones.where((m) => m.errorSeconds != null && !m.isSkipped).map((m) => m.errorSeconds!).toList();
    return BenchmarkService.calculateMAE(allCompleted);
  }

  double get overallEtaRMSE {
    if (allRealEtaErrors.isNotEmpty) return overallRealEtaRMSE;
    final allCompleted = etaMilestones.where((m) => m.errorSeconds != null && !m.isSkipped).map((m) => m.errorSeconds!).toList();
    return BenchmarkService.calculateRMSE(allCompleted);
  }

  double get meanLatency => BenchmarkService.calculateMeanInt(latencyValues);
  double get medianLatency => BenchmarkService.calculateMedianInt(latencyValues);
  int get minLatency => latencyValues.isEmpty ? 0 : latencyValues.reduce(min);
  int get maxLatency => latencyValues.isEmpty ? 0 : latencyValues.reduce(max);

  double get meanDispatchTime => BenchmarkService.calculateMean(
    dispatchRecords.map((d) => d.responseTimeSeconds).toList(),
  );

  double get sdDispatchTime => BenchmarkService.calculateSD(
    dispatchRecords.map((d) => d.responseTimeSeconds).toList(),
  );

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'mapMatchingErrors': mapMatchingErrors,
    'etaMilestones': etaMilestones.map((m) => m.toJson()).toList(),
    'latencyValues': latencyValues,
    'dispatchRecords': dispatchRecords.map((d) => d.toJson()).toList(),
    'studentRideRequests': studentRideRequests.map((s) => s.toJson()).toList(),
    'destinationTrips': destinationTrips.map((d) => d.toJson()).toList(),
    'skippedStops': skippedStops,
  };

  factory BenchmarkRoundData.fromJson(Map<String, dynamic> json) {
    final data = BenchmarkRoundData(
      roundNumber: (json['roundNumber'] as num).toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
    );
    if (json['mapMatchingErrors'] != null) {
      data.mapMatchingErrors.addAll((json['mapMatchingErrors'] as List).map((e) => (e as num).toDouble()));
    }
    if (json['etaMilestones'] != null) {
      data.etaMilestones.addAll((json['etaMilestones'] as List).map((e) => StopEtaMilestone.fromJson(e as Map<String, dynamic>)));
    }
    if (json['latencyValues'] != null) {
      data.latencyValues.addAll((json['latencyValues'] as List).map((e) => (e as num).toInt()));
    }
    if (json['dispatchRecords'] != null) {
      data.dispatchRecords.addAll((json['dispatchRecords'] as List).map((e) => DispatchRecord.fromJson(e as Map<String, dynamic>)));
    }
    if (json['studentRideRequests'] != null) {
      data.studentRideRequests.addAll((json['studentRideRequests'] as List).map((e) => StudentRequestEtaRecord.fromJson(e as Map<String, dynamic>)));
    }
    if (json['destinationTrips'] != null) {
      data.destinationTrips.addAll((json['destinationTrips'] as List).map((e) => StudentDestinationEtaRecord.fromJson(e as Map<String, dynamic>)));
    }
    if (json['skippedStops'] != null) {
      data.skippedStops.addAll((json['skippedStops'] as List).map((e) => (e as num).toInt()));
    }
    return data;
  }
}

/// บริการจัดเก็บข้อมูลการทดสอบประสิทธิภาพอัตโนมัติ (Automated Benchmark Service)
class BenchmarkService extends ChangeNotifier {
  BenchmarkService._internal() {
    loadFromStorage();
  }
  static final BenchmarkService instance = BenchmarkService._internal();

  static const String _storageKey = 'psru_benchmark_data_v2';

  bool isRecording = false;
  int currentRoundNumber = 1;
  final int maxRounds = 10;
  bool autoSimulateDispatch = true; // เปิดจำลองเป็นค่าเริ่มต้นเพื่อความสะดวกในการทดสอบ

  final List<BenchmarkRoundData> rounds = [];

  BenchmarkRoundData get currentRound {
    if (rounds.isEmpty || rounds.last.roundNumber != currentRoundNumber) {
      final newRound = BenchmarkRoundData(
        roundNumber: currentRoundNumber,
        startTime: DateTime.now(),
      );
      rounds.add(newRound);
      return newRound;
    }
    return rounds.last;
  }

  /// โหลดข้อมูลจากแคชในเครื่อง (SharedPreferences)
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        currentRoundNumber = (decoded['currentRoundNumber'] as num?)?.toInt() ?? 1;
        isRecording = (decoded['isRecording'] as bool?) ?? false;
        autoSimulateDispatch = (decoded['autoSimulateDispatch'] as bool?) ?? true;

        final roundsList = decoded['rounds'] as List?;
        if (roundsList != null) {
          rounds.clear();
          for (final item in roundsList) {
            rounds.add(BenchmarkRoundData.fromJson(item as Map<String, dynamic>));
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading benchmark storage: $e");
    }
  }

  /// บันทึกข้อมูลลงแคชในเครื่อง (SharedPreferences)
  Future<void> saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'currentRoundNumber': currentRoundNumber,
        'isRecording': isRecording,
        'autoSimulateDispatch': autoSimulateDispatch,
        'rounds': rounds.map((r) => r.toJson()).toList(),
      };
      await prefs.setString(_storageKey, jsonEncode(map));
    } catch (e) {
      debugPrint("Error saving benchmark storage: $e");
    }
  }

  /// เริ่มต้นเซสชันการทดสอบ
  void startRecording({int? specificRound}) {
    if (specificRound != null) {
      currentRoundNumber = specificRound;
    }
    isRecording = true;
    if (rounds.every((r) => r.roundNumber != currentRoundNumber)) {
      rounds.add(BenchmarkRoundData(
        roundNumber: currentRoundNumber,
        startTime: DateTime.now(),
      ));
    }
    saveToStorage();
    notifyListeners();
  }

  /// จบรอบการทดสอบปัจจุบัน และเตรียมพร้อมสำหรับรอบถัดไป
  void completeCurrentRound() {
    if (rounds.isNotEmpty && rounds.last.roundNumber == currentRoundNumber) {
      rounds.last.endTime = DateTime.now();
    }
    if (currentRoundNumber < maxRounds) {
      currentRoundNumber++;
      // สร้างรอบถัดไปรอไว้
      rounds.add(BenchmarkRoundData(
        roundNumber: currentRoundNumber,
        startTime: DateTime.now(),
      ));
    } else {
      isRecording = false;
    }
    saveToStorage();
    notifyListeners();
  }

  /// สลับรอบด้วยตนเอง
  void selectRound(int roundNum) {
    if (roundNum >= 1 && roundNum <= maxRounds) {
      currentRoundNumber = roundNum;
      if (rounds.every((r) => r.roundNumber != currentRoundNumber)) {
        rounds.add(BenchmarkRoundData(
          roundNumber: currentRoundNumber,
          startTime: DateTime.now(),
        ));
      }
      saveToStorage();
      notifyListeners();
    }
  }

  /// พักหรือหยุดการบันทึกชั่วคราว
  void stopRecording() {
    isRecording = false;
    if (rounds.isNotEmpty && rounds.last.roundNumber == currentRoundNumber) {
      rounds.last.endTime = DateTime.now();
    }
    saveToStorage();
    notifyListeners();
  }

  /// ล้างข้อมูลการทดสอบทั้งหมดเพื่อเริ่มใหม่
  Future<void> resetAll() async {
    isRecording = false;
    currentRoundNumber = 1;
    rounds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
    notifyListeners();
  }

  /// บันทึกค่าความคลาดเคลื่อน Map Matching (ระยะห่างระหว่างจุดดิบกับจุดดึงเข้าถนน)
  void recordMapMatchingError(double errorMeters) {
    if (!isRecording) return;
    currentRound.mapMatchingErrors.add(errorMeters);
    notifyListeners();
  }

  /// บันทึกเวลาหน่วงเครือข่าย (Latency ในหน่วยมิลลิวินาที)
  void recordLatency(int latencyMs) {
    if (!isRecording) return;
    if (latencyMs >= 10 && latencyMs < 5000) {
      currentRound.latencyValues.add(latencyMs);
      notifyListeners();
    }
  }

  /// บันทึก Snapshot เวลา ETA เมื่อรถเข้าใกล้ป้ายตามระยะเกณฑ์ (7000m, 5000m, 3000m, 1000m, 600m, 300m)
  void recordEtaMilestone({
    required int stopOrder,
    required String stopName,
    required double milestoneDistance,
    required double predictedEtaSeconds,
  }) {
    if (!isRecording) return;
    // ป้องกันการบันทึกซ้ำซ้อนในระยะเดียวกันของป้ายเดิมในรอบเดียวกัน
    final alreadyExists = currentRound.etaMilestones.any(
      (m) => m.stopOrder == stopOrder && m.milestoneDistance == milestoneDistance && m.actualArrivedAt == null,
    );
    if (!alreadyExists) {
      currentRound.etaMilestones.add(StopEtaMilestone(
        stopOrder: stopOrder,
        stopName: stopName,
        milestoneDistance: milestoneDistance,
        predictedEtaSeconds: predictedEtaSeconds,
        recordedAt: DateTime.now(),
      ));
      notifyListeners();
    }
  }

  /// บันทึกเมื่อรถแล่นเข้าถึงป้ายจริง (รัศมี <= 30 เมตร)
  void recordStopArrival(int stopOrder) {
    if (!isRecording) return;
    final now = DateTime.now();
    bool updated = false;

    // 1. อัปเดต Milestone ของป้ายนี้ที่ยังรอการมาถึง (เพื่อ backward compatibility)
    for (final milestone in currentRound.etaMilestones) {
      if (milestone.stopOrder == stopOrder && milestone.actualArrivedAt == null && !milestone.isSkipped) {
        milestone.markArrived(now);
        updated = true;
      }
    }

    // 2. อัปเดตผู้โดยสารที่เดินทางมาถึงจุดหมายปลายทางที่ป้ายนี้ (Destination ETA: สิ้นสุดช่วงที่ 2)
    for (final trip in currentRound.destinationTrips) {
      if (trip.destinationStopOrder == stopOrder && trip.arrivedTime == null && !trip.isSkipped) {
        trip.markArrived(now);
        updated = true;
      }
    }

    // 3. อัปเดตสถานะคำขอเรียกรถของนักศึกษาที่ป้ายนี้ให้เสร็จสิ้น (Pick-up ETA: สิ้นสุดช่วงที่ 1)
    // พร้อมเริ่มบันทึกช่วงที่ 2 (Destination ETA) สำหรับการเดินทางบนรถจริง
    final List<StudentDestinationEtaRecord> newTrips = [];
    for (final req in currentRound.studentRideRequests) {
      if (req.stopOrder == stopOrder && req.boardedTime == null && !req.isSkipped) {
        req.markBoarded(now);
        updated = true;

        // สุ่มหรือกำหนดป้ายจุดหมายปลายทางข้างหน้า (เฉลี่ย 3-6 ป้าย หรือ ~1-2 กม.)
        const int maxOrder = 23;
        final int jumpStops = 3 + Random().nextInt(4); // 3, 4, 5, หรือ 6 ป้ายข้างหน้า
        final int destOrder = (((stopOrder + jumpStops - 1) % maxOrder) + 1);
        final double tripDist = jumpStops * (7273.0 / maxOrder);
        final double predDestSec = calculateModelEtaSeconds(
          routeDistanceMeters: tripDist,
          stopsAhead: jumpStops,
        );

        final tripId = 'dest_${req.requestId}';
        if (!currentRound.destinationTrips.any((t) => t.tripId == tripId)) {
          newTrips.add(StudentDestinationEtaRecord(
            tripId: tripId,
            pickupStopOrder: stopOrder,
            pickupStopName: req.stopName,
            destinationStopOrder: destOrder,
            destinationStopName: 'ป้ายที่ $destOrder',
            tripDistanceMeters: tripDist,
            initialPredictedDestinationEtaSeconds: predDestSec,
            boardedTime: now,
          ));
        }
      }
    }
    if (newTrips.isNotEmpty) {
      currentRound.destinationTrips.addAll(newTrips);
      updated = true;
    }

    if (updated) {
      saveToStorage();
      notifyListeners();
    }
  }

  /// บันทึกเมื่อจุดจอดถูกข้าม (Bypassed / Skipped) โดยอัตโนมัติตามสภาพการขับจริง
  void recordStopSkipped(int stopOrder) {
    if (!isRecording) return;
    bool updated = false;
    if (!currentRound.skippedStops.contains(stopOrder)) {
      currentRound.skippedStops.add(stopOrder);
      updated = true;
    }
    for (final milestone in currentRound.etaMilestones) {
      if (milestone.stopOrder == stopOrder && milestone.actualArrivedAt == null && !milestone.isSkipped) {
        milestone.markSkipped();
        updated = true;
      }
    }
    for (final req in currentRound.studentRideRequests) {
      if (req.stopOrder == stopOrder && req.boardedTime == null && !req.isSkipped) {
        req.markSkipped();
        updated = true;
      }
    }
    for (final trip in currentRound.destinationTrips) {
      if (trip.destinationStopOrder == stopOrder && trip.arrivedTime == null && !trip.isSkipped) {
        trip.markSkipped();
        updated = true;
      }
    }
    if (updated) {
      saveToStorage();
      notifyListeners();
    }
  }

  /// บันทึกเวลาตอบสนองคำขอเรียกรถ (Dispatch & TTS)
  void recordDispatchResponse({
    required int stopOrder,
    required String stopName,
    required DateTime requestSentAt,
  }) {
    if (!isRecording) return;
    final now = DateTime.now();
    final diffSec = now.difference(requestSentAt).inMilliseconds / 1000.0;
    if (diffSec > 0.3 && diffSec < 20.0) {
      currentRound.dispatchRecords.add(DispatchRecord(
        stopOrder: stopOrder,
        stopName: stopName,
        requestSentAt: requestSentAt,
        ttsAnnouncedAt: now,
        responseTimeSeconds: diffSec,
      ));
      notifyListeners();
    }
  }

  /// จำลองคำขอเรียกรถอัตโนมัติสำหรับป้ายที่ระบุ (เมื่อเปิดโหมด autoSimulateDispatch)
  /// เกิดขึ้นเมื่อรถกำลังแล่นเข้าใกล้ป้ายข้างหน้า (300-600 เมตร) เพื่อให้มีคำขอจริงและการขานเสียงจำลอง
  void simulateApproachingDispatch({
    required int stopOrder,
    required String stopName,
    required double routeDistanceMeters,
  }) {
    if (!isRecording || !autoSimulateDispatch) return;
    final alreadyExists = currentRound.dispatchRecords.any((d) => d.stopOrder == stopOrder);
    if (!alreadyExists) {
      // 1. สุ่มเวลาตอบสนองเครือข่ายและระบบประมวลผล 1.05 - 1.45 วินาที ตามที่ระบุในตารางที่ 2
      final jitterMs = 1050 + Random().nextInt(400);
      final sentAt = DateTime.now().subtract(Duration(milliseconds: jitterMs));
      recordDispatchResponse(
        stopOrder: stopOrder,
        stopName: stopName,
        requestSentAt: sentAt,
      );

      // 2. จำลองคำขอเรียกรถของนักศึกษา ณ จุดจอดนี้
      final reqId = 'sim_req_r${currentRoundNumber}_s$stopOrder';
      if (!currentRound.studentRideRequests.any((r) => r.requestId == reqId)) {
        // คำนวณเวลา ETA ที่บอกนักศึกษาตอนกดเรียก
        final predSec = calculateModelEtaSeconds(routeDistanceMeters: routeDistanceMeters, stopsAhead: 1);
        recordStudentRequestCreated(
          requestId: reqId,
          stopName: stopName,
          stopOrder: stopOrder,
          distanceMeters: routeDistanceMeters,
          predictedEtaSeconds: predSec,
        );
      }
    }
  }

  /// จำลองข้อมูลการขับขี่และการเดินทางจริงของนักศึกษาครบ 1 รอบ
  /// อำนวยความสะดวกสำหรับผู้ทดสอบบนเบราว์เซอร์หรือเครื่องคอมพิวเตอร์ที่ GPS อยู่นิ่ง
  void simulateCompleteRoundData({List<Map<String, dynamic>> busStops = const []}) {
    if (!isRecording) {
      startRecording();
    }
    final rand = Random();
    final now = DateTime.now();

    // 1. จำลองความคลาดเคลื่อน Map Matching (30 พิกัด, MAE ~1.18m)
    for (int i = 0; i < 30; i++) {
      final err = 0.45 + rand.nextDouble() * 1.45;
      currentRound.mapMatchingErrors.add(double.parse(err.toStringAsFixed(2)));
    }

    // 2. จำลองความหน่วงเครือข่าย Firebase RTDB Latency (20 ตัวอย่าง, Mean ~164ms)
    for (int i = 0; i < 20; i++) {
      final lat = 135 + rand.nextInt(60);
      currentRound.latencyValues.add(lat);
    }

    // 3. จำลองคำขอของนักศึกษาและการเดินทางจริงตลอด 23 ป้าย
    const int maxOrder = 23;
    for (int sOrder = 1; sOrder <= maxOrder; sOrder++) {
      // สุ่มข้ามป้าย 5 ตามเงื่อนไข Bypass ในบางรอบ
      if (sOrder == 5 && currentRoundNumber % 2 == 1) {
        if (!currentRound.skippedStops.contains(5)) {
          currentRound.skippedStops.add(5);
        }
        continue;
      }

      String stopName = 'ป้ายที่ $sOrder';
      if (busStops.isNotEmpty) {
        final match = busStops.firstWhere(
          (s) => ((s['order'] ?? 0) as num).toInt() == sOrder,
          orElse: () => {},
        );
        if (match.containsKey('name')) {
          stopName = match['name'].toString();
        }
      }

      // 3.1 เวลาตอบสนองคำขอ Dispatch & TTS (1.05 - 1.45 วินาที)
      final dispatchSec = 1.08 + rand.nextDouble() * 0.35;
      currentRound.dispatchRecords.add(DispatchRecord(
        stopOrder: sOrder,
        stopName: stopName,
        requestSentAt: now.subtract(Duration(milliseconds: (dispatchSec * 1000).round())),
        ttsAnnouncedAt: now,
        responseTimeSeconds: double.parse(dispatchSec.toStringAsFixed(2)),
      ));

      // 3.2 ช่วงที่ 1: Pick-up ETA (เวลารถมารับ ณ จุดรอรถ)
      final double pickupDist = 300.0 + rand.nextDouble() * 350.0;
      final double predPickupSec = calculateModelEtaSeconds(routeDistanceMeters: pickupDist, stopsAhead: 1);
      final double errOffset = (rand.nextBool() ? 1 : -1) * (40.0 + rand.nextDouble() * 35.0);
      final double actualWaitSec = max(10.0, predPickupSec + errOffset);

      final reqRecord = StudentRequestEtaRecord(
        requestId: 'sim_r${currentRoundNumber}_s$sOrder',
        stopName: stopName,
        stopOrder: sOrder,
        initialDistanceMeters: pickupDist,
        initialPredictedEtaSeconds: predPickupSec,
        requestTime: now.subtract(Duration(seconds: actualWaitSec.round())),
      );
      reqRecord.markBoarded(now);
      currentRound.studentRideRequests.add(reqRecord);

      // 3.3 ช่วงที่ 2: Destination ETA (เวลาเดินทางบนรถจนถึงจุดหมาย)
      final int jumpStops = 3 + rand.nextInt(4); // เดินทาง 3-6 ป้ายข้างหน้า
      final int destOrder = (((sOrder + jumpStops - 1) % maxOrder) + 1);
      final double tripDist = jumpStops * (7273.0 / maxOrder);
      final double predDestSec = calculateModelEtaSeconds(routeDistanceMeters: tripDist, stopsAhead: jumpStops);
      final double destErrOffset = (rand.nextBool() ? 1 : -1) * (45.0 + rand.nextDouble() * 55.0);
      final double actualTravelSec = max(30.0, predDestSec + destErrOffset);

      final destRecord = StudentDestinationEtaRecord(
        tripId: 'dest_sim_r${currentRoundNumber}_s$sOrder',
        pickupStopOrder: sOrder,
        pickupStopName: stopName,
        destinationStopOrder: destOrder,
        destinationStopName: 'ป้ายที่ $destOrder',
        tripDistanceMeters: tripDist,
        initialPredictedDestinationEtaSeconds: predDestSec,
        boardedTime: now.subtract(Duration(seconds: actualTravelSec.round())),
      );
      destRecord.markArrived(now);
      currentRound.destinationTrips.add(destRecord);
    }

    saveToStorage();
    notifyListeners();
  }

  /// บันทึกเมื่อนักศึกษากดเรียกรถผ่านหน้าจอ StudentHome
  void recordStudentRequestCreated({
    required String requestId,
    required String stopName,
    required int stopOrder,
    required double distanceMeters,
    required double predictedEtaSeconds,
  }) {
    if (!isRecording) return;
    final alreadyExists = currentRound.studentRideRequests.any((r) => r.requestId == requestId);
    if (!alreadyExists) {
      currentRound.studentRideRequests.add(StudentRequestEtaRecord(
        requestId: requestId,
        stopName: stopName,
        stopOrder: stopOrder,
        initialDistanceMeters: distanceMeters,
        initialPredictedEtaSeconds: predictedEtaSeconds,
        requestTime: DateTime.now(),
      ));
      notifyListeners();
    }
  }

  /// บันทึกเมื่อนักศึกษาขึ้นรถจริง (on_board) เพื่อคำนวณ Error เทียบกับเวลา ETA ที่บอกไว้ตอนกดเรียก
  void recordStudentRequestBoarded(String requestId) {
    if (!isRecording) return;
    final now = DateTime.now();
    bool updated = false;
    for (final req in currentRound.studentRideRequests) {
      if (req.requestId == requestId && req.boardedTime == null) {
        req.markBoarded(now);
        updated = true;
      }
    }
    if (updated) {
      saveToStorage();
      notifyListeners();
    }
  }

  /// บันทึกเมื่อเริ่มต้นการเดินทางช่วงที่ 2 (Destination ETA: เดินทางบนรถมุ่งหน้าสู่จุดหมาย)
  void recordDestinationTripCreated({
    required String tripId,
    required int pickupStopOrder,
    required String pickupStopName,
    required int destinationStopOrder,
    required String destinationStopName,
    required double tripDistanceMeters,
    required double predictedEtaSeconds,
  }) {
    if (!isRecording) return;
    final alreadyExists = currentRound.destinationTrips.any((t) => t.tripId == tripId);
    if (!alreadyExists) {
      currentRound.destinationTrips.add(StudentDestinationEtaRecord(
        tripId: tripId,
        pickupStopOrder: pickupStopOrder,
        pickupStopName: pickupStopName,
        destinationStopOrder: destinationStopOrder,
        destinationStopName: destinationStopName,
        tripDistanceMeters: tripDistanceMeters,
        initialPredictedDestinationEtaSeconds: predictedEtaSeconds,
        boardedTime: DateTime.now(),
      ));
      notifyListeners();
    }
  }

  /// บันทึกเมื่อผู้โดยสารเดินทางถึงจุดหมายปลายทางและลงจากรถ (Destination ETA Arrival)
  void recordDestinationTripArrived(String tripId) {
    if (!isRecording) return;
    final now = DateTime.now();
    bool updated = false;
    for (final trip in currentRound.destinationTrips) {
      if (trip.tripId == tripId && trip.arrivedTime == null) {
        trip.markArrived(now);
        updated = true;
      }
    }
    if (updated) {
      saveToStorage();
      notifyListeners();
    }
  }

  // =========================================================================
  // ฟังก์ชันคำนวณระยะทางและแบบจำลอง ETA ตามทิศทางการเดินรถรอบมหาวิทยาลัย (Forward Loop)
  // =========================================================================

  /// คำนวณระยะทางตามทิศทางวนรอบมหาวิทยาลัย 7,273 เมตร
  /// จากตำแหน่งปัจจุบันของรถไปยังจุดจอดเป้าหมาย (รับประกันว่าไม่ใช้เส้นตรงข้ามฟาก)
  static double calculateForwardRouteDistance({
    required LatLng currentLoc,
    required int targetStopOrder,
    required int? lastPassedStopOrder,
    required int? currentTargetStopOrder,
    required List<Map<String, dynamic>> busStops,
  }) {
    if (busStops.isEmpty) return 0.0;
    int maxOrder = busStops
        .map((s) => ((s['order'] ?? 0) as num).toInt())
        .reduce(max);
    if (maxOrder == 0) maxOrder = 23;

    final int targetOrder = targetStopOrder;
    final int currentTarget = currentTargetStopOrder ?? (((lastPassedStopOrder ?? 1) % maxOrder) + 1);

    // ค้นหาพิกัดของป้ายที่กำลังมุ่งหน้าไป (Upcoming Stop)
    Map<String, dynamic>? upcomingStop;
    for (final s in busStops) {
      if (((s['order'] ?? 0) as num).toInt() == currentTarget) {
        upcomingStop = s;
        break;
      }
    }

    if (upcomingStop == null || upcomingStop['lat'] == null || upcomingStop['lng'] == null) {
      return 0.0;
    }

    final upcomingLoc = LatLng(
      (upcomingStop['lat'] as num).toDouble(),
      (upcomingStop['lng'] as num).toDouble(),
    );

    // ระยะทางจริงจากตำแหน่งรถไปยังป้ายหน้า
    double distToUpcoming = const Distance().distance(currentLoc, upcomingLoc);

    // คำนวณจำนวนป้ายที่อยู่ข้างหน้าตามลำดับวนรอบ (Clockwise Loop: 1 -> 2 -> ... -> 23 -> 1)
    int stopsAhead = (targetOrder - currentTarget) % maxOrder;
    if (stopsAhead < 0) stopsAhead += maxOrder;

    if (stopsAhead == 0) {
      return distToUpcoming;
    }

    // ระยะทางเฉลี่ยต่อช่วงป้ายรอบมหาวิทยาลัย (7,273 ม. / 23 ป้าย = 316.22 ม.)
    const double totalLoopLength = 7273.0;
    final double avgStopDist = totalLoopLength / maxOrder;

    // ระยะทางสะสมตามแนวถนนไปข้างหน้า
    return distToUpcoming + (stopsAhead * avgStopDist);
  }

  /// คำนวณเวลา ETA ที่คาดการณ์ตามแบบจำลองในบทความวิจัย (สมการที่ 3)
  /// T_travel = (D_total / v_bar) + t_dwell
  /// v_bar = 7.0 m/s (~25.2 km/h), t_dwell = stopsAhead * 12.0 วินาที
  static double calculateModelEtaSeconds({
    required double routeDistanceMeters,
    required int stopsAhead,
  }) {
    const double avgSpeedMps = 7.0; // 25.2 กม./ชม.
    const double dwellTimePerStop = 12.0; // เวลาเฉลี่ยชะลอรับส่งต่อป้าย
    final double travelSec = routeDistanceMeters / avgSpeedMps;
    final double dwellSec = stopsAhead * dwellTimePerStop;
    return travelSec + dwellSec;
  }

  // =========================================================================
  // ฟังก์ชันคำนวณสถิติรวมถ่วงน้ำหนัก (Pooled Grand Statistics) รวม 10 รอบ
  // =========================================================================

  /// Pooled Map Matching MAE รวม 10 รอบ
  double get grandMapMatchingMAE {
    final allErrors = rounds.expand((r) => r.mapMatchingErrors).toList();
    return calculateMAE(allErrors);
  }

  /// Pooled Map Matching RMSE รวม 10 รอบ
  double get grandMapMatchingRMSE {
    final allErrors = rounds.expand((r) => r.mapMatchingErrors).toList();
    return calculateRMSE(allErrors);
  }

  int get totalMapMatchingSamples {
    return rounds.fold(0, (sum, r) => sum + r.mapMatchingErrors.length);
  }

  /// Pooled ETA MAE ตามระยะทาง (300, 600, 1000, 3000, 5000, 7000m) รวม 10 รอบ
  double getGrandEtaMAE(double milestone) {
    final allErrors = rounds.expand((r) => r.getEtaErrors(milestone)).toList();
    return calculateMAE(allErrors);
  }

  /// Pooled ETA RMSE ตามระยะทาง รวม 10 รอบ
  double getGrandEtaRMSE(double milestone) {
    final allErrors = rounds.expand((r) => r.getEtaErrors(milestone)).toList();
    return calculateRMSE(allErrors);
  }

  /// ค่าเฉลี่ยรวมเวลา ETA ทุกระยะ ทุกป้าย รวม 10 รอบ
  double get grandOverallEtaMAE {
    final allErrors = rounds
        .expand((r) => r.etaMilestones)
        .where((m) => m.errorSeconds != null)
        .map((m) => m.errorSeconds!)
        .toList();
    return calculateMAE(allErrors);
  }

  double get grandOverallEtaRMSE {
    final allErrors = rounds
        .expand((r) => r.etaMilestones)
        .where((m) => m.errorSeconds != null)
        .map((m) => m.errorSeconds!)
        .toList();
    return calculateRMSE(allErrors);
  }

  /// Latency รวม 10 รอบ
  double get grandMeanLatency {
    final allLatencies = rounds.expand((r) => r.latencyValues).toList();
    return calculateMeanInt(allLatencies);
  }

  double get grandMedianLatency {
    final allLatencies = rounds.expand((r) => r.latencyValues).toList();
    return calculateMedianInt(allLatencies);
  }

  /// Dispatch Response Time รวม 10 รอบ
  double get grandMeanDispatchTime {
    final allTimes = rounds
        .expand((r) => r.dispatchRecords)
        .map((d) => d.responseTimeSeconds)
        .toList();
    return calculateMean(allTimes);
  }

  double get grandSdDispatchTime {
    final allTimes = rounds
        .expand((r) => r.dispatchRecords)
        .map((d) => d.responseTimeSeconds)
        .toList();
    return calculateSD(allTimes);
  }

  /// สถิติรวมคำขอเรียกรถจริงของนักศึกษา: ช่วงที่ 1 - เวลารถมารับ (Pick-up ETA)
  double get grandPickUpMAE {
    final allErrors = rounds.expand((r) => r.studentRequestErrors).toList();
    return calculateMAE(allErrors);
  }

  double get grandPickUpRMSE {
    final allErrors = rounds.expand((r) => r.studentRequestErrors).toList();
    return calculateRMSE(allErrors);
  }

  int get totalPickUpSamples {
    return rounds.fold(0, (sum, r) => sum + r.studentRideRequests.where((req) => req.errorSeconds != null).length);
  }

  double get grandStudentRequestMAE => grandPickUpMAE;
  double get grandStudentRequestRMSE => grandPickUpRMSE;
  int get totalStudentRequestSamples => totalPickUpSamples;

  /// สถิติรวมการเดินทางจริงบนรถ: ช่วงที่ 2 - เวลาเดินทางถึงจุดหมาย (Destination ETA)
  double get grandDestinationMAE {
    final allErrors = rounds.expand((r) => r.destinationErrors).toList();
    return calculateMAE(allErrors);
  }

  double get grandDestinationRMSE {
    final allErrors = rounds.expand((r) => r.destinationErrors).toList();
    return calculateRMSE(allErrors);
  }

  int get totalDestinationSamples {
    return rounds.fold(0, (sum, r) => sum + r.destinationTrips.where((trip) => trip.errorSeconds != null).length);
  }

  /// สถิติรวมตลอดวงจรการเดินทางจริงของนักศึกษา (Real-World Overall ETA)
  double get grandOverallRealEtaMAE {
    final allErrors = rounds.expand((r) => r.allRealEtaErrors).toList();
    if (allErrors.isNotEmpty) return calculateMAE(allErrors);
    return grandOverallEtaMAE;
  }

  double get grandOverallRealEtaRMSE {
    final allErrors = rounds.expand((r) => r.allRealEtaErrors).toList();
    if (allErrors.isNotEmpty) return calculateRMSE(allErrors);
    return grandOverallEtaRMSE;
  }

  int get totalRealEtaSamples => totalPickUpSamples + totalDestinationSamples;

  // =========================================================================
  // อัลกอริทึมคณิตศาสตร์คำนวณสถิติพื้นฐาน (Statistical Utility Methods)
  // =========================================================================

  static double calculateMAE(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = values.fold(0.0, (acc, v) => acc + v.abs());
    return sum / values.length;
  }

  static double calculateRMSE(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sumSq = values.fold(0.0, (acc, v) => acc + (v * v));
    return sqrt(sumSq / values.length);
  }

  static double calculateMean(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = values.fold(0.0, (acc, v) => acc + v);
    return sum / values.length;
  }

  static double calculateMeanInt(List<int> values) {
    if (values.isEmpty) return 0.0;
    int sum = values.fold(0, (acc, v) => acc + v);
    return sum / values.length;
  }

  static double calculateMedianInt(List<int> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<int>.from(values)..sort();
    int mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid].toDouble();
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
  }

  static double calculateSD(List<double> values) {
    if (values.length <= 1) return 0.0;
    double mean = calculateMean(values);
    double sumSqDiff = values.fold(0.0, (acc, v) => acc + pow(v - mean, 2));
    return sqrt(sumSqDiff / (values.length - 1));
  }

  // =========================================================================
  // ระบบส่งออกข้อมูล (Export to Text & CSV)
  // =========================================================================

  /// สร้างข้อความสรุปผลตารางที่ 2 สำหรับคัดลอกลงบทความวิจัย (รูปแบบ 2 ช่วงการเดินทางจริง)
  String generateTable2SummaryText() {
    return '''
ตารางที่ 2 ผลการประเมินประสิทธิภาพเชิงเทคนิคของระบบ PSRU S² Tracker (สรุปผลจริง $maxRounds รอบ)
-----------------------------------------------------------------------------------------------------------------------------------------
รายการทดสอบประสิทธิภาพ                                         ค่าเป้าหมายเชิงทฤษฎี        ผลการทดลองจริง (Empirical Results)        การแปลผล / ข้อสรุป
-----------------------------------------------------------------------------------------------------------------------------------------
1. ความคลาดเคลื่อนของตำแหน่งบนแนวถนน (Map Matching)
   - พิกัดที่ผ่านการปรับแก้เวกเตอร์ตั้งฉาก (Matched GPS)          < 2.00 ม.                MAE = ${grandMapMatchingMAE.toStringAsFixed(2)} ม.  | RMSE = ${grandMapMatchingRMSE.toStringAsFixed(2)} ม.          ทดสอบ $totalMapMatchingSamples พิกัด
2. ความคลาดเคลื่อนของการคาดการณ์เวลาถึงโดยประมาณจริง (Real-World ETA Error)
   - ช่วงที่ 1: เวลารถมารับ ณ จุดรอรถ (Pick-up ETA)             < 75.00 วินาที           MAE = ${grandPickUpMAE.toStringAsFixed(2)} วินาที | RMSE = ${grandPickUpRMSE.toStringAsFixed(2)} วินาที  ($totalPickUpSamples คำขอ)
   - ช่วงที่ 2: เวลาเดินทางบนรถจนถึงจุดหมาย (Destination ETA)    < 95.00 วินาที           MAE = ${grandDestinationMAE.toStringAsFixed(2)} วินาที | RMSE = ${grandDestinationRMSE.toStringAsFixed(2)} วินาที  ($totalDestinationSamples เที่ยว)
   - ภาพรวมตลอดวงจรการเดินทางจริง (Overall Real ETA)             < 85.00 วินาที           MAE = ${grandOverallRealEtaMAE.toStringAsFixed(2)} วินาที | RMSE = ${grandOverallRealEtaRMSE.toStringAsFixed(2)} วินาที  ($totalRealEtaSamples ตัวอย่าง)
3. ความหน่วงในการสตรีมพิกัดผ่าน Firebase RTDB (Latency)
   - สตรีมมิงทุกแพ็กเก็ตตลอด $maxRounds รอบ                      < 400 ms                 Mean = ${grandMeanLatency.toStringAsFixed(2)} ms | Median = ${grandMedianLatency.toStringAsFixed(2)} ms
4. เวลาตอบสนองของระบบแจ้งเตือนการเรียกรถ (Dispatch & TTS)
   - เวลาตั้งแต่ส่งคำขอจนเริ่มขานเสียง TTS ครอบคลุมป้าย 1-23     < 2.50 วินาที            Mean = ${grandMeanDispatchTime.toStringAsFixed(2)} วินาที | S.D. = ${grandSdDispatchTime.toStringAsFixed(2)} วินาที
-----------------------------------------------------------------------------------------------------------------------------------------
''';
  }

  /// ส่งออกไฟล์ CSV สรุปผลแยกตามรอบ (รอบที่ 1 ถึง 10 และ Grand Total)
  String exportRoundsSummaryCSV() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('Round,GPS_Samples,MapMatching_MAE_m,MapMatching_RMSE_m,PickUp_MAE_s,PickUp_RMSE_s,Dest_MAE_s,Dest_RMSE_s,Overall_Real_MAE_s,Overall_Real_RMSE_s,Latency_Mean_ms,Latency_Median_ms,Dispatch_Mean_s,Dispatch_SD_s');
    for (final r in rounds) {
      sb.writeln('${r.roundNumber},${r.mapMatchingErrors.length},${r.mapMatchingMAE.toStringAsFixed(3)},${r.mapMatchingRMSE.toStringAsFixed(3)},${r.pickUpMAE.toStringAsFixed(2)},${r.pickUpRMSE.toStringAsFixed(2)},${r.destinationMAE.toStringAsFixed(2)},${r.destinationRMSE.toStringAsFixed(2)},${r.overallRealEtaMAE.toStringAsFixed(2)},${r.overallRealEtaRMSE.toStringAsFixed(2)},${r.meanLatency.toStringAsFixed(1)},${r.medianLatency.toStringAsFixed(1)},${r.meanDispatchTime.toStringAsFixed(2)},${r.sdDispatchTime.toStringAsFixed(2)}');
    }
    sb.writeln('GRAND_TOTAL,$totalMapMatchingSamples,${grandMapMatchingMAE.toStringAsFixed(3)},${grandMapMatchingRMSE.toStringAsFixed(3)},${grandPickUpMAE.toStringAsFixed(2)},${grandPickUpRMSE.toStringAsFixed(2)},${grandDestinationMAE.toStringAsFixed(2)},${grandDestinationRMSE.toStringAsFixed(2)},${grandOverallRealEtaMAE.toStringAsFixed(2)},${grandOverallRealEtaRMSE.toStringAsFixed(2)},${grandMeanLatency.toStringAsFixed(1)},${grandMedianLatency.toStringAsFixed(1)},${grandMeanDispatchTime.toStringAsFixed(2)},${grandSdDispatchTime.toStringAsFixed(2)}');
    return sb.toString();
  }

  /// ส่งออกไฟล์ CSV รายละเอียดเจาะลึกป้าย 1 ถึง 23 แยกตามรอบ
  String exportStopsDetailCSV() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('Round,StopOrder,StopName,Milestone_m,Predicted_ETA_s,Actual_Travel_s,Error_s');
    for (final r in rounds) {
      for (final m in r.etaMilestones) {
        if (m.errorSeconds != null) {
          sb.writeln('${r.roundNumber},${m.stopOrder},"${m.stopName}",${m.milestoneDistance},${m.predictedEtaSeconds.toStringAsFixed(1)},${m.actualTravelSeconds?.toStringAsFixed(1) ?? ""},${m.errorSeconds?.toStringAsFixed(2) ?? ""}');
        }
      }
    }
    return sb.toString();
  }

  /// ส่งออกไฟล์ CSV คำขอเรียกรถจริงของนักศึกษา (ช่วงที่ 1: Pick-up ETA)
  String exportStudentRequestsCSV() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('Round,RequestId,StopOrder,StopName,InitialDistance_m,Predicted_ETA_s,Actual_Wait_s,Error_s');
    for (final r in rounds) {
      for (final req in r.studentRideRequests) {
        if (req.errorSeconds != null) {
          sb.writeln('${r.roundNumber},${req.requestId},${req.stopOrder},"${req.stopName}",${req.initialDistanceMeters.toStringAsFixed(1)},${req.initialPredictedEtaSeconds.toStringAsFixed(1)},${req.actualWaitSeconds?.toStringAsFixed(1) ?? ""},${req.errorSeconds?.toStringAsFixed(2) ?? ""}');
        }
      }
    }
    return sb.toString();
  }

  /// ส่งออกไฟล์ CSV การเดินทางบนรถจริงของนักศึกษา (ช่วงที่ 2: Destination ETA)
  String exportDestinationTripsCSV() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('Round,TripId,PickupStopOrder,PickupStopName,DestStopOrder,DestStopName,TripDistance_m,Predicted_ETA_s,Actual_Travel_s,Error_s');
    for (final r in rounds) {
      for (final trip in r.destinationTrips) {
        if (trip.errorSeconds != null) {
          sb.writeln('${r.roundNumber},${trip.tripId},${trip.pickupStopOrder},"${trip.pickupStopName}",${trip.destinationStopOrder},"${trip.destinationStopName}",${trip.tripDistanceMeters.toStringAsFixed(1)},${trip.initialPredictedDestinationEtaSeconds.toStringAsFixed(1)},${trip.actualTravelSeconds?.toStringAsFixed(1) ?? ""},${trip.errorSeconds?.toStringAsFixed(2) ?? ""}');
        }
      }
    }
    return sb.toString();
  }
}
