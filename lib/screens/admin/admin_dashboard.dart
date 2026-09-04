import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../route_data.dart';
import 'admin_live_map.dart';
import 'admin_drivers_tab.dart';
import 'admin_students_tab.dart';
import 'admin_analytics_tab.dart';
import 'admin_profile_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0; // เริ่มต้นที่หน้าภาพรวมระบบ

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 960;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF2F6F3),
      drawer: isDesktop
          ? null
          : Drawer(
              child: AdminSidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: (index) {
                  setState(() => _selectedIndex = index);
                  if (!isDesktop) Navigator.pop(context);
                },
              ),
            ),
      body: Row(
        children: [
          if (isDesktop)
            AdminSidebar(
              selectedIndex: _selectedIndex,
              onItemSelected: (index) {
                setState(() => _selectedIndex = index);
              },
            ),
          Expanded(
            child: _selectedIndex == 0
                ? const AdminDashboardOverview()
                : _selectedIndex == 1
                ? const AdminLiveMapTab()
                : _selectedIndex == 2
                ? const AdminDriversTab()
                : _selectedIndex == 3
                ? const AdminStudentsTab()
                : const AdminAnalyticsTab(),
          ),
        ],
      ),
    );
  }
}

class AdminDashboardOverview extends StatefulWidget {
  const AdminDashboardOverview({super.key});

  @override
  State<AdminDashboardOverview> createState() => _AdminDashboardOverviewState();
}

class _AdminDashboardOverviewState extends State<AdminDashboardOverview> {
  int availableCount = 0;
  int fullCount = 0;
  int breakCount = 0;
  int offlineCount = 0;
  List<Map<String, dynamic>> activeShuttleList = [];

  int passengersToday = 0;
  double avgWaitTimeMins = 0.0;

  StreamSubscription? _shuttlesSub;
  StreamSubscription? _rtdbSub;
  StreamSubscription? _ridesSub;
  StreamSubscription? _analyticsSub;

  List<Map<String, dynamic>> _firestoreShuttles = [];
  Map<String, Map<dynamic, dynamic>> _rtdbShuttles = {};

  @override
  void initState() {
    super.initState();
    _listenToShuttles();
    _listenToRideRequests();
  }

