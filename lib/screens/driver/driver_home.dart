import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart'; 
import '../../route_data.dart'; 

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
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

  List<Marker> _busStopMarkers = [];

  String? waitingStudentStop; 
  String? currentRequestId;

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase(); 
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('stops').get();
      
      List<Marker> newMarkers = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        newMarkers.add(
          Marker(
            point: LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()), 
            width: 35,
            height: 35,
            child: _buildBusStopMarker(),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _busStopMarkers = newMarkers;
        });
      }
    } catch (e) {
      print("❌ Error loading stops: $e");
    }
  }

  // ✨ แก้ไข 1: ใน dispose ให้ปิดแค่ Stream ห้ามเรียก setState เด็ดขาด
  @override
  void dispose() {
    positionStream?.cancel();
    requestStream?.cancel();
    super.dispose();
  }

  // ✨ แก้ไข 2: ตอน Logout ให้อัปเดตฐานข้อมูลเป็น offline แล้วเด้งออกเลย
  Future<void> _logout() async {
    // แจ้งฐานข้อมูลว่ารถคันนี้ออฟไลน์แล้ว
    FirebaseFirestore.instance.collection('buses').doc('bus_A').update({
      'status': 'offline',
    }).catchError((e) => print(e));

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

    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    
    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (!mounted) return; 
      
      LatLng newLoc = LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = newLoc);

      if (_psruBounds.contains(newLoc)) {
        _mapController.move(newLoc, 17.0);
      }

      FirebaseFirestore.instance.collection('buses').doc('bus_A').set({
        'name': 'รถรับส่ง สาย A',
        'lat': position.latitude,
        'lng': position.longitude,
        'status': 'online',
        'last_updated': FieldValue.serverTimestamp(),
      });
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

  // ✨ ฟังก์ชันนี้จะถูกเรียกเฉพาะตอนกดปุ่ม "เลิกงาน" เท่านั้น (ไม่ถูกเรียกตอน Logout แล้ว)
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
    
    FirebaseFirestore.instance.collection('buses').doc('bus_A').update({
      'status': 'offline',
    }).catchError((e) => print(e));
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
                      return Polyline(points: segment, strokeWidth: 5.0, color: Colors.lightGreen);
                    }).toList(),
                  ),

                if (isOnline)
                  MarkerLayer(
                    markers: [
                      ..._busStopMarkers,
                      if (_currentLocation != null)
                        Marker(
                          point: _currentLocation!,
                          width: 50, height: 50,
                          child: _buildMyBusMarker(),
                        ),
                    ],
                  ),
              ],
            ),
          ),

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

          Positioned(
            top: 100, 
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'ออนไลน์ (วิ่งให้บริการ)' : 'ออฟไลน์ (ยังไม่เริ่มงาน)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF595C5D)),
                  ),
                ],
              ),
            ),
          ),

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
                      child: const Icon(Icons.location_on, color: Color(0xFF176a21), size: 24),
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
            _buildNavItem(Icons.map, 'แผนที่', true),
            _buildNavItem(Icons.directions_bus_outlined, 'สถานะรถ', false),
            _buildNavItem(Icons.chat_bubble_outline, 'แชท', false),
            _buildNavItem(Icons.person_outline, 'โปรไฟล์', false),
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

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Container(
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
    );
  }

  Widget _buildBusStopMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF757778), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
      ),
      child: const Icon(Icons.hail, color: Color(0xFF757778), size: 18),
    );
  }

  Widget _buildMyBusMarker() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle),
        child: const Icon(Icons.directions_bus, color: Colors.white, size: 24),
      ),
    );
  }
}