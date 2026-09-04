import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'add_driver_dialog.dart';
import 'edit_driver_dialog.dart';
import 'admin_profile_dialog.dart';

class AdminDriversTab extends StatefulWidget {
  const AdminDriversTab({super.key});

  @override
  State<AdminDriversTab> createState() => _AdminDriversTabState();
}

class _AdminDriversTabState extends State<AdminDriversTab> {
  String _searchQuery = '';

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
              'จัดการคนขับรถ',
              style: TextStyle(
                color: Color(0xFF176a21),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        if (isDesktop)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: _buildHeader(context),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const DriversTitleRow(),
              const SizedBox(height: 24),
              DriversTableCard(
                searchQuery: _searchQuery,
                onSearchChanged: (q) => setState(() => _searchQuery = q),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
              Icons.badge_rounded,
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
                'จัดการข้อมูลพนักงานขับรถ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF176a21),
                ),
              ),
              Text(
                'ระบบบัญชีคนขับรถรับส่ง การมอบหมายรถ และประวัติการทำงาน',
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
    );
  }
}

class DriversTitleRow extends StatelessWidget {
  const DriversTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รายชื่อพนักงานขับรถ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2923),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ตรวจสอบสถานะการให้บริการ หมายเลขรถที่ประจำการ และสถิติเที่ยววิ่ง',
                    style: TextStyle(
                      color: const Color(0xFF5A605B).withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (!isMobile)
              StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref('shuttles').onValue,
                builder: (context, snapshot) {
                  String activeCount = '0';
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    final data =
                        snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                    final now = DateTime.now();
                    int count = 0;
                    data.forEach((key, value) {
                      if (value is Map && value['status'] == 'online') {
                        if (value.containsKey('last_updated') &&
                            value['last_updated'] != null) {
                          final lastUpdated =
                              DateTime.fromMillisecondsSinceEpoch(
                            (value['last_updated'] as num).toInt(),
                          );
                          if (now.difference(lastUpdated).inMinutes <= 4) {
                            count++;
                          }
                        }
                      }
                    });
                    activeCount = count.toString();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatBadge(
                        'รถที่ออนไลน์ขณะนี้',
                        '$activeCount คัน',
                        const Color(0xFF176a21),
                        const Color(0xFFE8F5E9),
                        Icons.directions_bus_rounded,
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatBadge(
    String label,
    String value,
    Color color,
    Color bgColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
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
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DriversTableCard extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const DriversTableCard({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<DriversTableCard> createState() => _DriversTableCardState();
}

class _DriversTableCardState extends State<DriversTableCard> {
  String _activeFilter = 'ทั้งหมด';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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

            // แถบค้นหา ตัวกรอง และปุ่มเพิ่มคนขับ
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Wrap(
                spacing: 16,
                runSpacing: 14,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // ตัวกรองสถานะ
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F6F3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFilterTab('ทั้งหมด', _activeFilter == 'ทั้งหมด'),
                          _buildFilterTab('พร้อมบริการ', _activeFilter == 'พร้อมบริการ'),
                          _buildFilterTab('ที่นั่งเต็ม', _activeFilter == 'ที่นั่งเต็ม'),
                          _buildFilterTab('พักเบรก', _activeFilter == 'พักเบรก'),
                          _buildFilterTab('ออฟไลน์', _activeFilter == 'ออฟไลน์'),
                        ],
                      ),
                    ),
                  ),

                  // ช่องค้นหาและปุ่มเพิ่มคนขับ
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 220,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6F3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.1),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: widget.onSearchChanged,
                          style: const TextStyle(
                            color: Color(0xFF2C2F30),
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'ค้นหาชื่อ, รหัส...',
                            hintStyle: TextStyle(
                              color: Color(0xFF718076),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Color(0xFF176a21),
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const AddDriverDialog(),
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'เพิ่มคนขับรถ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF176a21),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEFF2F0)),

            // ตารางรายชื่อคนขับ
            StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('shuttles').onValue,
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
                          child: CircularProgressIndicator(
                            color: Color(0xFF176a21),
                          ),
                        ),
                      );
                    }

                    var docs = snapshot.hasData ? snapshot.data!.docs : [];

                    Map<dynamic, dynamic>? getShuttleData(
                      Map<String, dynamic> userData,
                    ) {
                      if (!shuttlesSnapshot.hasData ||
                          shuttlesSnapshot.data!.snapshot.value == null) {
                        return null;
                      }
                      final shuttleName = userData['shuttle_name'];
                      if (shuttleName != null) {
                        try {
                          final data = shuttlesSnapshot.data!.snapshot.value
                              as Map<dynamic, dynamic>;
                          for (var key in data.keys) {
                            if (key == shuttleName ||
                                (data[key] is Map &&
                                    data[key]['name'] == shuttleName)) {
                              return data[key] as Map<dynamic, dynamic>;
                            }
                          }
                        } catch (_) {}
                      }
                      return null;
                    }

                    // กรองตามคำค้นหา
                    if (widget.searchQuery.isNotEmpty) {
                      final q = widget.searchQuery.toLowerCase();
                      docs = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = (data['name'] ?? '').toString().toLowerCase();
                        final id = (data['employee_id'] ?? data['student_id'] ?? '')
                            .toString()
                            .toLowerCase();
                        final phone = (data['phone'] ?? '').toString().toLowerCase();
                        return name.contains(q) || id.contains(q) || phone.contains(q);
                      }).toList();
                    }

                    // กรองตามแท็บสถานะ
                    if (_activeFilter != 'ทั้งหมด') {
                      docs = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final shuttleData = getShuttleData(data);
                        String rawStatus = shuttleData?['status'] ??
                            data['status'] ??
                            'offline';
                        String passengerStatus =
                            shuttleData?['passenger_status'] ??
                                data['passenger_status'] ??
                                (rawStatus == 'online'
                                    ? 'available'
                                    : 'offline');
                        if (rawStatus == 'offline') {
                          passengerStatus = 'offline';
                        }

                        if (_activeFilter == 'พร้อมบริการ') {
                          return passengerStatus == 'available';
                        }
                        if (_activeFilter == 'ที่นั่งเต็ม') {
                          return passengerStatus == 'full';
                        }
                        if (_activeFilter == 'พักเบรก') {
                          return passengerStatus == 'break';
                        }
                        if (_activeFilter == 'ออฟไลน์') {
                          return passengerStatus == 'offline';
                        }
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
                                width: constraints.maxWidth > 850
                                    ? constraints.maxWidth
                                    : 850,
                                child: Column(
                                  children: [
                                    // แถบหัวตาราง
                                    Container(
                                      color: const Color(0xFFF8FAF9),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          _buildTableHeader('ข้อมูลคนขับ', flex: 4),
                                          _buildTableHeader('รหัสประจำตัว', flex: 2),
                                          _buildTableHeader('รถที่ประจำการ', flex: 2),
                                          _buildTableHeader('สถานะบริการ', flex: 2),
                                          _buildTableHeader('เบอร์โทรศัพท์', flex: 2),
                                          _buildTableHeader(
                                            'การจัดการ',
                                            flex: 1,
                                            alignRight: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, color: Color(0xFFEFF2F0)),

                                    // รายการข้อมูล
                                    if (docs.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(48.0),
                                        child: Center(
                                          child: Text(
                                            'ไม่พบข้อมูลพนักงานขับรถตามเงื่อนไข',
                                            style: TextStyle(
                                              color: Color(0xFF718076),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      ...docs.map((doc) {
                                        final data =
                                            doc.data() as Map<String, dynamic>;
                                        final shuttleData = getShuttleData(data);

                                        String rawStatus =
                                            shuttleData?['status'] ??
                                                data['status'] ??
                                                'offline';
                                        String passengerStatus =
                                            shuttleData?['passenger_status'] ??
                                                data['passenger_status'] ??
                                                (rawStatus == 'online'
                                                    ? 'available'
                                                    : 'offline');
                                        if (rawStatus == 'offline') {
                                          passengerStatus = 'offline';
                                        }

                                        final name =
                                            data['name'] ?? 'ไม่มีชื่อ';
                                        final id = data['employee_id'] ??
                                            data['student_id'] ??
                                            'N/A';
                                        final phone = data['phone'] ?? '-';
                                        final shuttleName = data['shuttle_name'] ??
                                            data['shuttleName'] ??
                                            data['shuttle_number'] ??
                                            data['shuttleNumber'] ??
                                            'ยังไม่ผูกรถ';
                                        final avatar = data['avatar'] ??
                                            'assets/images/man1.png';

                                        return _buildDriverRow(
                                          name: name,
                                          id: id,
                                          phone: phone,
                                          shuttleName: shuttleName.toString(),
                                          status: passengerStatus,
                                          avatar: avatar,
                                          onEdit: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  EditDriverDialog(
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

                        // สรุปจำนวนรายการด้านล่าง
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 16.0,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFFEFF2F0)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'แสดงพนักงานทั้งหมด ${docs.length} คน',
                                style: const TextStyle(
                                  color: Color(0xFF718076),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
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
      ),
    );
  }

  Widget _buildFilterTab(String label, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF176a21).withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            color: isActive ? const Color(0xFF176a21) : const Color(0xFF718076),
            fontSize: 12.5,
          ),
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
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF5A605B),
        ),
      ),
    );
  }

  Widget _buildDriverRow({
    required String name,
    required String id,
    required String phone,
    required String shuttleName,
    required String status,
    required String avatar,
    required VoidCallback onEdit,
  }) {
    ImageProvider imageProvider;
    if (avatar.startsWith('http')) {
      imageProvider = NetworkImage(avatar);
    } else {
      imageProvider = AssetImage(avatar);
    }

    String statusText = 'ออฟไลน์';
    Color statusColor = const Color(0xFF757575);
    Color statusBgColor = const Color(0xFFF5F5F5);

    if (status == 'available') {
      statusText = 'พร้อมบริการ';
      statusColor = const Color(0xFF176a21);
      statusBgColor = const Color(0xFFE8F5E9);
    } else if (status == 'full') {
      statusText = 'ที่นั่งเต็ม';
      statusColor = const Color(0xFFE65100);
      statusBgColor = const Color(0xFFFFF3E0);
    } else if (status == 'break') {
      statusText = 'พักเบรก';
      statusColor = const Color(0xFFF57C00);
      statusBgColor = const Color(0xFFFFF8E1);
    }

    // จัดการแสดงผลชื่อรถประจำการ
    String displayShuttle = shuttleName.trim();
    bool isUnassigned = displayShuttle.isEmpty ||
        displayShuttle == '-' ||
        displayShuttle == 'ยังไม่ผูกรถ' ||
        displayShuttle == 'null';

    if (!isUnassigned) {
      final match = RegExp(r'(\d+)').firstMatch(displayShuttle);
      if (match != null) {
        final numStr = match.group(1)!.padLeft(2, '0');
        displayShuttle = 'Shuttle #$numStr';
      }
    } else {
      displayShuttle = 'ยังไม่ระบุรถ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEFF2F0))),
      ),
      child: Row(
        children: [
          // โปรไฟล์
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF176a21).withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: imageProvider,
                    backgroundColor: const Color(0xFFE8F5E9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF1E2923),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // รหัสพนักงาน
          Expanded(
            flex: 2,
            child: Text(
              id,
              style: const TextStyle(
                color: Color(0xFF5A605B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // รถที่ประจำการ
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isUnassigned
                        ? const Color(0xFFF5F5F5)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isUnassigned
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF176a21).withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.directions_bus_rounded,
                        size: 13,
                        color: isUnassigned
                            ? const Color(0xFF9E9E9E)
                            : const Color(0xFF176a21),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        displayShuttle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isUnassigned
                              ? const Color(0xFF757575)
                              : const Color(0xFF176a21),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // สถานะ
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(12),
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

          // เบอร์โทรศัพท์
          Expanded(
            flex: 2,
            child: Text(
              phone,
              style: const TextStyle(
                color: Color(0xFF5A605B),
                fontSize: 13,
              ),
            ),
          ),

          // การจัดการ
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF176a21),
                  size: 22,
                ),
                tooltip: 'แก้ไขข้อมูล',
                onPressed: onEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
