import 'dart:async';
import '../../services/shuttle_heading.dart';
import '../../widgets/shuttle_map_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../route_data.dart';
import '../../widgets/shuttle_3d_layer.dart';

/// หน้าจอทดสอบและพิสูจน์แนวคิดการเรนเดอร์ 3D (Phase 1 PoC)
class Shuttle3DPocScreen extends StatefulWidget {
  const Shuttle3DPocScreen({super.key});

  @override
  State<Shuttle3DPocScreen> createState() => _Shuttle3DPocScreenState();
}

class _SimulatedShuttle {
  final String id;
  final String label;
  LatLng position;
  double bearing;
  String status;
  int pathIndex;
  final bool isStatic;

  _SimulatedShuttle({
    required this.id,
    required this.label,
    required this.position,
    required this.bearing,
    required this.status,
    required this.pathIndex,
    this.isStatic = false,
  });
}

class _Shuttle3DPocScreenState extends State<Shuttle3DPocScreen> {
  final MapController _mapController = MapController();

  // พิกัดจุดจอดจำลองสำหรับทดสอบ Gesture
  final List<Map<String, dynamic>> _mockStops = [
    {
      'id': 'stop_1',
      'name': 'ป้าย 1 ประตูหน้า มรภ.',
      'lat': 16.82587080,
      'lng': 100.21657700,
    },
    {
      'id': 'stop_2',
      'name': 'ป้าย 2 คณะวิทยาการจัดการ',
      'lat': 16.82801460,
      'lng': 100.21605000,
    },
    {
      'id': 'stop_3',
      'name': 'ป้าย 3 อาคารกิจกรรมนักศึกษา',
      'lat': 16.83231830,
      'lng': 100.21405840,
    },
  ];

  // พิกัดเส้นทางจำลองสำหรับให้รถวิ่ง
  late List<LatLng> _simRoute;
  Timer? _driveTimer;
  bool _isDriving = false;
  bool _showWireframe = false;

  // รายการรถทดสอบจำลอง 5 คัน
  final List<_SimulatedShuttle> _shuttles = [];

  // สถานะกล้องสำหรับส่งให้ 3D Layer
  bool _modelReady = false;
  bool _enable3D = true;

  @override
  void initState() {
    super.initState();
    _initRoute();
  }

  void _initRoute() {
    if (shuttleRoutes.isNotEmpty && shuttleRoutes[0].isNotEmpty) {
      _simRoute = shuttleRoutes[0];
    } else {
      _simRoute = [
        const LatLng(16.82587080, 100.21657700),
        const LatLng(16.82801460, 100.21605000),
        const LatLng(16.83231830, 100.21405840),
      ];
    }

    _shuttles.clear();
    final routeLen = _simRoute.length;

    // สร้างข้อมูลรถจำลอง 5 คัน กระจายตามจุดต่างๆ บนเส้นทางของ มรภ.พิบูลสงคราม
    _shuttles.addAll([
      _SimulatedShuttle(
        id: 'shuttle_1',
        label: '01',
        position: _simRoute[0],
        bearing: routeLen > 1 ? shuttleBearing(_simRoute[0], _simRoute[1]) : 0.0,
        status: 'available',
        pathIndex: 0,
      ),
      _SimulatedShuttle(
        id: 'shuttle_2',
        label: '02',
        position: _simRoute[(routeLen * 0.25).floor() % routeLen],
        bearing: routeLen > 1
            ? shuttleBearing(
                _simRoute[(routeLen * 0.25).floor() % routeLen],
                _simRoute[((routeLen * 0.25).floor() + 1) % routeLen],
              )
            : 0.0,
        status: 'full',
        pathIndex: (routeLen * 0.25).floor() % routeLen,
      ),
      _SimulatedShuttle(
        id: 'shuttle_3',
        label: '03',
        position: _simRoute[(routeLen * 0.50).floor() % routeLen],
        bearing: routeLen > 1
            ? shuttleBearing(
                _simRoute[(routeLen * 0.50).floor() % routeLen],
                _simRoute[((routeLen * 0.50).floor() + 1) % routeLen],
              )
            : 0.0,
        status: 'available',
        pathIndex: (routeLen * 0.50).floor() % routeLen,
      ),
      _SimulatedShuttle(
        id: 'shuttle_4',
        label: '04',
        position: _simRoute[(routeLen * 0.70).floor() % routeLen],
        bearing: 120.0,
        status: 'break',
        pathIndex: (routeLen * 0.70).floor() % routeLen,
        isStatic: true,
      ),
      _SimulatedShuttle(
        id: 'shuttle_5',
        label: '05',
        position: _simRoute[(routeLen * 0.85).floor() % routeLen],
        bearing: routeLen > 1
            ? shuttleBearing(
                _simRoute[(routeLen * 0.85).floor() % routeLen],
                _simRoute[((routeLen * 0.85).floor() + 1) % routeLen],
              )
            : 0.0,
        status: 'available',
        pathIndex: (routeLen * 0.85).floor() % routeLen,
      ),
    ]);
  }

