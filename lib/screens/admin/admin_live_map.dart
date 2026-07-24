import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../route_data.dart';

class AdminLiveMapTab extends StatefulWidget {
  const AdminLiveMapTab({super.key});

  @override
  State<AdminLiveMapTab> createState() => _AdminLiveMapTabState();
}

class _AdminLiveMapTabState extends State<AdminLiveMapTab> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  
  List<Map<String, dynamic>> activeShuttles = [];
  List<Map<String, dynamic>> busStops = [];
  
  StreamSubscription<QuerySnapshot>? shuttleSubscription;
  
  Map<String, LatLng> _currentShuttleLocations = {};
  Map<String, LatLng> _oldShuttleLocations = {};
  Map<String, LatLng> _targetShuttleLocations = {};
  
  String? _selectedShuttleId;

  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase();
    _listenToShuttles();
    
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
              final lat = oldLoc.latitude + (targetLoc.latitude - oldLoc.latitude) * _markerAnimation.value;
              final lng = oldLoc.longitude + (targetLoc.longitude - oldLoc.longitude) * _markerAnimation.value;
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
    _markerAnimationController.dispose();
    super.dispose();
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('stops').get();
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
      debugPrint('Error fetching stops: $e');
    }
  }

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
          if (data.containsKey('last_updated') && data['last_updated'] != null) {
            final Timestamp? lastUpdated = data['last_updated'] as Timestamp?;
            if (lastUpdated != null && now.difference(lastUpdated.toDate()).inMinutes >= 3) {
              return false;
            }
            return true;
          }
          return false;
        }).toList();

        final newShuttles = validDocs.map((doc) => {
          'id': doc.id,
          'number': doc['number'],
          'lat': (doc['lat'] as num).toDouble(),
          'lng': (doc['lng'] as num).toDouble(),
          'passenger_status': doc.data().containsKey('passenger_status') ? doc['passenger_status'] : 'available',
        }).toList();
        
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
        _currentShuttleLocations.removeWhere((id, loc) => !activeIds.contains(id));
        _oldShuttleLocations.removeWhere((id, loc) => !activeIds.contains(id));
        _targetShuttleLocations.removeWhere((id, loc) => !activeIds.contains(id));
        
        setState(() {
          activeShuttles = newShuttles;
        });
        
        if (shouldAnimate) {
          _markerAnimationController.forward(from: 0.0);
        }
      }
    });
  }

  Widget _buildStopMarker({required String name}) {
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
              color: const Color(0xFF757778),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.hail,
            color: Color(0xFF757778),
            size: 15,
          ),
        ),
        Positioned(
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF176a21),
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
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2F30),
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
    Color statusColor = const Color(0xFF176a21); // Default (available)
    final passengerStatus = shuttle['passenger_status'] ?? 'available';
    if (passengerStatus == 'full') {
      statusColor = const Color(0xFF757778); // Full (grey)
    } else if (passengerStatus == 'break') {
      statusColor = const Color(0xFFF28522); // Break (orange)
    } else if (passengerStatus == 'offline' || shuttle['status'] == 'offline') {
      statusColor = Colors.red; // Offline (red)
    }

    String displayNum = (shuttle['number'] ?? '').toString();
    displayNum = displayNum.replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '').trim();

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

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _psruCenter,
        initialZoom: 15.5,
        maxZoom: 18.0,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom | InteractiveFlag.scrollWheelZoom,
          cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(), // ✨ ปิดการหมุนด้วยคีย์บอร์ด/เมาส์บน Web
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
              strokeWidth: 5.0,
              color: const Color(0xFF176a21).withOpacity(0.4),
            );
        }).toList(),
        ),
        MarkerLayer(
          markers: [
            ...busStops.map((stop) => Marker(
              key: ValueKey('stop_${stop['id'] ?? stop['name']}'),
              point: LatLng(stop['lat'], stop['lng']),
              width: 130,
              height: 65,
              child: RepaintBoundary(
                child: _buildStopMarker(
                  name: stop['name'] ?? '',
                ),
              ),
            )),
            ...activeShuttles.map((shuttle) {
              final id = shuttle['id'];
              final loc = _currentShuttleLocations[id] ?? LatLng(shuttle['lat'], shuttle['lng']);
              return Marker(
                point: loc,
                width: 80,
                height: 80,
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
    return Stack(
      children: [
        // Live Map
        _buildMap(),

        // Top Left: Command Center Routes
        Positioned(
          top: 24,
          left: 24,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ศูนย์ควบคุม', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('รถที่กำลังวิ่งทั้งหมด', style: TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 16),
                _buildRouteItem('รถทั้งหมดในระบบ', '${activeShuttles.length} คัน', activeShuttles.isNotEmpty),
              ],
            ),
          ),
        ),

        // Top Search Bar
        Positioned(
          top: 24,
          left: 320,
          child: Container(
            width: 300,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ค้นหาเส้นทาง, คนขับ, ป้ายรถ...',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),

        // Right Panel: Live Tracking
        if (_selectedShuttleId != null)
          Positioned(
            top: 24,
            right: 24,
            bottom: 120, // Leave space for bottom bar
            child: Builder(
              builder: (context) {
                final selectedShuttle = activeShuttles.firstWhere(
                  (s) => s['id'] == _selectedShuttleId,
                  orElse: () => activeShuttles.isNotEmpty ? activeShuttles.first : {},
                );
                
                if (selectedShuttle.isEmpty) return const SizedBox.shrink();

                return Container(
                  width: 340,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                const Text('กำลังติดตามสด', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF176a21))),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedShuttleId = null;
                                    });
                                  },
                                  child: const Icon(Icons.close, color: Colors.black54, size: 24),
                                ),
                              ],
                            ),
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text('รถบัส #${selectedShuttle['number']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 16),

                          // Driver Info
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 24,
                                  backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('คนขับหลัก', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
                                      const SizedBox(height: 2),
                                      const Text('คนขับรถรับส่ง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.star, size: 10, color: Color(0xFF176a21)),
                                                SizedBox(width: 4),
                                                Text('5.0', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF176a21))),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Stats
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Row(
                              children: [
                                Expanded(child: _buildPanelStat('ความจุปัจจุบัน', '${selectedShuttle['capacity_percent'] ?? 0}', '%', (selectedShuttle['capacity_percent'] ?? 0) / 100)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildPanelStat('สถานะผู้โดยสาร', '', '', 1.0, subStatus: selectedShuttle['passenger_status'] == 'full' ? 'หนาแน่น' : (selectedShuttle['passenger_status'] == 'break' ? 'พักเบรก' : 'ว่าง'))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                );
              }
            ),
          ),

        // Bottom Dashboard Bar
        Positioned(
          bottom: 24,
          left: 320,
          right: 24,
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildBottomStat(Icons.people_alt_outlined, '1,248', 'ผู้โดยสารรวม'),
                        Container(width: 1, height: 40, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 24)),
                        _buildBottomStat(Icons.schedule, '98.2%', 'ตรงเวลา'),
                        Container(width: 1, height: 40, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 24)),
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('1 การแจ้งเตือน', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 13)),
                                Text('รถล่าช้า (สายเหนือ)', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Map Controls
        Positioned(
          bottom: 100,
          left: 24,
          child: Column(
            children: [
              _buildMapControlButton(Icons.add),
              const SizedBox(height: 8),
              _buildMapControlButton(Icons.remove),
              const SizedBox(height: 16),
              _buildMapControlButton(Icons.my_location),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildMapPin(String label, {bool isActive = true}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF176a21) : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF176a21) : Colors.grey.shade600,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))],
          ),
        )
      ],
    );
  }

  Widget _buildRouteItem(String name, String activeCount, bool isPrimary) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isPrimary ? const Color(0xFF176a21) : Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPrimary ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            activeCount,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isPrimary ? const Color(0xFF176a21) : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanelStat(String label, String value, String unit, double progress, {String? subStatus}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(unit, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade300,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF176a21)),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          if (subStatus != null) ...[
            const SizedBox(height: 8),
            Text(subStatus, style: const TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold, fontSize: 10)),
          ]
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String title, String time, String subtitle, bool isNext) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isNext ? const Color(0xFF176a21) : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: isNext ? Border.all(color: const Color(0xFF176a21).withOpacity(0.3), width: 4) : null,
                ),
              ),
              Container(
                width: 2,
                height: 40,
                color: Colors.grey.shade200,
              )
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isNext ? const Color(0xFF176a21) : Colors.black87)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: isNext ? const Color(0xFFE8F5E9) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                      child: Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNext ? const Color(0xFF176a21) : Colors.black54)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF176a21), size: 28),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildMapControlButton(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Icon(icon, color: Colors.black87),
    );
  }
}
