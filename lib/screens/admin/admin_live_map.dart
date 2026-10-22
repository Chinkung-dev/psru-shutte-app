import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../../route_data.dart';
import 'admin_profile_dialog.dart';

class AdminLiveMapTab extends StatefulWidget {
  const AdminLiveMapTab({super.key});

  @override
  State<AdminLiveMapTab> createState() => _AdminLiveMapTabState();
}

class _AdminLiveMapTabState extends State<AdminLiveMapTab>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);

  // ขอบเขตล็อกมุมกล้องให้ครอบคลุมรอบมหาวิทยาลัย ไม่ให้เลื่อนหลุดออกนอกเมือง แต่เลื่อนดูจุดจอดริมขอบได้อิสระ
  final LatLngBounds _psruCameraBounds = LatLngBounds(
    const LatLng(16.82000, 100.20000),
    const LatLng(16.84100, 100.22100),
  );

  List<Map<String, dynamic>> activeShuttles = [];
  List<Map<String, dynamic>> busStops = [];

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final clampedZoom = destZoom.clamp(15.8, 18.5);
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: clampedZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  final Map<String, List<String>> _groupedStops = {
    '7-Eleven PSRU และตึก IT': ['7-Eleven PSRU', 'ตึก IT '],
    'คณะสังคมศาสตร์ และคณะพยาบาลศาสตร์': ['คณะสังคมศาสตร์', 'คณะพยาบาลศาสตร์'],
  };

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

  StreamSubscription? shuttleSubscription;
  StreamSubscription? rideRequestsSubscription;

  final Map<String, LatLng> _currentShuttleLocations = {};
  final Map<String, LatLng> _oldShuttleLocations = {};
  final Map<String, LatLng> _targetShuttleLocations = {};

  String? _selectedShuttleId;
  String? _selectedStudentRequestId;

  List<Map<String, dynamic>> _activeRideRequests = [];
  final Map<String, Map<String, dynamic>> _studentProfilesCache = {};

  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase();
    _listenToShuttles();
    _listenToRideRequests();

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

  @override
  void dispose() {
    shuttleSubscription?.cancel();
    rideRequestsSubscription?.cancel();
    _markerAnimationController.dispose();
    super.dispose();
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
          'name': data['name'],
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
      debugPrint("Error fetching stops: $e");
    }
  }

  void _listenToShuttles() {
    shuttleSubscription = FirebaseDatabase.instance
        .ref('shuttles')
        .onValue
        .listen((event) {
          if (mounted && event.snapshot.exists) {
            bool shouldAnimate = false;
            final now = DateTime.now();
            final data = event.snapshot.value as Map<dynamic, dynamic>;

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
                        now.difference(lastUpdated).inMinutes <= 4;
                  }

                  if (isRecentlyUpdated) {
                    newShuttles.add({
                      'id': key.toString(),
                      'number': value.containsKey('number')
                          ? value['number']
                          : '',
                      'name': value.containsKey('name')
                          ? value['name']
                          : 'Shuttle',
                      'lat': (value['lat'] as num).toDouble(),
                      'lng': (value['lng'] as num).toDouble(),
                      'driver_name': value['driver_name'] ?? 'คนขับประจำรถ',
                      'driver_avatar': value['driver_avatar'] ?? '',
                      'capacity_percent': value['capacity_percent'] ?? 0,
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
              final currentLoc = _currentShuttleLocations[id];

              if (currentLoc != null && currentLoc != newLoc) {
                _oldShuttleLocations[id] = currentLoc;
                _targetShuttleLocations[id] = newLoc;
                shouldAnimate = true;
              } else if (currentLoc == null) {
                _currentShuttleLocations[id] = newLoc;
                _targetShuttleLocations[id] = newLoc;
              }
            }

            final activeIds = newShuttles.map((s) => s['id'] as String).toSet();
            _currentShuttleLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _oldShuttleLocations.removeWhere(
              (id, loc) => !activeIds.contains(id),
            );
            _targetShuttleLocations.removeWhere(
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

  void _listenToRideRequests() {
    rideRequestsSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', whereIn: ['waiting', 'acknowledged'])
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          final now = DateTime.now();
          final List<Map<String, dynamic>> requests = [];

          for (var doc in snapshot.docs) {
            final data = doc.data();

            // กรองคำขอที่เก่าเกิน 2 ชั่วโมงออก เพื่อไม่ให้แสดงข้อมูลค้างในระบบ
            if (data.containsKey('timestamp') && data['timestamp'] != null) {
              DateTime? reqTime;
              if (data['timestamp'] is Timestamp) {
                reqTime = (data['timestamp'] as Timestamp).toDate();
              } else if (data['timestamp'] is String) {
                reqTime = DateTime.tryParse(data['timestamp']);
              }
              if (reqTime != null && now.difference(reqTime).inHours >= 2) {
                continue;
              }
            }

            // ดึงพิกัดนักศึกษา (ถ้ามี student_lat และ student_lng)
            double? sLat;
            double? sLng;
            if (data['student_lat'] is num) {
              sLat = (data['student_lat'] as num).toDouble();
            } else if (data['student_lat'] is String) {
              sLat = double.tryParse(data['student_lat']);
            }

            if (data['student_lng'] is num) {
              sLng = (data['student_lng'] as num).toDouble();
            } else if (data['student_lng'] is String) {
              sLng = double.tryParse(data['student_lng']);
            }

            // หากไม่มีพิกัด GPS ให้ใช้พิกัดของป้ายที่เลือกรถ
            if (sLat == null || sLng == null) {
              final String stopName =
                  data['stop_name']?.toString().trim() ?? '';
              if (stopName.isNotEmpty) {
                for (var s in busStops) {
                  if ((s['name'] ?? '').toString().trim() == stopName) {
                    if (s['lat'] is num && s['lng'] is num) {
                      sLat = (s['lat'] as num).toDouble();
                      sLng = (s['lng'] as num).toDouble();
                      break;
                    }
                  }
                }
              }
            }

            if (sLat != null && sLng != null) {
              final reqMap = {
                'id': doc.id,
                'student_uid': data['student_uid']?.toString(),
                'stop_name': data['stop_name']?.toString() ?? 'จุดรับผู้โดยสาร',
                'dropoff_stop': data['dropoff_stop']?.toString(),
                'status': data['status']?.toString() ?? 'waiting',
                'timestamp': data['timestamp'],
                'target_shuttle_id': data['target_shuttle_id']?.toString(),
                'lat': sLat,
                'lng': sLng,
              };
              requests.add(reqMap);

              final uid = reqMap['student_uid'] as String?;
              if (uid != null &&
                  uid.isNotEmpty &&
                  !_studentProfilesCache.containsKey(uid)) {
                _fetchStudentProfile(uid);
              }
            }
          }

          setState(() {
            _activeRideRequests = requests;
            if (_selectedStudentRequestId != null &&
                !requests.any((r) => r['id'] == _selectedStudentRequestId)) {
              _selectedStudentRequestId = null;
            }
          });
        }, onError: (e) {
          debugPrint("Firestore Error (ride_requests): $e");
        });
  }

  Future<void> _fetchStudentProfile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _studentProfilesCache[uid] = doc.data() ?? {};
        });
      }
    } catch (e) {
      debugPrint("Error fetching student profile: $e");
    }
  }

  Widget _buildStopMarker({required String name, bool isGroup = false}) {
    String cleanName = name
        .replaceAll('(ขาเข้า)', '')
        .replaceAll('(ขาออก)', '')
        .trim();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isGroup
                  ? const Color(0xFF176a21)
                  : const Color(0xFF66BB6A),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF176a21).withOpacity(0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.hail_rounded,
            color: isGroup ? const Color(0xFF176a21) : const Color(0xFF436B49),
            size: 15,
          ),
        ),
        Positioned(
          bottom: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF176a21).withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              cleanName,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E2923),
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

  Widget _buildShuttleMarker(Map<String, dynamic> shuttle) {
    Color statusColor = const Color(0xFF176a21);
    final passengerStatus = shuttle['passenger_status'] ?? 'available';
    if (passengerStatus == 'full') {
      statusColor = const Color(0xFFE65100);
    } else if (passengerStatus == 'break') {
      statusColor = const Color(0xFFF57C00);
    } else if (passengerStatus == 'offline' || shuttle['status'] == 'offline') {
      statusColor = const Color(0xFF757575);
    }

    String displayNum = (shuttle['number'] ?? '').toString();
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
                color: statusColor.withOpacity(0.35),
                blurRadius: 10,
                spreadRadius: 2,
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
              Icons.directions_bus_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        if (displayNum.isNotEmpty)
          Positioned(
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 1.0),
              ),
              child: Text(
                displayNum,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStudentMarker(Map<String, dynamic> req, bool isSelected) {
    final String status = req['status'] ?? 'waiting';
    final bool isWaiting = status == 'waiting';
    final Color primaryColor =
        isWaiting ? const Color(0xFF1E88E5) : const Color(0xFF00897B);
    final String statusText = isWaiting ? 'นักศึกษารอรถ' : 'คนขับรับทราบ';

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (isSelected)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryColor, width: 2.5),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.35),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        Positioned(
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _psruCenter,
        initialZoom: 16.2,
        minZoom: 15.8,
        maxZoom: 18.5,
        cameraConstraint:
            CameraConstraint.containCenter(bounds: _psruCameraBounds),
        interactionOptions: InteractionOptions(
          flags:
              InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
          cursorKeyboardRotationOptions:
              CursorKeyboardRotationOptions.disabled(),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.psru_shuttle_app',
        ),
        PolylineLayer(
          polylines: shuttleRoutes.map((segment) {
            return Polyline(
              points: segment,
              strokeWidth: 4.5,
              color: const Color(0xFF176a21).withOpacity(0.4),
            );
          }).toList(),
        ),
        MarkerLayer(
          markers: [
            ..._visualStops.map(
              (stop) => Marker(
                key: ValueKey('stop_${stop['id'] ?? stop['name']}'),
                point: LatLng(stop['lat'], stop['lng']),
                width: 160,
                height: 65,
                child: RepaintBoundary(
                  child: _buildStopMarker(
                    name: stop['name'] ?? '',
                    isGroup: stop['isGroup'] == true,
                  ),
                ),
              ),
            ),
            ...activeShuttles.map((shuttle) {
              final id = shuttle['id'];
              final loc =
                  _currentShuttleLocations[id] ??
                  LatLng(shuttle['lat'], shuttle['lng']);
              return Marker(
                point: loc,
                width: 70,
                height: 70,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedShuttleId = id;
                      _selectedStudentRequestId = null;
                    });
                  },
                  child: RepaintBoundary(child: _buildShuttleMarker(shuttle)),
                ),
              );
            }),
            ..._activeRideRequests.map((req) {
              final LatLng loc = LatLng(req['lat'], req['lng']);
              final isSelected = _selectedStudentRequestId == req['id'];
              return Marker(
                key: ValueKey('req_${req['id']}'),
                point: loc,
                width: 90,
                height: 70,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedStudentRequestId = req['id'];
                      _selectedShuttleId = null;
                    });
                  },
                  child: RepaintBoundary(
                    child: _buildStudentMarker(req, isSelected),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 720;
        final bool isDesktop = MediaQuery.of(context).size.width > 960;

        return Column(
          children: [
            // ส่วน Header ด้านบน
            if (isDesktop)
              Container(
                color: Colors.transparent,
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.black.withOpacity(0.04)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF176a21).withOpacity(0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.map_rounded,
                          color: Color(0xFF176a21),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'แผนที่ติดตามรถรับส่งสด (Live Map)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF176a21),
                            ),
                          ),
                          Text(
                            'พิกัดรถรับส่งและจุดจอดรอบมหาวิทยาลัยแบบเรียลไทม์',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5A605B),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => const AdminProfileDialog(),
                          );
                        },
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF176a21),
                              width: 2,
                            ),
                          ),
                          child: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F5E9),
                            radius: 18,
                            child: Icon(
                              Icons.admin_panel_settings_rounded,
                              color: Color(0xFF176a21),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // พื้นที่แผนที่และแผงควบคุมลอย
            Expanded(
              child: Stack(
                children: [
                  _buildMap(),

                  // แผงข้อมูลรถที่กำลังวิ่ง (ซ้ายบน)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      width: isCompact ? 220 : 260,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF176a21).withOpacity(0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF176a21).withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF176a21),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'สถานะรถ (Fleet)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF1E2923),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildRouteItem(
                            'รถออนไลน์ทั้งหมด',
                            '${activeShuttles.length} คัน',
                            activeShuttles.isNotEmpty,
                          ),
                          const SizedBox(height: 8),
                          _buildRouteItem(
                            'จุดจอดในระบบ',
                            '${busStops.length} จุด',
                            true,
                          ),
                          const SizedBox(height: 8),
                          _buildRouteItem(
                            'นักศึกษาเรียกรถ',
                            '${_activeRideRequests.length} คน',
                            _activeRideRequests.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // แผงรายละเอียดเมื่อคลิกเลือกรถ (ขวาบน)
                  if (_selectedShuttleId != null)
                    Positioned(
                      top: 20,
                      right: 20,
                      bottom: 24,
                      child: Builder(
                        builder: (context) {
                          final selectedShuttle = activeShuttles.firstWhere(
                            (s) => s['id'] == _selectedShuttleId,
                            orElse: () => activeShuttles.isNotEmpty
                                ? activeShuttles.first
                                : {},
                          );

                          if (selectedShuttle.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            width: isCompact ? constraints.maxWidth - 40 : 320,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.04),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF176a21,
                                  ).withOpacity(0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 4,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF176a21),
                                          Color(0xFF66BB6A),
                                          Color(0xFF9DF197),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF176a21),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'กำลังติดตามสด',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF176a21),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selectedShuttleId = null;
                                            });
                                          },
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: Color(0xFF718076),
                                            size: 22,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20.0,
                                    ),
                                    child: Text(
                                      'รถรับส่ง #${selectedShuttle['number'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1E2923),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // ข้อมูลคนขับ
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F6F3),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF176a21,
                                        ).withOpacity(0.08),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF176a21),
                                              width: 2,
                                            ),
                                          ),
                                          child: const CircleAvatar(
                                            radius: 20,
                                            backgroundColor: Color(0xFFE8F5E9),
                                            child: Icon(
                                              Icons.person_rounded,
                                              color: Color(0xFF176a21),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'คนขับประจำรถ',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF718076),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                selectedShuttle['driver_name'] ??
                                                    'คนขับรถรับส่ง',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: Color(0xFF1E2923),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // ข้อมูลสถานะความจุ
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20.0,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildPanelStat(
                                            'ความจุผู้โดยสาร',
                                            '${selectedShuttle['capacity_percent'] ?? 0}%',
                                            (selectedShuttle['capacity_percent'] ??
                                                    0) /
                                                100,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildPanelStatusBadge(
                                            selectedShuttle['passenger_status'] ??
                                                'available',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // แผงรายละเอียดเมื่อคลิกเลือกนักศึกษาที่เรียกรถ (ขวาบน)
                  if (_selectedStudentRequestId != null)
                    Positioned(
                      top: 20,
                      right: 20,
                      bottom: 24,
                      child: Builder(
                        builder: (context) {
                          final selectedRequest = _activeRideRequests.firstWhere(
                            (r) => r['id'] == _selectedStudentRequestId,
                            orElse: () => {},
                          );

                          if (selectedRequest.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return _buildStudentDetailPanel(
                            selectedRequest,
                            isCompact,
                            constraints,
                          );
                        },
                      ),
                    ),

                  // ปุ่มควบคุมแผนที่ (Zoom In, Out, Center)
                  Positioned(
                    bottom: 24,
                    left: 20,
                    child: Column(
                      children: [
                        _buildMapControlButton(Icons.add_rounded, () {
                          final currentZoom = _mapController.camera.zoom;
                          _animatedMapMove(
                            _mapController.camera.center,
                            currentZoom + 1.0,
                          );
                        }),
                        const SizedBox(height: 8),
                        _buildMapControlButton(Icons.remove_rounded, () {
                          final currentZoom = _mapController.camera.zoom;
                          _animatedMapMove(
                            _mapController.camera.center,
                            currentZoom - 1.0,
                          );
                        }),
                        const SizedBox(height: 12),
                        _buildMapControlButton(Icons.my_location_rounded, () {
                          _animatedMapMove(_psruCenter, 16.2);
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRouteItem(String name, String activeCount, bool isPrimary) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isPrimary
                ? const Color(0xFF176a21)
                : const Color(0xFF757575),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
            color: Color(0xFF2C2F30),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isPrimary
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            activeCount,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isPrimary
                  ? const Color(0xFF176a21)
                  : const Color(0xFF757575),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanelStat(String label, String value, double progress) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF718076),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E2923),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.black.withOpacity(0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF176a21),
              ),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelStatusBadge(String status) {
    Color color = const Color(0xFF176a21);
    Color bgColor = const Color(0xFFE8F5E9);
    String text = 'พร้อมบริการ';

    if (status == 'full') {
      color = const Color(0xFFE65100);
      bgColor = const Color(0xFFFFF3E0);
      text = 'ที่นั่งเต็ม';
    } else if (status == 'break') {
      color = const Color(0xFFF57C00);
      bgColor = const Color(0xFFFFF8E1);
      text = 'พักเบรก';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สถานะรับส่ง',
            style: TextStyle(
              color: Color(0xFF718076),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMapControlButton(IconData icon, VoidCallback onTap) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF176a21).withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: onTap,
          child: Icon(icon, color: const Color(0xFF176a21), size: 20),
        ),
      ),
    );
  }

  Widget _buildStudentDetailPanel(
    Map<String, dynamic> req,
    bool isCompact,
    BoxConstraints constraints,
  ) {
    final String? uid = req['student_uid'];
    final profile = uid != null ? (_studentProfilesCache[uid] ?? {}) : {};
    final String studentName =
        (profile['name'] != null &&
                profile['name'].toString().trim().isNotEmpty)
            ? profile['name'].toString().trim()
            : 'นักศึกษา / ผู้โดยสาร';
    final String studentId = profile['student_id']?.toString() ?? '-';
    final String phone = profile['phone']?.toString() ?? '-';
    final String stopName = req['stop_name'] ?? 'จุดรับผู้โดยสาร';
    final String? dropoff = req['dropoff_stop'];
    final String status = req['status'] ?? 'waiting';
    final bool isWaiting = status == 'waiting';

    String timeStr = '-';
    if (req['timestamp'] is Timestamp) {
      final dt = (req['timestamp'] as Timestamp).toDate();
      timeStr = DateFormat('HH:mm น.').format(dt);
    }

    return Container(
      width: isCompact ? constraints.maxWidth - 40 : 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E88E5).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1565C0),
                      Color(0xFF1E88E5),
                      Color(0xFF64B5F6),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E88E5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'คำขอเรียกรถ (นักศึกษา)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E88E5),
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedStudentRequestId = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFF5A605B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ข้อมูลส่วนตัวนักศึกษา
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1E88E5).withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xFFE3F2FD),
                        child: Icon(
                          Icons.person_rounded,
                          color: Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1E2923),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            studentId != '-'
                                ? 'รหัสนักศึกษา: $studentId'
                                : 'ผู้โดยสาร',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF718076),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // สถานะและเวลาที่เรียก
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isWaiting
                              ? const Color(0xFFE3F2FD)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'สถานะคำขอ',
                              style: TextStyle(
                                color: Color(0xFF718076),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isWaiting ? 'กำลังรอรถ' : 'คนขับรับทราบแล้ว',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isWaiting
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF176a21),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6F3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'เวลาที่กดเรียก',
                              style: TextStyle(
                                color: Color(0xFF718076),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E2923),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ข้อมูลจุดขึ้นรถและจุดลงรถ
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.04)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 18,
                            color: Color(0xFF176a21),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'จุดขึ้นรถ',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF718076),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  stopName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E2923),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (dropoff != null && dropoff.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider(height: 1, color: Color(0xFFE0E5E2)),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.flag_rounded,
                              size: 18,
                              color: Color(0xFFE65100),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'จุดลงรถปลายทาง',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF718076),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    dropoff,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E2923),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (phone != '-') ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider(height: 1, color: Color(0xFFE0E5E2)),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_rounded,
                              size: 18,
                              color: Color(0xFF1E88E5),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E2923),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ปุ่มโฟกัสพิกัดนักศึกษาบนแผนที่
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _animatedMapMove(LatLng(req['lat'], req['lng']), 17.5);
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text(
                      'นำมุมมองแผนที่ไปยังจุดนี้',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
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
