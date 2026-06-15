import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart'; 
import '../../route_data.dart'; 
import 'student_profile.dart'; 
import 'student_chat_screen.dart'; // ✨ Import หน้าแชทเข้ามาแล้ว

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  int _selectedIndex = 0;

  bool isWaiting = false;
  String? selectedStopName;

  final MapController _mapController = MapController();

  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  final LatLngBounds _psruBounds = LatLngBounds(
    const LatLng(16.81500, 100.19000), 
    const LatLng(16.84500, 100.23000), 
  );

  final LatLng _busLocation = const LatLng(16.826835, 100.208930);

  List<Map<String, dynamic>> busStops = [];
  bool _isLoadingStops = true; 

  String? activeRequestId;
  StreamSubscription<DocumentSnapshot>? requestSubscription;
  StreamSubscription<DocumentSnapshot>? userSubscription;

  List<LatLng> highlightedPath = [];
  final Map<LatLng, List<LatLng>> _routeGraph = {};

  List<String> favoriteStops = [];

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase(); 
    _listenToFavoriteStops(); 
    _buildRouteGraph(); 
  }

  void _listenToFavoriteStops() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data()!.containsKey('favorite_stops')) {
          if (mounted) {
            setState(() {
              favoriteStops = List<String>.from(doc.data()!['favorite_stops']);
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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'favorite_stops': favoriteStops,
      });
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
        double alt = distances[current]! + distanceCalc.distance(current, neighbor);
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

    setState(() {
      highlightedPath = path;
    });
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('stops').get();
      
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
    requestSubscription?.cancel(); 
    userSubscription?.cancel(); 
    super.dispose();
  }

  Future<void> _logout() async {
    requestSubscription?.cancel();
    userSubscription?.cancel();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _moveToStop(Map<String, dynamic> stop) {
    if (isWaiting) return; 
    
    setState(() {
      selectedStopName = stop['name'];
    });
    
    LatLng target = LatLng(stop['lat'], stop['lng']);
    _mapController.move(target, 17.5);
    
    _calculateHighlightedPath(_busLocation, target);
    
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _toggleWaitState() async {
    if (isWaiting) {
      if (activeRequestId != null) {
        await FirebaseFirestore.instance.collection('ride_requests').doc(activeRequestId).delete();
        requestSubscription?.cancel();
      }
      setState(() {
        isWaiting = false;
        activeRequestId = null;
      });
    } else {
      setState(() => isWaiting = true);
      final user = FirebaseAuth.instance.currentUser;
      
      final docRef = await FirebaseFirestore.instance.collection('ride_requests').add({
        'student_uid': user?.uid,
        'stop_name': selectedStopName,
        'status': 'waiting',
        'timestamp': FieldValue.serverTimestamp(),
      });

      activeRequestId = docRef.id;

      requestSubscription = docRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'acknowledged') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('คนขับรับทราบแล้ว! กำลังเดินทางไปรับครับ 🚌', style: TextStyle(fontWeight: FontWeight.bold)), 
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() {
              isWaiting = false;
              activeRequestId = null;
              selectedStopName = null; 
              highlightedPath.clear(); 
            });
            requestSubscription?.cancel();
          }
        }
      });
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
              const Center(child: Text("หน้าสถานะรถ (กำลังพัฒนา)")), 
              
              // ✨ เปลี่ยนเป็นหน้า StudentChatScreen ที่เพิ่งสร้าง
              const StudentChatScreen(), 
              
              const StudentProfileScreen(), 
            ],
          ),

          // Bottom Navigation Bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))
                ]
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(icon: Icons.map, label: 'แผนที่', index: 0),
                    _buildNavItem(icon: Icons.directions_bus_outlined, label: 'สถานะรถ', index: 1),
                    _buildNavItem(icon: Icons.chat_bubble_outline, label: 'แชท', index: 2),
                    _buildNavItem(icon: Icons.person_outline, label: 'โปรไฟล์', index: 3),
                  ],
                ),
              ),
            ),
          )
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
              onTap: (tapPosition, point) {
                if (!isWaiting) {
                  setState(() {
                    selectedStopName = null;
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
                      point: LatLng(stop['lat'], stop['lng']), 
                      width: isSelected ? 50 : 40, height: isSelected ? 50 : 40,
                      child: GestureDetector(onTap: () => _moveToStop(stop), child: _buildStopMarker(isSelected: isSelected)),
                    );
                  }),
                  Marker(point: _busLocation, width: 45, height: 45, child: _buildBusMarker()),
                ],
              ),
            ],
          ),
        ),

        if (_isLoadingStops)
          const Center(child: Card(child: Padding(padding: EdgeInsets.all(16.0), child: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(width: 16), Text("กำลังโหลดป้ายรถ...")])))),

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
                    IconButton(icon: const Icon(Icons.logout, color: Color(0xFF595C5D), size: 26), onPressed: _logout)
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          top: 130, left: 20, right: 20,
          child: Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (_isLoadingStops) return const Iterable<Map<String, dynamic>>.empty();
              if (textEditingValue.text.isEmpty) return busStops; 
              return busStops.where((stop) => stop['name'].toString().toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            displayStringForOption: (option) => option['name'],
            onSelected: (selection) => _moveToStop(selection),
            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))]),
                child: TextField(
                  controller: controller, 
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: _isLoadingStops ? 'กำลังโหลดข้อมูล...' : 'ค้นหาจุดจอดรถ...', 
                    hintStyle: const TextStyle(color: Color(0xFF757778), fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF757778)), 
                    border: InputBorder.none, 
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    suffixIcon: controller.text.isNotEmpty && !isWaiting 
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF757778), size: 20), 
                            onPressed: () { 
                              controller.clear(); 
                              setState(() {
                                selectedStopName = null;
                                highlightedPath.clear(); 
                              }); 
                            },
                          ) 
                        : null,
                  ),
                  onChanged: (value) => setState(() {}), 
                  enabled: !_isLoadingStops && !isWaiting, 
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
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), child: Text('#จุดเรียกรถทั้งหมด', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500))),
                        Divider(height: 1, color: Colors.grey.shade200),
                        Flexible(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            shrinkWrap: true,
                            itemCount: sortedOptions.length,
                            itemBuilder: (context, index) {
                              final option = sortedOptions[index];
                              final bool isFav = favoriteStops.contains(option['name']);

                              return Material(
                                color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                                child: InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, color: Color(0xFF176a21), size: 22),
                                        const SizedBox(width: 16),
                                        Expanded(child: Text(option['name'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF2C2F30)))),
                                        GestureDetector(
                                          onTap: () => _toggleFavorite(option['name']), 
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              isFav ? Icons.star : Icons.star_border, 
                                              color: isFav ? Colors.amber : Colors.grey.shade400, 
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

        if (selectedStopName != null)
          Positioned(
            bottom: 90, left: 0, right: 0, 
            child: AnimatedOpacity(
              opacity: selectedStopName != null ? 1.0 : 0.0, 
              duration: const Duration(milliseconds: 300), 
              child: _buildStopDetailsCard(),
            ),
          ),
      ],
    );
  }
  
  Widget _buildNavItem({required IconData icon, required String label, required int index}) {
    bool isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Widget _buildBusMarker() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]), 
      padding: const EdgeInsets.all(4), 
      child: Container(decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle), child: const Icon(Icons.directions_bus, color: Colors.white, size: 20)),
    );
  }

  Widget _buildStopDetailsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: const Color(0xFF2C2F30).withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFEFF1F2), borderRadius: BorderRadius.circular(20)), child: const Text('จุดจอดรถรับส่ง', style: TextStyle(color: Color(0xFF595C5D), fontWeight: FontWeight.bold, fontSize: 12))),
              if (!isWaiting) 
                GestureDetector(
                  onTap: () => setState(() {
                    selectedStopName = null;
                    highlightedPath.clear(); 
                  }), 
                  child: const Icon(Icons.close, color: Color(0xFF757778)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(selectedStopName ?? '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF2C2F30))),
          const SizedBox(height: 8),
          
          if (isWaiting)
            const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)), SizedBox(width: 10), Text('กำลังส่งสัญญาณเรียกคนขับ...', style: TextStyle(fontSize: 14, color: Colors.orange, fontWeight: FontWeight.bold))])
          else
            const Row(children: [Icon(Icons.directions_bus, size: 16, color: Color(0xFF176a21)), SizedBox(width: 8), Text('รถรับส่ง สาย A กำลังวิ่งให้บริการ', style: TextStyle(fontSize: 14, color: Color(0xFF176a21), fontWeight: FontWeight.w500))]),
            
          const SizedBox(height: 24),
          
          GestureDetector(
            onTap: _toggleWaitState,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300), width: double.infinity, height: 56,
              decoration: BoxDecoration(gradient: LinearGradient(colors: isWaiting ? [Colors.red.shade400, Colors.red.shade600] : [const Color(0xFF9DF197), const Color(0xFF176a21)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: (isWaiting ? Colors.red : const Color(0xFF176a21)).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, 
                  children: [
                    Icon(isWaiting ? Icons.cancel : Icons.waving_hand, color: Colors.white, size: 20), 
                    const SizedBox(width: 10), 
                    Text(isWaiting ? 'ยกเลิกการรอรถ' : 'แจ้งรอรถที่จุดนี้', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}