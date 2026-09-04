import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // สำหรับเช็ค kIsWeb
import 'package:flutter/services.dart'; // สำหรับ HapticFeedback
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../widgets/top_toast.dart';
import 'package:flutter_tts/flutter_tts.dart'; // สำหรับเสียง AI พูดภาษาไทย
import 'package:audioplayers/audioplayers.dart'; // สำหรับเล่นไฟล์เสียง MP3 จุดจอด
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart'; // สำหรับเล่นเสียงแจ้งเตือนมือถือ
import 'package:shared_preferences/shared_preferences.dart';
import '../../route_data.dart';
import 'driver_profile.dart'; // Import หน้าโปรไฟล์คนขับรถ
import 'driver_status_screen.dart'; // Import หน้าสถานะรถ
import 'driver_chat_screen.dart'; // Import หน้าแชทคนขับรถ

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with TickerProviderStateMixin {
  int _selectedIndex = 0; // เพิ่มตัวแปรสำหรับ BottomNavigationBar
  bool isOnline = false;
  bool _isAutoFollow = true; // หน้าจอขยับตามตำแหน่งรถอัตโนมัติ

  LatLng? _currentLocation;
  LatLng? _oldLocation;
  LatLng? _targetLocation;
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  late AnimationController _otherMarkersAnimationController;
  late Animation<double> _otherMarkersAnimation;
  late FlutterTts flutterTts; // ตัวอ่านเสียง AI ภาษาไทย
  String _ttsLang = "th-TH"; // เก็บค่ารหัสภาษาที่ใช้งานได้จริงบนอุปกรณ์นั้นๆ
  StreamSubscription<Position>? positionStream;
  StreamSubscription<QuerySnapshot>? requestStream;
  StreamSubscription? myShuttleSubscription; // ฟังสถานะตัวเอง
  StreamSubscription<DocumentSnapshot>? _userSessionSubscription; // ฟังเซสชันของบัญชีคนขับ
  String? _localSessionId; // เก็บ Session ID ของเครื่องปัจจุบัน
  bool _isForceLoggingOut = false; // ป้องกันการเปิด Dialog เตือนซ้ำ
  Timer?
  _heartbeatTimer; // Heartbeat สำหรับอัปเดตเวลาให้สดใหม่อยู่เสมอตอนจอดรอรับส่ง
  String _currentPassengerStatus = 'available';
  final AudioPlayer _alertPlayer = AudioPlayer(); // ตัวเล่นเสียงแจ้งเตือน

  StreamSubscription<QuerySnapshot>? _chatNotificationSub;
  StreamSubscription? _chatSubscription;
  DateTime _chatListenerStartTime = DateTime.now();
  Map<String, dynamic>? _incomingChatNotification;
  Timer? _chatNotificationTimer;
  String? _lastNotifiedMessageId;

  final MapController _mapController = MapController();

  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  final LatLngBounds _psruBounds = LatLngBounds(
    const LatLng(16.81500, 100.19000),
    const LatLng(16.84500, 100.23000),
  );

  List<Map<String, dynamic>> busStops = [];

  // จัดกลุ่มจุดจอดที่อยู่ใกล้กันให้แสดงเป็นหมุดเดียว (สอดคล้องกับฝั่งนักศึกษา)
  final Map<String, List<String>> _groupedStops = {
    '7-Eleven PSRU และตึก IT': ['7-Eleven PSRU', 'ตึก IT '],
    'คณะสังคมศาสตร์ และคณะพยาบาลศาสตร์': ['คณะสังคมศาสตร์', 'คณะพยาบาลศาสตร์'],
  };

  // ข้อมูลจุดจอดสำหรับแสดงบนแผนที่ (ยุบรวมจุดที่จัดกลุ่มแล้ว)
  List<Map<String, dynamic>> get _visualStops {
    List<Map<String, dynamic>> result = [];
    Set<String> groupedNames = {};

    _groupedStops.forEach((groupName, memberNames) {
      var members = busStops
          .where((s) => memberNames.contains(s['name']))
          .toList();
      if (members.isNotEmpty) {
        double avgLat =
            members
                .map((e) => (e['lat'] as num).toDouble())
                .reduce((a, b) => a + b) /
            members.length;
        double avgLng =
            members
                .map((e) => (e['lng'] as num).toDouble())
                .reduce((a, b) => a + b) /
            members.length;
        result.add({
          'isGroup': true,
          'name': groupName,
          'lat': avgLat,
          'lng': avgLng,
          'members': members,
        });
        groupedNames.addAll(memberNames);
      }
    });

    for (var stop in busStops) {
      if (!groupedNames.contains(stop['name'])) {
        result.add(stop);
      }
    }
    return result;
  }

  String? waitingStudentStop;
  List<String> activeRequestIds = []; // เก็บไอดีคำขอทั้งหมดในป้ายที่กำลังรอ
  int activeStudentCount = 0; // จำนวนนักศึกษาที่รออยู่ป้ายนั้น
  String?
  currentRequestStatus; // เก็บสถานะการเรียก ('waiting' หรือ 'acknowledged')

  // เก็บตำแหน่งของนักศึกษาที่เรียกรถทั้งหมด
  List<Map<String, dynamic>> waitingStudentsList = [];

  // ตัวแปรสำหรับเก็บข้อมูลรถคันอื่นๆ ที่กำลังออนไลน์
  List<Map<String, dynamic>> activeShuttles = [];
  StreamSubscription? allShuttlesSubscription;
  Map<String, LatLng> _otherCurrentLocations = {};
  Map<String, LatLng> _otherOldLocations = {};
  Map<String, LatLng> _otherTargetLocations = {};

  // ตัวแปรสำหรับเก็บข้อมูลรถรับส่งของคนขับคนนี้
  String? _shuttleDocId;
  String? _shuttleName;
  String? _shuttleNumber;

  // ตัวแปรจำกัดเวลาส่งข้อมูล (Throttling 3 วินาที) และพิกัดล่าสุด (Distance Check 5 เมตร) เพื่อประหยัดโควตาและแบตเตอรี่
  DateTime? _lastFirebaseUpdate;
  LatLng? _lastUploadedLocation;

  // ตัวแปรสำหรับ Smart Routing และ Drop-off TTS
  int? _lastPassedStopOrder;
  int _currentTargetStopOrder = 1; // เริ่มที่ป้าย order 1
  final Set<String> _announcedDropOffStops = {}; // กัน TTS พูดซ้ำ
  Set<String> _activeDropOffStops = {}; // รายชื่อป้ายที่มีคนจะลง
  Map<String, int> _dropOffCounts = {}; // จำนวนนักศึกษาที่จะลงแต่ละป้าย

  @override
  void initState() {
    super.initState();
    _initTts(); // เตรียมระบบอ่านข้อความ AI ภาษาไทย

    // Setup animation controller for smooth marker movement (900ms ให้หมุดเคลื่อนที่ต่อเนื่องเมื่อรถวิ่ง 20-30 กม./ชม.)
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _markerAnimation =
        CurvedAnimation(
          parent: _markerAnimationController,
          curve: Curves.easeInOut,
        )..addListener(() {
          if (mounted) {
            bool needsUpdate = false;
            if (_oldLocation != null && _targetLocation != null) {
              final lat =
                  _oldLocation!.latitude +
                  (_targetLocation!.latitude - _oldLocation!.latitude) *
                      _markerAnimation.value;
              final lng =
                  _oldLocation!.longitude +
                  (_targetLocation!.longitude - _oldLocation!.longitude) *
                      _markerAnimation.value;
              _currentLocation = LatLng(lat, lng);
              needsUpdate = true;

              // ขยับกล้องแผนที่ให้ตามตัวรถอัตโนมัติเมื่อเปิดโหมด Auto-Follow อยู่
              if (_isAutoFollow && _currentLocation != null) {
                _mapController.move(
                  _currentLocation!,
                  _mapController.camera.zoom,
                );
              }
            }

            if (needsUpdate) {
              setState(() {});
            }
          }
        });

    _otherMarkersAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 3200,
      ), // สอดคล้องกับการส่งข้อมูลทุก 3 วินาทีของคันอื่น
    );
    _otherMarkersAnimation =
        CurvedAnimation(
          parent: _otherMarkersAnimationController,
          curve: Curves.linear, // เคลื่อนที่สม่ำเสมอ
        )..addListener(() {
          if (mounted) {
            bool needsUpdate = false;
            for (var id in _otherTargetLocations.keys) {
              final oldLoc = _otherOldLocations[id];
              final targetLoc = _otherTargetLocations[id];
              if (oldLoc != null && targetLoc != null) {
                final lat =
                    oldLoc.latitude +
                    (targetLoc.latitude - oldLoc.latitude) *
                        _otherMarkersAnimation.value;
                final lng =
                    oldLoc.longitude +
                    (targetLoc.longitude - oldLoc.longitude) *
                        _otherMarkersAnimation.value;
                _otherCurrentLocations[id] = LatLng(lat, lng);
                needsUpdate = true;
              }
            }
            if (needsUpdate) {
              setState(() {});
            }
          }
        });

    _fetchStopsFromFirebase();
    _fetchDriverShuttle(); // ดึงข้อมูลรถของคนขับ
    _listenToUserSession(); // เริ่มฟังสถานะเซสชันของคนขับเพื่อป้องกันการล็อกอินซ้ำ
  }

  // ฟังก์ชันสำหรับหาว่าคนขับคนนี้ รับผิดชอบรถคันไหน
  Future<void> _fetchDriverShuttle() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? docId;
      Map<String, dynamic>? shuttleData;

      // 1. ค้นหาเอกสารรถใน Firestore collection 'shuttles' ที่ driver_uid ตรงกับ uid ของคนขับคนนี้
      try {
        final firestoreShuttleQuery = await FirebaseFirestore.instance
            .collection('shuttles')
            .where('driver_uid', isEqualTo: user.uid)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 8));

        if (firestoreShuttleQuery.docs.isNotEmpty) {
          final doc = firestoreShuttleQuery.docs.first;
          docId = doc.id;
          shuttleData = doc.data();
          _shuttleName = shuttleData['name']?.toString().trim();
          _shuttleNumber = shuttleData['number']?.toString().trim();
        }
      } catch (e) {
        print("Error querying Firestore shuttles by driver_uid: $e");
      }

      // 2. ถ้าไม่พบจาก driver_uid ใน shuttles ให้ไปค้นจากเอกสาร users/{uid}
      if (_shuttleName == null || _shuttleName!.isEmpty) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 8));

          final uData = userDoc.data();
          _shuttleName =
              uData?['shuttle_name']?.toString().trim() ??
              uData?['name']?.toString().trim();
          _shuttleNumber =
              uData?['shuttle_number']?.toString().trim() ??
              uData?['number']?.toString().trim();
        } catch (e) {
          print("Error querying user doc: $e");
        }
      }

      // 3. หากยังไม่พบอีก ให้ใช้ค่าตั้งต้น
      if (_shuttleName == null || _shuttleName!.isEmpty) {
        _shuttleName = 'รถรับส่ง สาย 1';
        _shuttleNumber = '1';
      }

      // 4. ดึงข้อมูล User (ชื่อและรูป Avatar) สำหรับอัปเดตใส่เอกสารรถ
      String driverName = 'คนขับรถประจำคัน';
      String driverAvatar = 'assets/images/man1.png';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (userDoc.exists) {
          driverName = userDoc.data()?['name'] ?? driverName;
          driverAvatar = userDoc.data()?['avatar'] ?? driverAvatar;
        }
      } catch (e) {
        print("Error getting driver user profile: $e");
      }

      // 5. ตรวจสอบ Realtime Database (RTDB) node 'shuttles'
      // กำหนด Key ใน RTDB เป็นชื่อคันรถที่อ่านง่าย (เช่น shuttle_01, shuttle_02)
      String targetRtdbKey = '';
      String cleanNum = (_shuttleNumber ?? '').replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      if (cleanNum.isEmpty && _shuttleName != null) {
        cleanNum = _shuttleName!.replaceAll(RegExp(r'[^0-9]'), '');
      }

      if (cleanNum.isNotEmpty) {
        targetRtdbKey = 'shuttle_${cleanNum.padLeft(2, '0')}';
      } else if (docId != null && docId.isNotEmpty) {
        targetRtdbKey = docId;
      } else {
        targetRtdbKey = user.uid;
      }

      // หากมีการสลับมาใช้ Key รูปแบบอ่านง่าย ให้ลบ Node เก่าที่เป็น Firestore Doc ID หรือ User UID ค้างไว้ทิ้ง
      if (docId != null && docId != targetRtdbKey) {
        try {
          final oldDocNode = FirebaseDatabase.instance
              .ref('shuttles')
              .child(docId);
          final oldSnap = await oldDocNode.get().timeout(
            const Duration(seconds: 3),
          );
          if (oldSnap.exists) {
            await oldDocNode.remove();
          }
        } catch (e) {
          print("Error removing old docId RTDB node: $e");
        }
      }
      if (user.uid != targetRtdbKey) {
        try {
          final oldUserNode = FirebaseDatabase.instance
              .ref('shuttles')
              .child(user.uid);
          final oldSnap = await oldUserNode.get().timeout(
            const Duration(seconds: 3),
          );
          if (oldSnap.exists) {
            await oldUserNode.remove();
          }
        } catch (e) {
          print("Error removing old user.uid RTDB node: $e");
        }
      }

      final rtdbRef = FirebaseDatabase.instance
          .ref('shuttles')
          .child(targetRtdbKey);
      DatabaseEvent? rtdbSnap;
      try {
        rtdbSnap = await rtdbRef.once().timeout(const Duration(seconds: 8));
      } catch (e) {
        print("RTDB check error: $e");
      }

      if (rtdbSnap == null || !rtdbSnap.snapshot.exists) {
        // ถ้ายังไม่มี node ใน RTDB ให้สร้างใหม่
        await rtdbRef.set({
          'name': _shuttleName,
          'number': _shuttleNumber ?? '1',
          'status': 'offline',
          'lat': 16.82753,
          'lng': 100.20686,
          'driver_name': driverName,
          'driver_avatar': driverAvatar,
          'driver_uid': user.uid,
        });
      } else {
        // ถ้ามี node ใน RTDB แล้ว ให้อัปเดตข้อมูลคนขับล่าสุด
        await rtdbRef.update({
          'driver_name': driverName,
          'driver_avatar': driverAvatar,
          'driver_uid': user.uid,
          if (_shuttleName != null) 'name': _shuttleName,
          if (_shuttleNumber != null) 'number': _shuttleNumber,
        });
      }

      if (mounted) {
        setState(() {
          _shuttleDocId = targetRtdbKey;
        });
        _listenToChatMessages(); // เริ่มฟังเสียงแจ้งเตือนข้อความแชทใหม่

        // ตั้งค่า onDisconnect เพื่อให้เปลี่ยนเป็น offline เมื่อหลุดการเชื่อมต่อ
        rtdbRef.child('status').onDisconnect().set('offline');

        // เริ่มฟังเอกสารรถคันนี้ เพื่อคอยอัปเดตสถานะแบบ Real-time ให้สีหมุดเปลี่ยนตาม
        myShuttleSubscription = rtdbRef.onValue.listen((event) {
          if (event.snapshot.exists && mounted) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            if (data.containsKey('passenger_status')) {
              setState(() {
                _currentPassengerStatus = data['passenger_status'].toString();
              });
            }
          }
        }, onError: (e) => print("RTDB Error (shuttles doc): $e"));
      }

      // เริ่มฟังสัญญาณรถทุกคัน เพื่อนำมาแสดงจุดบนแผนที่ให้คนขับเห็นกันเอง
      _listenToAllShuttles();
    } catch (e) {
      print("Error fetching driver shuttle: $e");
    }
  }

  // ฟังก์ชันฟังสัญญาณข้อความแชทใหม่ เพื่อเล่นเสียงและแสดงป๊อปอัปแจ้งเตือน
  void _listenToChatMessages() {
    _chatNotificationSub?.cancel();
    _chatSubscription?.cancel();

    String cleanNum = (_shuttleNumber ?? _shuttleName ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    if (cleanNum.isEmpty &&
        _shuttleDocId != null &&
        !_shuttleDocId!.startsWith('-')) {
      cleanNum = _shuttleDocId!.replaceAll(RegExp(r'[^0-9]'), '');
    }
    String baseRoom = 'shuttle_01';
    if (cleanNum.isNotEmpty) {
      int numVal = int.tryParse(cleanNum) ?? 1;
      baseRoom = 'shuttle_${numVal.toString().padLeft(2, '0')}';
    } else if (_shuttleDocId != null && !_shuttleDocId!.startsWith('-')) {
      baseRoom = _shuttleDocId!;
    }

    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String roomId = '${baseRoom}_$todayDate';

    bool isInitial = true;

    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .snapshots()
        .listen((snapshot) {
          if (isInitial) {
            isInitial = false;
            return; // ข้ามข้อความเก่าทั้งหมดที่ได้จากการเปิดฟังครั้งแรก
          }

          // ถ้ากำลังเปิดอยู่ในหน้าแชท (แท็บ 2) ไม่ต้องแสดงป๊อปอัปบังหน้าจอ
          if (_selectedIndex == 2) return;

          final currentUserId = FirebaseAuth.instance.currentUser?.uid;

          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data();
              if (data == null) continue;

              final String senderRole =
                  (data['sender_role'] ?? data['senderRole'] ?? '').toString();
              final String senderId =
                  (data['sender_id'] ?? data['senderId'] ?? '').toString();

              if (senderId != currentUserId &&
                  (senderRole == 'student' || senderRole.isEmpty)) {
                final String senderName =
                    (data['sender_name'] ?? data['senderName'] ?? 'นักศึกษา')
                        .toString();
                final String messageText =
                    (data['text'] ??
                            (data['imageUrl'] != null || data['image_url'] != null
                                ? ' ได้ส่งรูปภาพ'
                                : 'ข้อความใหม่'))
                        .toString();

                _triggerVoiceAlertForChat();

                if (mounted) {
                  _chatNotificationTimer?.cancel();
                  setState(() {
                    _incomingChatNotification = {
                      'sender': senderName,
                      'text': messageText,
                      'id': change.doc.id,
                    };
                  });

                  _chatNotificationTimer = Timer(
                    const Duration(seconds: 7),
                    () {
                      if (mounted) {
                        setState(() {
                          _incomingChatNotification = null;
                        });
                      }
                    },
                  );
                }
              }
            }
          }
        });
  }

  // ฟังก์ชันสำหรับเพิ่มจำนวนรอบการวิ่งในวันนี้
  Future<void> _incrementDailyRound() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final String todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        int currentRounds = 0;
        if (data['last_round_date'] == todayStr) {
          currentRounds = ((data['daily_round_count'] ?? 0) as num).toInt();
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'last_round_date': todayStr,
          'daily_round_count': currentRounds + 1,
        }, SetOptions(merge: true));

        print(" Round Completed! Total today: ${currentRounds + 1}");
      }
    } catch (e) {
      print("Error incrementing daily round: $e");
    }
  }

  // ฟังก์ชันฟังสัญญาณรถทุกคันที่กำลังออนไลน์ (เพื่อนำมาแสดงจุดบนแผนที่ให้คนขับเห็นกันเอง)
  void _listenToAllShuttles() {
    allShuttlesSubscription = FirebaseDatabase.instance
        .ref('shuttles')
        .onValue
        .listen((event) {
          if (mounted && event.snapshot.exists) {
            bool shouldAnimate = false;
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            final now = DateTime.now();

            final List<Map<String, dynamic>> newShuttles = [];

            data.forEach((key, value) {
              if (value != null && value is Map) {
                final status = value['status'];
                if (status == 'online') {
                  final lastUpdatedMillis = value['last_updated'];
                  bool isRecentlyUpdated = false;
                  if (lastUpdatedMillis != null) {
                    final lastUpdated = DateTime.fromMillisecondsSinceEpoch(
                      (lastUpdatedMillis as num).toInt(),
                    );
                    isRecentlyUpdated =
                        now.difference(lastUpdated).inMinutes <= 2;
                  }

                  if (isRecentlyUpdated && key.toString() != _shuttleDocId) {
                    double sLat = 0.0;
                    double sLng = 0.0;
                    if (value['lat'] is double)
                      sLat = value['lat'];
                    else if (value['lat'] is int)
                      sLat = (value['lat'] as int).toDouble();
                    else if (value['lat'] is String)
                      sLat = double.tryParse(value['lat'].toString()) ?? 0.0;

                    if (value['lng'] is double)
                      sLng = value['lng'];
                    else if (value['lng'] is int)
                      sLng = (value['lng'] as int).toDouble();
                    else if (value['lng'] is String)
                      sLng = double.tryParse(value['lng'].toString()) ?? 0.0;

                    newShuttles.add({
                      'id': key.toString(),
                      'number': value.containsKey('number')
                          ? value['number']
                          : null,
                      'lat': sLat,
                      'lng': sLng,
                      'passenger_status': value.containsKey('passenger_status')
                          ? value['passenger_status']
                          : 'available',
                    });
                  }
                }
              }
            });

            for (var shuttle in newShuttles) {
              final String id = shuttle['id'];
              final LatLng newLoc = LatLng(shuttle['lat'], shuttle['lng']);
              final currentLoc = _otherCurrentLocations[id];
              if (currentLoc != null && currentLoc != newLoc) {
                // _otherOldLocations จะถูกอัปเดตแบบ sync พร้อมกันใน _restartMarkerAnimation
                _otherTargetLocations[id] = newLoc;
                shouldAnimate = true;
              } else if (currentLoc == null) {
                _otherCurrentLocations[id] = newLoc;
                _otherTargetLocations[id] = newLoc;
              }
            }

            final activeIds = newShuttles.map((s) => s['id'] as String).toSet();
            _otherCurrentLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _otherOldLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _otherTargetLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );

            setState(() {
              activeShuttles = newShuttles;
            });

            if (shouldAnimate) {
              _restartOtherMarkersAnimation();
            }
          }
        });
  }

  // ฟังก์ชันเริ่มแอนิเมชันใหม่สำหรับหมุดรถตัวเอง (900ms)
  void _restartMarkerAnimation() {
    if (_currentLocation != null) {
      _oldLocation = _currentLocation;
    }
    _markerAnimationController.forward(from: 0.0);
  }

  // ฟังก์ชันเริ่มแอนิเมชันใหม่สำหรับหมุดรถคันอื่น (3200ms)
  void _restartOtherMarkersAnimation() {
    for (var id in _otherCurrentLocations.keys) {
      if (_otherCurrentLocations[id] != null) {
        _otherOldLocations[id] = _otherCurrentLocations[id]!;
      }
    }
    _otherMarkersAnimationController.forward(from: 0.0);
  }

  //อัลกอริทึม Snap to Route: ล็อกตำแหน่งหมุดให้อยู่บนเส้นทางถนนเท่านั้น
  LatLng _snapToRoute(LatLng rawPoint) {
    LatLng snappedPoint = rawPoint;
    double minDistSq = double.infinity;

    for (final routeSegment in shuttleRoutes) {
      if (routeSegment.length < 2) continue;
      for (int i = 0; i < routeSegment.length - 1; i++) {
        final a = routeSegment[i];
        final b = routeSegment[i + 1];

        final ax = a.latitude;
        final ay = a.longitude;
        final bx = b.latitude;
        final by = b.longitude;
        final px = rawPoint.latitude;
        final py = rawPoint.longitude;

        final abx = bx - ax;
        final aby = by - ay;
        final apx = px - ax;
        final apy = py - ay;

        final abLenSq = abx * abx + aby * aby;
        double cx, cy;

        if (abLenSq == 0) {
          cx = ax;
          cy = ay;
        } else {
          double t = (apx * abx + apy * aby) / abLenSq;
          if (t < 0)
            t = 0;
          else if (t > 1)
            t = 1;
          cx = ax + t * abx;
          cy = ay + t * aby;
        }

        final dx = px - cx;
        final dy = py - cy;
        final distSq = dx * dx + dy * dy;

        if (distSq < minDistSq) {
          minDistSq = distSq;
          snappedPoint = LatLng(cx, cy);
        }
      }
    }

    return snappedPoint;
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stops')
          .get();

      List<Map<String, dynamic>> loadedStops = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rawLat = data['lat'];
        final rawLng = data['lng'];
        double lat = 0.0;
        double lng = 0.0;

        if (rawLat is double)
          lat = rawLat;
        else if (rawLat is int)
          lat = rawLat.toDouble();
        else if (rawLat is String)
          lat = double.tryParse(rawLat) ?? 0.0;

        if (rawLng is double)
          lng = rawLng;
        else if (rawLng is int)
          lng = rawLng.toDouble();
        else if (rawLng is String)
          lng = double.tryParse(rawLng) ?? 0.0;

        loadedStops.add({
          'id': doc.id,
          'stop_id': data['stop_id'] ?? doc.id,
          'name': data['name'] ?? 'จุดจอด',
          'lat': lat,
          'lng': lng,
          'order': data['order'],
        });
      }

      if (mounted) {
        setState(() {
          busStops = loadedStops;
        });
      }
    } catch (e) {
      print(" Error loading stops: $e");
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    _heartbeatTimer?.cancel();
    _markerAnimationController.dispose();
    _otherMarkersAnimationController.dispose();
    positionStream?.cancel();
    _userSessionSubscription?.cancel();
    requestStream?.cancel();
    _chatNotificationSub?.cancel();
    _chatSubscription?.cancel();
    _chatNotificationTimer?.cancel();
    myShuttleSubscription?.cancel();
    allShuttlesSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _localSessionId = prefs.getString('current_session_id');
    } catch (_) {}

    _userSessionSubscription?.cancel();
    _userSessionSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .handleError(
          (e) => debugPrint("Firestore Error (driver user session): $e"),
        )
        .listen((doc) async {
          if (!doc.exists || doc.data() == null) return;
          final data = doc.data()!;

          // 1. ตรวจสอบการเข้าสู่ระบบซ้ำ (Single Active Session)
          final serverSessionId = data['current_session_id'] as String?;
          if (serverSessionId != null) {
            if (_localSessionId == null) {
              _localSessionId = serverSessionId;
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('current_session_id', serverSessionId);
              } catch (_) {}
            } else if (serverSessionId != _localSessionId) {
              _handleConcurrentLogin();
              return;
            }
          }
        });
  }

  /// จัดการเมื่อตรวจพบว่ามีการเข้าสู่ระบบซ้ำจากอุปกรณ์อื่นสำหรับคนขับ
  void _handleConcurrentLogin() {
    if (_isForceLoggingOut) return;
    _isForceLoggingOut = true;

    // หยุดการส่งพิกัด GPS ทันทีเพื่อความปลอดภัย
    positionStream?.cancel();
    _heartbeatTimer?.cancel();
    flutterTts.stop();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text(
                'มีการเข้าสู่ระบบจากอุปกรณ์อื่น',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'บัญชีคนขับนี้ถูกเข้าสู่ระบบจากอุปกรณ์อื่นแล้ว ระบบได้นำคุณออกจากระบบเพื่อความปลอดภัย หากต้องการใช้งานต่อ กรุณาเข้าสู่ระบบใหม่อีกครั้ง',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF595C5D),
              height: 1.4,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF176a21),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _logout();
              },
              child: const Text(
                'ตกลง',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    _alertPlayer.dispose(); // คืนหน่วยความจำ

    if (_shuttleDocId != null) {
      try {
        await FirebaseDatabase.instance
            .ref('shuttles')
            .child(_shuttleDocId!)
            .update({'status': 'offline'})
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Offline Update Error: $e");
      }
    }

    // 1. พาผู้ใช้กลับไปหน้า Login ทันที (เพื่อให้ Navigator ทำลาย Widget ปัจจุบันและปิด Stream ย่อยทั้งหมดในแอปอัตโนมัติ)
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }

    // 2. หน่วงเวลา 500ms เพื่อให้กระบวนการเปลี่ยนหน้าและ Dispose ทำงานเสร็จสิ้น ป้องกัน Firebase Error / แอปค้าง
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. ออกจากระบบ (กำหนดเวลา Timeout กันแอปค้างถ้าเน็ตหลุด)
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
  }

  // เตรียมการทำงานของเสียง AI ภาษาไทย
  Future<void> _initTts() async {
    try {
      flutterTts = FlutterTts();

      // ตรวจสอบว่าระบบรองรับรหัสภาษาไทยแบบใด (บางระบบใช้ th-TH บางระบบใช้ th)
      dynamic isThThAvailable = await flutterTts.isLanguageAvailable("th-TH");
      dynamic isThAvailable = await flutterTts.isLanguageAvailable("th");

      if (isThThAvailable == true || isThThAvailable == 1) {
        _ttsLang = "th-TH";
      } else if (isThAvailable == true || isThAvailable == 1) {
        _ttsLang = "th";
      } else {
        _ttsLang = "th-TH"; // ลองตั้งค่าเริ่มต้นไว้
      }

      await flutterTts.setLanguage(_ttsLang);

      if (!kIsWeb) {
        await flutterTts.setSpeechRate(0.5); // ความเร็วปกติ
        // คงเสียงเดิมไว้ (เสียงผู้หญิง) และปรับระดับเสียงให้ดังสุด (1.0 คือสูงสุดของระบบ TTS)
        // หากต้องการดังกว่านี้ ต้องเพิ่มเสียง Media ของตัวเครื่องมือถือครับ
        await flutterTts.setVolume(1.0);
        await flutterTts.setPitch(1.0);
      }
    } catch (e) {
      print(" Error initializing TTS: $e");
    }
  }

  // ตัวแปรสำหรับจัดการเสียงแจ้งเตือนแบบหน่วงเวลา
  DateTime? _lastVoiceAlertTime;
  String? _lastVoiceAlertStopName;
  Timer? _ttsDebounceTimer;

  // ฟังก์ชันเล่นเสียงแจ้งเตือนและอ่านชื่อป้าย
  Future<void> _triggerVoiceAlert(String stopName, int count) async {
    // 1. ถ้ายอดมาจากป้ายเดิม และมีการกดเรียกซ้ำ ให้ยกเลิกคิวพูด TTS เดิมก่อน
    _ttsDebounceTimer?.cancel();

    final now = DateTime.now();
    bool playSound = true;

    // ป้องกันเสียงเคาะแก้ว (ติ๊ง) รัวเกินไป
    if (_lastVoiceAlertTime != null && _lastVoiceAlertStopName == stopName) {
      if (now.difference(_lastVoiceAlertTime!).inSeconds < 5) {
        playSound = false; // ถ้าเพิ่งดังไปไม่เกิน 5 วิ ไม่ต้องดังซ้ำ
      }
    }

    if (playSound) {
      _lastVoiceAlertTime = now;
      _lastVoiceAlertStopName = stopName;
      try {
        if (!kIsWeb) {
          HapticFeedback.heavyImpact(); // ระบบสั่นเมื่อมีการเรียกรถ
        }
        await _alertPlayer.setVolume(1.0);
        await _alertPlayer.play(
          AssetSource('voice/glass_1.mp3'),
        ); // เสียงแจ้งเตือนเมื่อนักศึกษากดเรียกรถ (glass_1.mp3)
      } catch (e) {
        print("Error playing alert sound: $e");
      }
    }

    // 2. หน่วงเวลาไว้ 2 วินาที เผื่อมีคนกดเพิ่มในจุดเดียวกัน
    _ttsDebounceTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || !isOnline) return;

      try {
        await flutterTts.stop();
        // 3. ปรับแก้คำอ่านบางคำที่ AI อ่านผิด (เช่น IT ให้อ่านว่า ไอที)
        String phoneticStopName = stopName
            .replaceAll('IT', 'ไอที')
            .replaceAll('ทีปวิชญ์', 'ทีปะวิช');

        String textToSpeak;
        if (count > 1) {
          textToSpeak = "มีนักศึกษา $count คน รออยู่ที่ $phoneticStopName";
        } else {
          textToSpeak = "มีนักศึกษารออยู่ที่ $phoneticStopName";
        }
        // ย้ำการตั้งค่าภาษาไทยอีกครั้งบน Web ก่อนพูด โดยใช้ค่าที่เซฟไว้ตอน init
        await flutterTts.setLanguage(_ttsLang);
        await flutterTts.speak(textToSpeak);
      } catch (e) {
        print(" Error triggering TTS: $e");
      }
    });
  }

  // ฟังก์ชันเล่นเสียงแจ้งเตือนกระดิ่งเมื่อถึงจุดหมาย
  Future<void> _triggerDropOffVoiceAlert(String stopName) async {
    if (!mounted || !isOnline) return;

    try {
      if (!kIsWeb) {
        HapticFeedback.heavyImpact(); // ระบบสั่นเมื่อถึงจุดหมาย
      }
      await _alertPlayer.setVolume(1.0);
      await _alertPlayer.play(
        AssetSource('voice/glass_1.mp3'),
      ); // เสียงแจ้งเตือนจุดลงรถ (glass_2.mp3)

      await Future.delayed(
        const Duration(milliseconds: 1200),
      ); // รอให้เสียงกระดิ่งจบ

      await flutterTts.stop();
      String phoneticStopName = stopName
          .replaceAll('IT', 'ไอที')
          .replaceAll('ทีปวิชญ์', 'ทีปะวิช')
          .replaceAll('(ขาเข้า)', '')
          .replaceAll('(ขาออก)', '')
          .trim();

      // ย้ำการตั้งค่าภาษาไทยอีกครั้งบน Web ก่อนพูด
      await flutterTts.setLanguage(_ttsLang);
      await flutterTts.speak("มีนักศึกษาลงที่ $phoneticStopName");
    } catch (e) {
      print(" Error triggering drop-off TTS: $e");
    }
  }

  Future<void> _startShift() async {
    // กระตุ้นการเล่นเสียง 1 ครั้ง ทันทีที่ผู้ใช้กดปุ่ม เพื่อปลดล็อก Audio Context (สำคัญมากบน Web) และเพื่อยืนยันให้คนขับทราบ
    try {
      // 1. พูดข้อความต้อนรับ (ทำงานทุกแพลตฟอร์ม)
      await flutterTts.setLanguage(_ttsLang);
      await flutterTts.setVolume(1.0);
      await flutterTts.speak("เปิดระบบรับผู้โดยสาร");

      // 2. ปลดล็อก AudioPlayer (เสียง mp3) เฉพาะ Web เพื่อแก้ปัญหา Autoplay Policy
      if (kIsWeb) {
        await _alertPlayer.setVolume(0.0);
        await _alertPlayer.play(AssetSource('voice/glass_1.mp3'));
        await Future.delayed(const Duration(milliseconds: 200));
        await _alertPlayer.setVolume(1.0);
      }
    } catch (e) {
      print("Error unlocking audio context: $e");
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!serviceEnabled) {
      TopToast.show(context, ' กรุณาเปิด GPS ในอุปกรณ์ของคุณ', isError: true);
      return;
    }

    if (_shuttleDocId == null) {
      await _fetchDriverShuttle();
    }

    if (_shuttleDocId == null) {
      TopToast.show(
        context,
        ' ไม่พบข้อมูลรถของคุณ (การเชื่อมต่อฐานข้อมูลล้มเหลว) กรุณารีสตาร์ทแอป',
        isError: true,
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        TopToast.show(
          context,
          ' สิทธิ์การเข้าถึงตำแหน่งถูกปฏิเสธ',
          isError: true,
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      TopToast.show(
        context,
        ' สิทธิ์การเข้าถึงตำแหน่งถูกบล็อก กรุณาเปิดสิทธิ์ในตั้งค่า',
        isError: true,
      );
      return;
    }

    if (!mounted) return;

    final fallbackLoc = const LatLng(
      16.829708,
      100.20716,
    ); // หอประชุมศรีวชิรโชติ

    // แสดงตำแหน่งไอคอนเริ่มต้นบนแผนที่ทันที เพื่อป้องกันอาการค้างหรือรอโหลด GPS (Instant UX)
    _lastFirebaseUpdate = null;
    _lastUploadedLocation = null;
    setState(() {
      isOnline = true;
      _isAutoFollow = true; // เปิดติดตามตำแหน่งรถอัตโนมัติเมื่อเริ่มงาน
      _currentLocation = fallbackLoc;
      _targetLocation = fallbackLoc;
    });
    _mapController.move(fallbackLoc, 16.5);

    try {
      // 1. ดึงพิกัดล่าสุดในแคชเครื่องก่อน (Last Known Position) มักจะได้ผลทันทีโดยไม่ต้องรอสัญญาณดาวเทียม
      Position? lastPos;
      try {
        lastPos = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager:
              Theme.of(context).platform == TargetPlatform.android,
        );
      } catch (e) {
        // Fallback for Web platform
      }

      if (lastPos != null) {
        LatLng lastLoc = _snapToRoute(
          LatLng(lastPos.latitude, lastPos.longitude),
        );
        print(
          " GPS Last Known: ${lastPos.latitude}, ${lastPos.longitude} -> Snapped: ${lastLoc.latitude}, ${lastLoc.longitude}",
        );
        if (mounted) {
          setState(() {
            _currentLocation = lastLoc;
            _targetLocation = lastLoc;
          });
          if (_psruBounds.contains(lastLoc)) {
            _mapController.move(lastLoc, 16.5);
          }
        }
      }

      // 2. ดึงพิกัดปัจจุบันจริงในพื้นหลัง โดยกำหนด Timeout ไว้ 3 วินาที
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
        forceAndroidLocationManager:
            Theme.of(context).platform == TargetPlatform.android,
      );
      LatLng newLoc = _snapToRoute(
        LatLng(initialPos.latitude, initialPos.longitude),
      );

      print(
        " GPS Initialized: ${initialPos.latitude}, ${initialPos.longitude} -> Snapped: ${newLoc.latitude}, ${newLoc.longitude}",
      );

      if (mounted) {
        setState(() {
          _currentLocation = newLoc;
          _targetLocation = newLoc;
        });

        // ค้นหาป้ายที่ใกล้ที่สุดเมื่อเปิดแอป เพื่อเซ็ตเริ่มต้นให้ระบบ Routing (ป้องกันบั๊ก ETA เริ่มที่ป้าย 1 เสมอ)
        if (busStops.isNotEmpty) {
          double minDist = double.infinity;
          int closestOrder = 1;
          for (var stop in busStops) {
            if (stop['lat'] != null && stop['lng'] != null) {
              final loc = LatLng(stop['lat'], stop['lng']);
              final d = const Distance().distance(newLoc, loc);
              if (d < minDist) {
                minDist = d;
                closestOrder = stop['order'] ?? 1;
              }
            }
          }
          _lastPassedStopOrder = closestOrder;
          int maxOrder = busStops
              .map((s) => ((s['order'] ?? 0) as num).toInt())
              .reduce((a, b) => a > b ? a : b);
          if (maxOrder == 0) maxOrder = 23;
          _currentTargetStopOrder = (closestOrder % maxOrder) + 1;
        }

        // เช็คว่าพิกัดอยู่ในเขตมหาลัยหรือไม่
        if (_psruBounds.contains(newLoc)) {
          _mapController.move(newLoc, 16.5);
        } else {
          TopToast.show(
            context,
            ' ตำแหน่ง GPS ของคุณอยู่นอกพื้นที่มหาวิทยาลัย',
            isError: true,
          );
        }

        if (_shuttleDocId != null) {
          _lastFirebaseUpdate = DateTime.now();
          _lastUploadedLocation = newLoc;
          FirebaseDatabase.instance
              .ref('shuttles')
              .child(_shuttleDocId!)
              .update({
                'lat': newLoc.latitude,
                'lng': newLoc.longitude,
                'status': 'online',
                'last_updated': ServerValue.timestamp,
              });
        }
      }
    } catch (e) {
      print(" Error getting initial location (Using Fallback): $e");
      // หาก _currentLocation ยังเป็นค่าเริ่มต้นอยู่ (หอประชุมฯ) หรือดึงพิกัดล่าสุดสำเร็จแล้วก็ให้ค้างค่านั้นไว้
      if (mounted) {
        TopToast.show(
          context,
          ' ดึงพิกัดจริงล่าช้า ระบบใช้พิกัดที่มีล่าสุด',
          isError: true,
        );

        if (_shuttleDocId != null && _currentLocation != null) {
          _lastFirebaseUpdate = DateTime.now();
          _lastUploadedLocation = _currentLocation;
          FirebaseDatabase.instance
              .ref('shuttles')
              .child(_shuttleDocId!)
              .update({
                'lat': _currentLocation!.latitude,
                'lng': _currentLocation!.longitude,
                'status': 'online',
                'last_updated': ServerValue.timestamp,
              });
        }
      }
    }

    // ตั้งค่า distanceFilter เป็น 2 เมตร และอัปเดตทุก 800ms เพื่อรองรับรถวิ่งความเร็ว 20-30 กม./ชม.
    late final LocationSettings locationSettings;
    if (Theme.of(context).platform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        forceLocationManager: true,
        intervalDuration: const Duration(
          milliseconds: 800,
        ), // อัปเดตพิกัด GPS ทุกๆ 0.8 วินาที
      );
    } else if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
    }

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (!mounted) return;

        LatLng rawLoc = LatLng(position.latitude, position.longitude);
        LatLng newLoc = _snapToRoute(rawLoc);
        print(
          " GPS Updated: ${position.latitude}, ${position.longitude} -> Snapped: ${newLoc.latitude}, ${newLoc.longitude}",
        );

        if (_currentLocation == null) {
          setState(() {
            _currentLocation = newLoc;
            _targetLocation = newLoc;
          });
          if (_isAutoFollow) {
            _mapController.move(newLoc, 16.5);
          }
        } else {
          _targetLocation = newLoc;
          _restartMarkerAnimation();
        }

        // Smart Throttling & Distance Check: ส่งข้อมูลขึ้น Firestore ต่อเมื่อรถขยับไปอย่างน้อย 3 เมตร และเว้นระยะเวลาอย่างน้อย 1.2 วินาที (พอดีกับความเร็ว 20-30 กม./ชม.)
        final now = DateTime.now();
        final double distanceMoved = _lastUploadedLocation == null
            ? 999.0
            : const Distance().distance(_lastUploadedLocation!, newLoc);

        // Smart Routing: ตรวจสอบการผ่านป้าย (รัศมี 30 เมตร) เพื่ออัปเดต last_passed_stop
        if (busStops.isNotEmpty) {
          try {
            int maxOrder = busStops
                .map((s) => ((s['order'] ?? 0) as num).toInt())
                .reduce((a, b) => a > b ? a : b);
            if (maxOrder == 0) maxOrder = 23;

            // Strict Window Routing: คาดการณ์ป้ายล่วงหน้า 2 ป้ายเป็นหลัก
            List<int> upcomingStops = [];
            for (int i = 0; i < 2; i++) {
              int nextOrder =
                  ((_currentTargetStopOrder - 1 + i) % maxOrder) + 1;
              upcomingStops.add(nextOrder);

              // กฎพิเศษ: ถ้ารอบใหม่เริ่มต้นขึ้น (เป้าหมายคือป้าย 1) ไม่อนุญาตให้ข้าม
              // ต้องบังคับให้ผ่านป้าย 1 เสมอ ป้องกันการกระโดดไป 2 หรือ 3
              if (_currentTargetStopOrder == 1) {
                break;
              }
            }

            int detectedStopOrder = -1;
            double minDistance = 30.0;
            Map<String, dynamic>? detectedStopData;

            // ตรวจจับว่าเข้าใกล้ป้ายใดใน Window หรือไม่
            for (var stop in busStops) {
              int order = ((stop['order'] ?? 0) as num).toInt();
              if (upcomingStops.contains(order) &&
                  stop['lat'] != null &&
                  stop['lng'] != null) {
                final targetLoc = LatLng(stop['lat'], stop['lng']);
                final distanceToTarget = const Distance().distance(
                  newLoc,
                  targetLoc,
                );
                if (distanceToTarget <= minDistance) {
                  minDistance = distanceToTarget;
                  detectedStopOrder = order;
                  detectedStopData = stop;
                }
              }
            }

            // ระบบกู้คืน (Smart Recovery Mode): ค้นหาจากทุกป้าย แต่จำกัดการกระโดดข้ามอย่างเข้มงวด
            if (detectedStopOrder == -1) {
              minDistance = 30.0;
              for (var stop in busStops) {
                int order = ((stop['order'] ?? 0) as num).toInt();

                // ป้องกันการ Spam ตรวจจับป้ายเดิมซ้ำๆ (jump = 0)
                if (_lastPassedStopOrder != null &&
                    order == _lastPassedStopOrder) {
                  continue;
                }

                if (stop['lat'] != null && stop['lng'] != null) {
                  final targetLoc = LatLng(stop['lat'], stop['lng']);
                  final distanceToTarget = const Distance().distance(
                    newLoc,
                    targetLoc,
                  );

                  if (distanceToTarget <= minDistance) {
                    bool isAllowed = true;
                    if (_lastPassedStopOrder != null) {
                      int jump = order - _lastPassedStopOrder!;
                      if (jump < 0) jump += maxOrder;
                      // กฎใหม่: อนุญาตให้ข้ามได้สูงสุด 2 ป้าย และย้อนกลับได้แค่ 1 ป้าย
                      if (jump > 2 && jump < maxOrder - 2) {
                        isAllowed = false;
                      }

                      // กฎพิเศษ: ถ้าเพิ่งผ่านป้าย 23 ไม่อนุญาตให้ข้ามป้าย 1
                      if (_lastPassedStopOrder == maxOrder &&
                          jump > 1 &&
                          jump < maxOrder - 1) {
                        isAllowed = false;
                      }
                    }

                    if (isAllowed) {
                      minDistance = distanceToTarget;
                      detectedStopOrder = order;
                      detectedStopData = stop;
                    }
                  }
                }
              }
              if (detectedStopOrder != -1) {
                print(
                  " [Smart Recovery] กู้คืนพิกัด GPS โดยกระโดดไปป้ายที่ $detectedStopOrder",
                );
              }
            }

            if (detectedStopOrder != -1 && detectedStopData != null) {
              print(
                " Passed Stop: ${detectedStopData['name']} (Order: $detectedStopOrder)",
              );

              // ตรวจสอบว่าขับครบรอบหรือไม่ (ถ้าป้ายล่าสุดที่ผ่านอยู่ท้ายซอย แล้วป้ายใหม่โผล่มาต้นซอย)
              if (_lastPassedStopOrder != null) {
                int thresholdHigh = maxOrder > 10 ? maxOrder - 5 : maxOrder - 2;
                int thresholdLow = maxOrder > 10 ? 5 : 2;
                if (_lastPassedStopOrder! >= thresholdHigh &&
                    detectedStopOrder <= thresholdLow) {
                  print(" วนกลับมาเริ่มต้นรอบใหม่!");
                  _announcedDropOffStops.clear();
                  _incrementDailyRound(); // นับว่าจบรอบ 1 รอบและบันทึกลง Firestore
                }
              }

              _lastPassedStopOrder = detectedStopOrder;
              _currentTargetStopOrder = (detectedStopOrder % maxOrder) + 1;
            }

            // Drop-off TTS Alert (แจ้งเตือนล่วงหน้า 150 เมตร) - โฟกัสป้ายเป้าหมายปัจจุบันเสมอ
            final currentTargetStop = busStops.firstWhere(
              (s) => s['order'] == _currentTargetStopOrder,
              orElse: () => busStops.first,
            );
            if (currentTargetStop['lat'] != null &&
                currentTargetStop['lng'] != null) {
              final targetLoc = LatLng(
                currentTargetStop['lat'],
                currentTargetStop['lng'],
              );
              final distanceToCurrentTarget = const Distance().distance(
                newLoc,
                targetLoc,
              );
              if (distanceToCurrentTarget <= 150.0 &&
                  _activeDropOffStops.contains(currentTargetStop['name'])) {
                if (!_announcedDropOffStops.contains(
                  currentTargetStop['name'],
                )) {
                  _announcedDropOffStops.add(currentTargetStop['name']);
                  _triggerDropOffVoiceAlert(currentTargetStop['name']);
                }
              }
            }
          } catch (e) {
            print("Error checking stop distance: $e");
          }
        }

        print(
          " [GPS Check] id=$_shuttleDocId, dist=$distanceMoved, lastUpd=$_lastFirebaseUpdate",
        );
        if (_shuttleDocId != null &&
            distanceMoved >= 2.0 &&
            (_lastFirebaseUpdate == null ||
                now.difference(_lastFirebaseUpdate!).inMilliseconds >= 2000)) {
          _lastFirebaseUpdate = now;
          _lastUploadedLocation = newLoc;

          final updateData = {
            'lat': newLoc.latitude,
            'lng': newLoc.longitude,
            'status': 'online',
            'last_updated': ServerValue.timestamp,
          };
          // แนบ last_passed_stop ไปด้วย
          if (_lastPassedStopOrder != null) {
            updateData['last_passed_stop'] = _lastPassedStopOrder as Object;
          }

          FirebaseDatabase.instance
              .ref('shuttles')
              .child(_shuttleDocId!)
              .update(updateData);
          print(" [DriverHome] Updated location in RTDB: $updateData");
        }
      },
      onError: (error) {
        print(" GPS Stream Error: $error");
      },
    );

    requestStream = FirebaseFirestore.instance
        .collection('ride_requests')
        .where(
          'status',
          whereIn: ['waiting', 'acknowledged', 'on_board'],
        ) // เพิ่ม on_board
        .snapshots()
        .handleError((e) => print("Firestore Error (ride_requests): $e"))
        .listen((snapshot) {
          if (!mounted) return;

          if (snapshot.docs.isNotEmpty) {
            // กรองเอาเฉพาะคำขอที่เจาะจงเรียกรถคันนี้เท่านั้น และต้องไม่เก่าเกิน 2 ชั่วโมง (ป้องกันข้อมูลค้างในระบบ)
            final validDocs = snapshot.docs.where((doc) {
              final data = doc.data();

              if (data.containsKey('timestamp') && data['timestamp'] != null) {
                final requestTime = (data['timestamp'] as Timestamp).toDate();
                if (DateTime.now().difference(requestTime).inHours >= 2) {
                  return false; // ข้อมูลเก่าเกิน 2 ชั่วโมง ไม่นำมาแสดง
                }
              }

              if (data.containsKey('target_shuttle_id') &&
                  data['target_shuttle_id'] != null) {
                return data['target_shuttle_id'] == _shuttleDocId;
              }
              return true; // ถ้าระบบเก่าไม่มี target_shuttle_id ให้มองว่าเรียกได้ทุกคน
            }).toList();

            // เรียงลำดับคำขอตามเวลา (เก่าสุดขึ้นก่อน - เข้าคิวก่อนได้ก่อน FIFO)
            final docs = validDocs;
            docs.sort((a, b) {
              final aData = a.data();
              final bData = b.data();
              final aTime = aData['timestamp'] as Timestamp?;
              final bTime = bData['timestamp'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return aTime.compareTo(bTime); // ascending (เก่าสุดมาก่อน)
            });

            // ดึงตำแหน่งนักศึกษาทั้งหมดที่รอหรือกำลังรอรถ (ซ่อนเมื่อขึ้นรถแล้ว)
            final List<Map<String, dynamic>> students = [];
            for (var doc in docs) {
              final data = doc.data();
              if (data['status'] != 'on_board' &&
                  data.containsKey('student_lat') &&
                  data.containsKey('student_lng')) {
                double sLat = 0.0;
                double sLng = 0.0;
                if (data['student_lat'] is double)
                  sLat = data['student_lat'];
                else if (data['student_lat'] is int)
                  sLat = (data['student_lat'] as int).toDouble();
                else if (data['student_lat'] is String)
                  sLat = double.tryParse(data['student_lat'].toString()) ?? 0.0;

                if (data['student_lng'] is double)
                  sLng = data['student_lng'];
                else if (data['student_lng'] is int)
                  sLng = (data['student_lng'] as int).toDouble();
                else if (data['student_lng'] is String)
                  sLng = double.tryParse(data['student_lng'].toString()) ?? 0.0;

                students.add({
                  'id': doc.id,
                  'lat': sLat,
                  'lng': sLng,
                  'status': data['status'],
                });
              }
            }

            // อัปเดตรายชื่อจุดลงรถและนับจำนวนคนที่ลงแต่ละป้าย (ทั้งคนที่อยู่บนรถ และคนที่เรียกรถอยู่)
            final Set<String> dropOffStops = {};
            final Map<String, int> dropOffCounts = {};
            for (var doc in docs) {
              final data = doc.data();
              if (data.containsKey('dropoff_stop') &&
                  data['dropoff_stop'] != null &&
                  data['dropoff_stop'].toString().trim().isNotEmpty) {
                final String dStop = data['dropoff_stop'].toString().trim();
                dropOffStops.add(dStop);
                dropOffCounts[dStop] = (dropOffCounts[dStop] ?? 0) + 1;
              }
            }

            // ค้นหาคำขอที่มีสถานะ 'waiting' เพื่อเป็นป้ายหลัก (active)
            QueryDocumentSnapshot? activeDoc;
            for (var doc in docs) {
              if (doc['status'] == 'waiting') {
                activeDoc = doc;
                break;
              }
            }

            if (activeDoc != null) {
              String targetStop = activeDoc['stop_name'];

              // รวบรวมคำขอทั้งหมดที่อยู่ป้ายเดียวกันและมีสถานะ waiting
              List<String> targetIds = [];
              for (var doc in docs) {
                if (doc['status'] == 'waiting' &&
                    doc['stop_name'] == targetStop) {
                  targetIds.add(doc.id);
                }
              }

              // ตรวจสอบว่ามี id ไหนที่เพิ่งเข้ามาใหม่หรือไม่
              bool hasNewRequest = false;
              for (var id in targetIds) {
                if (!activeRequestIds.contains(id)) {
                  hasNewRequest = true;
                  break;
                }
              }

              if (hasNewRequest) {
                _triggerVoiceAlert(targetStop, targetIds.length);
              }

              setState(() {
                _activeDropOffStops = dropOffStops;
                _dropOffCounts = dropOffCounts;
                waitingStudentsList = students;
                waitingStudentStop = targetStop;
                activeRequestIds = targetIds;
                activeStudentCount = targetIds.length;
                currentRequestStatus = 'waiting';
              });
            } else {
              // ถ้าไม่มีคำขอ waiting เลย (อาจจะ acknowledged หรือ on_board หมดแล้ว)
              setState(() {
                _activeDropOffStops = dropOffStops;
                _dropOffCounts = dropOffCounts;
                waitingStudentsList = students;
                waitingStudentStop = null;
                activeRequestIds = [];
                activeStudentCount = 0;
                currentRequestStatus = null;
              });
            }
          } else {
            // เมื่อนักศึกษาลงรถเสร็จสิ้น/ลบคำขอออกจาก Firestore ทั้งหมด
            setState(() {
              _activeDropOffStops = {};
              _dropOffCounts = {};
              waitingStudentsList = [];
              waitingStudentStop = null;
              activeRequestIds = [];
              activeStudentCount = 0;
              currentRequestStatus = null;
            });
          }
        });

    // เริ่ม Heartbeat ทุกๆ 30 วินาที เพื่ออัปเดตเวลาล่าสุดและ "เลี้ยงการเชื่อมต่อเน็ตไม่ให้หลับ"
    // พอเน็ตไม่หลับ เวลามีคนเรียกรถ มันจะเด้งขึ้นหน้าจอทันที ไม่ต้องรอหน่วง! (30 วิ ช่วยประหยัดโควต้ากว่า 15 วิ)
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isOnline || _shuttleDocId == null) {
        timer.cancel();
        return;
      }
      _lastFirebaseUpdate = DateTime.now();

      // 1. เลี้ยงการเชื่อมต่อ Realtime Database
      FirebaseDatabase.instance.ref('shuttles').child(_shuttleDocId!).update({
        'last_updated': ServerValue.timestamp,
      });

      // 2.  เลี้ยงการเชื่อมต่อ Firestore (สำคัญมาก!)
      // ป้องกันบั๊กมือถือตัดการเชื่อมต่อ Firestore เมื่อเปิดทิ้งไว้นานๆ ทำให้ไม่เห็นคนเรียกรถ
      FirebaseFirestore.instance
          .collection('shuttles_ping')
          .doc(_shuttleDocId!)
          .set({'last_ping': FieldValue.serverTimestamp()})
          .catchError((e) => print("Firestore Ping Error: $e"));
    });
  }

  void _stopTracking() {
    _heartbeatTimer?.cancel();
    positionStream?.cancel();
    requestStream?.cancel();

    _lastUploadedLocation = null;
    _lastFirebaseUpdate = null;

    if (mounted) {
      setState(() {
        isOnline = false;
        _currentLocation = null; // ซ่อนหมุดตำแหน่งรถตอนออฟไลน์
        _targetLocation = null;
        _oldLocation = null;
        waitingStudentStop = null;
        activeRequestIds = [];
        activeStudentCount = 0;
        currentRequestStatus = null;
      });
    }

    if (_shuttleDocId != null) {
      FirebaseDatabase.instance
          .ref('shuttles')
          .child(_shuttleDocId!)
          .update({'status': 'offline'})
          .catchError((e) => print(e));
    }
  }

  Future<void> _acknowledgeRequest() async {
    if (activeRequestIds.isNotEmpty) {
      final int count = activeRequestIds.length;
      final batch = FirebaseFirestore.instance.batch();
      for (var id in activeRequestIds) {
        final docRef = FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(id);
        batch.update(docRef, {
          'status': 'acknowledged',
          'acknowledged_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      // บันทึกสถิติลง Analytics
      try {
        final now = DateTime.now();
        final dateStr =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

        FirebaseFirestore.instance
            .collection('analytics')
            .doc('daily_stats_$dateStr')
            .set({
              'acknowledged_requests_count': FieldValue.increment(count),
              'on_time_trips': FieldValue.increment(count),
              'last_updated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (e) {
        print("Error updating driver acknowledge analytics: $e");
      }

      if (mounted) {
        setState(() {
          activeRequestIds = [];
          activeStudentCount = 0;
          currentRequestStatus = 'acknowledged';
        });
      }
    }
  }

  Future<void> _triggerVoiceAlertForChat() async {
    try {
      HapticFeedback.heavyImpact();
      if (!kIsWeb) {
        FlutterRingtonePlayer().playNotification();
      }
      await _alertPlayer.setVolume(1.0);
      await _alertPlayer.play(AssetSource('voice/chat_sound.mp3'));
    } catch (e) {
      print("Error playing chat alert sound: $e");
    }
  }

  Widget _buildIncomingChatPopup() {
    if (_incomingChatNotification == null) return const SizedBox.shrink();

    final String sender = _incomingChatNotification!['sender'] ?? 'นักศึกษา';
    final String text = _incomingChatNotification!['text'] ?? '';
    final double topPadding = MediaQuery.of(context).padding.top > 0
        ? MediaQuery.of(context).padding.top + 8
        : 14;

    return Positioned(
      top: topPadding,
      left: 14,
      right: 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Dismissible(
            key: const Key('driver_incoming_chat_popup'),
            direction: DismissDirection.up,
            onDismissed: (_) {
              _chatNotificationTimer?.cancel();
              setState(() {
                _incomingChatNotification = null;
              });
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _chatNotificationTimer?.cancel();
                  setState(() {
                    _incomingChatNotification = null;
                    _selectedIndex = 2; // สลับไปหน้าแชตทันที
                  });
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFF9FAF9),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFF81C784).withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF176a21).withValues(alpha: 0.14),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // ไอคอนวงกลมพร้อมจุดแสดงสถานะข้อความใหม่
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF176a21).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // ข้อมูลผู้ส่งและข้อความ
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    sender,
                                    style: const TextStyle(
                                      color: Color(0xFF2C2F30),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF64B5F6).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'นักศึกษา',
                                    style: TextStyle(
                                      color: Color(0xFF1976D2),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              text,
                              style: const TextStyle(
                                color: Color(0xFF5A605B),
                                fontSize: 13,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // ปุ่มกดตอบกลับ & ปุ่มปิด
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              _chatNotificationTimer?.cancel();
                              setState(() {
                                _incomingChatNotification = null;
                                _selectedIndex = 2; // สลับไปหน้าแชตทันที
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF176a21).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ตอบกลับ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  SizedBox(width: 3),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              _chatNotificationTimer?.cancel();
                              setState(() {
                                _incomingChatNotification = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF757778),
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F2),
      body: Stack(
        children: [
          // IndexedStack สลับหน้าจอตาม Bottom Navigation
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildMapScreen(), // หน้าแผนที่ (หน้า 0)
              DriverStatusScreen(
                shuttleDocId: _shuttleDocId,
              ), // หน้าสถานะรถ (หน้า 1)
              DriverChatScreen(
                shuttleDocId: _shuttleDocId ?? _shuttleNumber ?? '1',
                shuttleName: _shuttleName ?? 'Shuttle #01',
              ), // หน้าแชทคนขับรถ (หน้า 2)
              const DriverProfileScreen(), // หน้าโปรไฟล์คนขับรถ (หน้า 3)
            ],
          ),

          // ป๊อปอัปแจ้งเตือนข้อความแชตใหม่จากนักศึกษา
          _buildIncomingChatPopup(),

          // Bottom Navigation Bar สไตล์ Floating Dock โมเดิร์น (ลอยขึ้นมาจากขอบล่าง และเว้นระยะซ้าย-ขวา)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom > 0
                ? MediaQuery.of(context).padding.bottom + 8
                : 16,
            left: 16,
            right: 16,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildCurvedBottomNav(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // แยกส่วนแผนที่ออกมาเป็นฟังก์ชัน
  Widget _buildMapScreen() {
    return Stack(
      children: [
        // แผนที่หลัก
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _psruCenter,
              initialZoom: 15.5,
              minZoom: 14.5,
              maxZoom: 18.0,
              cameraConstraint:
                  CameraConstraint.containCenter(bounds: _psruBounds),
              interactionOptions: InteractionOptions(
                flags:
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
                cursorKeyboardRotationOptions:
                    CursorKeyboardRotationOptions.disabled(), // ปิดการหมุนด้วยคีย์บอร์ด/เมาส์บน Web
              ),
              // ตรวจจับเมื่อคนขับใช้นิ้วเลื่อนหรือแตะแผนที่ด้วยตัวเอง ให้ปิด Auto-Follow อัตโนมัติ
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isAutoFollow) {
                  setState(() {
                    _isAutoFollow = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.psru_shuttle_app',
              ),

              // แสดงเส้นทางเสมอ แต่ให้สีจางลงตอนออฟไลน์
              PolylineLayer(
                polylines: shuttleRoutes.map((segment) {
                  return Polyline(
                    points: segment,
                    strokeWidth: 5.0,
                    color: const Color(
                      0xFF176a21,
                    ).withOpacity(isOnline ? 0.4 : 0.15),
                  );
                }).toList(),
              ),

              MarkerLayer(
                markers: [
                  // แสดงป้ายจอดแบบยุบกลุ่มจุดจอดที่อยู่ใกล้กัน (พร้อมแสดงจุดหมายนักศึกษาเป็นสีเขียว)
                  ..._visualStops.map((vStop) {
                    final String name = (vStop['name'] ?? '').toString();
                    bool isPickupSelected = false;
                    bool isDropoffSelected = false;
                    int dropoffCount = 0;

                    if (vStop['isGroup'] == true) {
                      final members = vStop['members'] as List;
                      isPickupSelected = members.any(
                        (m) => m['name'] == waitingStudentStop,
                      );
                      for (var m in members) {
                        final String mName = (m['name'] ?? '').toString();
                        if (_activeDropOffStops.contains(mName)) {
                          isDropoffSelected = true;
                          dropoffCount += (_dropOffCounts[mName] ?? 0);
                        }
                      }
                    } else {
                      isPickupSelected = (waitingStudentStop == name);
                      if (_activeDropOffStops.contains(name)) {
                        isDropoffSelected = true;
                        dropoffCount = (_dropOffCounts[name] ?? 0);
                      }
                    }

                    final bool isHighlighted =
                        isPickupSelected || isDropoffSelected;

                    return Marker(
                      key: ValueKey('stop_$name'),
                      point: LatLng(vStop['lat'], vStop['lng']),
                      width: 160,
                      height: isHighlighted ? 80 : 65,
                      child: RepaintBoundary(
                        child: _buildStopMarker(
                          name: name,
                          isPickupSelected: isPickupSelected,
                          isDropoffSelected: isDropoffSelected,
                          dropoffCount: dropoffCount,
                          isGroup: vStop['isGroup'] == true,
                        ),
                      ),
                    );
                  }),

                  // แสดงตำแหน่งรถคันอื่นๆ ที่กำลังออนไลน์ (เพื่อให้คนขับเห็นกันเอง)
                  ...activeShuttles.map((shuttle) {
                    final currentLoc =
                        _otherCurrentLocations[shuttle['id']] ??
                        LatLng(shuttle['lat'], shuttle['lng']);
                    return Marker(
                      key: ValueKey('other_shuttle_${shuttle['id']}'),
                      point: currentLoc,
                      width: 80,
                      height: 80,
                      child: RepaintBoundary(
                        child: _buildBusMarker(
                          shuttle.containsKey('passenger_status')
                              ? shuttle['passenger_status']
                              : 'available',
                          shuttle['number']?.toString(),
                        ),
                      ),
                    );
                  }),
                  // แสดงตำแหน่งของนักศึกษาที่เรียกรถ
                  ...waitingStudentsList.map((student) {
                    return Marker(
                      key: ValueKey('student_${student['id']}'),
                      point: LatLng(student['lat'], student['lng']),
                      width: 80,
                      height: 80,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.0,
                                ),
                              ),
                              child: const Text(
                                'นักศึกษา',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // แสดงตำแหน่งรถตัวเอง
                  if (isOnline && _currentLocation != null)
                    Marker(
                      key: const ValueKey('my_bus_marker'),
                      point: _currentLocation!,
                      width: 80,
                      height: 80,
                      child: RepaintBoundary(child: _buildMyBusMarker()),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ปุ่ม My Location (เป้าเล็งรถตัวเอง และเปิด/ปิด Auto-Follow)
        if (isOnline && _currentLocation != null)
          Positioned(
            bottom:
                (waitingStudentStop != null &&
                    currentRequestStatus == 'waiting')
                ? 210
                : 110, // ปรับตำแหน่งให้พ้นการ์ดแจ้งเตือนและ Bottom Nav
            right: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: _isAutoFollow
                  ? const Color(0xFF176a21)
                  : Colors.white,
              elevation: 4,
              onPressed: () {
                setState(() {
                  _isAutoFollow = true; // เปิดติดตามตำแหน่งรถอัตโนมัติ
                });
                _mapController.move(_currentLocation!, 16.5);
              },
              child: Icon(
                _isAutoFollow ? Icons.my_location : Icons.location_searching,
                color: _isAutoFollow ? Colors.white : const Color(0xFF176a21),
              ),
            ),
          ),

        // Curved Bottom Header (ขอบล่างโค้งมน สะอาดตา)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFF8FAF8),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(26),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF176a21).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.03),
                width: 1.0,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ฝั่งซ้าย: โลโก้
                        Image.asset(
                          'lib/screens/driver/logo.png',
                          height: 38,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Row(
                              children: [
                                Icon(
                                  Icons.directions_bus,
                                  color: Color(0xFF176a21),
                                  size: 26,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'PSRU Shuttle',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF176a21),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        // ฝั่งขวา: ปุ่มสถานะออนไลน์ / เลิกงาน / ออกจากระบบ
                        if (isOnline)
                          GestureDetector(
                            onTap: _stopTracking,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFEF5350).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.power_settings_new_rounded,
                                    color: Color(0xFFC62828),
                                    size: 16,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'เลิกงาน',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFC62828),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: _logout,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.04),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    color: Color(0xFF5A605B),
                                    size: 16,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'ออก',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF5A605B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ป้ายสถานะรถแบบลอยชิดซ้ายบนแผนที่ (Floating Status Pill on Map)
        Positioned(
          top: 84,
          left: 16,
          child: SafeArea(
            top: true,
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (isOnline
                            ? const Color(0xFF176a21)
                            : const Color(0xFFD84315))
                        .withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: isOnline
                      ? const Color(0xFF81C784).withValues(alpha: 0.6)
                      : Colors.orange.shade200,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF22C55E) : const Color(0xFFF57C00),
                      shape: BoxShape.circle,
                      boxShadow: isOnline
                          ? [
                              BoxShadow(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    isOnline
                        ? 'ออนไลน์ (กำลังวิ่งรถ) '
                        : 'ออฟไลน์ (ยังไม่เริ่มงาน)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? const Color(0xFF1B5E20) : const Color(0xFFD84315),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // หน้าต่างออฟไลน์ (แสดงเป็นการ์ดลอยด้านล่างเมื่อยังไม่เริ่มงาน)
        if (!isOnline)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildOfflineSheet(),
            ),
          ),

        // การแจ้งเตือนเวลามีนักศึกษาเรียก (Popup ด้านล่าง)
        if (isOnline &&
            waitingStudentStop != null &&
            currentRequestStatus == 'waiting')
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF176a21).withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF9DF197),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.front_hand,
                          color: Color(0xFF176a21),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'มีนักศึกษารออยู่ที่:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              waitingStudentStop!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (activeStudentCount > 1)
                              Text(
                                '(จำนวน $activeStudentCount คน)',
                                style: const TextStyle(
                                  color: Color(0xFF9DF197),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _acknowledgeRequest,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'รับทราบ',
                            style: TextStyle(
                              color: Color(0xFF176a21),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // วิดเจ็ต Bottom Navigation Bar ดีไซน์โค้งเว้า (Curved Notch) พรีเมียม พร้อมชิปไอคอนและ Live Status Indicator
  Widget _buildCurvedBottomNav() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map_outlined, 'activeIcon': Icons.map, 'label': 'Map'},
      {
        'icon': Icons.directions_bus_outlined,
        'activeIcon': Icons.directions_bus,
        'label': 'Status',
      },
      {
        'icon': Icons.chat_bubble_outline,
        'activeIcon': Icons.chat_bubble,
        'label': 'Chat',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'Profile',
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double itemWidth = width / navItems.length;
        final double targetX = itemWidth * _selectedIndex + itemWidth / 2;

        return SizedBox(
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. พื้นหลังบาร์สีขาวไข่มุกพร้อมรอยบากเว้า (Pearl Gradient & Curved Notch)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: targetX, end: targetX),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, animatedX, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(width, 80),
                        painter: _CurvedNavPainter(
                          notchCenter: animatedX,
                        ),
                      ),
                      // 2. ปุ่มวงกลมสีเขียวมรกตลอยอยู่ในรอยบาก (พร้อมขอบสีขาวคมชัด)
                      Positioned(
                        top: 2,
                        left: animatedX - 23,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 3.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF176a21).withValues(alpha: 0.38),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            navItems[_selectedIndex]['activeIcon'],
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 3. รายการปุ่มกดและข้อความแต่ละแท็บ (พร้อม Capsule Chip รองรับไอคอน)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: List.generate(navItems.length, (index) {
                    final bool isActive = _selectedIndex == index;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _selectedIndex = index);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isActive) ...[
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      navItems[index]['icon'],
                                      color: const Color(0xFF5A605B),
                                      size: 19,
                                    ),
                                  ),
                                  // จุดเขียวกระพริบเตือนเมื่อออนไลน์ในหน้าสถานะ
                                  if (index == 1 && isOnline)
                                    Positioned(
                                      top: -1,
                                      right: -1,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.6),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5A605B),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 24),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF176a21),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOfflineSheet() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: const Color(0xFF176a21).withValues(alpha: 0.10),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF176a21).withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ป้ายสถานะ Capsule Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.04),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF57C00),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'สถานะ: ออฟไลน์ (ยังไม่เริ่มงาน)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A605B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'พร้อมเริ่มให้บริการรถรับส่ง',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E2923),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'กดปุ่มด้านล่างเพื่อเริ่มแชร์ตำแหน่ง GPS และรับคำขอจากนักศึกษา',
              style: TextStyle(
                color: Color(0xFF718076),
                fontSize: 12.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _startShift,
                borderRadius: BorderRadius.circular(24),
                child: Ink(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF176a21).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'เริ่มงาน (Online)',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusMarker(String? status, String? shuttleNumber) {
    Color statusColor = const Color(0xFF176a21); // Default available
    if (status == 'full') {
      statusColor = const Color(0xFF757778); // Grey
    } else if (status == 'break') {
      statusColor = const Color(0xFFF28522); // Orange
    } else if (status == 'offline') {
      statusColor = Colors.red; // Red
    }

    String displayNum = shuttleNumber ?? '';
    displayNum = displayNum
        .replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '')
        .trim();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // วงกลมไอคอนรถบัส
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        // ป้ายเบอร์รถ
        if (displayNum.isNotEmpty)
          Positioned(
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21).withOpacity(0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 1.0),
              ),
              child: Text(
                displayNum,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStopMarker({
    required String name,
    required bool isPickupSelected,
    required bool isDropoffSelected,
    int dropoffCount = 0,
    bool isGroup = false,
  }) {
    final bool isHighlighted = isPickupSelected || isDropoffSelected;

    String cleanName = name
        .replaceAll('(ขาเข้า)', '')
        .replaceAll('(ขาออก)', '')
        .trim();

    Color pinBgColor = Colors.white;
    Color pinBorderColor = isGroup
        ? const Color(0xFF176a21)
        : const Color(0xFF66BB6A);
    Color pinIconColor = isGroup
        ? const Color(0xFF176a21)
        : const Color(0xFF436B49);
    Color labelBgColor = Colors.white;
    Color labelTextColor = const Color(0xFF1E2923);
    Color labelBorderColor = const Color(0xFF176a21).withValues(alpha: 0.20);
    IconData iconData = Icons.hail_rounded;

    if (isDropoffSelected) {
      pinBgColor = const Color(0xFF176a21);
      pinBorderColor = Colors.white;
      pinIconColor = Colors.white;
      labelBgColor = const Color(0xFF176a21);
      labelTextColor = Colors.white;
      labelBorderColor = Colors.white;
      iconData = Icons.location_on_rounded;
    } else if (isPickupSelected) {
      pinBgColor = const Color(0xFFF57C00);
      pinBorderColor = Colors.white;
      pinIconColor = Colors.white;
      labelBgColor = const Color(0xFFF57C00);
      labelTextColor = Colors.white;
      labelBorderColor = Colors.white;
      iconData = Icons.hail_rounded;
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // หมุดไอคอนจุดจอด
        Container(
          width: isHighlighted ? 34 : 28,
          height: isHighlighted ? 34 : 28,
          decoration: BoxDecoration(
            color: pinBgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: pinBorderColor,
              width: isHighlighted ? 2.5 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDropoffSelected
                    ? const Color(0xFF176a21).withValues(alpha: 0.40)
                    : (isPickupSelected
                          ? const Color(0xFFF57C00).withValues(alpha: 0.40)
                          : const Color(0xFF176a21).withValues(alpha: 0.18)),
                blurRadius: isHighlighted ? 10 : 6,
                spreadRadius: isHighlighted ? 1 : 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            iconData,
            color: pinIconColor,
            size: isHighlighted ? 18 : 15,
          ),
        ),

        // ป้ายแสดงจำนวนคนลงรถ (ถ้ามีนักศึกษาระบุลงป้ายนี้)
        if (isDropoffSelected && dropoffCount > 0)
          Positioned(
            top: -24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF176a21).withValues(alpha: 0.30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_pin_circle_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'ลง $dropoffCount คน',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ป้ายชื่อจุดจอดรถ
        Positioned(
          bottom: isHighlighted ? 38 : 32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: labelBgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: labelBorderColor,
                width: isHighlighted ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isHighlighted
                      ? (isDropoffSelected
                            ? const Color(0xFF176a21).withValues(alpha: 0.25)
                            : const Color(0xFFF57C00).withValues(alpha: 0.25))
                      : Colors.black.withValues(alpha: 0.10),
                  blurRadius: isHighlighted ? 8 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              cleanName,
              style: TextStyle(
                fontSize: isHighlighted ? 11 : 10,
                fontWeight: FontWeight.bold,
                color: labelTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  // ดีไซน์หมุดตำแหน่งรถคนขับให้ดูเด่นชัดและ Real-time พร้อมแสดงสีตามสถานะ
  Widget _buildMyBusMarker() {
    Color statusColor = const Color(0xFF176a21); // Default (ว่าง)
    if (_currentPassengerStatus == 'full') {
      statusColor = const Color(0xFF757778); // เต็ม (สีเทา)
    } else if (_currentPassengerStatus == 'break') {
      statusColor = const Color(0xFFF28522); // พัก (สีส้ม)
    } else if (_currentPassengerStatus == 'offline') {
      statusColor = Colors.red; // เลิกงาน (สีแดง)
    }

    String displayNum = _shuttleNumber ?? '';
    displayNum = displayNum
        .replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '')
        .trim();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(isOnline ? 0.6 : 0.2),
                blurRadius: isOnline ? 12 : 4,
                spreadRadius: isOnline ? 4 : 0,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isOnline ? statusColor : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        if (displayNum.isNotEmpty)
          Positioned(
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21).withOpacity(0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 1.0),
              ),
              child: Text(
                displayNum,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// CustomPainter สำหรับวาด Bottom Navigation Bar โค้งเว้า (Curved Notch) ขอบมนสวยงามพอดี (Radius = 16px)
class _CurvedNavPainter extends CustomPainter {
  final double notchCenter;

  _CurvedNavPainter({required this.notchCenter});

  @override
  void paint(Canvas canvas, Size size) {
    const double barTop = 16.0;
    const double notchDepth = 25.0;
    const double notchHalfWidth = 34.0;
    const double radius = 16.0; // ปรับลดความโค้งขอบมนซ้าย-ขวาลงมาที่ 16px ตามที่ต้องการ

    // 1. สร้าง Base Path สี่เหลี่ยมขอบมนโค้งมนสวยกระชับ
    final RRect barRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, size.height - barTop),
      const Radius.circular(radius),
    );

    // 2. สร้าง Path รอยบากโค้งเว้า นุ่มนวล
    final Path notchPath = Path();
    notchPath.moveTo(notchCenter - notchHalfWidth, barTop);
    notchPath.cubicTo(
      notchCenter - 20,
      barTop,
      notchCenter - 22,
      barTop + notchDepth,
      notchCenter,
      barTop + notchDepth,
    );
    notchPath.cubicTo(
      notchCenter + 22,
      barTop + notchDepth,
      notchCenter + 20,
      barTop,
      notchCenter + notchHalfWidth,
      barTop,
    );
    notchPath.lineTo(notchCenter + notchHalfWidth, 0);
    notchPath.lineTo(notchCenter - notchHalfWidth, 0);
    notchPath.close();

    // 3. ผสานตัดรอยบากออกจากตัวบาร์อย่างนุ่มนวล
    final Path finalPath = Path.combine(
      PathOperation.difference,
      Path()..addRRect(barRRect),
      notchPath,
    );

    // 4. วาดเงามิติ 2 ชั้น (เงาสีเขียวมรกตบางๆ + เงา Depth นุ่มนวล)
    canvas.drawShadow(
      finalPath,
      const Color(0xFF176a21).withValues(alpha: 0.08),
      16.0,
      true,
    );
    canvas.drawShadow(
      finalPath,
      Colors.black.withValues(alpha: 0.08),
      10.0,
      true,
    );

    // 5. วาดพื้นหลังไล่เฉดสีขาวไข่มุก (Soft Pearl Gradient) สวยพรีเมียม
    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF9FBF9),
        ],
      ).createShader(Rect.fromLTWH(0, barTop, size.width, size.height - barTop));
    canvas.drawPath(finalPath, fillPaint);

    // 6. วาดเส้นขอบบางประณีต (Subtle Hairline Accent Border)
    final Paint borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(finalPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedNavPainter oldDelegate) {
    return oldDelegate.notchCenter != notchCenter;
  }
}