  void _listenToShuttles() {
    _shuttlesSub = FirebaseFirestore.instance
        .collection('shuttles')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _firestoreShuttles =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _mergeAndRefreshShuttles();
    }, onError: (e) {
      debugPrint("Firestore Error (shuttles): $e");
    });

    _rtdbSub = FirebaseDatabase.instance.ref('shuttles').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value is Map) {
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
    }, onError: (e) {
      debugPrint("RTDB Error (shuttles): $e");
    });
  }

  void _mergeAndRefreshShuttles() {
    int a = 0, f = 0, b = 0, o = 0;
    final now = DateTime.now();
    final Map<String, Map<String, dynamic>> shuttleMap = {};

    _rtdbShuttles.forEach((rtdbKey, rtdbDoc) {
      Map<String, dynamic>? matchingFsDoc;
      for (var fsDoc in _firestoreShuttles) {
        if (fsDoc['id'] == rtdbKey ||
            (fsDoc['number'] != null &&
                fsDoc['number'].toString() == rtdbDoc['number']?.toString()) ||
            (fsDoc['name'] != null &&
                fsDoc['name'].toString() == rtdbDoc['name']?.toString())) {
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
          isOnline = true;
        }
      }

      String pStatus = isOnline
          ? (rtdbDoc['passenger_status'] ??
                  matchingFsDoc?['passenger_status'] ??
                  'available')
              .toString()
          : 'offline';

      final String driverName = (rtdbDoc['driver_name'] ??
              matchingFsDoc?['driver_name'] ??
              'คนขับรถประจำคัน')
          .toString();
      final String driverAvatar = (rtdbDoc['driver_avatar'] ??
              matchingFsDoc?['driver_avatar'] ??
              '')
          .toString();
      final double lat = (rtdbDoc['lat'] as num?)?.toDouble() ??
          (matchingFsDoc?['lat'] as num?)?.toDouble() ??
          16.82753;
      final double lng = (rtdbDoc['lng'] as num?)?.toDouble() ??
          (matchingFsDoc?['lng'] as num?)?.toDouble() ??
          100.20686;

      shuttleMap[shuttleKey] = {
        'id': rtdbKey.toString(),
        'name': name,
        'number': number,
        'cleanNum': cleanNum,
        'status': isOnline ? 'online' : 'offline',
        'passenger_status': pStatus,
        'driver_name': driverName,
        'driver_avatar': driverAvatar,
        'capacity_percent': rtdbDoc['capacity_percent'] ??
            matchingFsDoc?['capacity_percent'] ??
            0,
        'lat': lat,
        'lng': lng,
      };
    });

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
        shuttleMap[shuttleKey] = {
          'id': fsDoc['id'].toString(),
          'name': name,
          'number': number,
          'cleanNum': cleanNum,
          'status': 'offline',
          'passenger_status': 'offline',
          'driver_name': (fsDoc['driver_name'] ?? 'คนขับรถประจำคัน').toString(),
          'driver_avatar': (fsDoc['driver_avatar'] ?? '').toString(),
          'capacity_percent': fsDoc['capacity_percent'] ?? 0,
          'lat': (fsDoc['lat'] as num?)?.toDouble() ?? 16.82753,
          'lng': (fsDoc['lng'] as num?)?.toDouble() ?? 100.20686,
        };
      }
    }

    List<Map<String, dynamic>> list = shuttleMap.values.toList();

    list.sort((a, b) {
      bool aOnline = a['status'] == 'online';
      bool bOnline = b['status'] == 'online';
      if (aOnline && !bOnline) return -1;
      if (!aOnline && bOnline) return 1;
      return (a['cleanNum'] as String).compareTo(b['cleanNum'] as String);
    });

    for (var shuttle in list) {
      String status = shuttle['status'];
      String pStatus = shuttle['passenger_status'];

      if (status == 'online') {
        if (pStatus == 'full') {
          f++;
        } else if (pStatus == 'break') {
          b++;
        } else {
          a++;
        }
      } else {
        o++;
      }
    }

    if (mounted) {
      setState(() {
        availableCount = a;
        fullCount = f;
        breakCount = b;
        offlineCount = o;
        activeShuttleList = list;
      });
    }
  }

  void _listenToRideRequests() {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    _analyticsSub = FirebaseFirestore.instance
        .collection('analytics')
        .doc('daily_stats_$dateStr')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final int totalPass =
            ((data['total_passengers'] ?? data['total_requests'] ?? 0) as num)
                .toInt();
        final num totalWaitSec = (data['total_wait_seconds'] ?? 0) as num;
        final int boardedCount =
            ((data['boarded_count'] ?? 0) as num).toInt();
        final int ackCount =
            ((data['acknowledged_requests_count'] ?? 0) as num).toInt();

        // ใช้นับจำนวนรอบที่ขึ้นรถจริง (boarded_count) เป็นหลัก หากยังไม่มีให้ใช้ ackCount
        final int tripCount = boardedCount > 0 ? boardedCount : ackCount;

        double avgMins = 0.0;
        if (tripCount > 0 && totalWaitSec > 0) {
          avgMins = (totalWaitSec / tripCount) / 60.0;
        }

        setState(() {
          passengersToday = totalPass;
          avgWaitTimeMins = avgMins;
        });
      }
    });

    _ridesSub = FirebaseFirestore.instance
        .collection('ride_requests')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (passengersToday == 0 && snapshot.docs.isNotEmpty) {
        setState(() {
          passengersToday = snapshot.docs.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _shuttlesSub?.cancel();
    _rtdbSub?.cancel();
    _ridesSub?.cancel();
    _analyticsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 960;

    return CustomScrollView(
      slivers: [
        if (!isDesktop)
          SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF176a21)),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            title: const Text(
              'ศูนย์ควบคุมภาพรวม',
              style: TextStyle(
                color: Color(0xFF176a21),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        if (isDesktop)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: DashboardHeader(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const FleetOverviewTitle(),
              const SizedBox(height: 20),
              StatsRowWidget(
                availableCount: availableCount,
                fullCount: fullCount,
                breakCount: breakCount,
                offlineCount: offlineCount,
                passengersToday: passengersToday,
                avgWaitTimeMins: avgWaitTimeMins,
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: LeftColumnContent(
                            activeShuttles: activeShuttleList,
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(
                          flex: 6,
                          child: RightColumnContent(),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        LeftColumnContent(activeShuttles: activeShuttleList),
                        const SizedBox(height: 24),
                        const RightColumnContent(),
                      ],
                    );
                  }
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ส่วนหัว Sidebar แสดงโลโก้แบบเดิม
          Padding(
            padding: const EdgeInsets.only(
              top: 24.0,
              left: 24.0,
              right: 24.0,
              bottom: 16.0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'lib/screens/driver/logo.png',
                width: 140,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEFF2F0)),
          const SizedBox(height: 16),

          // รายการเมนูหลัก
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _buildNavItem(
                  icon: Icons.dashboard_rounded,
                  title: 'ภาพรวมระบบ',
                  subtitle: 'Dashboard',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.map_rounded,
                  title: 'แผนที่ติดตามสด',
                  subtitle: 'Live Map',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.badge_rounded,
                  title: 'จัดการคนขับรถ',
                  subtitle: 'Drivers',
                  index: 2,
                ),
                _buildNavItem(
                  icon: Icons.school_rounded,
                  title: 'จัดการนักศึกษา',
                  subtitle: 'Students',
                  index: 3,
                ),
                _buildNavItem(
                  icon: Icons.insights_rounded,
                  title: 'รายงานและสถิติ',
                  subtitle: 'Analytics',
                  index: 4,
                ),
              ],
            ),
          ),

          // ส่วนท้าย Sidebar: โปรไฟล์ & ออกจากระบบ
          const Divider(height: 1, color: Color(0xFFEFF2F0)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AdminProfileDialog(),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F6F3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF176a21).withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF176a21),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ผู้ดูแลระบบ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF2C2F30),
                                ),
                              ),
                              Text(
                                'จัดการโปรไฟล์',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF718076),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF718076),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: const Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'ยืนยันการออกจากระบบ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          content: const Text(
                            'คุณต้องการออกจากระบบผู้ดูแลใช่หรือไม่?',
                            style: TextStyle(fontSize: 14),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text(
                                'ยกเลิก',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('ออกจากระบบ'),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirm == true) {
                      try {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        debugPrint("Sign out error: $e");
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'ออกจากระบบ',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required int index,
  }) {
    final isActive = selectedIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF176a21) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF176a21).withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(
          icon,
          color: isActive ? Colors.white : const Color(0xFF5A605B),
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF2C2F30),
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isActive
                ? Colors.white.withOpacity(0.8)
                : const Color(0xFF8A938C),
            fontSize: 11,
          ),
        ),
        onTap: () => onItemSelected(index),
      ),
    );
  }
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
              Icons.dashboard_rounded,
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
                'ศูนย์ควบคุมภาพรวม',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF176a21),
                ),
              ),
              Text(
                'PSRU Smart Campus Transportation',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5A605B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 260,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F6F3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF176a21).withOpacity(0.12),
              ),
            ),
            child: TextField(
              style: const TextStyle(color: Color(0xFF2C2F30), fontSize: 13),
              decoration: InputDecoration(
                hintText: 'ค้นหาข้อมูลในระบบ...',
                hintStyle: const TextStyle(
                  color: Color(0xFF718076),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF176a21),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 16),
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
    );
  }
}

