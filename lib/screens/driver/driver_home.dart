import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // ✨ สำหรับเช็ค kIsWeb
import 'package:flutter/services.dart'; // ✨ สำหรับ HapticFeedback
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:flutter_tts/flutter_tts.dart'; // ✨ สำหรับเสียง AI พูดภาษาไทย
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart'; // ✨ สำหรับเล่นเสียงแจ้งเตือนมือถือ
import 'package:audioplayers/audioplayers.dart'; // ✨ สำหรับเล่นไฟล์เสียง MP3 จุดจอด
import '../../route_data.dart';
import 'driver_profile.dart'; // ✨ Import หน้าโปรไฟล์คนขับรถ
import 'driver_status_screen.dart'; // ✨ Import หน้าสถานะรถ
import 'driver_chat_screen.dart'; // ✨ Import หน้าแชทคนขับรถ

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with TickerProviderStateMixin {
  int _selectedIndex = 0; // ✨ เพิ่มตัวแปรสำหรับ BottomNavigationBar
  bool isOnline = false;
  bool _isAutoFollow = true; // ✨ หน้าจอขยับตามตำแหน่งรถอัตโนมัติ

  LatLng? _currentLocation;
  LatLng? _oldLocation;
  LatLng? _targetLocation;
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  late FlutterTts flutterTts; // ✨ ตัวอ่านเสียง AI ภาษาไทย
  StreamSubscription<Position>? positionStream;
  StreamSubscription<QuerySnapshot>? requestStream;
  StreamSubscription<DocumentSnapshot>?
  myShuttleSubscription; // ✨ ฟังสถานะตัวเอง
  Timer?
  _heartbeatTimer; // ✨ Heartbeat สำหรับอัปเดตเวลาให้สดใหม่อยู่เสมอตอนจอดรอรับส่ง
  String _currentPassengerStatus = 'available';

  final MapController _mapController = MapController();

  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  final LatLngBounds _psruBounds = LatLngBounds(
    const LatLng(16.81500, 100.19000),
    const LatLng(16.84500, 100.23000),
  );

  List<Map<String, dynamic>> busStops = [];

  String? waitingStudentStop;
  List<String> activeRequestIds = []; // ✨ เก็บไอดีคำขอทั้งหมดในป้ายที่กำลังรอ
  int activeStudentCount = 0; // ✨ จำนวนนักศึกษาที่รออยู่ป้ายนั้น
  String?
  currentRequestStatus; // ✨ เก็บสถานะการเรียก ('waiting' หรือ 'acknowledged')

  // ✨ เก็บตำแหน่งของนักศึกษาที่เรียกรถทั้งหมด
  List<Map<String, dynamic>> waitingStudentsList = [];

  // ✨ ตัวแปรสำหรับเก็บข้อมูลรถคันอื่นๆ ที่กำลังออนไลน์
  List<Map<String, dynamic>> activeShuttles = [];
  StreamSubscription<QuerySnapshot>? allShuttlesSubscription;
  Map<String, LatLng> _otherCurrentLocations = {};
  Map<String, LatLng> _otherOldLocations = {};
  Map<String, LatLng> _otherTargetLocations = {};

  // ✨ ตัวแปรสำหรับเก็บข้อมูลรถรับส่งของคนขับคนนี้
  String? _shuttleDocId;
  String? _shuttleName;
  String? _shuttleNumber;

  // ✨ ตัวแปรจำกัดเวลาส่งข้อมูล (Throttling 3 วินาที) และพิกัดล่าสุด (Distance Check 5 เมตร) เพื่อประหยัดโควตาและแบตเตอรี่
  DateTime? _lastFirebaseUpdate;
  LatLng? _lastUploadedLocation;

  @override
  void initState() {
    super.initState();
    _initTts(); // ✨ เตรียมระบบอ่านข้อความ AI ภาษาไทย

    // ✨ Setup animation controller for smooth marker movement (900ms ให้หมุดเคลื่อนที่ต่อเนื่องเมื่อรถวิ่ง 20-30 กม./ชม.)
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

              // ✨ ขยับกล้องแผนที่ให้ตามตัวรถอัตโนมัติเมื่อเปิดโหมด Auto-Follow อยู่
              if (_isAutoFollow && _currentLocation != null) {
                _mapController.move(
                  _currentLocation!,
                  _mapController.camera.zoom,
                );
              }
            }

            // ✨ อัปเดตพิกัดรถคันอื่นๆ แบบสมูท
            for (var id in _otherTargetLocations.keys) {
              final oldLoc = _otherOldLocations[id];
              final targetLoc = _otherTargetLocations[id];
              if (oldLoc != null && targetLoc != null) {
                final lat =
                    oldLoc.latitude +
                    (targetLoc.latitude - oldLoc.latitude) *
                        _markerAnimation.value;
                final lng =
                    oldLoc.longitude +
                    (targetLoc.longitude - oldLoc.longitude) *
                        _markerAnimation.value;
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
    _fetchDriverShuttle(); // ✨ ดึงข้อมูลรถของคนขับ
  }

  // ✨ ฟังก์ชันสำหรับหาว่าคนขับคนนี้ รับผิดชอบรถคันไหน
  Future<void> _fetchDriverShuttle() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _shuttleName = userDoc.data()?['shuttle_name'];
        _shuttleNumber = userDoc.data()?['shuttle_number']?.toString();

        if (_shuttleName != null) {
          final shuttleQuery = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: _shuttleName)
              .limit(1)
              .get();

          String? docId;
          if (shuttleQuery.docs.isNotEmpty) {
            docId = shuttleQuery.docs.first.id;
          } else {
            // ลองค้นหาตาม number
            final numQuery = await FirebaseFirestore.instance
                .collection('shuttles')
                .where(
                  'number',
                  isEqualTo: userDoc.data()?['shuttle_number'] ?? '',
                )
                .limit(1)
                .get();
            if (numQuery.docs.isNotEmpty) {
              docId = numQuery.docs.first.id;
            } else {
              // สร้างรถคันใหม่ในระบบ
              final newDoc = await FirebaseFirestore.instance
                  .collection('shuttles')
                  .add({
                    'name': _shuttleName,
                    'number': userDoc.data()?['shuttle_number'] ?? '1',
                    'status': 'offline',
                    'lat': 16.82753,
                    'lng': 100.20686,
                  });
              docId = newDoc.id;
            }
          }

          if (docId != null) {
            setState(() {
              _shuttleDocId = docId;
            });

            // ✨ บันทึกชื่อและรูป Avatar คนขับลงในเอกสารรถเพื่อให้หน้านักศึกษาดึงไปแสดงผล
            final driverName = userDoc.data()?['name'] ?? 'คนขับรถประจำคัน';
            final driverAvatar =
                userDoc.data()?['avatar'] ?? 'assets/images/man1.png';
            FirebaseFirestore.instance.collection('shuttles').doc(docId).set({
              'driver_name': driverName,
              'driver_avatar': driverAvatar,
              'driver_uid': user.uid,
            }, SetOptions(merge: true));

            // ✨ เริ่มฟังเอกสารรถคันนี้ เพื่อคอยอัปเดตสถานะแบบ Real-time ให้สีหมุดเปลี่ยนตาม
            myShuttleSubscription = FirebaseFirestore.instance
                .collection('shuttles')
                .doc(docId)
                .snapshots()
                .handleError((e) => print("Firestore Error (shuttles doc): $e"))
                .listen((doc) {
                  if (doc.exists && mounted) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data.containsKey('passenger_status')) {
                      setState(() {
                        _currentPassengerStatus = data['passenger_status'];
                      });
                    }
                  }
                });
          }
        }
      }

      // ✨ เริ่มฟังสัญญาณรถทุกคัน เพื่อนำมาแสดงจุดบนแผนที่ให้คนขับเห็นกันเอง
      _listenToAllShuttles();
    } catch (e) {
      print("Error fetching driver shuttle: $e");
    }
  }

  // ✨ ฟังก์ชันฟังสัญญาณรถทุกคันที่กำลังออนไลน์ (เพื่อนำมาแสดงจุดบนแผนที่ให้คนขับเห็นกันเอง)
  void _listenToAllShuttles() {
    allShuttlesSubscription = FirebaseFirestore.instance
        .collection('shuttles')
        .where('status', isEqualTo: 'online')
        .snapshots()
        .handleError((e) => print("Firestore Error (all shuttles): $e"))
        .listen((snapshot) {
          if (mounted) {
            bool shouldAnimate = false;
            final now = DateTime.now();
            final validDocs = snapshot.docs.where((doc) {
              final data = doc.data();
              if (data.containsKey('last_updated') &&
                  data['last_updated'] != null) {
                final lastUpdated = (data['last_updated'] as Timestamp)
                    .toDate();
                // ถ้ารถอัปเดตล่าสุดภายใน 2 นาที ถือว่ายังออนไลน์อยู่จริงๆ
                return now.difference(lastUpdated).inMinutes <= 2;
              }
              return false;
            }).toList();

            final newShuttles = validDocs
                .map(
                  (doc) => {
                    'id': doc.id,
                    'number': doc.data().containsKey('number')
                        ? doc['number']
                        : null,
                    'lat': (doc['lat'] as num).toDouble(),
                    'lng': (doc['lng'] as num).toDouble(),
                    'passenger_status':
                        doc.data().containsKey('passenger_status')
                        ? doc['passenger_status']
                        : 'available', // ✨ เพิ่มการดึงสถานะ
                  },
                )
                .where(
                  (shuttle) => shuttle['id'] != _shuttleDocId,
                ) // ไม่เอาหมุดของตัวเองมาซ้ำ
                .toList();

            for (var shuttle in newShuttles) {
              final String id = shuttle['id'];
              final LatLng newLoc = LatLng(shuttle['lat'], shuttle['lng']);
              final currentLoc = _otherCurrentLocations[id];
              if (currentLoc != null && currentLoc != newLoc) {
                _otherOldLocations[id] = currentLoc;
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
              _markerAnimationController.forward(from: 0.0);
            }
          }
        });
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
        loadedStops.add({
          'id': doc.id,
          'stop_id': data['stop_id'] ?? doc.id,
          'name': data['name'] ?? 'จุดจอด',
          'lat': (data['lat'] as num).toDouble(),
          'lng': (data['lng'] as num).toDouble(),
        });
      }

      if (mounted) {
        setState(() {
          busStops = loadedStops;
        });
      }
    } catch (e) {
      print("❌ Error loading stops: $e");
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    _heartbeatTimer?.cancel();
    _markerAnimationController.dispose();
    positionStream?.cancel();
    requestStream?.cancel();
    myShuttleSubscription?.cancel();
    allShuttlesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    if (_shuttleDocId != null) {
      FirebaseFirestore.instance
          .collection('shuttles')
          .doc(_shuttleDocId)
          .set({'status': 'offline'}, SetOptions(merge: true))
          .catchError((e) => print(e));
    }
    myShuttleSubscription?.cancel();

    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // ✨ เตรียมการทำงานของเสียง AI ภาษาไทย
  Future<void> _initTts() async {
    try {
      flutterTts = FlutterTts();

      // ✨ ตรวจสอบว่าระบบรองรับรหัสภาษาไทยแบบใด (บางระบบใช้ th-TH บางระบบใช้ th)
      dynamic isThThAvailable = await flutterTts.isLanguageAvailable("th-TH");
      dynamic isThAvailable = await flutterTts.isLanguageAvailable("th");

      if (isThThAvailable == true || isThThAvailable == 1) {
        await flutterTts.setLanguage("th-TH");
      } else if (isThAvailable == true || isThAvailable == 1) {
        await flutterTts.setLanguage("th");
      } else {
        await flutterTts.setLanguage("th-TH"); // ลองตั้งค่าเริ่มต้นไว้
      }

      if (!kIsWeb) {
        await flutterTts.setSpeechRate(0.5); // ความเร็วปกติ
        // ✨ คงเสียงเดิมไว้ (เสียงผู้หญิง) และปรับระดับเสียงให้ดังสุด (1.0 คือสูงสุดของระบบ TTS)
        // หากต้องการดังกว่านี้ ต้องเพิ่มเสียง Media ของตัวเครื่องมือถือครับ
        await flutterTts.setVolume(1.0); 
        await flutterTts.setPitch(1.0);
      }
    } catch (e) {
      print("❌ Error initializing TTS: $e");
    }
  }

  // ✨ ตัวแปรสำหรับจัดการเสียงแจ้งเตือนแบบหน่วงเวลา
  DateTime? _lastVoiceAlertTime;
  String? _lastVoiceAlertStopName;
  Timer? _ttsDebounceTimer;

  // ✨ ฟังก์ชันเล่นเสียงแจ้งเตือนและอ่านชื่อป้าย
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
        HapticFeedback.heavyImpact();
        final AudioPlayer chatPlayer = AudioPlayer();
        await chatPlayer.play(AssetSource('voice/glass_1.mp3'));
      } catch (_) {}
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
        await flutterTts.speak(textToSpeak);
      } catch (e) {
        print("❌ Error triggering TTS: $e");
      }
    });
  }

  Future<void> _startShift() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ กรุณาเปิด GPS ในอุปกรณ์ของคุณ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ สิทธิ์การเข้าถึงตำแหน่งถูกปฏิเสธ'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ สิทธิ์การเข้าถึงตำแหน่งถูกบล็อก กรุณาเปิดสิทธิ์ในตั้งค่า',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    final fallbackLoc = const LatLng(
      16.829708,
      100.20716,
    ); // หอประชุมศรีวชิรโชติ

    // 🌟 แสดงตำแหน่งไอคอนเริ่มต้นบนแผนที่ทันที เพื่อป้องกันอาการค้างหรือรอโหลด GPS (Instant UX)
    _lastFirebaseUpdate = null;
    _lastUploadedLocation = null;
    setState(() {
      isOnline = true;
      _isAutoFollow = true; // ✨ เปิดติดตามตำแหน่งรถอัตโนมัติเมื่อเริ่มงาน
      _currentLocation = fallbackLoc;
      _targetLocation = fallbackLoc;
    });
    _mapController.move(fallbackLoc, 16.5);

    try {
      // 1. ดึงพิกัดล่าสุดในแคชเครื่องก่อน (Last Known Position) มักจะได้ผลทันทีโดยไม่ต้องรอสัญญาณดาวเทียม
      Position? lastPos = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager:
            Theme.of(context).platform == TargetPlatform.android,
      );
      if (lastPos != null) {
        LatLng lastLoc = _snapToRoute(
          LatLng(lastPos.latitude, lastPos.longitude),
        );
        print(
          "📍 GPS Last Known: ${lastPos.latitude}, ${lastPos.longitude} -> Snapped: ${lastLoc.latitude}, ${lastLoc.longitude}",
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
        "📍 GPS Initialized: ${initialPos.latitude}, ${initialPos.longitude} -> Snapped: ${newLoc.latitude}, ${newLoc.longitude}",
      );

      if (mounted) {
        setState(() {
          _currentLocation = newLoc;
          _targetLocation = newLoc;
        });

        // เช็คว่าพิกัดอยู่ในเขตมหาลัยหรือไม่
        if (_psruBounds.contains(newLoc)) {
          _mapController.move(newLoc, 16.5);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ ตำแหน่ง GPS ของคุณอยู่นอกพื้นที่มหาวิทยาลัย'),
            ),
          );
        }

        if (_shuttleDocId != null) {
          _lastFirebaseUpdate = DateTime.now();
          _lastUploadedLocation = newLoc;
          FirebaseFirestore.instance
              .collection('shuttles')
              .doc(_shuttleDocId)
              .set({
                'lat': newLoc.latitude,
                'lng': newLoc.longitude,
                'status': 'online',
                'last_updated': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      print("❌ Error getting initial location (Using Fallback): $e");
      // หาก _currentLocation ยังเป็นค่าเริ่มต้นอยู่ (หอประชุมฯ) หรือดึงพิกัดล่าสุดสำเร็จแล้วก็ให้ค้างค่านั้นไว้
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ดึงพิกัดจริงล่าช้า ($e) ระบบใช้พิกัดที่มีล่าสุด'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        if (_shuttleDocId != null && _currentLocation != null) {
          _lastFirebaseUpdate = DateTime.now();
          _lastUploadedLocation = _currentLocation;
          FirebaseFirestore.instance
              .collection('shuttles')
              .doc(_shuttleDocId)
              .set({
                'lat': _currentLocation!.latitude,
                'lng': _currentLocation!.longitude,
                'status': 'online',
                'last_updated': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      }
    }

    // ✨ ตั้งค่า distanceFilter เป็น 2 เมตร และอัปเดตทุก 800ms เพื่อรองรับรถวิ่งความเร็ว 20-30 กม./ชม.
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

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!mounted) return;

            LatLng rawLoc = LatLng(position.latitude, position.longitude);
            LatLng newLoc = _snapToRoute(rawLoc);
            print(
              "📍 GPS Updated: ${position.latitude}, ${position.longitude} -> Snapped: ${newLoc.latitude}, ${newLoc.longitude}",
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
              _oldLocation = _currentLocation;
              _targetLocation = newLoc;
              _markerAnimationController.forward(from: 0.0);
            }

            // ✨ Smart Throttling & Distance Check: ส่งข้อมูลขึ้น Firestore ต่อเมื่อรถขยับไปอย่างน้อย 3 เมตร และเว้นระยะเวลาอย่างน้อย 1.2 วินาที (พอดีกับความเร็ว 20-30 กม./ชม.)
            final now = DateTime.now();
            final double distanceMoved = _lastUploadedLocation == null
                ? 999.0
                : const Distance().distance(_lastUploadedLocation!, newLoc);

            if (_shuttleDocId != null &&
                distanceMoved >= 3.0 &&
                (_lastFirebaseUpdate == null ||
                    now.difference(_lastFirebaseUpdate!).inMilliseconds >=
                        3000)) {
              _lastFirebaseUpdate = now;
              _lastUploadedLocation = newLoc;
              FirebaseFirestore.instance
                  .collection('shuttles')
                  .doc(_shuttleDocId)
                  .set({
                    'lat': newLoc.latitude,
                    'lng': newLoc.longitude,
                    'status': 'online',
                    'last_updated': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
            }
          },
          onError: (error) {
            print("❌ GPS Stream Error: $error");
          },
        );

    requestStream = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', whereIn: ['waiting', 'acknowledged'])
        .snapshots()
        .handleError((e) => print("Firestore Error (ride_requests): $e"))
        .listen((snapshot) {
          if (!mounted) return;

          if (snapshot.docs.isNotEmpty) {
            // ✨ กรองเอาเฉพาะคำขอที่เจาะจงเรียกรถคันนี้เท่านั้น (หรือคำขอที่ไม่ได้ระบุเป้าหมายเพื่อให้รองรับระบบเดิม)
            final validDocs = snapshot.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (data.containsKey('target_shuttle_id') && data['target_shuttle_id'] != null) {
                return data['target_shuttle_id'] == _shuttleDocId;
              }
              return true; // ถ้าระบบเก่าไม่มี target_shuttle_id ให้มองว่าเรียกได้ทุกคน
            }).toList();

            // ✨ เรียงลำดับคำขอตามเวลา (เก่าสุดขึ้นก่อน - เข้าคิวก่อนได้ก่อน FIFO)
            final docs = validDocs;
            docs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['timestamp'] as Timestamp?;
              final bTime = bData['timestamp'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return aTime.compareTo(bTime); // ascending (เก่าสุดมาก่อน)
            });

            // ✨ ดึงตำแหน่งนักศึกษาทั้งหมดที่รอหรือกำลังรอรถ
            final List<Map<String, dynamic>> students = [];
            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data.containsKey('student_lat') &&
                  data.containsKey('student_lng')) {
                students.add({
                  'id': doc.id,
                  'lat': (data['student_lat'] as num).toDouble(),
                  'lng': (data['student_lng'] as num).toDouble(),
                  'status': data['status'],
                });
              }
            }

            // ✨ ค้นหาคำขอที่มีสถานะ 'waiting' เพื่อเป็นป้ายหลัก (active)
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

              // ✨ ตรวจสอบว่ามี id ไหนที่เพิ่งเข้ามาใหม่หรือไม่
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
                waitingStudentsList = students;
                waitingStudentStop = targetStop;
                activeRequestIds = targetIds;
                activeStudentCount = targetIds.length;
                currentRequestStatus = 'waiting';
              });
            } else {
              // ถ้าไม่มีคำขอ waiting เลย (อาจจะ acknowledged หมดแล้ว)
              setState(() {
                waitingStudentsList = students;
                waitingStudentStop = null;
                activeRequestIds = [];
                activeStudentCount = 0;
                currentRequestStatus = null;
              });
            }
          } else {
            setState(() {
              waitingStudentsList = [];
              waitingStudentStop = null;
              activeRequestIds = [];
              activeStudentCount = 0;
              currentRequestStatus = null;
            });
          }
        });

    // ✨ เริ่ม Heartbeat ทุกๆ 30 วินาที เพื่ออัปเดตเวลาล่าสุดและ "เลี้ยงการเชื่อมต่อเน็ตไม่ให้หลับ"
    // พอเน็ตไม่หลับ เวลามีคนเรียกรถ มันจะเด้งขึ้นหน้าจอทันที ไม่ต้องรอหน่วง! (30 วิ ช่วยประหยัดโควต้ากว่า 15 วิ)
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isOnline || _shuttleDocId == null) {
        timer.cancel();
        return;
      }
      _lastFirebaseUpdate = DateTime.now();
      FirebaseFirestore.instance.collection('shuttles').doc(_shuttleDocId).set({
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      FirebaseFirestore.instance
          .collection('shuttles')
          .doc(_shuttleDocId)
          .set({'status': 'offline'}, SetOptions(merge: true))
          .catchError((e) => print(e));
    }
  }

  Future<void> _acknowledgeRequest() async {
    if (activeRequestIds.isNotEmpty) {
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

      if (mounted) {
        setState(() {
          activeRequestIds = [];
          activeStudentCount = 0;
          currentRequestStatus = 'acknowledged';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F2),
      body: Stack(
        children: [
          // 📌 IndexedStack สลับหน้าจอตาม Bottom Navigation
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildMapScreen(), // หน้าแผนที่ (หน้า 0)
              const DriverStatusScreen(), // ✨ หน้าสถานะรถ (หน้า 1)
              DriverChatScreen(
                shuttleDocId: _shuttleDocId,
                shuttleName: _shuttleName,
              ), // ✨ หน้าแชทคนขับรถ (หน้า 2)
              const DriverProfileScreen(), // ✨ หน้าโปรไฟล์คนขับรถ (หน้า 3)
            ],
          ),

          // ✨ Bottom Navigation Bar สไตล์ Curved Notch โมเดิร์นเหมือนฝั่งนักศึกษา
          Positioned(
            bottom: MediaQuery.of(context).size.width > 800 ? 20 : 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _buildCurvedBottomNav(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✨ แยกส่วนแผนที่ออกมาเป็นฟังก์ชัน
  Widget _buildMapScreen() {
    return Stack(
      children: [
        // 🗺️ แผนที่หลัก
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _psruCenter,
              initialZoom: 15.5,
              minZoom: 14.5,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(bounds: _psruBounds),
              interactionOptions: InteractionOptions(
                flags:
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
                cursorKeyboardRotationOptions:
                    CursorKeyboardRotationOptions.disabled(), // ✨ ปิดการหมุนด้วยคีย์บอร์ด/เมาส์บน Web
              ),
              // ✨ ตรวจจับเมื่อคนขับใช้นิ้วเลื่อนหรือแตะแผนที่ด้วยตัวเอง ให้ปิด Auto-Follow อัตโนมัติ
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

              // ✨ แสดงเส้นทางเสมอ แต่ให้สีจางลงตอนออฟไลน์
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
                  // ✨ แสดงป้ายจอดพร้อมชื่อป้ายเหมือนฝั่งนักศึกษา
                  ...busStops.map((stop) {
                    bool isSelected = waitingStudentStop == stop['name'];
                    return Marker(
                      key: ValueKey('stop_${stop['name']}'),
                      point: LatLng(stop['lat'], stop['lng']),
                      width: isSelected ? 150 : 130,
                      height: isSelected ? 75 : 65,
                      child: RepaintBoundary(
                        child: _buildStopMarker(
                          isSelected: isSelected,
                          name: stop['name'] ?? '',
                        ),
                      ),
                    );
                  }),

                  // ✨ แสดงตำแหน่งรถคันอื่นๆ ที่กำลังออนไลน์ (เพื่อให้คนขับเห็นกันเอง)
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
                  // ✨ แสดงตำแหน่งของนักศึกษาที่เรียกรถ
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
                  // ✨ แสดงตำแหน่งรถตัวเอง
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

        // 📍 ปุ่ม My Location (เป้าเล็งรถตัวเอง และเปิด/ปิด Auto-Follow)
        if (isOnline && _currentLocation != null)
          Positioned(
            bottom:
                (waitingStudentStop != null &&
                    currentRequestStatus == 'waiting')
                ? 190
                : 100, // ปรับตำแหน่งให้พ้นการ์ดแจ้งเตือน
            right: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: _isAutoFollow
                  ? const Color(0xFF176a21)
                  : Colors.white,
              elevation: 4,
              onPressed: () {
                setState(() {
                  _isAutoFollow = true; // ✨ เปิดติดตามตำแหน่งรถอัตโนมัติ
                });
                _mapController.move(_currentLocation!, 16.5);
              },
              child: Icon(
                _isAutoFollow ? Icons.my_location : Icons.location_searching,
                color: _isAutoFollow ? Colors.white : const Color(0xFF176a21),
              ),
            ),
          ),

        // 🚍 แถบด้านบน
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset(
                      'lib/screens/driver/logo.png',
                      height: 42,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Row(
                          children: [
                            Icon(
                              Icons.directions_bus,
                              color: Color(0xFF176a21),
                              size: 28,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'PSRU Shuttle',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF176a21),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (isOnline)
                      GestureDetector(
                        onTap: _stopTracking,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Text(
                            'เลิกงาน',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(
                          Icons.logout,
                          color: Color(0xFF595C5D),
                          size: 26,
                        ),
                        onPressed: _logout,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 🟢 สถานะออนไลน์/ออฟไลน์
        Positioned(
          top: 140,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF176a21) : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: isOnline
                        ? [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.5),
                              blurRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isOnline
                      ? 'ออนไลน์ (กำลังวิ่งรถ)'
                      : 'ออฟไลน์ (ยังไม่เริ่มงาน)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF595C5D),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 🛑 หน้าต่างออฟไลน์ (แสดงเป็นการ์ดลอยด้านล่างเมื่อยังไม่เริ่มงาน)
        if (!isOnline)
          Positioned(
            bottom: 95,
            left: 0,
            right: 0,
            child: _buildOfflineSheet(),
          ),

        // 🧑‍🎓 การแจ้งเตือนเวลามีนักศึกษาเรียก (Popup ด้านล่าง)
        if (isOnline &&
            waitingStudentStop != null &&
            currentRequestStatus == 'waiting')
          Positioned(
            bottom: 95,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF176a21).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
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
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          waitingStudentStop!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (activeStudentCount > 1)
                          Text(
                            '(จำนวน $activeStudentCount คน)',
                            style: const TextStyle(
                              color: Color(0xFF9DF197),
                              fontSize: 14,
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
                            color: Colors.black.withOpacity(0.15),
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
      ],
    );
  }

  // ✨ วิดเจ็ต Bottom Navigation Bar ดีไซน์โค้งเว้าพร้อมปุ่มวงกลมลอยเหมือนฝั่งนักศึกษา
  Widget _buildCurvedBottomNav() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map_outlined, 'activeIcon': Icons.map, 'label': 'แผนที่'},
      {
        'icon': Icons.directions_bus_outlined,
        'activeIcon': Icons.directions_bus,
        'label': 'สถานะรถ',
      },
      {
        'icon': Icons.chat_bubble_outline,
        'activeIcon': Icons.chat_bubble,
        'label': 'แชท',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'โปรไฟล์',
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double itemWidth = width / navItems.length;
        final double targetX = itemWidth * _selectedIndex + itemWidth / 2;

        // เช็คว่าหน้าจอโดยรวมกว้างกว่า 800 หรือไม่ (iPad/Desktop)
        final bool isDesktop = MediaQuery.of(context).size.width > 800;

        return SizedBox(
          height: 85,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // พื้นหลังบาร์สีขาวพร้อมรอยบาก (Curved Notch)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: targetX, end: targetX),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (context, animatedX, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(width, 85),
                        painter: _CurvedNavPainter(
                          notchCenter: animatedX,
                          isDesktop: isDesktop,
                        ),
                      ),
                      // ปุ่มวงกลมสีเขียวลอยในรอยบาก
                      Positioned(
                        top: 2,
                        left: animatedX - 24,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF176a21),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF176a21,
                                ).withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            navItems[_selectedIndex]['activeIcon'],
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // รายการปุ่มกดแต่ละ Tab
              Positioned(
                top: 18,
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
                              Icon(
                                navItems[index]['icon'],
                                color: const Color(0xFF757778),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF757778),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 28),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C2F30).withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'ออฟไลน์ (ยังไม่เริ่มงาน)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF595C5D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'ระบบกำลังรอการเชื่อมต่อเพื่อเริ่มติดตามตำแหน่งรถ',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _startShift,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9DF197), Color(0xFF176a21)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF176a21).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'เริ่มงาน (Online)',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildStopMarker({required bool isSelected, required String name}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ป้ายชื่อจุดจอดรถ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF176a21) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white : const Color(0xFF176a21),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: isSelected ? 11 : 10,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : const Color(0xFF2C2F30),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 3),
        // หมุดไอคอนจุดจอด
        Container(
          width: isSelected ? 34 : 28,
          height: isSelected ? 34 : 28,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF176a21) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : const Color(0xFF757778),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.3 : 0.1),
                blurRadius: isSelected ? 6 : 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.hail,
            color: isSelected ? Colors.white : const Color(0xFF757778),
            size: isSelected ? 18 : 15,
          ),
        ),
      ],
    );
  }

  // ✨ ดีไซน์หมุดตำแหน่งรถคนขับให้ดูเด่นชัดและ Real-time พร้อมแสดงสีตามสถานะ
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

// ✨ CustomPainter สำหรับวาด Bottom Navigation Bar โค้งเว้า (Curved Notch) ตามสไตล์โมเดิร์น
class _CurvedNavPainter extends CustomPainter {
  final double notchCenter;
  final bool isDesktop;

  _CurvedNavPainter({required this.notchCenter, this.isDesktop = false});

  @override
  void paint(Canvas canvas, Size size) {
    const double barTop = 18.0;
    const double notchDepth = 30.0;
    const double notchHalfWidth = 42.0;

    // ถ้าเป็นหน้าจอใหญ่ ให้มีขอบมน (radius = 30) ไม่งั้นให้ขอบตรง (radius = 0)
    double radius = isDesktop ? 30.0 : 0.0;

    Path path = Path();
    path.moveTo(radius, barTop);

    if (notchCenter - notchHalfWidth > radius) {
      path.lineTo(notchCenter - notchHalfWidth, barTop);
    } else {
      path.lineTo(notchCenter - notchHalfWidth, barTop);
    }

    // โค้งลงไปในรอยบาก (Left curve)
    path.cubicTo(
      notchCenter - 22,
      barTop,
      notchCenter - 26,
      barTop + notchDepth,
      notchCenter,
      barTop + notchDepth,
    );

    // โค้งขึ้นจากรอยบาก (Right curve)
    path.cubicTo(
      notchCenter + 26,
      barTop + notchDepth,
      notchCenter + 22,
      barTop,
      notchCenter + notchHalfWidth,
      barTop,
    );

    path.lineTo(size.width - radius, barTop);

    if (radius > 0) {
      // มุมขวาบน
      path.arcToPoint(
        Offset(size.width, barTop + radius),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      // เส้นลงมามุมขวาล่าง
      path.lineTo(size.width, size.height - radius);
      // มุมขวาล่าง
      path.arcToPoint(
        Offset(size.width - radius, size.height),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      // เส้นไปมุมซ้ายล่าง
      path.lineTo(radius, size.height);
      // มุมซ้ายล่าง
      path.arcToPoint(
        Offset(0, size.height - radius),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      // เส้นไปมุมซ้ายบน
      path.lineTo(0, barTop + radius);
      // มุมซ้ายบน
      path.arcToPoint(
        Offset(radius, barTop),
        radius: Radius.circular(radius),
        clockwise: true,
      );
    } else {
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    path.close();

    // วาดเงาให้บาร์ด้านล่าง
    canvas.drawShadow(path, Colors.black.withOpacity(0.08), 15.0, true);

    // วาดพื้นหลังสีขาว
    Paint paint = Paint()..color = Colors.white;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvedNavPainter oldDelegate) {
    return oldDelegate.notchCenter != notchCenter ||
        oldDelegate.isDesktop != isDesktop;
  }
}
