import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'student_chat_screen.dart';

class StudentLiveStatusScreen extends StatefulWidget {
  final List<Map<String, dynamic>> busStops;

  const StudentLiveStatusScreen({
    super.key,
    required this.busStops,
  });

  @override
  State<StudentLiveStatusScreen> createState() => _StudentLiveStatusScreenState();
}

class _StudentLiveStatusScreenState extends State<StudentLiveStatusScreen> {
  late final Stream<QuerySnapshot> _shuttlesStream;

  @override
  void initState() {
    super.initState();
    _shuttlesStream =
        FirebaseFirestore.instance.collection('shuttles').snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8), // สีพื้นหลังเทาอ่อนสะอาดตาตามดีไซน์
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<QuerySnapshot>(
          stream: _shuttlesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF176a21)),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            // คำนวณสถิติต่างๆ แบบ Real-time
            int availableCount = 0;
            int fullCount = 0;
            int breakCount = 0;
            int offlineCount = 0;
            int totalActive = 0;

            List<Map<String, dynamic>> shuttleList = [];

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final String shuttleId = doc.id;
              final String name = (data['name'] ?? shuttleId).toString();
              final String number = (data['number'] ?? '').toString();
              final String status = data['status'] ?? 'offline'; // 'online' หรือ 'offline'
              
              // สถานะผู้โดยสาร: 'available', 'full', 'break', 'offline'
              String passengerStatus = data['passenger_status'] ?? 
                  (status == 'online' ? 'available' : 'offline');
              
              if (status == 'offline') {
                passengerStatus = 'offline';
              }

              // นับจำนวนตามสถานะ
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

              // จัดการตัวเลขให้สวยงาม เช่น SH#03 -> 03
              String cleanNum = number.replaceAll(RegExp(r'[^0-9]'), '');
              final String badgeText = cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : name;

              // คำนวณระยะทางและป้ายที่ใกล้ที่สุด (มุ่งหน้าไปที่...)
              double lat = (data['lat'] as num?)?.toDouble() ?? 16.82753;
              final double lng = (data['lng'] as num?)?.toDouble() ?? 100.20686;
              
              String nearestStopName = "ภายในมหาวิทยาลัย";
              int etaMinutes = 3;

              if (widget.busStops.isNotEmpty) {
                double minDistance = double.infinity;
                const Distance distance = Distance();
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
                  // คำนวณ ETA โดยใช้ความเร็วเฉลี่ย ~350 เมตร/นาที (ขั้นต่ำ 1 นาที)
                  etaMinutes = (minDistance / 350).round();
                  if (etaMinutes < 1) etaMinutes = 1;
                }
              }

              shuttleList.add({
                'shuttleId': shuttleId,
                'name': name,
                'number': number,
                'cleanNum': cleanNum,
                'badgeText': badgeText,
                'driverName': data['driver_name'] ?? 'คนขับรถประจำคัน',
                'driverAvatar': data['driver_avatar'] ?? '',
                'status': status,
                'passengerStatus': passengerStatus,
                'isOnline': status == 'online',
                'nearestStopName': nearestStopName,
                'etaMinutes': etaMinutes,
              });
            }

            // เรียงลำดับ: รถที่ออนไลน์ขึ้นก่อน ตามด้วยหมายเลขรถ
            shuttleList.sort((a, b) {
              bool aOnline = a['isOnline'];
              bool bOnline = b['isOnline'];
              if (aOnline && !bOnline) return -1;
              if (!aOnline && bOnline) return 1;
              return (a['cleanNum'] as String).compareTo(b['cleanNum'] as String);
            });

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  
                  // 🌟 Hero Card (รถรับส่งทั้งหมด)
                  _buildHeroCard(totalActive),
                  const SizedBox(height: 16),

                  // 📊 4 Grid Cards (สถานะรถว่าง/เต็ม/พัก/ออฟไลน์)
                  _buildStatsGrid(availableCount, fullCount, breakCount, offlineCount),
                  
                  // 🏷️ Section Title (สถานะรถ + REAL-TIME)
                  _buildSectionTitle(),
                  
                  // 🚌 รายการรถรับส่งแต่ละคัน
                  if (shuttleList.isEmpty)
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
                    ...shuttleList.map((shuttle) => _buildShuttleCard(shuttle)),

                  const SizedBox(height: 100), // เว้นที่ด้านล่างเผื่อ Bottom Navigation Bar
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 🏛️ ส่วนหัวข้อ PSRU Shuttle
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.directions_bus,
            color: Color(0xFF176a21),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'PSRU Shuttle',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF176a21),
          ),
        ),
      ],
    );
  }

  // 🌟 Hero Card (รถรับส่งทั้งหมด Active)
  Widget _buildHeroCard(int totalActive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'รถรับส่งทั้งหมด',
                style: TextStyle(
                  color: Color(0xFF595C5D),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$totalActive',
                    style: const TextStyle(
                      color: Color(0xFF176a21),
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Active',
                    style: TextStyle(
                      color: Color(0xFF176a21),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Color(0xFF176a21),
              size: 38,
            ),
          ),
        ],
      ),
    );
  }

  // 📊 4 Grid Cards
  Widget _buildStatsGrid(int available, int full, int breakTime, int offline) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'รถว่าง',
                Icons.check_circle_outline,
                available,
                iconColor: const Color(0xFF176a21),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'รถเต็ม',
                Icons.block,
                full,
                iconColor: const Color(0xFF757778),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'เวลาพักเบรค',
                Icons.pause_circle_outline,
                breakTime,
                iconColor: const Color(0xFFF28522),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'นอกเวลางาน',
                Icons.power_settings_new,
                offline,
                iconColor: const Color(0xFF595C5D),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    IconData icon,
    int count, {
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF595C5D),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF2C2F30),
              fontSize: 26,
              fontWeight: FontWeight.bold,
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
                    '${etaMinutes}m',
                    style: const TextStyle(
                      color: Color(0xFF176a21),
                      fontSize: 18,
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
