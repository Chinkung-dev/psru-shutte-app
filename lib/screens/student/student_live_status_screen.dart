import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart' hide Path;
import 'student_chat_screen.dart';

class StudentLiveStatusScreen extends StatefulWidget {
  final List<Map<String, dynamic>> busStops;

  final Function(int)? onSelectTab;

  const StudentLiveStatusScreen({
    super.key,
    required this.busStops,
    this.onSelectTab,
  });

  @override
  State<StudentLiveStatusScreen> createState() => _StudentLiveStatusScreenState();
}

class _StudentLiveStatusScreenState extends State<StudentLiveStatusScreen> {
  StreamSubscription? _firestoreSub;
  StreamSubscription? _rtdbSub;
  List<Map<String, dynamic>> _firestoreShuttles = [];
  Map<String, Map<dynamic, dynamic>> _rtdbShuttles = {};
  List<Map<String, dynamic>> _shuttleList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToShuttles();
  }

  void _listenToShuttles() {
    _firestoreSub = FirebaseFirestore.instance.collection('shuttles').snapshots().listen((snapshot) {
      if (!mounted) return;
      _firestoreShuttles = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _mergeAndRefreshShuttles();
    });

    _rtdbSub = FirebaseDatabase.instance.ref('shuttles').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final Map<String, Map<dynamic, dynamic>> parsed = {};
        data.forEach((key, value) {
          if (value is Map) {
            parsed[key.toString()] = value;
          }
        });
        _rtdbShuttles = parsed;
      } else {
        _rtdbShuttles = {};
      }
      _mergeAndRefreshShuttles();
    });
  }

  void _mergeAndRefreshShuttles() {
    final Map<String, Map<String, dynamic>> shuttleMap = {};
    final now = DateTime.now();
    final Distance distance = Distance();

    // 1. ดึงข้อมูลจาก Realtime Database (RTDB) เป็นหลัก เพราะพิกัดและสถานะออนไลน์จริงจะอัปเดตที่ RTDB
    _rtdbShuttles.forEach((rtdbKey, rtdbDoc) {
      if (rtdbDoc is! Map) return;

      // ค้นหา Firestore doc ที่สอดคล้องกัน (ลองค้นหาด้วย ID, เลขคันรถ, หรือชื่อรถ)
      Map<String, dynamic>? matchingFsDoc;
      final String rtdbNumStr = (rtdbDoc['number'] ?? '').toString();
      final String rtdbCleanNum = rtdbNumStr.replaceAll(RegExp(r'[^0-9]'), '');
      final String rtdbNameStr = (rtdbDoc['name'] ?? '').toString();

      for (var fsDoc in _firestoreShuttles) {
        final String fsNumStr = (fsDoc['number'] ?? '').toString();
        final String fsCleanNum = fsNumStr.replaceAll(RegExp(r'[^0-9]'), '');
        final String fsNameStr = (fsDoc['name'] ?? '').toString();
        final String fsId = fsDoc['id'].toString();

        if (fsId == rtdbKey ||
            (fsCleanNum.isNotEmpty && rtdbCleanNum.isNotEmpty && fsCleanNum == rtdbCleanNum) ||
            (fsNameStr.isNotEmpty && fsNameStr == rtdbNameStr)) {
          matchingFsDoc = fsDoc;
          break;
        }
      }

      final String name =
          (rtdbDoc['name'] ?? matchingFsDoc?['name'] ?? 'Shuttle').toString();
      final String number =
          (rtdbDoc['number'] ?? matchingFsDoc?['number'] ?? '').toString();

      String cleanNum = number.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.isEmpty) {
        cleanNum = name.replaceAll(RegExp(r'[^0-9]'), '');
      }
      final String shuttleKey =
          cleanNum.isNotEmpty ? cleanNum : name.toLowerCase().trim();

      String rtdbStatus = (rtdbDoc['status'] ?? 'offline').toString();
      bool isOnline = false;

      if (rtdbStatus == 'online') {
        final lastUpdatedMillis = rtdbDoc['last_updated'];
        if (lastUpdatedMillis != null && lastUpdatedMillis is num) {
          final lastUpdated = DateTime.fromMillisecondsSinceEpoch(
            lastUpdatedMillis.toInt(),
          );
          if (now.difference(lastUpdated).inMinutes.abs() <= 5) {
            isOnline = true;
          }
        } else {
          // ถ้าสถานะเป็น online และเพิ่งอัปเดตเข้ามา ให้ถือว่า online
          isOnline = true;
        }
      }

      final String status = isOnline ? 'online' : 'offline';
      final String passengerStatus = isOnline
          ? (rtdbDoc['passenger_status'] ?? matchingFsDoc?['passenger_status'] ?? 'available').toString()
          : 'offline';

      final double lat = (rtdbDoc['lat'] as num?)?.toDouble() ??
          (matchingFsDoc?['lat'] as num?)?.toDouble() ??
          16.82753;
      final double lng = (rtdbDoc['lng'] as num?)?.toDouble() ??
          (matchingFsDoc?['lng'] as num?)?.toDouble() ??
          100.20686;

      final String badgeText =
          cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : name;

      String nearestStopName = "ภายในมหาวิทยาลัย";
      int etaMinutes = 3;

      if (widget.busStops.isNotEmpty) {
        double minDistance = double.infinity;
        final LatLng shuttlePos = LatLng(lat, lng);

        for (var stop in widget.busStops) {
          if (stop['lat'] != null && stop['lng'] != null) {
            double dist = distance.as(
              LengthUnit.Meter,
              shuttlePos,
              LatLng(stop['lat'], stop['lng']),
            );
            if (dist < minDistance) {
              minDistance = dist;
              nearestStopName = stop['name'] ?? 'จุดจอด';
            }
          }
        }
        if (minDistance != double.infinity) {
          etaMinutes = (minDistance / 350).round();
          if (etaMinutes < 1) etaMinutes = 1;
        }
      }

      final driverName = (rtdbDoc['driver_name'] ??
              matchingFsDoc?['driver_name'] ??
              'คนขับรถประจำคัน')
          .toString();
      final driverAvatar = (rtdbDoc['driver_avatar'] ??
              matchingFsDoc?['driver_avatar'] ??
              'assets/images/man1.png')
          .toString();

      if (!shuttleMap.containsKey(shuttleKey) || isOnline) {
        shuttleMap[shuttleKey] = {
          'shuttleId': rtdbKey.toString(),
          'name': name,
          'number': number,
          'cleanNum': cleanNum,
          'badgeText': badgeText,
          'driverName': driverName,
          'driverAvatar': driverAvatar,
          'status': status,
          'passengerStatus': passengerStatus,
          'isOnline': isOnline,
          'nearestStopName': nearestStopName,
          'etaMinutes': etaMinutes,
        };
      }
    });

    // 2. เติมเอกสารจาก Firestore ที่ยังไม่มีใน RTDB (รถออฟไลน์ที่ลงทะเบียนไว้ในระบบ)
    for (var fsDoc in _firestoreShuttles) {
      final String name = (fsDoc['name'] ?? fsDoc['id']).toString();
      final String number = (fsDoc['number'] ?? '').toString();
      String cleanNum = number.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.isEmpty) {
        cleanNum = name.replaceAll(RegExp(r'[^0-9]'), '');
      }
      final String shuttleKey =
          cleanNum.isNotEmpty ? cleanNum : name.toLowerCase().trim();

      if (!shuttleMap.containsKey(shuttleKey)) {
        final String badgeText =
            cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : name;

        shuttleMap[shuttleKey] = {
          'shuttleId': fsDoc['id'].toString(),
          'name': name,
          'number': number,
          'cleanNum': cleanNum,
          'badgeText': badgeText,
          'driverName': (fsDoc['driver_name'] ?? 'คนขับรถประจำคัน').toString(),
          'driverAvatar': (fsDoc['driver_avatar'] ?? 'assets/images/man1.png').toString(),
          'status': 'offline',
          'passengerStatus': 'offline',
          'isOnline': false,
          'nearestStopName': 'ภายในมหาวิทยาลัย',
          'etaMinutes': 3,
        };
      }
    }

    final List<Map<String, dynamic>> list = shuttleMap.values.toList();

    list.sort((a, b) {
      bool aOnline = a['isOnline'];
      bool bOnline = b['isOnline'];
      if (aOnline && !bOnline) return -1;
      if (!aOnline && bOnline) return 1;
      return (a['cleanNum'] as String).compareTo(b['cleanNum'] as String);
    });

    if (mounted) {
      setState(() {
        _shuttleList = list;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _rtdbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7F8),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF176a21)),
        ),
      );
    }

    int availableCount = 0;
    int fullCount = 0;
    int breakCount = 0;
    int offlineCount = 0;
    int totalActive = 0;

    for (var shuttle in _shuttleList) {
      final String passengerStatus = shuttle['passengerStatus'];
      if (passengerStatus == 'available') {
        availableCount++;
        totalActive++;
      } else if (passengerStatus == 'full') {
        fullCount++;
        totalActive++;
      } else if (passengerStatus == 'break') {
        breakCount++;
        totalActive++;
      } else {
        offlineCount++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8), // สีพื้นหลังเทาอ่อนสะอาดตาตามดีไซน์
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🌟 Hero Card (รถรับส่งทั้งหมด)
                      _buildHeroCard(totalActive),
                      const SizedBox(height: 16),

                      // 📊 4 Grid Cards (สถานะรถว่าง/เต็ม/พัก/ออฟไลน์)
                      _buildStatsGrid(availableCount, fullCount, breakCount, offlineCount),
                      
                      // 🏷️ Section Title (สถานะรถ + REAL-TIME)
                      _buildSectionTitle(),
                      
                      // 🚌 รายการรถรับส่งแต่ละคัน
                      if (_shuttleList.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Text(
                              'ยังไม่มีข้อมูลรถรับส่งในระบบ',
                              style: TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          ),
                        )
                      else
                        ..._shuttleList.map((shuttle) => _buildShuttleCard(shuttle)),
                      
                      const SizedBox(height: 100), // เว้นที่ว่างด้านล่างไม่ให้แถบเมนู (Bottom Nav) บังคันสุดท้าย
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Header 
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(
                'lib/screens/driver/logo.png',
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.menu, color: Color(0xFF176a21), size: 28),
              ),
              const SizedBox(width: 42), // เว้นที่ไว้แทนปุ่มที่เอาออกไป
            ],
          ),
        ),
      ),
    );
  }

  // 🌟 Hero Card
  Widget _buildHeroCard(int activeCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'รถรับส่งทั้งหมด',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF595C5D),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$activeCount',
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1,
                        color: Color(0xFF176a21),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF176a21),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Color(0xFF176a21),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  // 📊 4 Grid Cards (คำนวณความสูงให้เท่ากันพอดีและรองรับทุกขนาดหน้าจอ)
  Widget _buildStatsGrid(
      int available, int full, int breakTime, int offline) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = (constraints.maxWidth - 16) / 2;
        const double targetHeight = 88.0;
        final double aspectRatio = itemWidth / targetHeight;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: aspectRatio,
          children: [
            _buildStatCard(
                'รถว่าง', available, Icons.check_circle_outline, const Color(0xFF176a21)),
            _buildStatCard('รถเต็ม', full, Icons.block, const Color(0xFF595C5D)),
            _buildStatCard(
                'เวลาพักเบรค', breakTime, Icons.pause_circle_outline, const Color(0xFFF28522)),
            _buildStatCard(
                'นอกเวลางาน', offline, Icons.power_settings_new, const Color(0xFF595C5D)),
          ],
        );
      },
    );
  }

  // Card ย่อยใน Grid
  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF595C5D),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF2C2F30),
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // 🏷️ Section Title
  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'สถานะรถ',
            style: TextStyle(
              color: Color(0xFF2C2F30),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'REAL-TIME',
              style: TextStyle(
                color: Color(0xFF176a21),
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🚌 การ์ดแสดงสถานะรถแต่ละคัน
  Widget _buildShuttleCard(Map<String, dynamic> shuttle) {
    final String badgeText = shuttle['badgeText'];
    final String passengerStatus = shuttle['passengerStatus'];
    final bool isOnline = shuttle['isOnline'];
    final String nearestStopName = shuttle['nearestStopName'];
    final int etaMinutes = shuttle['etaMinutes'];

    // กำหนดสีจุดสถานะและข้อความ
    Color dotColor = Colors.grey;
    String subtitleText = 'นอกเวลางาน (ออฟไลน์)';
    Color subtitleColor = Colors.grey[600]!;

    if (isOnline) {
      if (passengerStatus == 'available') {
        dotColor = const Color(0xFF176a21); // เขียว
        subtitleText = 'กำลังมุ่งหน้าไปที่ $nearestStopName';
        subtitleColor = const Color(0xFF595C5D);
      } else if (passengerStatus == 'full') {
        dotColor = const Color(0xFF757778); // เทาเข้ม
        subtitleText = 'กำลังมุ่งหน้าไปที่ $nearestStopName (รถเต็ม)';
        subtitleColor = const Color(0xFFE53935);
      } else if (passengerStatus == 'break') {
        dotColor = const Color(0xFFF28522); // ส้ม
        subtitleText = 'คนขับกำลังพักเบรค';
        subtitleColor = const Color(0xFFF28522);
      } else {
        dotColor = Colors.grey;
        subtitleText = 'นอกเวลางาน';
        subtitleColor = Colors.grey[600]!;
      }
    }

    final bool showEta = isOnline && (passengerStatus == 'available' || passengerStatus == 'full');

    return GestureDetector(
      onTap: () {
        // กดที่การ์ดรถเพื่อไปหน้าแชทกับคนขับคันนั้นทันที
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentChatScreen(
              shuttleId: shuttle['shuttleId'],
              shuttleName: shuttle['name'],
              driverName: shuttle['driverName'],
              driverAvatar: shuttle['driverAvatar'],
              onSelectTab: widget.onSelectTab,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // ไอคอนรถพร้อมจุดสถานะ (Dot badge)
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isOnline && passengerStatus == 'available'
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF5F7F8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_bus,
                    color: isOnline && passengerStatus == 'available'
                        ? const Color(0xFF176a21)
                        : Colors.grey[600],
                    size: 26,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // รายละเอียดชื่อและจุดหมาย
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2F30),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitleText,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // เวลา ETA หรือสถานะ
            if (showEta)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$etaMinutes นาที',
                    style: const TextStyle(
                      color: Color(0xFF176a21),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'ETA',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  passengerStatus == 'break' ? 'พักเบรค' : 'ออฟไลน์',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

