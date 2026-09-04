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

  List<Map<String, dynamic>> activeShuttles = [];
  List<Map<String, dynamic>> busStops = [];

  void _animatedMapMove(LatLng destLocation, double destZoom) {
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
      end: destZoom,
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
    'คณะสังคมศาสตร์ และคณะพยาบาลศาสตร์': [
      'คณะสังคมศาสตร์',
      'คณะพยาบาลศาสตร์',
    ],
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

  int totalPassengersToday = 0;
  double onTimePercentage = 100.0;

  final Map<String, LatLng> _currentShuttleLocations = {};
  final Map<String, LatLng> _oldShuttleLocations = {};
  final Map<String, LatLng> _targetShuttleLocations = {};

  String? _selectedShuttleId;

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
    _markerAnimation = CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeInOut,
    )..addListener(() {
        if (mounted) {
          setState(() {
            for (var id in _targetShuttleLocations.keys) {
              final oldLoc = _oldShuttleLocations[id];
              final targetLoc = _targetShuttleLocations[id];
              if (oldLoc != null && targetLoc != null) {
                final lat = oldLoc.latitude +
                    (targetLoc.latitude - oldLoc.latitude) *
                        _markerAnimation.value;
                final lng = oldLoc.longitude +
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

  void _listenToRideRequests() {
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    rideRequestsSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      int total = snapshot.docs.length;
      int onTimeCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final Timestamp? startTs = data['timestamp'] as Timestamp?;
        final Timestamp? ackTs = data['acknowledged_at'] as Timestamp?;

        if (startTs != null && ackTs != null) {
          final start = startTs.toDate();
          final ack = ackTs.toDate();
          if (ack.difference(start).inMinutes <= 5) {
            onTimeCount++;
          }
        } else if (data['status'] == 'acknowledged' ||
            data['status'] == 'on_board' ||
            data['status'] == 'completed') {
          onTimeCount++;
        }
      }

      double rate = total > 0 ? (onTimeCount / total) * 100.0 : 100.0;

      setState(() {
        totalPassengersToday = total;
        onTimePercentage = rate;
      });
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
      final snapshot =
          await FirebaseFirestore.instance.collection('stops').get();
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
                isRecentlyUpdated = now.difference(lastUpdated).inMinutes <= 4;
              }

              if (isRecentlyUpdated) {
                newShuttles.add({
                  'id': key.toString(),
                  'number': value.containsKey('number') ? value['number'] : '',
                  'name': value.containsKey('name') ? value['name'] : 'Shuttle',
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
        _currentShuttleLocations
            .removeWhere((id, loc) => !activeIds.contains(id));
        _oldShuttleLocations
            .removeWhere((id, loc) => !activeIds.contains(id));
        _targetShuttleLocations
            .removeWhere((id, loc) => !activeIds.contains(id));

        setState(() {
          activeShuttles = newShuttles;
        });

        if (shouldAnimate) {
          _markerAnimationController.forward(from: 0.0);
        }
      }
    });
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
              color: isGroup ? const Color(0xFF176a21) : const Color(0xFF66BB6A),
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

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _psruCenter,
        initialZoom: 15.5,
        maxZoom: 18.0,
        minZoom: 14.0,
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(
            const LatLng(16.81500, 100.19000),
            const LatLng(16.84500, 100.23000),
          ),
        ),
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
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
            ..._visualStops.map((stop) => Marker(
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
                )),
            ...activeShuttles.map((shuttle) {
              final id = shuttle['id'];
              final loc = _currentShuttleLocations[id] ??
                  LatLng(shuttle['lat'], shuttle['lng']);
              return Marker(
                point: loc,
                width: 70,
                height: 70,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedShuttleId = id;
                    });
                  },
                  child: RepaintBoundary(
                    child: _buildShuttleMarker(shuttle),
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
                                'สถานะกองรถ (Fleet)',
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
                        ],
                      ),
                    ),
                  ),

                  // แผงรายละเอียดเมื่อคลิกเลือกรถ (ขวาบน)
                  if (_selectedShuttleId != null)
                    Positioned(
                      top: 20,
                      right: 20,
                      bottom: 110,
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
                            width: isCompact
                                ? constraints.maxWidth - 40
                                : 320,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.04),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF176a21)
                                      .withOpacity(0.12),
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
                                        color: const Color(0xFF176a21)
                                            .withOpacity(0.08),
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

                  // แถบสรุปสถิติด้านล่าง (Bottom Dashboard Floating Bar)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        height: 68,
                        width: (constraints.maxWidth - 48).clamp(280.0, 420.0),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(34),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF176a21).withOpacity(0.10),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: _buildBottomStat(
                                Icons.groups_rounded,
                                NumberFormat('#,##0')
                                    .format(totalPassengersToday),
                                'ผู้โดยสารสะสม',
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 32,
                              color: const Color(0xFFEFF2F0),
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            Expanded(
                              child: _buildBottomStat(
                                Icons.timer_outlined,
                                '${onTimePercentage.toStringAsFixed(1)}%',
                                'อัตราตรงเวลา',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ปุ่มควบคุมแผนที่ (Zoom In, Out, Center)
                  Positioned(
                    bottom: 110,
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
                        _buildMapControlButton(
                          Icons.my_location_rounded,
                          () {
                            _animatedMapMove(_psruCenter, 15.5);
                          },
                        ),
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
            color: isPrimary ? const Color(0xFF176a21) : const Color(0xFF757575),
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

  Widget _buildBottomStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF176a21), size: 18),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF1E2923),
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF718076),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
}