  @override
  void dispose() {
    _driveTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// สลับการจำลองรถวิ่งตามเส้นทางสำหรับรถที่กำลังให้บริการ
  void _toggleSimulation() {
    if (_isDriving) {
      _driveTimer?.cancel();
      if (mounted) {
        setState(() {
          _isDriving = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isDriving = true;
        });
      }
      _driveTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          for (final shuttle in _shuttles) {
            if (shuttle.isStatic) continue;
            final nextIndex = (shuttle.pathIndex + 1) % _simRoute.length;
            final nextPos = _simRoute[nextIndex];
            shuttle.bearing = shuttleBearing(shuttle.position, nextPos);
            shuttle.position = nextPos;
            shuttle.pathIndex = nextIndex;
          }
        });
      });
    }
  }

  /// หมุนรถ 45 องศาเพื่อทดสอบการเปลี่ยนทิศ
  void _rotateManual() {
    setState(() {
      for (final shuttle in _shuttles) {
        shuttle.bearing = (shuttle.bearing + 45.0) % 360.0;
      }
    });
  }

  /// สลับสถานะรถ (ว่าง / เต็ม / พัก / ออฟไลน์)
  void _cycleStatus() {
    setState(() {
      for (final shuttle in _shuttles) {
        if (shuttle.status == 'available') {
          shuttle.status = 'full';
        } else if (shuttle.status == 'full') {
          shuttle.status = 'break';
        } else if (shuttle.status == 'break') {
          shuttle.status = 'offline';
        } else {
          shuttle.status = 'available';
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // เตรียมข้อมูลรถ 3D ทั้ง 5 คัน สำหรับส่งให้ Shuttle3DLayer
    final shuttles3D = _shuttles.map((s) {
      return Shuttle3DObjectData(
        id: s.id,
        position: s.position,
        bearing: s.bearing,
        status: s.status,
        label: s.label,
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ทดสอบรถ PSRU 3D',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF176A21),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'สลับรถ 3D / หมุดสำรอง',
            icon: Icon(_enable3D ? Icons.view_in_ar : Icons.directions_bus),
            onPressed: () => setState(() {
              _enable3D = !_enable3D;
              _modelReady = false;
            }),
          ),
          IconButton(
            icon: Icon(_showWireframe ? Icons.grid_on : Icons.grid_off),
            tooltip: 'โหมด Wireframe',
            onPressed: () {
              setState(() {
                _showWireframe = !_showWireframe;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. แผนที่พื้นฐาน FlutterMap (OpenStreetMap)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(16.8285, 100.2155),
              initialZoom: 16.2,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.psru_shuttle_app',
              ),
              // วาดเส้นทางถนนสีเขียวโปร่งใส
              PolylineLayer(
                polylines: shuttleRoutes.map((seg) {
                  return Polyline(
                    points: seg,
                    strokeWidth: 5.0,
                    color: const Color(0xFF176A21).withValues(alpha: 0.4),
                  );
                }).toList(),
              ),
              if (_enable3D)
                Builder(
                  builder: (context) => Shuttle3DLayer(
                    mapCamera: MapCamera.of(context),
                    shuttles: shuttles3D,
                    showWireframe: _showWireframe,
                    onReadyChanged: (ready) {
                      if (mounted && _modelReady != ready) {
                        setState(() => _modelReady = ready);
                      }
                    },
                  ),
                ),
              // หมุดป้ายจุดจอดจำลอง (สำหรับทดสอบการแตะบนแผนที่)
              MarkerLayer(
                markers: _mockStops.map((stop) {
                  return Marker(
                    point: LatLng(stop['lat'] as double, stop['lng'] as double),
                    width: 140,
                    height: 50,
                    child: GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'แตะหมุดสำเร็จ: ${stop['name']} (Gesture ผ่าน 100%)',
                            ),
                            duration: const Duration(seconds: 2),
                            backgroundColor: const Color(0xFF176A21),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF176A21),
                                width: 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 3),
                              ],
                            ),
                            child: Text(
                              stop['name'].toString(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF176A21),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(
                            Icons.location_on,
                            color: Color(0xFF176A21),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              // ป้าย 2D ประจำรถทั้ง 5 คัน ที่ลอยอยู่เหนือตัวรถ 3D
              MarkerLayer(
                markers: _shuttles.map((shuttle) {
                  return Marker(
                    point: shuttle.position,
                    width: 150,
                    height: 100,
                    rotate: true,
                    child: IgnorePointer(
                      child: ShuttleMapBadge(
                        number: shuttle.label,
                        status: shuttle.status,
                        showFallback: !_enable3D || !_modelReady,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // 3. แผงแจ้งสถานะการทดสอบด้านบน (HUD Card)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.verified,
                        color: Color(0xFF176A21),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'พรีวิวโมเดล PSRU (5 คัน)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF176A21),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF176A21).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'รถรับส่ง 5 คัน',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF176A21),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_enable3D && _modelReady ? "โหลดโมเดล GLB รถ 5 คันแล้ว" : "แสดงหมุดสำรอง"}\nกำลังวิ่ง ${_shuttles.where((s) => !s.isStatic).length} คัน, จอดพัก ${_shuttles.where((s) => s.isStatic).length} คัน',
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),

          // 4. แผงควบคุมการทดสอบด้านล่าง (Control Panel)
          Positioned(
            bottom: 20,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // ปุ่ม 1: วิ่ง/หยุดรถ
                  ElevatedButton.icon(
                    onPressed: _toggleSimulation,
                    icon: Icon(_isDriving ? Icons.pause : Icons.play_arrow),
                    label: Text(_isDriving ? 'หยุดวิ่ง' : 'จำลองรถวิ่ง'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDriving
                          ? Colors.orange
                          : const Color(0xFF176A21),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  // ปุ่ม 2: หมุนทิศทาง
                  OutlinedButton.icon(
                    onPressed: _rotateManual,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('หมุน +45°'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF176A21),
                      side: const BorderSide(color: Color(0xFF176A21)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  // ปุ่ม 3: สลับสถานะรถ
                  OutlinedButton.icon(
                    onPressed: _cycleStatus,
                    icon: const Icon(Icons.color_lens),
                    label: const Text('เปลี่ยนสี'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: const BorderSide(color: Colors.blueGrey),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
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
}
