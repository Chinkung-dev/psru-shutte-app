import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../route_data.dart';
import 'student_profile.dart';
import 'student_chat_list_screen.dart'; // ✨ Import หน้ารวมห้องแชท
import 'student_live_status_screen.dart'; // ✨ Import หน้า Live Status
import 'package:geolocator/geolocator.dart'; // ✨ เพิ่มเพื่อดึงตำแหน่งผู้ใช้

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  final Map<String, LatLng> _oldShuttleLocations = {};
  final Map<String, LatLng> _targetShuttleLocations = {};
  final Map<String, LatLng> _currentShuttleLocations = {};

  bool isWaiting = false;
  bool isAcknowledged = false; // ✨ เพิ่มสถานะเมื่อคนขับกดรับทราบแล้ว
  bool isCardMinimized = false; // ✨ ย่อการ์ดเหลือแค่ปุ่มเมื่อกดที่แผนที่
  String? selectedStopName;
  LatLng? selectedStopLatLng; // ✨ เก็บพิกัดป้ายที่เลือก
  String? estimatedArrivalText; // ✨ ข้อความแสดงเวลา ETA
  String? targetedShuttleId; // ✨ เก็บ ID ของรถคันที่ใกล้ที่สุดเพื่อส่งคำขอเจาะจง
  LatLng? _myLocation; // ✨ ตำแหน่งปัจจุบันของนักศึกษา

  final MapController _mapController = MapController();

  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  final LatLngBounds _psruBounds = LatLngBounds(
    const LatLng(16.81500, 100.19000),
    const LatLng(16.84500, 100.23000),
  );

  List<Map<String, dynamic>> activeShuttles =
      []; // ✨ เก็บรายการรถที่กำลังออนไลน์

  List<Map<String, dynamic>> busStops = [];
  bool _isLoadingStops = true;

  String? activeRequestId;
  StreamSubscription<DocumentSnapshot>? requestSubscription;
  StreamSubscription<DocumentSnapshot>? userSubscription;
  StreamSubscription<QuerySnapshot>?
  shuttleSubscription; // ✨ เพิ่ม Subscription สำหรับฟังตำแหน่งรถ

  List<LatLng> highlightedPath = [];
  final Map<LatLng, List<LatLng>> _routeGraph = {};

  List<String> favoriteStops = [];
  bool _isAutoFollow = true; // ✨ ตัวแปรเช็คว่ากล้องติดตามเป้าหมายอยู่หรือไม่

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase();
    _listenToFavoriteStops();
    _buildRouteGraph();
    _listenToShuttles(); // ✨ เริ่มฟังตำแหน่งรถ
    _zoomToUserLocation(); // ✨ ดึงตำแหน่งผู้ใช้และซูมแผนที่

    // ✨ Setup animation controller for smooth marker movement (1200ms สอดคล้องกับการอัปเดตจากรถคนขับทุก 1.2 วินาทีเพื่อให้ลื่นไหลสุดๆ)
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _markerAnimation =
        CurvedAnimation(
          parent: _markerAnimationController,
          curve: Curves.easeInOut,
        )..addListener(() {
          if (mounted) {
            setState(() {
              for (var id in _targetShuttleLocations.keys) {
                final oldLoc = _oldShuttleLocations[id];
                final targetLoc = _targetShuttleLocations[id];
                if (oldLoc != null && targetLoc != null) {
                  final lat =
                      oldLoc.latitude +
                      (targetLoc.latitude - oldLoc.latitude) *
                          _markerAnimation.value;
                  final lng =
                      oldLoc.longitude +
                      (targetLoc.longitude - oldLoc.longitude) *
                          _markerAnimation.value;
                  _currentShuttleLocations[id] = LatLng(lat, lng);
                } else if (targetLoc != null) {
                  _currentShuttleLocations[id] = targetLoc;
                }
              }
            });
          }
        });
  }

  // ✨ ดึงตำแหน่งปัจจุบันของนักศึกษาแล้วซูมแผนที่ไป
  Future<void> _zoomToUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));
          
      if (mounted) {
        final loc = LatLng(position.latitude, position.longitude);
        setState(() {
          _myLocation = loc;
        });
        _mapController.move(loc, 17.0);
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  // ✨ ฟังก์ชันฟังตำแหน่งรถแบบ Real-time พร้อมอนิเมชันหมุดให้ราบรื่นและกรองรถค้าง (Timeout Filter)
  void _listenToShuttles() {
    shuttleSubscription = FirebaseFirestore.instance
        .collection('shuttles')
        .where('status', isEqualTo: 'online')
        .snapshots()
        .handleError((e) => print("Firestore Error (shuttles): $e"))
        .listen((snapshot) {
          if (mounted) {
            bool shouldAnimate = false;
            final now = DateTime.now();

            final validDocs = snapshot.docs.where((doc) {
              final data = doc.data();
              if (data.containsKey('last_updated') &&
                  data['last_updated'] != null) {
                final Timestamp? lastUpdated =
                    data['last_updated'] as Timestamp?;
                if (lastUpdated != null &&
                    now.difference(lastUpdated.toDate()).inMinutes >= 3) {
                  return false; // รถไม่อัปเดตเกิน 3 นาที ถือว่าปิดแอปหรือออฟไลน์ไปแล้ว
                }
                return true;
              }
              return false; // ไม่มี timestamp ถือว่าเป็นข้อมูลเก่าค้างระบบ
            }).toList();

            final newShuttles = validDocs
                .map(
                  (doc) => {
                    'id': doc.id,
                    'lat': (doc['lat'] as num).toDouble(),
                    'lng': (doc['lng'] as num).toDouble(),
                    'passenger_status':
                        doc.data().containsKey('passenger_status')
                        ? doc['passenger_status']
                        : 'available',
                    'number': doc.data().containsKey('number') ? doc['number'] : '',
                  },
                )
                .toList();

            bool hasMeaningfulChange =
                false; // ✨ ตรวจสอบว่ามีรถคันไหนขยับจริงหรือเปลี่ยนสถานะที่นั่งหรือไม่

            for (var shuttle in newShuttles) {
              final String id = shuttle['id'];
              final LatLng newLoc = LatLng(shuttle['lat'], shuttle['lng']);
              final String newPassengerStatus = shuttle['passenger_status'];
              final currentLoc = _currentShuttleLocations[id];

              // เช็คว่าสถานะผู้โดยสารเปลี่ยนหรือไม่
              bool statusChanged = true;
              for (var oldS in activeShuttles) {
                if (oldS['id'] == id &&
                    oldS['passenger_status'] == newPassengerStatus) {
                  statusChanged = false;
                  break;
                }
              }
              if (statusChanged) {
                hasMeaningfulChange = true;
              }

              if (currentLoc == null) {
                _currentShuttleLocations[id] = newLoc;
                _targetShuttleLocations[id] = newLoc;
                hasMeaningfulChange = true;
              } else if (currentLoc.latitude != newLoc.latitude ||
                  currentLoc.longitude != newLoc.longitude) {
                _oldShuttleLocations[id] = currentLoc;
                _targetShuttleLocations[id] = newLoc;
                shouldAnimate = true;
                hasMeaningfulChange = true;
              }
            }

            final activeIds = newShuttles.map((s) => s['id'] as String).toSet();
            if (activeIds.length != activeShuttles.length) {
              hasMeaningfulChange = true;
            }

            _currentShuttleLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _oldShuttleLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _targetShuttleLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );

            // ✨ State Guard: อัปเดต UI และคำนวณกราฟเส้นทางใหม่เฉพาะเมื่อรถขยับจริง หรือสถานะเปลี่ยนเท่านั้น (เพื่อประหยัดแบตเตอรี่และไม่รีบิ้วฟรีเมื่อได้รับ Heartbeat)
            if (hasMeaningfulChange) {
              setState(() {
                activeShuttles = newShuttles;
              });

              if (shouldAnimate) {
                _markerAnimationController.forward(from: 0.0);
              }

              // ถ้านักศึกษาเลือกป้ายไว้ ให้ทำการอัปเดตเส้นทางและเวลา ETA (ไม่ว่ารถจะออนไลน์หรือเพิ่งออฟไลน์ไป)
              if (selectedStopLatLng != null) {
                _updateRouteAndETA();
              }
            }
          }
        });
  }

  void _listenToFavoriteStops() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .handleError((e) => print("Firestore Error (users): $e"))
          .listen((doc) {
            if (doc.exists && doc.data()!.containsKey('favorite_stops')) {
              if (mounted) {
                setState(() {
                  favoriteStops = List<String>.from(
                    doc.data()!['favorite_stops'],
                  );
                });
              }
            }
          });
    }
  }

  Future<void> _toggleFavorite(String stopName) async {
    setState(() {
      if (favoriteStops.contains(stopName)) {
        favoriteStops.remove(stopName);
      } else {
        favoriteStops.add(stopName);
      }
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'favorite_stops': favoriteStops},
      );
    }
  }

  // ---------------------------------------------------------
  // ระบบคำนวณเส้นทาง (Graph & Pathfinding)
  // ---------------------------------------------------------
  void _buildRouteGraph() {
    const distanceCalc = Distance();
    for (var segment in shuttleRoutes) {
      for (int i = 0; i < segment.length - 1; i++) {
        final p1 = segment[i];
        final p2 = segment[i + 1];
        _routeGraph.putIfAbsent(p1, () => []).add(p2);
        _routeGraph.putIfAbsent(p2, () => []).add(p1);
      }
    }

    List<LatLng> allNodes = _routeGraph.keys.toList();
    for (int i = 0; i < allNodes.length; i++) {
      for (int j = i + 1; j < allNodes.length; j++) {
        if (distanceCalc.distance(allNodes[i], allNodes[j]) <= 20.0) {
          if (!_routeGraph[allNodes[i]]!.contains(allNodes[j])) {
            _routeGraph[allNodes[i]]!.add(allNodes[j]);
            _routeGraph[allNodes[j]]!.add(allNodes[i]);
          }
        }
      }
    }
  }

  LatLng? _getClosestNode(LatLng target) {
    if (_routeGraph.isEmpty) return null;
    LatLng? closest;
    double minDistance = double.infinity;
    const distanceCalc = Distance();

    for (var node in _routeGraph.keys) {
      double dist = distanceCalc.distance(target, node);
      if (dist < minDistance) {
        minDistance = dist;
        closest = node;
      }
    }
    return closest;
  }

  void _calculateHighlightedPath(LatLng startLoc, LatLng endLoc) {
    LatLng? startNode = _getClosestNode(startLoc);
    LatLng? endNode = _getClosestNode(endLoc);

    if (startNode == null || endNode == null) {
      setState(() => highlightedPath.clear());
      return;
    }

    Set<LatLng> unvisited = Set.from(_routeGraph.keys);
    Map<LatLng, double> distances = {};
    Map<LatLng, LatLng> previous = {};
    const distanceCalc = Distance();

    for (var node in _routeGraph.keys) {
      distances[node] = double.infinity;
    }
    distances[startNode] = 0;

    while (unvisited.isNotEmpty) {
      LatLng? current;
      double minDist = double.infinity;
      for (var node in unvisited) {
        if (distances[node]! < minDist) {
          minDist = distances[node]!;
          current = node;
        }
      }

      if (current == null || current == endNode) break;
      unvisited.remove(current);

      for (var neighbor in _routeGraph[current] ?? []) {
        if (!unvisited.contains(neighbor)) continue;
        double alt =
            distances[current]! + distanceCalc.distance(current, neighbor);
        if (alt < distances[neighbor]!) {
          distances[neighbor] = alt;
          previous[neighbor] = current;
        }
      }
    }

    List<LatLng> path = [];
    LatLng? curr = endNode;
    if (previous.containsKey(curr) || curr == startNode) {
      while (curr != null) {
        path.insert(0, curr);
        curr = previous[curr];
      }
    }

    if (path.isNotEmpty) {
      path.insert(0, startLoc);
      path.add(endLoc);
    }

    // ✨ คำนวณระยะทางรวมตามถนนจริงเป็นเมตร
    double totalMeters = 0;
    if (distances[endNode] != null && distances[endNode] != double.infinity) {
      totalMeters =
          distanceCalc.distance(startLoc, startNode) +
          distances[endNode]! +
          distanceCalc.distance(endNode, endLoc);
    } else {
      totalMeters = distanceCalc.distance(startLoc, endLoc);
    }

    String eta;
    double speed =
        7.0; // ~25.2 กม./ชม. (ความเร็วเฉลี่ย 20-30 กม./ชม. รวมชะลอทางแยก/รับส่ง)
    double sec =
        (totalMeters / speed) + 15.0; // เผื่อเวลาชะลอทางแยก/รับส่ง 15 วินาที

    if (totalMeters <= 30) {
      eta = "รถกำลังจะถึงป้าย";
    } else if (sec <= 60) {
      eta = "ประมาณ 1 นาที (${totalMeters.round()} ม.)";
    } else {
      int mins = (sec / 60).ceil();
      eta = "ประมาณ $mins นาที (${totalMeters.round()} ม.)";
    }

    setState(() {
      highlightedPath = path;
      estimatedArrivalText = eta;
    });
  }

  // ✨ หาพิกัดกึ่งกลางของเส้นทางไฮไลท์สำหรับแสดงป้ายข้อความเวลา ETA บนแผนที่
  LatLng? _getPathMidpoint() {
    if (highlightedPath.isEmpty) return null;
    if (highlightedPath.length == 1) return highlightedPath.first;
    int midIndex = highlightedPath.length ~/ 2;
    if (highlightedPath.length == 2) {
      return LatLng(
        (highlightedPath[0].latitude + highlightedPath[1].latitude) / 2,
        (highlightedPath[0].longitude + highlightedPath[1].longitude) / 2,
      );
    }
    return highlightedPath[midIndex];
  }

  // ✨ วิดเจ็ตข้อความแสดงเวลาประมาณการ (ETA) ข้างเส้นทางไฮไลท์บนแผนที่ (เหลือแค่ไอคอนและตัวหนังสือ)
  Widget _buildRouteEtaBadge(String etaText) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer, color: Color(0xFF176a21), size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            etaText,
            style: const TextStyle(
              color: Color(0xFF176a21),
              fontSize: 13.0,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, 0),
                ),
                Shadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
          'name': data['name'],
          'lat': (data['lat'] as num).toDouble(),
          'lng': (data['lng'] as num).toDouble(),
        });
      }

      if (mounted) {
        setState(() {
          busStops = loadedStops;
          _isLoadingStops = false;
        });
      }
    } catch (e) {
      print("Error loading stops: $e");
      if (mounted) setState(() => _isLoadingStops = false);
    }
  }

  @override
  void dispose() {
    _markerAnimationController.dispose();
    requestSubscription?.cancel();
    userSubscription?.cancel();
    shuttleSubscription?.cancel(); // ✨ ยกเลิกฟังตำแหน่งรถ
    super.dispose();
  }

  Future<void> _logout() async {
    requestSubscription?.cancel();
    userSubscription?.cancel();
    shuttleSubscription?.cancel(); // ✨ ยกเลิกฟังตำแหน่งรถ
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _moveToStop(Map<String, dynamic> stop) {
    if (isAcknowledged) {
      if (isCardMinimized) {
        setState(() => isCardMinimized = false);
      }
      return;
    }
    if (isWaiting) return;

    setState(() {
      selectedStopName = stop['name'];
      selectedStopLatLng = LatLng(stop['lat'], stop['lng']);
    });

    _mapController.move(selectedStopLatLng!, 17.5);
    _updateRouteAndETA();

    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ✨ คำนวณเส้นทางและเวลา ETA จากรถคันที่ใกล้ป้ายที่สุด
  void _updateRouteAndETA() {
    if (selectedStopLatLng == null) return;

    LatLng target = selectedStopLatLng!;
    if (activeShuttles.isEmpty) {
      setState(() {
        highlightedPath.clear();
        estimatedArrivalText =
            "⚠️ ขณะนี้ยังไม่มีคนขับเปิดแอปออนไลน์อยู่ \n(ไม่สามารถแสดงเส้นทางและเวลา ETA ได้)";
      });
      return;
    }

    LatLng closestBusLoc = LatLng(
      activeShuttles.first['lat'],
      activeShuttles.first['lng'],
    );
    String? closestBusId = activeShuttles.first['id'];
    double minDirectDist = double.infinity;
    const distCalc = Distance();

    for (var bus in activeShuttles) {
      LatLng busLoc = LatLng(bus['lat'], bus['lng']);
      double d = distCalc.distance(busLoc, target);
      if (d < minDirectDist) {
        minDirectDist = d;
        closestBusLoc = busLoc;
        closestBusId = bus['id'];
      }
    }

    targetedShuttleId = closestBusId;
    _calculateHighlightedPath(closestBusLoc, target);
  }

  Future<void> _toggleWaitState() async {
    if (isWaiting || isAcknowledged) {
      if (activeRequestId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('ride_requests')
              .doc(activeRequestId)
              .delete();
        } catch (e) {
          print("Error deleting request: $e");
        }
        requestSubscription?.cancel();
      }
      if (mounted) {
        setState(() {
          isWaiting = false;
          isAcknowledged = false;
          isCardMinimized = false;
          activeRequestId = null;
          selectedStopName = null;
          selectedStopLatLng = null;
          estimatedArrivalText = null;
          highlightedPath.clear();
        });
      }
    } else {
      setState(() {
        isWaiting = true;
        isAcknowledged = false;
      });
      final user = FirebaseAuth.instance.currentUser;

      try {
        final docRef = await FirebaseFirestore.instance
            .collection('ride_requests')
            .add({
              'student_uid': user?.uid,
              'stop_name': selectedStopName,
              'status': 'waiting',
              'timestamp': FieldValue.serverTimestamp(),
              if (_myLocation != null) 'student_lat': _myLocation!.latitude,
              if (_myLocation != null) 'student_lng': _myLocation!.longitude,
              if (targetedShuttleId != null) 'target_shuttle_id': targetedShuttleId,
            });

        activeRequestId = docRef.id;

        requestSubscription?.cancel();
        requestSubscription = docRef.snapshots().handleError((e) => print("Firestore Error (ride_requests): $e")).listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            if (data != null && data['status'] == 'acknowledged') {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'คนขับรับทราบแล้ว! กำลังเดินทางไปรับที่ป้ายครับ 🚌',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                setState(() {
                  isWaiting = false;
                  isAcknowledged =
                      true; // ✨ เปลี่ยนสถานะเป็นคนขับรับทราบแล้ว และคงเส้นทางกับป้ายจอดไว้
                  isCardMinimized = false;
                });
                _updateRouteAndETA();
              }
            }
          }
        });
      } catch (e) {
        print("Error requesting ride: $e");
        if (mounted) {
          setState(() => isWaiting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F2),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildMapScreen(),
              StudentLiveStatusScreen(
                busStops: busStops,
              ), // ✨ หน้า Live Status ตามดีไซน์
              // ✨ เปลี่ยนเป็นหน้า StudentChatListScreen ที่รวมรายการแชททุกคัน
              const StudentChatListScreen(),

              const StudentProfileScreen(),
            ],
          ),

          // ✨ Bottom Navigation Bar สไตล์ Curved Notch โมเดิร์น
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

  Widget _buildMapScreen() {
    return Stack(
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
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom | InteractiveFlag.scrollWheelZoom,
                cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(), // ✨ ปิดการหมุนด้วยคีย์บอร์ด/เมาส์บน Web
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isAutoFollow) {
                  setState(() {
                    _isAutoFollow = false;
                  });
                }
              },
              onTap: (tapPosition, point) {
                if (isAcknowledged) {
                  setState(() {
                    isCardMinimized =
                        true; // ✨ ย่อกรอบรายละเอียดออก ให้เหลือแค่ปุ่ม "ขึ้นรถเรียบร้อย"
                  });
                } else if (!isWaiting) {
                  setState(() {
                    selectedStopName = null;
                    selectedStopLatLng = null;
                    estimatedArrivalText = null;
                    highlightedPath.clear();
                  });
                }
                FocusManager.instance.primaryFocus?.unfocus();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.psru_shuttle_app',
              ),
              PolylineLayer(
                polylines: [
                  ...shuttleRoutes.map((segment) {
                    return Polyline(
                      points: segment,
                      strokeWidth: 5.0,
                      color: const Color(0xFF176a21).withOpacity(0.3),
                    );
                  }),
                  if (highlightedPath.isNotEmpty)
                    Polyline(
                      points: highlightedPath,
                      strokeWidth: 6.0,
                      color: const Color(0xFF176a21),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  ...busStops.map((stop) {
                    bool isSelected = selectedStopName == stop['name'];
                    return Marker(
                      key: ValueKey('stop_${stop['name']}'),
                      point: LatLng(stop['lat'], stop['lng']),
                      width: isSelected ? 150 : 130,
                      height: isSelected ? 75 : 65,
                      child: RepaintBoundary(
                        child: GestureDetector(
                          onTap: () => _moveToStop(stop),
                          child: _buildStopMarker(
                            isSelected: isSelected,
                            name: stop['name'] ?? '',
                          ),
                        ),
                      ),
                    );
                  }),
                  // ✨ แสดงตำแหน่งนักศึกษา
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
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
                              size: 16, // ใส่ไอคอนรูปคนตรงกลางสีฟ้า
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white, width: 1.0),
                              ),
                              child: const Text(
                                'ฉัน', // ข้อความบอกว่าเป็นตัวนักศึกษาเอง
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // ✨ แสดงหมุดรถรับส่งทุกคันที่ออนไลน์ (ขยับแบบอนิเมชันเหมือนฝั่งคนขับ)
                  ...activeShuttles.map((shuttle) {
                    final String id = shuttle['id'];
                    final LatLng displayLoc =
                        _currentShuttleLocations[id] ??
                        LatLng(
                          (shuttle['lat'] as num).toDouble(),
                          (shuttle['lng'] as num).toDouble(),
                        );
                    return Marker(
                      key: ValueKey('shuttle_$id'),
                      point: displayLoc,
                      width: 80,
                      height: 80,
                      child: RepaintBoundary(
                        child: _buildBusMarker(shuttle['passenger_status'], shuttle['number']?.toString()),
                      ),
                    );
                  }),
                  // ✨ แสดงป้ายเวลาประมาณการ (ETA Badge) ข้างเส้นทางไฮไลท์บนแผนที่
                  if (highlightedPath.isNotEmpty &&
                      estimatedArrivalText != null &&
                      _getPathMidpoint() != null)
                    Marker(
                      key: const ValueKey('eta_badge'),
                      point: _getPathMidpoint()!,
                      width: 170,
                      height: 40,
                      child: RepaintBoundary(
                        child: _buildRouteEtaBadge(estimatedArrivalText!),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        if (_isLoadingStops)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text("กำลังโหลดป้ายรถ..."),
                  ],
                ),
              ),
            ),
          ),

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

        // ✨ ปุ่มเป้าเล็ง (แบบเดียวกับของคนขับ)
        Positioned(
          bottom: (selectedStopName != null) ? 230 : 100, // ขยับหลบการ์ดด้านล่างถ้ายกขึ้นมา
          right: 20,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: _isAutoFollow ? const Color(0xFF176a21) : Colors.white,
            elevation: 4,
            onPressed: () {
              setState(() {
                _isAutoFollow = true;
              });
              if (selectedStopLatLng != null) {
                _mapController.move(selectedStopLatLng!, 17.5);
              } else if (_myLocation != null) {
                _mapController.move(_myLocation!, 17.0);
              } else {
                _mapController.move(_psruCenter, 15.5);
              }
            },
            child: Icon(
              _isAutoFollow ? Icons.my_location : Icons.location_searching,
              color: _isAutoFollow ? Colors.white : const Color(0xFF176a21),
            ),
          ),
        ),

        Positioned(
          top: 150,
          left: 0, // change from 20 to 0 to allow centering
          right: 0, // change from 20 to 0 to allow centering
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (_isLoadingStops)
                return const Iterable<Map<String, dynamic>>.empty();
              if (textEditingValue.text.isEmpty) return busStops;
              return busStops.where(
                (stop) => stop['name'].toString().toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            displayStringForOption: (option) => option['name'],
            onSelected: (selection) => _moveToStop(selection),
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: _isLoadingStops
                            ? 'กำลังโหลดข้อมูล...'
                            : 'ค้นหาจุดจอดรถ...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF757778),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF757778),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        suffixIcon:
                            controller.text.isNotEmpty &&
                                !isWaiting &&
                                !isAcknowledged
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Color(0xFF757778),
                                  size: 20,
                                ),
                                onPressed: () {
                                  controller.clear();
                                  setState(() {
                                    selectedStopName = null;
                                    selectedStopLatLng = null;
                                    estimatedArrivalText = null;
                                    highlightedPath.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() {}),
                      enabled:
                          !_isLoadingStops && !isWaiting && !isAcknowledged,
                    ),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              List<Map<String, dynamic>> sortedOptions = options.toList();
              sortedOptions.sort((a, b) {
                bool aIsFav = favoriteStops.contains(a['name']);
                bool bIsFav = favoriteStops.contains(b['name']);
                if (aIsFav && !bIsFav) return -1;
                if (!aIsFav && bIsFav) return 1;
                return 0;
              });

              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: MediaQuery.of(context).size.width - 40,
                    constraints: const BoxConstraints(maxHeight: 350),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Text(
                            '#จุดเรียกรถทั้งหมด',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Divider(height: 1, color: Colors.grey.shade200),
                        Flexible(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            shrinkWrap: true,
                            itemCount: sortedOptions.length,
                            itemBuilder: (context, index) {
                              final option = sortedOptions[index];
                              final bool isFav = favoriteStops.contains(
                                option['name'],
                              );

                              return Material(
                                color: index % 2 == 0
                                    ? Colors.grey.shade50
                                    : Colors.white,
                                child: InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          color: Color(0xFF176a21),
                                          size: 22,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            option['name'],
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF2C2F30),
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () =>
                                              _toggleFavorite(option['name']),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              isFav
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: isFav
                                                  ? Colors.amber
                                                  : Colors.grey.shade400,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
              ),
            ),
          ),
        ),
        if (selectedStopName != null)
          Positioned(
            bottom: 90,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: selectedStopName != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildStopDetailsCard(),
            ),
          ),
      ],
    );
  }

  // ✨ วิดเจ็ต Bottom Navigation Bar ดีไซน์โค้งเว้าพร้อมปุ่มวงกลมลอย
  Widget _buildCurvedBottomNav() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map_outlined, 'activeIcon': Icons.map, 'label': 'Map'},
      {
        'icon': Icons.directions_bus_outlined,
        'activeIcon': Icons.directions_bus,
        'label': 'Live Status',
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
                color: Colors.black.withValues(alpha: 0.15),
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
                color: Colors.black.withValues(alpha: isSelected ? 0.3 : 0.1),
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
    displayNum = displayNum.replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '').trim();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // วงกลมไอคอนรถบัส (จะอยู่ตรงกลาง LatLng พอดี)
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
          padding: const EdgeInsets.all(3), // ลดความหนาขอบขาวลง
          child: Container(
            padding: const EdgeInsets.all(7), // ระยะห่างขอบสีถึงไอคอน
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 22,
            ), // ปรับขนาดไอคอนรถบัสตามที่ต้องการ
          ),
        ),
        // ป้ายเบอร์รถ (จะห้อยอยู่ด้านล่างวงกลม)
        if (displayNum.isNotEmpty)
          Positioned(
            bottom: -4, // ขยับลงมาด้านล่างวงกลม
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21).withOpacity(0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 1.0), // ลดความหนาขอบขาวของป้ายเบอร์
              ),
              child: Text(
                displayNum,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900, // ปรับให้หนาพิเศษ
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStopDetailsCard() {
    // ✨ ถ้าอยู่ในสถานะคนขับรับทราบแล้ว และถูกย่อจากการกดที่แผนที่ ให้แสดงเหลือแค่ปุ่ม "ขึ้นรถเรียบร้อยแล้ว"
    if (isAcknowledged && isCardMinimized) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            child: GestureDetector(
              onTap: _toggleWaitState,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9DF197), Color(0xFF176a21)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF176a21).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'ขึ้นรถเรียบร้อยแล้ว (เสร็จสิ้น)',
                        style: TextStyle(
                          fontSize: 15.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C2F30).withOpacity(0.1),
                blurRadius: 25,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF1F2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'จุดจอดรถรับส่ง',
                      style: TextStyle(
                        color: Color(0xFF595C5D),
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (!isWaiting)
                    GestureDetector(
                      onTap: () async {
                        if (activeRequestId != null) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('ride_requests')
                                .doc(activeRequestId)
                                .delete();
                          } catch (e) {
                            print("Error deleting request: $e");
                          }
                          requestSubscription?.cancel();
                        }
                        if (mounted) {
                          setState(() {
                            isWaiting = false;
                            isAcknowledged = false;
                            isCardMinimized = false;
                            activeRequestId = null;
                            selectedStopName = null;
                            selectedStopLatLng = null;
                            estimatedArrivalText = null;
                            highlightedPath.clear();
                          });
                        }
                      },
                      child: const Icon(
                        Icons.close,
                        color: Color(0xFF757778),
                        size: 20,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                selectedStopName ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C2F30),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),

              if (isWaiting)
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'กำลังส่งสัญญาณเรียกคนขับ...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else if (isAcknowledged)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Color(0xFF176a21),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'คนขับรับทราบแล้ว! รถกำลังเดินทางมารับคุณที่ป้าย',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF176a21),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (estimatedArrivalText != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            activeShuttles.isEmpty
                                ? Icons.info_outline
                                : Icons.timer_outlined,
                            size: 16,
                            color: activeShuttles.isEmpty
                                ? const Color(0xFFD84315)
                                : const Color(0xFF595C5D),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              activeShuttles.isEmpty
                                  ? estimatedArrivalText!
                                  : 'รถจะมาถึง: $estimatedArrivalText',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: activeShuttles.isEmpty
                                    ? const Color(0xFFD84315)
                                    : const Color(0xFF595C5D),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                )
              else if (estimatedArrivalText != null)
                Row(
                  children: [
                    Icon(
                      activeShuttles.isEmpty
                          ? Icons.info_outline
                          : Icons.timer_outlined,
                      size: 16,
                      color: activeShuttles.isEmpty
                          ? const Color(0xFFD84315)
                          : const Color(0xFF176a21),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        estimatedArrivalText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: activeShuttles.isEmpty
                              ? const Color(0xFFD84315)
                              : const Color(0xFF176a21),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(
                      activeShuttles.isEmpty
                          ? Icons.info_outline
                          : Icons.directions_bus,
                      size: 16,
                      color: activeShuttles.isEmpty
                          ? const Color(0xFFD84315)
                          : const Color(0xFF176a21),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeShuttles.isEmpty
                            ? '⚠️ ขณะนี้ยังไม่มีคนขับเปิดแอปออนไลน์ในระบบ'
                            : 'รถรับส่ง สาย A กำลังวิ่งให้บริการ',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: activeShuttles.isEmpty
                              ? const Color(0xFFD84315)
                              : const Color(0xFF176a21),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 14),

              GestureDetector(
                onTap: _toggleWaitState,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isWaiting
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : [const Color(0xFF9DF197), const Color(0xFF176a21)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isWaiting ? Colors.red : const Color(0xFF176a21))
                                .withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isWaiting
                              ? Icons.cancel
                              : (isAcknowledged
                                    ? Icons.check
                                    : Icons.waving_hand),
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isWaiting
                              ? 'ยกเลิกการรอรถ'
                              : (isAcknowledged
                                    ? 'ขึ้นรถเรียบร้อยแล้ว (เสร็จสิ้น)'
                                    : 'แจ้งรอรถที่จุดนี้'),
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
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
      ),
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
    return oldDelegate.notchCenter != notchCenter || oldDelegate.isDesktop != isDesktop;
  }
}
