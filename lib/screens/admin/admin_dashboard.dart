import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../route_data.dart';
import 'admin_live_map.dart';
import 'admin_drivers_tab.dart';
import 'admin_analytics_tab.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✨ เพิ่ม Import FirebaseAuth สำหรับล็อกเอาต์

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 1; // Start on Live Map for preview, or 0 for Overview

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isTablet =
        MediaQuery.of(context).size.width > 600 &&
        MediaQuery.of(context).size.width <= 900;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F9FA),
      // ✨ เพิ่ม AppBar สำหรับมือถือ/แท็บเล็ต เพื่อให้มีปุ่ม Hamburger Menu
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black87),
              title: const Text(
                'PSRU Admin',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
            ),
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
  StreamSubscription? _ridesSub;

  @override
  void initState() {
    super.initState();
    _listenToShuttles();
    _listenToRideRequests();
  }

  void _listenToShuttles() {
    _shuttlesSub = FirebaseFirestore.instance.collection('shuttles').snapshots().listen((snapshot) {
      if (!mounted) return;
      int a = 0, f = 0, b = 0, o = 0;
      List<Map<String, dynamic>> list = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'offline';
        String pStatus = data['passenger_status'] ?? (status == 'online' ? 'available' : 'offline');
        if (status == 'offline') pStatus = 'offline';

        if (pStatus == 'available') a++;
        else if (pStatus == 'full') f++;
        else if (pStatus == 'break') b++;
        else o++;
        
        list.add({
          'id': doc.id,
          'name': data['name'] ?? doc.id,
          'number': data['number'] ?? '',
          'status': status,
          'passenger_status': pStatus,
          'driver_name': data['driver_name'] ?? 'ไม่ระบุ',
          'driver_avatar': data['driver_avatar'] ?? '',
          'capacity_percent': data['capacity_percent'] ?? 0,
          'lat': data['lat'] ?? 16.82753,
          'lng': data['lng'] ?? 100.20686,
        });
      }
      setState(() {
        availableCount = a;
        fullCount = f;
        breakCount = b;
        offlineCount = o;
        activeShuttleList = list;
      });
    });
  }

  void _listenToRideRequests() {
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    _ridesSub = FirebaseFirestore.instance.collection('ride_requests')
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .snapshots().listen((snapshot) {
      if (!mounted) return;
      int todayCount = snapshot.docs.length;
      
      double totalWaitMins = 0.0;
      int waitCount = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['timestamp'] != null && data['acknowledged_at'] != null) {
          final start = (data['timestamp'] as Timestamp).toDate();
          final end = (data['acknowledged_at'] as Timestamp).toDate();
          totalWaitMins += end.difference(start).inSeconds / 60.0;
          waitCount++;
        }
      }
      
      setState(() {
        passengersToday = todayCount;
        avgWaitTimeMins = waitCount > 0 ? (totalWaitMins / waitCount) : 0.0;
      });
    });
  }

  @override
  void dispose() {
    _shuttlesSub?.cancel();
    _ridesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return CustomScrollView(
      slivers: [
        if (!isDesktop)
          SliverAppBar(
            backgroundColor: Colors.white,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Colors.black87),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            title: const Text(
              'ศูนย์ควบคุม',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (isDesktop)
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: const DashboardHeader(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const FleetOverviewTitle(),
              const SizedBox(height: 24),
              StatsRowWidget(
                availableCount: availableCount,
                fullCount: fullCount,
                breakCount: breakCount,
                offlineCount: offlineCount,
                passengersToday: passengersToday,
                avgWaitTimeMins: avgWaitTimeMins,
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 800) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: LeftColumnContent(activeShuttles: activeShuttleList)),
                        const SizedBox(width: 24),
                        const Expanded(flex: 6, child: RightColumnContent()),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        LeftColumnContent(activeShuttles: activeShuttleList),
                        const SizedBox(height: 32),
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
      width: 250,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 24.0,
              left: 24.0,
              right: 24.0,
              bottom: 10.0,
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
          _buildNavItem(Icons.dashboard_rounded, 'Overview', 0),
          _buildNavItem(Icons.map_outlined, 'Live Map', 1),
          _buildNavItem(Icons.people_outline, 'Drivers', 2),
          _buildNavItem(Icons.analytics_outlined, 'Analytics', 3),
          const Spacer(),
          _buildNavItem(Icons.settings_outlined, 'Settings', 4),
          _buildNavItem(Icons.help_outline, 'Support', 5),
          const SizedBox(height: 16),
          // ✨ เพิ่มปุ่มออกจากระบบ (Logout)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
              title: const Text(
                'ออกจากระบบ',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              hoverColor: Colors.redAccent.withOpacity(0.1),
              onTap: () async {
                bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('ยืนยันการออกจากระบบ'),
                      content: const Text('คุณต้องการออกจากระบบใช่หรือไม่?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('ออกจากระบบ', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    );
                  },
                );

                if (confirm == true) {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index) {
    final isActive = selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF176a21).withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? const Color(0xFF176a21) : Colors.grey.shade600,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? const Color(0xFF176a21) : Colors.grey.shade700,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () => onItemSelected(index),
      ),
    );
  }
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'ศูนย์ควบคุม',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        Container(
          width: 300,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'ค้นหาเส้นทาง, คนขับ...',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.grey.shade500,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
        const CircleAvatar(
          backgroundColor: Color(0xFF176a21),
          radius: 18,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

class FleetOverviewTitle extends StatelessWidget {
  const FleetOverviewTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ภาพรวมระบบรถรับส่ง',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
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
                    'ระบบทำงานปกติ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'ข้อมูลและสถิติแบบเรียลไทม์สำหรับ PSRU Shuttle',
          style: TextStyle(color: Colors.black54, fontSize: 14),
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
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildFleetStatusCard(context),
        _buildStatCard(
          context,
          label: 'นักศึกษาที่ใช้บริการวันนี้',
          icon: Icons.people_alt,
          iconColor: const Color(0xFF176a21),
          iconBgColor: const Color(0xFF9DF197).withOpacity(0.3),
          trend: 'รวมวันนี้',
          trendColor: const Color(0xFF176a21),
          value: passengersToday.toString(),
        ),
        _buildStatCard(
          context,
          label: 'เวลารอเฉลี่ย',
          icon: Icons.timer,
          iconColor: const Color(0xFF00bcd4),
          iconBgColor: const Color(0xFF00bcd4).withOpacity(0.1),
          trend: 'นาที/คน',
          trendColor: const Color(0xFF176a21),
          value: avgWaitTimeMins.toStringAsFixed(1),
          unit: ' นาที',
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String trend,
    required Color trendColor,
    required String value,
    String? unit,
    required String label,
  }) {
    // Calculate width to be responsive
    final screenWidth = MediaQuery.of(context).size.width;
    double cardWidth = (screenWidth - 250 - 48 - 32) / 3;
    if (screenWidth <= 900) cardWidth = (screenWidth - 48 - 16) / 2;
    if (screenWidth <= 600) cardWidth = screenWidth - 48;
    if (cardWidth < 200) cardWidth = 200; // minimum width

    return Container(
      width: cardWidth,
      height: 190,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              Text(
                trend,
                style: TextStyle(
                  color: trendColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (unit != null)
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFleetStatusCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double cardWidth = (screenWidth - 250 - 48 - 32) / 3;
    if (screenWidth <= 900) cardWidth = (screenWidth - 48 - 16) / 2;
    if (screenWidth <= 600) cardWidth = screenWidth - 48;
    if (cardWidth < 200) cardWidth = 200;

    return Container(
      width: cardWidth,
      height: 190,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สถานะรถทั้งหมด',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  Icons.directions_bus,
                  const Color(0xFF176a21),
                  const Color(0xFF9DF197).withOpacity(0.3),
                  availableCount.toString(),
                  'กำลังวิ่ง',
                ),
              ),
              Expanded(
                child: _buildMiniStat(
                  Icons.bus_alert,
                  Colors.orange,
                  Colors.orange.withOpacity(0.1),
                  fullCount.toString(),
                  'รถเต็ม',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  Icons.local_cafe,
                  Colors.amber.shade700,
                  Colors.amber.withOpacity(0.1),
                  breakCount.toString(),
                  'พักเบรก',
                ),
              ),
              Expanded(
                child: _buildMiniStat(
                  Icons.directions_off,
                  Colors.grey.shade600,
                  Colors.grey.withOpacity(0.1),
                  offlineCount.toString(),
                  'เลิกงาน',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    IconData icon,
    Color color,
    Color bgColor,
    String value,
    String label,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ],
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
    // Sort shuttles to match student app: online first, then by number
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
              'สถานะรถ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30)),
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
        const SizedBox(height: 16),
        if (sortedShuttles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'ยังไม่มีข้อมูลรถรับส่งในระบบ',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ),
          )
        else
          ...sortedShuttles.map((shuttle) {
            return _buildShuttleCard(shuttle);
          }),

        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'แผนที่รถรับส่ง',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'LIVE MAP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(16.83017, 100.21046),
              initialZoom: 15.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none, // Make it a static preview map
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
                    strokeWidth: 4.0,
                    color: const Color(0xFF176a21).withOpacity(0.5),
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: activeShuttles.where((s) => s['status'] == 'online').map((shuttle) {
                  return Marker(
                    point: LatLng(shuttle['lat'] ?? 16.82753, shuttle['lng'] ?? 100.20686),
                    width: 60,
                    height: 65,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF176a21),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              )
                            ],
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.directions_bus,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF176a21).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ((shuttle['number'] ?? '').toString()).replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '').trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
    final String badgeText = cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : shuttle['name'];
    
    final bool isOnline = shuttle['status'] == 'online';
    final String passengerStatus = shuttle['passenger_status'] ?? 'offline';
    
    Color dotColor = Colors.grey;
    String subtitleText = 'นอกเวลางาน (ออฟไลน์)';
    Color subtitleColor = Colors.grey[600]!;
    String rightBadgeText = 'ออฟไลน์';

    if (isOnline) {
      if (passengerStatus == 'available') {
        dotColor = const Color(0xFF176a21); // เขียว
        subtitleText = 'กำลังวิ่งให้บริการ';
        subtitleColor = const Color(0xFF595C5D);
        rightBadgeText = 'ให้บริการ';
      } else if (passengerStatus == 'full') {
        dotColor = const Color(0xFF757778); // เทาเข้ม
        subtitleText = 'กำลังวิ่งให้บริการ (รถเต็ม)';
        subtitleColor = const Color(0xFFE53935);
        rightBadgeText = 'รถเต็ม';
      } else if (passengerStatus == 'break') {
        dotColor = const Color(0xFFF28522); // ส้ม
        subtitleText = 'คนขับกำลังพักเบรค';
        subtitleColor = const Color(0xFFF28522);
        rightBadgeText = 'พักเบรค';
      } else {
        dotColor = Colors.grey;
        subtitleText = 'นอกเวลางาน';
        subtitleColor = Colors.grey[600]!;
        rightBadgeText = 'ออฟไลน์';
      }
    }

    return Container(
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              rightBadgeText,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RightColumnContent extends StatelessWidget {
  const RightColumnContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 5),
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
                        'ปริมาณผู้โดยสารรายวัน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'แนวโน้มประสิทธิภาพในช่วง 24 ชั่วโมงที่ผ่านมา',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '24 ชั่วโมงล่าสุด',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 200,
                width: double.infinity,
                child: CustomPaint(painter: ChartPainter()),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '7:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '08:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '10:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '12:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '14:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '16:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                  Text(
                    '18:00',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Color(0xFFEEEEEE)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildChartStat('เวลาที่กดเรียกรถเยอะที่สุด', '12:30 น.'),
                  _buildChartStat('เที่ยวรถรวม', '42'),
                  _buildChartStat('กดเรียกรถทั้งหมด', '12 ครั้ง'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                icon: Icons.assignment,
                title: 'บันทึกซ่อมบำรุง',
                subtitle: 'รถ 2 คันถึงกำหนด\nตรวจเช็ค',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.campaign,
                title: 'ประกาศแจ้งเตือน',
                subtitle: 'แจ้งเตือนนักศึกษา\nเรื่องรถล่าช้า',
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
            fontSize: 10,
            color: Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF176a21), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    height: 1.2,
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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF176a21)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path();
    path.moveTo(0, size.height * 0.7);

    // Create a smooth bezier curve for the chart
    path.cubicTo(
      size.width * 0.15,
      size.height * 0.6,
      size.width * 0.25,
      size.height * 0.3,
      size.width * 0.4,
      size.height * 0.3,
    );
    path.cubicTo(
      size.width * 0.55,
      size.height * 0.3,
      size.width * 0.6,
      size.height * 0.2,
      size.width * 0.7,
      size.height * 0.5,
    );
    path.cubicTo(
      size.width * 0.85,
      size.height * 0.5,
      size.width * 0.9,
      size.height * 0.2,
      size.width,
      size.height * 0.3,
    );

    // Draw Gradient Fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF176a21).withOpacity(0.3),
          const Color(0xFF176a21).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw data points
    final dotPaint = Paint()..color = const Color(0xFF176a21);
    final dotBgPaint = Paint()..color = Colors.white;

    void drawDot(Offset offset) {
      canvas.drawCircle(offset, 6, dotBgPaint);
      canvas.drawCircle(offset, 4, dotPaint);
    }

    drawDot(Offset(size.width * 0.4, size.height * 0.3));
    drawDot(Offset(size.width * 0.7, size.height * 0.5));
    drawDot(Offset(size.width * 0.95, size.height * 0.23));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
