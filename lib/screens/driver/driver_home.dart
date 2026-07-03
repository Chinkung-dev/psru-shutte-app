import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  LatLng? _currentLocation;
  LatLng? _oldLocation;
  LatLng? _targetLocation;
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  StreamSubscription<Position>? positionStream;
  StreamSubscription<QuerySnapshot>? requestStream;
  StreamSubscription<DocumentSnapshot>?
  myShuttleSubscription; // ✨ ฟังสถานะตัวเอง
  Timer? _heartbeatTimer; // ✨ Heartbeat สำหรับอัปเดตเวลาให้สดใหม่อยู่เสมอตอนจอดรอรับส่ง
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

  // ✨ ตัวแปรสำหรับเก็บข้อมูลรถรับส่งของคนขับคนนี้
  String? _shuttleDocId;
  String? _shuttleName;

  // ✨ ตัวแปรจำกัดเวลาส่งข้อมูลขึ้น Firebase (Throttling) ทุกๆ 3 วินาที เพื่อประหยัดโควตาและแบตเตอรี่
  DateTime? _lastFirebaseUpdate;

  @override
  void initState() {
    super.initState();

    // ✨ Setup animation controller for smooth marker movement
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 400,
      ), // ปรับให้สั้นลงเป็น 400ms เพื่อให้หมุดตอบสนองและขยับถี่ขึ้น
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
                .where('number', isEqualTo: userDoc.data()?['shuttle_number'] ?? '')
                .limit(1)
                .get();
            if (numQuery.docs.isNotEmpty) {
              docId = numQuery.docs.first.id;
            } else {
              // สร้างรถคันใหม่ในระบบ
              final newDoc = await FirebaseFirestore.instance.collection('shuttles').add({
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
            final driverAvatar = userDoc.data()?['avatar'] ?? 'assets/images/man1.png';
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
            '⚠️ สิทธิ์การเข้าถึงตำแหน่งถูกบล็อกถาวร กรุณาเปิดสิทธิ์ในตั้งค่า',
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
    setState(() {
      isOnline = true;
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

    // ✨ ตั้งค่า distanceFilter เป็น 3 เมตร เพื่อลดการทำงานเมื่อจอดนิ่ง (ติดไฟแดง/จอดรับนักศึกษา)
    // และตั้งค่า intervalDuration ให้เหมาะสมเพื่อประหยัดแบตเตอรี่
    late final LocationSettings locationSettings;
    if (Theme.of(context).platform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: true,
        intervalDuration: const Duration(
          milliseconds: 1000,
        ), // อัปเดตพิกัด GPS ทุกๆ 1 วินาที
      );
    } else if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
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
            } else {
              _oldLocation = _currentLocation;
              _targetLocation = newLoc;
              _markerAnimationController.forward(from: 0.0);
            }

            // ✨ Throttling: ยิงอัปเดตขึ้น Firebase Firestore ทุกๆ 1 วินาที (เพื่อให้หน้าแอปนักศึกษาตอบสนองเร็วและสมูตที่สุด)
            final now = DateTime.now();
            if (_shuttleDocId != null &&
                (_lastFirebaseUpdate == null ||
                    now.difference(_lastFirebaseUpdate!).inSeconds >= 1)) {
              _lastFirebaseUpdate = now;
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
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;

          if (snapshot.docs.isNotEmpty) {
            setState(() {
              waitingStudentStop = snapshot.docs.first['stop_name'];
              currentRequestId = snapshot.docs.first.id;
            });
          } else {
            setState(() {
              waitingStudentStop = null;
            });
          }
        });

    // ✨ เริ่ม Heartbeat ทุกๆ 30 วินาที เพื่อให้อัปเดตเวลาล่าสุด (last_updated) ตอนรถจอดรอที่ป้าย
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isOnline || _shuttleDocId == null) {
        timer.cancel();
        return;
      }
      FirebaseFirestore.instance
          .collection('shuttles')
          .doc(_shuttleDocId)
          .set({
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });
  }

  void _stopTracking() {
    _heartbeatTimer?.cancel();
    positionStream?.cancel();
    requestStream?.cancel();

    if (mounted) {
      setState(() {
        isOnline = false;
        _currentLocation = null; // ซ่อนหมุดตำแหน่งรถตอนออฟไลน์
        _targetLocation = null;
        _oldLocation = null;
        waitingStudentStop = null;
        currentRequestId = null;
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
              DriverChatScreen(shuttleDocId: _shuttleDocId, shuttleName: _shuttleName), // ✨ หน้าแชทคนขับรถ (หน้า 2)
              const DriverProfileScreen(), // ✨ หน้าโปรไฟล์คนขับรถ (หน้า 3)
            ],
          ),

          // 📱 เมนูด้านล่างสุด
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: isOnline ? _buildBottomNav() : _buildOfflineSheet(),
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
                  // ✨ แสดงป้ายจอดเสมอ
                  ...busStops.map((stop) {
                    bool isSelected = waitingStudentStop == stop['name'];
                    return Marker(
                      point: LatLng(stop['lat'], stop['lng']),
                      width: isSelected ? 50 : 40,
                      height: isSelected ? 50 : 40,
                      child: _buildStopMarker(isSelected: isSelected),
                    );
                  }),
                  // ✨ แสดงตำแหน่งรถตัวเอง
                  if (isOnline && _currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 45,
                      height: 45,
                      child: _buildMyBusMarker(),
                    ),
                ],
              ),
            ],
          ),
        ),

        // 📍 ปุ่ม My Location (เป้าเล็งรถตัวเอง)
        if (isOnline && _currentLocation != null)
          Positioned(
            bottom: 110, // ปรับตำแหน่งให้พ้น Sheet
            right: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () {
                _mapController.move(_currentLocation!, 16.5);
              },
              child: const Icon(Icons.my_location, color: Color(0xFF176a21)),
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
                    const Row(
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
          top: 120,
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

        // 🧑‍🎓 การแจ้งเตือนเวลามีนักศึกษาเรียก (Popup ด้านล่าง)
        if (isOnline && waitingStudentStop != null)
          Positioned(
            bottom: 125,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
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
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          waitingStudentStop!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
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
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'รับทราบ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.map, 'แผนที่', 0),
            _buildNavItem(Icons.directions_bus_outlined, 'สถานะรถ', 1),
            _buildNavItem(Icons.chat_bubble_outline, 'แชท', 2),
            _buildNavItem(Icons.person_outline, 'โปรไฟล์', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineSheet() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
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
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _startShift,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF81C784), Color(0xFF388E3C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
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
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: isActive
            ? BoxDecoration(
                color: const Color(0xFF9DF197).withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFF176a21)
                  : const Color(0xFF757778),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive
                    ? const Color(0xFF176a21)
                    : const Color(0xFF757778),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopMarker({required bool isSelected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF176a21) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : const Color(0xFF757778),
          width: isSelected ? 3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.3 : 0.1),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.hail,
        color: isSelected ? Colors.white : const Color(0xFF757778),
        size: isSelected ? 24 : 18,
      ),
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
