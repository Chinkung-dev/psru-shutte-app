import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'student_chat_screen.dart';

class StudentChatListScreen extends StatefulWidget {
  const StudentChatListScreen({super.key});

  @override
  State<StudentChatListScreen> createState() => _StudentChatListScreenState();
}

class _StudentChatListScreenState extends State<StudentChatListScreen> {
  String _searchQuery = '';
  late final Stream<QuerySnapshot> _driversStream;
  late final Stream<QuerySnapshot> _shuttlesStream;

  @override
  void initState() {
    super.initState();
    _driversStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots();
    _shuttlesStream = FirebaseFirestore.instance
        .collection('shuttles')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF5F7F8,
      ), // สีพื้นหลังเทาอ่อนสะอาดตาตามดีไซน์
      body: Column(
        children: [
          _buildHeader(context),
          _buildMessagesTitle(),
          _buildSearchBar(),
          Expanded(child: _buildShuttleList()),
          const SizedBox(
            height: 80,
          ), // เว้นที่ด้านล่างเผื่อ Bottom Navigation Bar
        ],
      ),
    );
  }

  // ส่วนหัวข้อแบบแถบสีขาวเหมือน student_home
  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  Scaffold.maybeOf(context)?.openDrawer();
                },
                child: Container(
                  width: 150,
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'lib/screens/driver/logo.png',
                    height: 42,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.menu, color: Color(0xFF176a21), size: 28),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ส่วนหัวข้อ Messages (อยู่ด้านบนช่องค้นหา Search conversations)
  Widget _buildMessagesTitle() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Center(
        child: Text(
          'Messages',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF176a21),
          ),
        ),
      ),
    );
  }

  // ช่องค้นหา Search conversations...
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECEF), // สีเทาอ่อนโค้งมนตามแบบ
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: const InputDecoration(
          icon: Icon(Icons.search, color: Colors.blueGrey),
          hintText: 'Search conversations...',
          hintStyle: TextStyle(color: Colors.blueGrey, fontSize: 15),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // ส่วนรายการห้องแชทรถแต่ละคัน
  Widget _buildShuttleList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _driversStream,
      builder: (context, driverSnapshot) {
        final driverDocs = driverSnapshot.hasData
            ? driverSnapshot.data!.docs
            : [];
        final Map<String, Map<String, dynamic>> driverMapByShuttleName = {};
        final Map<String, Map<String, dynamic>> driverMapByShuttleNum = {};

        for (var doc in driverDocs) {
          final d = doc.data() as Map<String, dynamic>;
          final sName = (d['shuttle_name'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final sNum = (d['shuttle_number'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          if (sName.isNotEmpty) driverMapByShuttleName[sName] = d;
          if (sNum.isNotEmpty) driverMapByShuttleNum[sNum] = d;
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _shuttlesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF176a21)),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  'ยังไม่มีรถรับส่งในระบบ',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final String name = (data['name'] ?? doc.id).toString();
              final String number = (data['number'] ?? '').toString();

              final dMap =
                  driverMapByShuttleName[name.toLowerCase().trim()] ??
                  driverMapByShuttleNum[number.toLowerCase().trim()];
              final String driverName =
                  data['driver_name'] ??
                  data['driverName'] ??
                  dMap?['name'] ??
                  'คนขับรถประจำคัน';

              final q = _searchQuery;
              return name.toLowerCase().contains(q) ||
                  number.toLowerCase().contains(q) ||
                  driverName.toLowerCase().contains(q);
            }).toList();

            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  'ไม่พบห้องสนทนาที่ค้นหา',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final String shuttleId = doc.id;
                final String shuttleName = data['name'] ?? shuttleId;
                final String shuttleNumber = data['number'] ?? '';

                final dMap =
                    driverMapByShuttleName[shuttleName.toLowerCase().trim()] ??
                    driverMapByShuttleNum[shuttleNumber.toLowerCase().trim()];
                final String driverName =
                    data['driver_name'] ??
                    data['driverName'] ??
                    dMap?['name'] ??
                    'คนขับรถประจำคัน';
                final String driverAvatar =
                    data['driver_avatar'] ??
                    data['avatar'] ??
                    dMap?['avatar'] ??
                    '';

                final bool isOnline = data['status'] == 'online';

                // จัดการตัวเลขให้สวยงาม ไม่ให้ซ้ำซ้อน เช่น SH#03 -> 03
                String cleanNum = shuttleNumber.replaceAll(
                  RegExp(r'[^0-9]'),
                  '',
                );
                final String badgeText = cleanNum.isNotEmpty
                    ? 'Shuttle #$cleanNum'
                    : shuttleName;

                return _buildChatCard(
                  context: context,
                  shuttleId: shuttleId,
                  shuttleName: shuttleName,
                  driverName: driverName,
                  driverAvatar: driverAvatar,
                  badgeText: badgeText,
                  isOnline: isOnline,
                );
              },
            );
          },
        );
      },
    );
  }

  // การ์ดแชทแต่ละคันตามดีไซน์ Mockup
  Widget _buildChatCard({
    required BuildContext context,
    required String shuttleId,
    required String shuttleName,
    required String driverName,
    required String driverAvatar,
    required String badgeText,
    required bool isOnline,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(shuttleId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String lastMessage = 'แตะเพื่อเริ่มการสนทนา...';
        String timeString = '';

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final lastDoc =
              snapshot.data!.docs.first.data() as Map<String, dynamic>;
          final String text = lastDoc['text'] ?? '';
          lastMessage = '"$text"'; // ใส่เครื่องหมายคำพูดตามแบบภาพ

          final Timestamp? timestamp = lastDoc['timestamp'] as Timestamp?;
          if (timestamp != null) {
            final date = timestamp.toDate();
            final now = DateTime.now();
            if (date.year == now.year &&
                date.month == now.month &&
                date.day == now.day) {
              timeString = DateFormat('hh:mm a').format(date);
            } else {
              timeString = 'Yesterday';
            }
          }
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentChatScreen(
                  shuttleId: shuttleId,
                  shuttleName: shuttleName,
                  driverName: driverName,
                  driverAvatar: driverAvatar,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // รูป Avatar พร้อมจุดสถานะออนไลน์
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF176a21).withOpacity(0.1),
                      backgroundImage: driverAvatar.isNotEmpty
                          ? (driverAvatar.startsWith('http')
                                ? NetworkImage(driverAvatar) as ImageProvider
                                : AssetImage(driverAvatar))
                          : null,
                      child: driverAvatar.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Color(0xFF176a21),
                              size: 34,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF2E7D32)
                              : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // รายละเอียดคนขับและข้อความ
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Driver: $driverName',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C2F30),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            timeString,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // ป้าย Badge บอกเบอร์รถ (สีเขียวอ่อนตามภาพ)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ตัวอย่างข้อความล่าสุด
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF5A6065),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOnline)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32),
                                shape: BoxShape.circle,
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
      },
    );
  }
}
