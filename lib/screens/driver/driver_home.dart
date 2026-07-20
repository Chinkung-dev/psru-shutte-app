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
  String? currentRequestId;
  String?
  currentRequestStatus; // ✨ เก็บสถานะการเรียก ('waiting' หรือ 'acknowledged')

  // ✨ ตัวแปรสำหรับเก็บข้อมูลรถรับส่งของคนขับคนนี้
  String? _shuttleDocId;
  String? _shuttleName;

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
          if (_oldLocation != null && _targetLocation != null && mounted) {
            final lat =
                _oldLocation!.latitude +
                (_targetLocation!.latitude - _oldLocation!.latitude) *
                    _markerAnimation.value;
            final lng =
                _oldLocation!.longitude +
                (_targetLocation!.longitude - _oldLocation!.longitude) *
                    _markerAnimation.value;
            setState(() {
              _currentLocation = LatLng(lat, lng);
            });
            // ✨ ขยับกล้องแผนที่ให้ตามตัวรถอัตโนมัติเมื่อเปิดโหมด Auto-Follow อยู่
            if (_isAutoFollow && _currentLocation != null) {
              _mapController.move(
                _currentLocation!,
                _mapController.camera.zoom,
              );
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
    } catch (e) {
      print("Error fetching driver shuttle: $e");
    }
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

      await flutterTts.setSpeechRate(0.5); // ความเร็วพอเหมาะฟังง่าย
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
    } catch (e) {
      print("❌ Error initializing TTS: $e");
    }
  }

  // ✨ ฟังก์ชันเล่นเสียงแจ้งเตือนและไฟล์เสียงจุดจอด (.mp3) ตาม stop_id
  Future<void> _triggerVoiceAlert(String stopName) async {
    try {
      // 1. สั่นเตือนแรงๆ + เล่นเสียงแจ้งเตือนแบบเคาะแก้ว (Glass Ting)
      try {
        HapticFeedback.heavyImpact();
        final AudioPlayer chatPlayer = AudioPlayer();
        await chatPlayer.play(AssetSource('voice/glass_1.mp3'));
        // รอให้เสียงแจ้งเตือนจบก่อน (กันค้างด้วยการตั้งเวลาไว้ 2 วินาที)
        await chatPlayer.onPlayerComplete.first.timeout(
          const Duration(seconds: 1),
        );
      } catch (_) {}

      if (!mounted || !isOnline) return;

      // 2. หา stop_id จากชื่อป้ายที่ส่งเข้ามา (เช่น "อาคาร IT" -> "stop_01")
      String? stopId;
      for (var stop in busStops) {
        if (stop['name'] == stopName ||
            stop['stop_id'] == stopName ||
            stop['id'] == stopName) {
          stopId = stop['stop_id'] ?? stop['id'];
          break;
        }
      }

      // 3. เปิดเล่นไฟล์เสียงจาก Assets ใน assets/voice/
      if (stopId != null) {
        final AudioPlayer audioPlayer = AudioPlayer();
        await audioPlayer.play(AssetSource('voice/voice_$stopId.mp3'));
      } else {
        print("⚠️ ไม่พบ stop_id สำหรับป้าย '$stopName' ในรายการ busStops");
      }
    } catch (e) {
      print("❌ Error triggering voice alert: $e");
    }
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
        .listen((snapshot) {
          if (!mounted) return;

          if (snapshot.docs.isNotEmpty) {
            // ✨ ค้นหาคำขอที่มีสถานะ 'waiting' ก่อนเป็นอันดับแรก เพื่อให้ปุ่ม "รับทราบ" ขึ้นเสมอเมื่อมีคนเรียกรถใหม่
            QueryDocumentSnapshot activeDoc = snapshot.docs.first;
            for (var doc in snapshot.docs) {
              if (doc['status'] == 'waiting') {
                activeDoc = doc;
                break;
              }
            }

            // ✨ หากมีคำขอใหม่ที่มีสถานะ 'waiting' ให้ส่งเสียงเตือนและเสียง AI พูดชื่อจุดจอดรถ
            if (activeDoc['status'] == 'waiting' &&
                currentRequestId != activeDoc.id) {
              _triggerVoiceAlert(activeDoc['stop_name'] ?? 'จุดจอดรถ');
            }

            setState(() {
              waitingStudentStop = activeDoc['stop_name'];
              currentRequestId = activeDoc.id;
              currentRequestStatus = activeDoc['status'];
            });
          } else {
            setState(() {
              waitingStudentStop = null;
              currentRequestId = null;
              currentRequestStatus = null;
            });
          }
        });

    // ✨ เริ่ม Heartbeat ทุกๆ 60 วินาที เพื่อให้อัปเดตเวลาล่าสุด (last_updated) ตอนรถจอดรอที่ป้าย ไม่ให้ระบบตัดเป็นออฟไลน์
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
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
        currentRequestId = null;
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
    if (currentRequestId != null) {
      await FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(currentRequestId)
          .update({'status': 'acknowledged'});
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
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildCurvedBottomNav(),
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
                  // ✨ แสดงตำแหน่งรถตัวเอง
                  if (isOnline && _currentLocation != null)
                    Marker(
                      key: const ValueKey('my_bus_marker'),
                      point: _currentLocation!,
                      width: 45,
                      height: 45,
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
                        painter: _CurvedNavPainter(notchCenter: animatedX),
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

    return Container(
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
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: isOnline ? statusColor : Colors.grey,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.directions_bus, color: Colors.white, size: 20),
      ),
    );
  }
}

// ✨ CustomPainter สำหรับวาด Bottom Navigation Bar โค้งเว้า (Curved Notch) ตามสไตล์โมเดิร์น
class _CurvedNavPainter extends CustomPainter {
  final double notchCenter;

  _CurvedNavPainter({required this.notchCenter});

  @override
  void paint(Canvas canvas, Size size) {
    const double barTop = 18.0;
    const double notchDepth = 30.0;
    const double notchHalfWidth = 42.0;

    Path path = Path();
    path.moveTo(0, barTop);

    if (notchCenter - notchHalfWidth > 0) {
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

    path.lineTo(size.width, barTop);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // วาดเงาให้บาร์ด้านล่าง
    canvas.drawShadow(path, Colors.black.withOpacity(0.08), 15.0, true);

    // วาดพื้นหลังสีขาว
    Paint paint = Paint()..color = Colors.white;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvedNavPainter oldDelegate) {
    return oldDelegate.notchCenter != notchCenter;
  }
}
