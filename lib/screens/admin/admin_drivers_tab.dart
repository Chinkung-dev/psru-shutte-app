import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_driver_dialog.dart';
import 'edit_driver_dialog.dart';

class AdminDriversTab extends StatelessWidget {
  const AdminDriversTab({super.key});

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
              child: const DriversHeader(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const DriversTitleRow(),
              const SizedBox(height: 32),
              const DriversTableCard(),
            ]),
          ),
        ),
      ],
    );
  }
}

class DriversHeader extends StatelessWidget {
  const DriversHeader({super.key});

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
              hintText: 'ค้นหาคนขับ, รหัสพนักงาน...',
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

class DriversTitleRow extends StatelessWidget {
  const DriversTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 400,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ข้อมูลพนักงานขับรถ',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'จัดการพนักงานขับรถของมหาวิทยาลัย ติดตามผลการทำงาน และตรวจสอบสถานะใบอนุญาตและตารางเดินรถ',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('shuttles')
              .where('status', isEqualTo: 'online')
              .snapshots(),
          builder: (context, snapshot) {
            String activeCount = '0';
            if (snapshot.hasData) {
              activeCount = snapshot.data!.docs.length.toString();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatCard('รถที่กำลังวิ่ง', activeCount, '', true),
                const SizedBox(width: 16),
                _buildStatCard(
                  'คะแนนเฉลี่ย',
                  '4.88',
                  '',
                  false,
                  icon: Icons.star_border,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    String trend,
    bool isPositive, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (trend.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? const Color(0xFF176a21) : Colors.red,
                  ),
                ),
              ],
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: const Color(0xFF176a21), size: 24),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class DriversTableCard extends StatefulWidget {
  const DriversTableCard({super.key});

  @override
  State<DriversTableCard> createState() => _DriversTableCardState();
}

class _DriversTableCardState extends State<DriversTableCard> {
  String _activeFilter = 'ทั้งหมด';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Row
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'ทั้งหมด'),
                        child: _buildFilterTab(
                          'ทั้งหมด',
                          _activeFilter == 'ทั้งหมด',
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'ว่าง'),
                        child: _buildFilterTab('ว่าง', _activeFilter == 'ว่าง'),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'เต็ม'),
                        child: _buildFilterTab('เต็ม', _activeFilter == 'เต็ม'),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'พักเบรก'),
                        child: _buildFilterTab(
                          'พักเบรก',
                          _activeFilter == 'พักเบรก',
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _activeFilter = 'ออฟไลน์'),
                        child: _buildFilterTab(
                          'ออฟไลน์',
                          _activeFilter == 'ออฟไลน์',
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.filter_list,
                    color: Color(0xFF176a21),
                    size: 20,
                  ),
                  label: const Text(
                    'ตัวกรองเพิ่มเติม',
                    style: TextStyle(
                      color: Color(0xFF176a21),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AddDriverDialog(),
                    ).then((result) {
                      if (result == true) {
                        // Refresh drivers logic if needed
                      }
                    });
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text(
                    'เพิ่มคนขับรถ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Content & Pagination Footer
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('shuttles').snapshots(),
            builder: (context, shuttlesSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'driver')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(64.0),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF176a21)),
                      ),
                    );
                  }

                  var docs = snapshot.hasData ? snapshot.data!.docs : [];
                  
                  // Helper function to get real-time status from shuttles
                  Map<String, dynamic>? getShuttleData(Map<String, dynamic> userData) {
                    if (!shuttlesSnapshot.hasData) return null;
                    final shuttleName = userData['shuttle_name'];
                    if (shuttleName != null) {
                      try {
                        return shuttlesSnapshot.data!.docs
                            .firstWhere((s) => s.id == shuttleName || (s.data() as Map<String, dynamic>)['name'] == shuttleName)
                            .data() as Map<String, dynamic>;
                      } catch (e) {}
                    }
                    return null;
                  }

                  if (_activeFilter != 'ทั้งหมด') {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final shuttleData = getShuttleData(data);
                      String rawStatus = shuttleData?['status'] ?? data['status'] ?? 'offline';
                      String passengerStatus = shuttleData?['passenger_status'] ??
                          data['passenger_status'] ??
                          (rawStatus == 'online' ? 'available' : 'offline');
                      if (rawStatus == 'offline') passengerStatus = 'offline';

                      if (_activeFilter == 'ว่าง')
                        return passengerStatus == 'available';
                      if (_activeFilter == 'เต็ม') return passengerStatus == 'full';
                      if (_activeFilter == 'พักเบรก')
                        return passengerStatus == 'break';
                      if (_activeFilter == 'ออฟไลน์')
                        return passengerStatus == 'offline';
                      return true;
                    }).toList();
                  }

              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: constraints.maxWidth > 900
                              ? constraints.maxWidth
                              : 900,
                          child: Column(
                            children: [
                              // Table Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade100,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildTableHeader('โปรไฟล์คนขับ', flex: 3),
                                    _buildTableHeader('รหัสพนักงาน', flex: 2),
                                    _buildTableHeader('สถานะ', flex: 2),
                                    _buildTableHeader('รอบวิ่งวันนี้', flex: 2),
                                    _buildTableHeader('คะแนน', flex: 1),
                                    _buildTableHeader(
                                      'จัดการ',
                                      flex: 1,
                                      alignRight: true,
                                    ),
                                  ],
                                ),
                              ),

                              // Table Rows
                              if (docs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                    child: Text(
                                      'ไม่มีข้อมูลพนักงานขับรถ',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ),
                                )
                              else
                                ...docs.map((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  
                                  final shuttleData = getShuttleData(data);

                                  // จัดการปีที่เริ่มงาน
                                  String joinedStr = 'เริ่มงานปี N/A';
                                  if (data['created_at'] != null) {
                                    try {
                                      final date =
                                          (data['created_at'] as Timestamp)
                                              .toDate();
                                      joinedStr = 'เริ่มงานปี ${date.year}';
                                    } catch (e) {
                                      // fallback
                                    }
                                  }

                                  // จัดการสถานะให้ดึงจาก shuttles เป็นหลัก
                                  String rawStatus = shuttleData?['status'] ?? data['status'] ?? 'offline';
                                  String passengerStatus = shuttleData?['passenger_status'] ??
                                      data['passenger_status'] ??
                                      (rawStatus == 'online' ? 'available' : 'offline');
                                  if (rawStatus == 'offline') passengerStatus = 'offline';

                                  final name = data['name'] ?? 'ไม่มีชื่อ';
                                  final id =
                                      data['employee_id'] ??
                                      data['student_id'] ??
                                      'N/A';
                                  final trips = data['trips_today'] ?? 0;
                                  final tripsProgress = trips > 0
                                      ? (trips / 20.0).clamp(0.0, 1.0)
                                      : 0.0;
                                  final rating =
                                      data['rating']?.toString() ?? '5.0';
                                  final imageUrl =
                                      data['avatar'] ??
                                      'assets/images/man1.png';

                                  return _buildDriverRow(
                                    name: name,
                                    joined: joinedStr,
                                    id: id,
                                    status: passengerStatus,
                                    trips: trips,
                                    tripsProgress: tripsProgress,
                                    rating: rating,
                                    imageUrl: imageUrl,
                                    onEdit: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => EditDriverDialog(
                                          docId: doc.id,
                                          driverData: data,
                                        ),
                                      );
                                    },
                                  );
                                }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Pagination Footer
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'แสดง ${docs.length} คน',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            _buildPageButton(Icons.chevron_left),
                            const SizedBox(width: 8),
                            _buildPageButton(Icons.chevron_right),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ],
  ),
);
}

  Widget _buildFilterTab(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.black87 : Colors.black54,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTableHeader(
    String title, {
    required int flex,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildDriverRow({
    required String name,
    required String joined,
    required String id,
    required String status,
    required int trips,
    required double tripsProgress,
    required String rating,
    required String imageUrl,
    required VoidCallback onEdit,
  }) {
    ImageProvider imageProvider;
    if (imageUrl.startsWith('http')) {
      imageProvider = NetworkImage(imageUrl);
    } else {
      imageProvider = AssetImage(imageUrl);
    }

    String statusText = 'ออฟไลน์';
    Color statusColor = Colors.red;
    Color statusBgColor = Colors.red.shade50;

    if (status == 'available') {
      statusText = 'ว่าง';
      statusColor = const Color(0xFF176a21);
      statusBgColor = const Color(0xFFE8F5E9);
    } else if (status == 'full') {
      statusText = 'เต็ม';
      statusColor = const Color(0xFF757778);
      statusBgColor = Colors.grey.shade200;
    } else if (status == 'break') {
      statusText = 'พักเบรก';
      statusColor = const Color(0xFFF28522);
      statusBgColor = Colors.orange.shade50;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // Profile
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(radius: 20, backgroundImage: imageProvider),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      joined,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ID
          Expanded(
            flex: 2,
            child: Text(
              id,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),

          // Status
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Trips
          Expanded(
            flex: 2,
            child: Text(
              trips.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),

          // Rating
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Text(
                  rating,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.star,
                  color:
                      double.tryParse(rating) != null &&
                          double.parse(rating) >= 4.5
                      ? const Color(0xFF176a21)
                      : Colors.grey.shade400,
                  size: 14,
                ),
              ],
            ),
          ),

          // Actions
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onEdit,
                  child: Text(
                    'แก้ไขข้อมูล',
                    style: TextStyle(
                      color: const Color(0xFF176a21),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
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

  Widget _buildPageButton(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.black54, size: 20),
    );
  }
}

class DriversAlertsRow extends StatelessWidget {
  const DriversAlertsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              Expanded(
                child: _buildAlertCard(
                  Icons.verified,
                  'แจ้งเตือนใบอนุญาต',
                  'มีคนขับ 3 คนที่ใบอนุญาตจะหมดอายุในอีก 30 วัน โปรดดำเนินการ',
                  'ตรวจสอบวันหมดอายุ',
                  const Color(0xFF00bcd4),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAlertCard(
                  Icons.calendar_month,
                  'ตารางงานถัดไป',
                  'จัดตารางวันหยุดเสร็จสิ้น มีคนขับ 12 คนสำหรับรอบพิเศษเสาร์อาทิตย์นี้',
                  'ดูตารางงาน',
                  const Color(0xFF176a21),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAlertCard(
                  Icons.error_outline,
                  'รายงานอุบัติเหตุ',
                  'ไม่มีรายงานอุบัติเหตุรุนแรงในช่วง 24 ชั่วโมงที่ผ่านมา รักษามาตรฐานความปลอดภัยไว้',
                  'ดูบันทึกล่าสุด',
                  Colors.redAccent,
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildAlertCard(
                Icons.verified,
                'แจ้งเตือนใบอนุญาต',
                'มีคนขับ 3 คนที่ใบอนุญาตจะหมดอายุในอีก 30 วัน โปรดดำเนินการ',
                'ตรวจสอบวันหมดอายุ',
                const Color(0xFF00bcd4),
              ),
              const SizedBox(height: 16),
              _buildAlertCard(
                Icons.calendar_month,
                'ตารางงานถัดไป',
                'จัดตารางวันหยุดเสร็จสิ้น มีคนขับ 12 คนสำหรับรอบพิเศษเสาร์อาทิตย์นี้',
                'ดูตารางงาน',
                const Color(0xFF176a21),
              ),
              const SizedBox(height: 16),
              _buildAlertCard(
                Icons.error_outline,
                'รายงานอุบัติเหตุ',
                'ไม่มีรายงานอุบัติเหตุรุนแรงในช่วง 24 ชั่วโมงที่ผ่านมา รักษามาตรฐานความปลอดภัยไว้',
                'ดูบันทึกล่าสุด',
                Colors.redAccent,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildAlertCard(
    IconData icon,
    String title,
    String description,
    String actionText,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                actionText,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward, color: color, size: 14),
            ],
          ),
        ],
      ),
    );
  }
}
