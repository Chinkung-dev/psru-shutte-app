import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart' hide Path;
import '../../widgets/app_loading_view.dart';
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
  StreamSubscription? _rtdbSub;
  Map<String, Map<dynamic, dynamic>> _rtdbShuttles = {};
  List<Map<String, dynamic>> _shuttleList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToShuttles();
  }

  void _listenToShuttles() {
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

    // ดึงข้อมูลจาก Realtime Database (RTDB) เป็นหลัก
    _rtdbShuttles.forEach((rtdbKey, rtdbDoc) {
      final String name = (rtdbDoc['name'] ?? 'Shuttle').toString();
      final String number = (rtdbDoc['number'] ?? '').toString();

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
          isOnline = true;
        }
      }

      final String status = isOnline ? 'online' : 'offline';
      final String passengerStatus = isOnline
          ? (rtdbDoc['passenger_status'] ?? 'available').toString()
          : 'offline';

      final double lat = (rtdbDoc['lat'] as num?)?.toDouble() ?? 16.82753;
      final double lng = (rtdbDoc['lng'] as num?)?.toDouble() ?? 100.20686;

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

      final driverName = (rtdbDoc['driver_name'] ?? 'คนขับรถประจำคัน').toString();
      final driverAvatar = (rtdbDoc['driver_avatar'] ?? 'assets/images/man1.png').toString();

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
    });

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
    _rtdbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppLoadingView(
        isScaffold: true,
        message: 'กำลังโหลดสถานะรถรับส่งสด...',
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
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมเขียวมิ้นต์อ่อนๆ ช่วยขับให้การ์ดดูมีมิติ
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
                      // Hero Card (รถรับส่งทั้งหมด)
                      _buildHeroCard(totalActive),
                      const SizedBox(height: 16),

                      // 4 Grid Cards (สถานะรถว่าง/เต็ม/พัก/ออฟไลน์)
                      _buildStatsGrid(availableCount, fullCount, breakCount, offlineCount),
                      
                      // Section Title (สถานะรถ + REAL-TIME)
                      _buildSectionTitle(),
                      
                      // รายการรถรับส่งแต่ละคัน
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

  // Header ดีไซน์ Curved Bottom Edge แบบเดียวกับหน้าหลัก
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF8FAF8),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.03),
          width: 1.0,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(
                'assets/images/LOGO02.png',
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      color: Color(0xFF176a21),
                      size: 26,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'PSRU Shuttle',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 42),
            ],
          ),
        ),
      ),
    );
  }

  // Hero Card (ดีไซน์สีขาวอมมิ้นต์นุ่มนวล สบายตา ไม่ทึบ)
  Widget _buildHeroCard(int activeCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFEAF5ED),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF81C784).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'รถรับส่งที่กำลังให้บริการ',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF5A605B),
                    fontWeight: FontWeight.w600,
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
                        fontSize: 38,
                        height: 1,
                        color: Color(0xFF176a21),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: activeCount > 0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFF1F5F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: activeCount > 0
                              ? const Color(0xFF81C784).withValues(alpha: 0.6)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        activeCount > 0 ? 'คัน พร้อมรับส่ง ' : 'ยังไม่มีรถออนไลน์',
                        style: TextStyle(
                          fontSize: 12,
                          color: activeCount > 0
                              ? const Color(0xFF1B5E20)
                              : const Color(0xFF757778),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF81C784).withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: Color(0xFF176a21),
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  // 4 Grid Cards (สถานะรถพร้อมกรอบสีพาสเทลนุ่มนวล)
  Widget _buildStatsGrid(
      int available, int full, int breakTime, int offline) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = (constraints.maxWidth - 14) / 2;
        const double targetHeight = 88.0;
        final double aspectRatio = itemWidth / targetHeight;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: aspectRatio,
          children: [
            _buildStatCard(
              'รถว่างพร้อมรับ',
              available,
              Icons.check_circle_rounded,
              const Color(0xFF176a21),
              const Color(0xFFE8F5E9),
              const Color(0xFF81C784).withValues(alpha: 0.4),
            ),
            _buildStatCard(
              'รถเต็มชั่วคราว',
              full,
              Icons.people_alt_rounded,
              const Color(0xFFD32F2F),
              const Color(0xFFFFEBEE),
              const Color(0xFFEF9A9A).withValues(alpha: 0.4),
            ),
            _buildStatCard(
              'เวลาพักเบรค',
              breakTime,
              Icons.pause_circle_rounded,
              const Color(0xFFF57C00),
              const Color(0xFFFFF3E0),
              const Color(0xFFFFCC80).withValues(alpha: 0.4),
            ),
            _buildStatCard(
              'นอกเวลางาน',
              offline,
              Icons.power_settings_new_rounded,
              const Color(0xFF5A605B),
              const Color(0xFFF1F5F2),
              Colors.black.withValues(alpha: 0.06),
            ),
          ],
        );
      },
    );
  }

  // Card ย่อยใน Grid
  Widget _buildStatCard(
    String title,
    int count,
    IconData icon,
    Color color,
    Color bgIconColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgIconColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF5A605B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Section Title
  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'สถานะรถรับส่ง',
            style: TextStyle(
              color: Color(0xFF2C2F30),
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF81C784).withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Color(0xFF176a21), size: 14),
                SizedBox(width: 2),
                Text(
                  'REAL-TIME',
                  style: TextStyle(
                    color: Color(0xFF176a21),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // การ์ดแสดงสถานะรถแต่ละคัน (พร้อมกรอบเขียวมรกตและเงาลอย)
  Widget _buildShuttleCard(Map<String, dynamic> shuttle) {
    final String badgeText = shuttle['badgeText'];
    final String passengerStatus = shuttle['passengerStatus'];
    final bool isOnline = shuttle['isOnline'];
    final String nearestStopName = shuttle['nearestStopName'];
    final int etaMinutes = shuttle['etaMinutes'];

    // กำหนดสีจุดสถานะและข้อความ
    Color dotColor = Colors.grey;
    String subtitleText = 'นอกเวลางาน (ออฟไลน์)';
    Color subtitleColor = const Color(0xFF757778);

    if (isOnline) {
      if (passengerStatus == 'available') {
        dotColor = const Color(0xFF22C55E); // เขียว
        subtitleText = 'กำลังมุ่งหน้าไปที่ $nearestStopName';
        subtitleColor = const Color(0xFF595C5D);
      } else if (passengerStatus == 'full') {
        dotColor = const Color(0xFFE53935); // แดง
        subtitleText = 'กำลังมุ่งหน้าไปที่ $nearestStopName (รถเต็ม)';
        subtitleColor = const Color(0xFFE53935);
      } else if (passengerStatus == 'break') {
        dotColor = const Color(0xFFF57C00); // ส้ม
        subtitleText = 'คนขับกำลังพักเบรค';
        subtitleColor = const Color(0xFFF57C00);
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isOnline
                ? const Color(0xFF81C784).withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.04),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isOnline
                  ? const Color(0xFF176a21).withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.02),
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
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isOnline && passengerStatus == 'available'
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF1F5F2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_bus_rounded,
                    color: isOnline && passengerStatus == 'available'
                        ? const Color(0xFF176a21)
                        : Colors.grey[600],
                    size: 24,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            // รายละเอียดชื่อและจุดหมาย
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2F30),
                        ),
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitleText,
                    style: TextStyle(
                      fontSize: 13,
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
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'ETA',
                    style: TextStyle(
                      color: Color(0xFF757778),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  passengerStatus == 'break' ? 'พักเบรค' : 'ออฟไลน์',
                  style: const TextStyle(
                    color: Color(0xFF757778),
                    fontSize: 11.5,
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


