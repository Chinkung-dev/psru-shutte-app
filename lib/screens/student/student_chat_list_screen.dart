import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    _buildMessagesTitle(),
          _buildSearchBar(),
          Expanded(child: _buildShuttleList()),
          const SizedBox(
            height: 80,
          ), // เว้นที่ด้านล่างเผื่อ Bottom Navigation Bar
                  ],
                ),
              ),
            ),
          ),
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

                bool isOnline = data['status'] == 'online';

                // ✨ ตรวจสอบ Timeout 5 นาทีว่ารถยังออนอยู่จริงไหม
                final Timestamp? lastUpdated = data['last_updated'] as Timestamp?;
                if (lastUpdated != null) {
                  final now = DateTime.now();
                  final updatedTime = lastUpdated.toDate();
                  if (now.difference(updatedTime).inMinutes > 5) {
                    isOnline = false;
                  }
                } else if (isOnline) {
                  isOnline = false; // เผื่อกรณีค้าง
                }

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
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String targetRoom = '${shuttleId}_$todayDate';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(targetRoom)
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
          final String? imageUrl = lastDoc['imageUrl'] as String?;
          final String senderRole = lastDoc['senderRole'] ?? 'student';
          
          if (imageUrl != null) {
            lastMessage = text.isNotEmpty ? '"$text" [ส่งรูปภาพ]' : '[ส่งรูปภาพ]';
          } else {
            lastMessage = '"$text"'; // ใส่เครื่องหมายคำพูดตามแบบภาพ
          }

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

        // ห่อด้วย FutureBuilder เพื่อเช็คว่าอ่านหรือยัง
        return FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, prefSnapshot) {
            bool isUnread = false;
            if (prefSnapshot.hasData && snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
              final lastDoc = snapshot.data!.docs.first.data() as Map<String, dynamic>;
              final senderRole = lastDoc['senderRole'] ?? 'student';
              final Timestamp? msgTimestamp = lastDoc['timestamp'] as Timestamp?;
              
              if (senderRole == 'driver' && msgTimestamp != null) {
                final int lastReadTime = prefSnapshot.data!.getInt('last_read_$targetRoom') ?? 0;
                if (msgTimestamp.millisecondsSinceEpoch > lastReadTime) {
                  isUnread = true;
                }
              }
            }

            return GestureDetector(
              onTap: () {
                // อัปเดต state ของ local ให้เป็นอ่านแล้วทันทีเพื่อความสมูท
                if (prefSnapshot.hasData) {
                  prefSnapshot.data!.setInt('last_read_$targetRoom', DateTime.now().millisecondsSinceEpoch);
                  setState(() {});
                }
                
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
                ).then((_) {
                  // รีเฟรชหน้าจอนี้เมื่อกลับมาจากหน้าแชท เพื่อล้างตัวหนา
                  setState(() {});
                });
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
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                  color: isUnread ? Colors.black : Colors.grey,
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                    color: isUnread ? Colors.black : const Color(0xFF5A6065),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isUnread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              else if (isOnline)
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
          }
        );
      },
    );
  }
}
