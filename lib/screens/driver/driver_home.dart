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

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  int _selectedIndex = 0; // ✨ เพิ่มตัวแปรสำหรับ BottomNavigationBar
  bool isOnline = false;
  
  LatLng? _currentLocation;
  StreamSubscription<Position>? positionStream;
  StreamSubscription<QuerySnapshot>? requestStream;

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

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase(); 
    _fetchDriverShuttle(); // ✨ ดึงข้อมูลรถของคนขับ
  }

  // ✨ ฟังก์ชันสำหรับหาว่าคนขับคนนี้ รับผิดชอบรถคันไหน
  Future<void> _fetchDriverShuttle() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        _shuttleName = userDoc.data()?['shuttle_name'];

        if (_shuttleName != null) {
          final shuttleQuery = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: _shuttleName)
              .limit(1)
              .get();
              
          if (shuttleQuery.docs.isNotEmpty) {
            setState(() {
              _shuttleDocId = shuttleQuery.docs.first.id;
            });
          }
        }
      }
    } catch (e) {
      print("Error fetching driver shuttle: $e");
    }
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('stops').get();
      
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
    positionStream?.cancel();
    requestStream?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    // ✨ เปลี่ยนจาก buses เป็น shuttles
    if (_shuttleDocId != null) {
      FirebaseFirestore.instance.collection('shuttles').doc(_shuttleDocId).set({
        'status': 'offline',
      }, SetOptions(merge: true)).catchError((e) => print(e));
    }

    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _startShift() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเปิด GPS ในมือถือ')));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    if (!mounted) return;

    setState(() {
      isOnline = true;
    });

    // อัปเดตตำแหน่งทุกๆ 5 เมตร
    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    
    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (!mounted) return; 
      
      LatLng newLoc = LatLng(position.latitude, position.longitude);
      
      // ให้แผนที่เลื่อนไปหาจุดแรกที่เจอตอนเริ่มงานเท่านั้น จะได้ไม่กระตุกเวลาคนขับเลื่อนดูแผนที่เอง
      if (_currentLocation == null && _psruBounds.contains(newLoc)) {
        _mapController.move(newLoc, 16.5);
      }

      setState(() => _currentLocation = newLoc);

      // ✨ อัปเดตพิกัดไปที่ shuttles แทน buses
      if (_shuttleDocId != null) {
        FirebaseFirestore.instance.collection('shuttles').doc(_shuttleDocId).set({
          'lat': position.latitude,
          'lng': position.longitude,
          'status': 'online',
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

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
          currentRequestId = null;
        });
      }
    });
  }

  void _stopTracking() {
    positionStream?.cancel();
    requestStream?.cancel();
    
    if (mounted) {
      setState(() {
        isOnline = false;
        _currentLocation = null;
        waitingStudentStop = null;
        currentRequestId = null;
      });
    }
    
    // ✨ เปลี่ยนจาก buses เป็น shuttles
    if (_shuttleDocId != null) {
      FirebaseFirestore.instance.collection('shuttles').doc(_shuttleDocId).set({
        'status': 'offline',
      }, SetOptions(merge: true)).catchError((e) => print(e));
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
              const Center(child: Text("หน้าแชท (กำลังพัฒนา)")), // หน้า 2
              const DriverProfileScreen(), // ✨ หน้าโปรไฟล์คนขับรถ (หน้า 3)
            ],
          ),

          // 📱 เมนูด้านล่างสุด
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: isOnline 
                ? _buildBottomNav() 
                : _buildOfflineSheet(), 
          )
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

              if (isOnline)
                PolylineLayer(
                  polylines: shuttleRoutes.map((segment) {
                    return Polyline(
                      points: segment, 
                      strokeWidth: 5.0, 
                      color: const Color(0xFF176a21).withOpacity(0.3),
                    );
                  }).toList(),
                ),

              if (isOnline)
                MarkerLayer(
                  markers: [
                    ...busStops.map((stop) {
                      bool isSelected = waitingStudentStop == stop['name'];
                      return Marker(
                        point: LatLng(stop['lat'], stop['lng']), 
                        width: isSelected ? 50 : 40, height: isSelected ? 50 : 40,
                        child: _buildStopMarker(isSelected: isSelected),
                      );
                    }),
                    if (_currentLocation != null)
                      Marker(
                        point: _currentLocation!,
                        width: 45, height: 45,
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
            bottom: 110, // ให้อยู่เหนือ BottomNav หรือแจ้งเตือน
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
          top: 0, left: 0, right: 0,
          child: Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.directions_bus, color: Color(0xFF176a21), size: 28),
                        SizedBox(width: 10),
                        Text('PSRU Shuttle', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF176a21))),
                      ],
                    ),
                    if (isOnline)
                      GestureDetector(
                        onTap: _stopTracking,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(15)),
                          child: const Text('เลิกงาน', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.logout, color: Color(0xFF595C5D), size: 26),
                        onPressed: _logout,
                      )
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF176a21) : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: isOnline ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 4)] : [],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isOnline ? 'ออนไลน์ (กำลังวิ่งรถ)' : 'ออฟไลน์ (ยังไม่เริ่มงาน)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF595C5D)),
                ),
              ],
            ),
          ),
        ),

        // 🧑‍🎓 การแจ้งเตือนเวลามีนักศึกษาเรียก (Popup ด้านล่าง)
        if (isOnline && waitingStudentStop != null)
          Positioned(
            bottom: 90, 
            left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21), 
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))]
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Color(0xFF9DF197), shape: BoxShape.circle),
                    child: const Icon(Icons.front_hand, color: Color(0xFF176a21), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('มีนักศึกษารออยู่ที่:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(waitingStudentStop!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _acknowledgeRequest, 
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                      child: const Text('รับทราบ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  )
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5))]
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                const Text('ออฟไลน์ (ยังไม่เริ่มงาน)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF595C5D))),
              ],
            ),
            const SizedBox(height: 8),
            const Text('ระบบกำลังรอการเชื่อมต่อเพื่อเริ่มติดตามตำแหน่งรถ', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _startShift,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF81C784), Color(0xFF388E3C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Text('เริ่มงาน (Online)', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
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
        decoration: isActive ? BoxDecoration(color: const Color(0xFF9DF197).withOpacity(0.3), borderRadius: BorderRadius.circular(16)) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? const Color(0xFF176a21) : const Color(0xFF757778)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.bold : FontWeight.w600, color: isActive ? const Color(0xFF176a21) : const Color(0xFF757778))),
          ],
        ),
      ),
    );
  }

  Widget _buildStopMarker({required bool isSelected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200), 
      decoration: BoxDecoration(color: isSelected ? const Color(0xFF176a21) : Colors.white, shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.white : const Color(0xFF757778), width: isSelected ? 3 : 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isSelected ? 0.3 : 0.1), blurRadius: isSelected ? 8 : 4, offset: const Offset(0, 2))]), 
      child: Icon(Icons.hail, color: isSelected ? Colors.white : const Color(0xFF757778), size: isSelected ? 24 : 18),
    );
  }

  // ดีไซน์หมุดตำแหน่งรถคนขับ
  Widget _buildMyBusMarker() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]), 
      padding: const EdgeInsets.all(4), 
      child: Container(decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle), child: const Icon(Icons.directions_bus, color: Colors.white, size: 20)),
    );
  }
}