class FleetOverviewTitle extends StatelessWidget {
  const FleetOverviewTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ภาพรวมระบบรถรับส่ง',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2923),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ติดตามสถานะรถ ความหนาแน่น และเวลาการรอแบบเรียลไทม์',
              style: TextStyle(
                color: const Color(0xFF5A605B).withOpacity(0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF176a21).withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF176a21),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ระบบทำงานปกติ (Live)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF176a21),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StatsRowWidget extends StatelessWidget {
  final int availableCount;
  final int fullCount;
  final int breakCount;
  final int offlineCount;
  final int passengersToday;
  final double avgWaitTimeMins;

  const StatsRowWidget({
    super.key,
    required this.availableCount,
    required this.fullCount,
    required this.breakCount,
    required this.offlineCount,
    required this.passengersToday,
    required this.avgWaitTimeMins,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double spacing = 16.0;
        int columns = 3;
        if (constraints.maxWidth < 650) {
          columns = 1;
        } else if (constraints.maxWidth < 980) {
          columns = 2;
        }

        final double cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildFleetStatusCard(),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                label: 'ผู้ใช้บริการสะสมวันนี้',
                icon: Icons.people_alt_rounded,
                iconColor: const Color(0xFF176a21),
                iconBgColor: const Color(0xFFE8F5E9),
                badgeText: 'รวมวันนี้',
                value: passengersToday.toString(),
                unit: ' คน',
                gradientColors: const [Color(0xFF176a21), Color(0xFF66BB6A)],
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                label: 'เวลารอรถเฉลี่ย',
                icon: Icons.hourglass_top_rounded,
                iconColor: const Color(0xFF0288D1),
                iconBgColor: const Color(0xFFE1F5FE),
                badgeText: 'นาที/คน',
                value: avgWaitTimeMins.toStringAsFixed(1),
                unit: ' นาที',
                gradientColors: const [Color(0xFF0288D1), Color(0xFF4FC3F7)],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String badgeText,
    required String value,
    String? unit,
    required List<Color> gradientColors,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: iconBgColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6F3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            color: Color(0xFF176a21),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF718076),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                      if (unit != null)
                        Text(
                          unit,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF718076),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetStatusCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'สถานะรถรับส่งทั้งหมด',
                    style: TextStyle(
                      color: Color(0xFF718076),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          icon: Icons.directions_bus_rounded,
                          color: const Color(0xFF176a21),
                          bgColor: const Color(0xFFE8F5E9),
                          value: availableCount.toString(),
                          label: 'กำลังวิ่ง',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMiniStat(
                          icon: Icons.groups_rounded,
                          color: const Color(0xFFE65100),
                          bgColor: const Color(0xFFFFF3E0),
                          value: fullCount.toString(),
                          label: 'รถเต็ม',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          icon: Icons.coffee_rounded,
                          color: const Color(0xFFF57C00),
                          bgColor: const Color(0xFFFFF8E1),
                          value: breakCount.toString(),
                          label: 'พักเบรก',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMiniStat(
                          icon: Icons.power_off_rounded,
                          color: const Color(0xFF757575),
                          bgColor: const Color(0xFFF5F5F5),
                          value: offlineCount.toString(),
                          label: 'ออฟไลน์',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LeftColumnContent extends StatelessWidget {
  final List<Map<String, dynamic>> activeShuttles;

  const LeftColumnContent({
    super.key,
    required this.activeShuttles,
  });

  @override
  Widget build(BuildContext context) {
    final sortedShuttles = List<Map<String, dynamic>>.from(activeShuttles);
    sortedShuttles.sort((a, b) {
      bool aOnline = a['status'] == 'online';
      bool bOnline = b['status'] == 'online';
      if (aOnline && !bOnline) return -1;
      if (!aOnline && bOnline) return 1;
      return (a['number']?.toString() ?? '').compareTo(b['number']?.toString() ?? '');
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'สถานะรถรับส่งประจำการ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2923),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    color: Color(0xFF176a21),
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'เรียลไทม์',
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
        const SizedBox(height: 14),
        if (sortedShuttles.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text(
                'ยังไม่มีข้อมูลรถรับส่งในระบบ',
                style: TextStyle(color: Color(0xFF718076), fontSize: 14),
              ),
            ),
          )
        else
          ...sortedShuttles.map((shuttle) => _buildShuttleCard(shuttle)),
        const SizedBox(height: 24),

        // กล่องแผนที่ย่อจำลอง
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'พิกัดรถบนแผนที่มหาวิทยาลัย',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E2923),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6F3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'PSRU MAP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF176a21),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF176a21).withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(16.83017, 100.21046),
              initialZoom: 15.0,
              maxZoom: 18.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.none,
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
                    strokeWidth: 3.5,
                    color: const Color(0xFF176a21).withOpacity(0.4),
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: activeShuttles
                    .where((s) => s['status'] == 'online')
                    .map((shuttle) {
                  return Marker(
                    point: LatLng(
                      shuttle['lat'] ?? 16.82753,
                      shuttle['lng'] ?? 100.20686,
                    ),
                    width: 50,
                    height: 50,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF176a21),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShuttleCard(Map<String, dynamic> shuttle) {
    final String number = (shuttle['number'] ?? '').toString();
    String cleanNum = number.replaceAll(RegExp(r'[^0-9]'), '');
    final String titleText =
        cleanNum.isNotEmpty ? 'รถรับส่งคันที่ $cleanNum' : (shuttle['name'] ?? 'Shuttle');

    final bool isOnline = shuttle['status'] == 'online';
    final String passengerStatus = shuttle['passenger_status'] ?? 'offline';

    Color statusColor = const Color(0xFF757575);
    Color statusBgColor = const Color(0xFFF5F5F5);
    String statusText = 'ออฟไลน์';
    String subtitleText = 'ยังไม่เริ่มให้บริการ';

    if (isOnline) {
      if (passengerStatus == 'available') {
        statusColor = const Color(0xFF176a21);
        statusBgColor = const Color(0xFFE8F5E9);
        statusText = 'พร้อมบริการ';
        subtitleText = 'กำลังวิ่งรับส่งผู้โดยสาร';
      } else if (passengerStatus == 'full') {
        statusColor = const Color(0xFFE65100);
        statusBgColor = const Color(0xFFFFF3E0);
        statusText = 'ที่นั่งเต็ม';
        subtitleText = 'กำลังเดินทางไปจุดส่งถัดไป';
      } else if (passengerStatus == 'break') {
        statusColor = const Color(0xFFF57C00);
        statusBgColor = const Color(0xFFFFF8E1);
        statusText = 'พักเบรก';
        subtitleText = 'คนขับกำลังพักชั่วคราว';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_bus_rounded,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2923),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF5A605B).withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RightColumnContent extends StatefulWidget {
  const RightColumnContent({super.key});

  @override
  State<RightColumnContent> createState() => _RightColumnContentState();
}

class _RightColumnContentState extends State<RightColumnContent> {
  StreamSubscription? _ridesSub;
  StreamSubscription? _rtdbSub;

  List<double> _hourlyCounts = List.filled(13, 0.0);
  String _peakTimeText = '-';
  int _totalCompletedTrips = 0;
  int _totalRideRequests = 0;

  @override
  void initState() {
    super.initState();
    _listenToRealtimeData();
  }

  void _listenToRealtimeData() {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    _ridesSub = FirebaseFirestore.instance
        .collection('analytics')
        .doc('daily_stats_$dateStr')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;

      int totalRequests = 0;
      List<double> buckets = List.filled(13, 0.0);
      Map<int, int> hourCounts = {};

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        totalRequests = ((data['total_requests'] ??
                data['total_passengers'] ??
                0) as num)
            .toInt();

        if (data['hourly_counts'] != null) {
          final map = Map<String, dynamic>.from(data['hourly_counts']);
          map.forEach((hStr, val) {
            final int h = int.tryParse(hStr) ?? 0;
            final int count = ((val ?? 0) as num).toInt();
            hourCounts[h] = count;

            if (h <= 7) {
              buckets[0] += count;
            } else if (h >= 19) {
              buckets[12] += count;
            } else {
              buckets[h - 7] += count;
            }
          });
        }
      }

      String peak = '-';
      if (hourCounts.isNotEmpty) {
        int maxHour = 12;
        int maxCount = -1;
        hourCounts.forEach((hour, reqCount) {
          if (reqCount > maxCount && reqCount > 0) {
            maxCount = reqCount;
            maxHour = hour;
          }
        });
        if (maxCount > 0) {
          String paddedH = maxHour.toString().padLeft(2, '0');
          peak = '$paddedH:00 น.';
        }
      }

      setState(() {
        _totalRideRequests = totalRequests;
        _hourlyCounts = buckets;
        _peakTimeText = peak;
      });
    });

    _rtdbSub = FirebaseDatabase.instance.ref('shuttles').onValue.listen((event) {
      if (!mounted) return;
      int tripsSum = 0;
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, val) {
          if (val is Map && val.containsKey('daily_rounds')) {
            tripsSum += (val['daily_rounds'] as num).toInt();
          }
        });
      }

      setState(() {
        _totalCompletedTrips = tripsSum;
      });
    });
  }

  @override
  void dispose() {
    _ridesSub?.cancel();
    _rtdbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF176a21).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ปริมาณผู้โดยสารประจำวัน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'แนวโน้มความหนาแน่นของการเรียกรถในแต่ละช่วงเวลา',
                        style: TextStyle(
                          color: Color(0xFF718076),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F6F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '24 ชม. ล่าสุด',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: ChartPainter(values: _hourlyCounts),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(13, (index) {
                  final String h = (7 + index).toString().padLeft(2, '0');
                  return Text(
                    '$h:00',
                    style: const TextStyle(
                      color: Color(0xFF718076),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFEFF2F0)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildChartStat('ช่วงที่เรียกรถเยอะสุด', _peakTimeText),
                  _buildChartStat('เที่ยวรถรวมวันนี้', '$_totalCompletedTrips รอบ'),
                  _buildChartStat('คำขอเรียกรถรวม', '$_totalRideRequests ครั้ง'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                icon: Icons.build_circle_rounded,
                title: 'บันทึกการบำรุงรักษา',
                subtitle: 'ตรวจเช็คสภาพตามระยะ',
                color: const Color(0xFF176a21),
                bgColor: const Color(0xFFE8F5E9),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.notifications_active_rounded,
                title: 'ประกาศของระบบ',
                subtitle: 'แจ้งเตือนผู้ใช้งาน',
                color: const Color(0xFF0288D1),
                bgColor: const Color(0xFFE1F5FE),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF718076),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E2923),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: Color(0xFF1E2923),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF718076),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final List<double> values;
  ChartPainter({List<double>? values})
      : values = values ?? List.filled(13, 0.0);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF176a21)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final points = <Offset>[];
    double maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) maxV = 1.0;

    for (int i = 0; i < values.length; i++) {
      double x = size.width * (i / (values.length - 1));
      double normY = values[i] / maxV;
      double y = size.height * 0.85 - (size.height * 0.65 * normY);
      points.add(Offset(x, y));
    }

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
        final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
        path.cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          p1.dx,
          p1.dy,
        );
      }
    }

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF176a21).withOpacity(0.25),
          const Color(0xFF176a21).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = const Color(0xFF176a21);
    final dotBgPaint = Paint()..color = Colors.white;

    void drawDot(Offset offset) {
      canvas.drawCircle(offset, 4.0, dotBgPaint);
      canvas.drawCircle(offset, 2.5, dotPaint);
    }

    for (var pt in points) {
      drawDot(pt);
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
