import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/app_loading_view.dart';
import 'student_chat_screen.dart';

class StudentChatListScreen extends StatefulWidget {
  final Function(int)? onSelectTab;
  const StudentChatListScreen({super.key, this.onSelectTab});

  @override
  State<StudentChatListScreen> createState() => _StudentChatListScreenState();
}

class _StudentChatListScreenState extends State<StudentChatListScreen> {
  String _searchQuery = '';
  StreamSubscription? _rtdbSub;
  StreamSubscription? _driversSub;

  Map<dynamic, dynamic> _rtdbShuttles = {};
  List<Map<String, dynamic>> _driverUsers = [];
  List<Map<String, dynamic>> _shuttleList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToData();
  }

  void _listenToData() {
    _driversSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _driverUsers = snapshot.docs.map((d) => d.data()).toList();
      _mergeAndRefreshChatList();
    });

    _rtdbSub = FirebaseDatabase.instance.ref('shuttles').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value is Map) {
        _rtdbShuttles = event.snapshot.value as Map<dynamic, dynamic>;
      } else {
        _rtdbShuttles = {};
      }
      _mergeAndRefreshChatList();
    });
  }

  void _mergeAndRefreshChatList() {
    final Map<String, Map<String, dynamic>> shuttleMap = {};
    final now = DateTime.now();

    // 1. ประมวลผล RTDB Shuttles (เป็นข้อมูลหลักสำหรับสถานะ Real-time)
    _rtdbShuttles.forEach((rtdbKey, rtdbDoc) {
      if (rtdbDoc is! Map) return;

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

      final String badgeText =
          cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : name;
      final String driverName = (rtdbDoc['driver_name'] ?? '').toString();
      final String driverAvatar = (rtdbDoc['driver_avatar'] ?? '').toString();

      shuttleMap[shuttleKey] = {
        'shuttleId': rtdbKey.toString(),
        'name': name,
        'number': number,
        'cleanNum': cleanNum,
        'badgeText': badgeText,
        'driverName': driverName.isNotEmpty ? driverName : 'คนขับรถประจำคัน',
        'driverAvatar': driverAvatar,
        'isOnline': isOnline,
      };
    });

    // 2. ผสานข้อมูลจาก Firestore Driver Users (users role == 'driver')
    for (var dUser in _driverUsers) {
      final String sName = (dUser['shuttle_name'] ?? '').toString();
      final String sNum = (dUser['shuttle_number'] ?? '').toString();
      String cleanNum = sNum.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.isEmpty) {
        cleanNum = sName.replaceAll(RegExp(r'[^0-9]'), '');
      }
      final String shuttleKey =
          cleanNum.isNotEmpty ? cleanNum : sName.toLowerCase().trim();

      if (shuttleKey.isEmpty) continue;

      final String badgeText =
          cleanNum.isNotEmpty ? 'Shuttle #$cleanNum' : sName;
      final String uDriverName = (dUser['name'] ?? '').toString();
      final String uDriverAvatar = (dUser['avatar'] ?? '').toString();

      if (shuttleMap.containsKey(shuttleKey)) {
        var existing = shuttleMap[shuttleKey]!;
        if ((existing['driverName'] == 'คนขับรถประจำคัน' ||
                (existing['driverName'] as String).isEmpty) &&
            uDriverName.isNotEmpty) {
          existing['driverName'] = uDriverName;
        }
        if ((existing['driverAvatar'] as String).isEmpty &&
            uDriverAvatar.isNotEmpty) {
          existing['driverAvatar'] = uDriverAvatar;
        }
      } else {
        shuttleMap[shuttleKey] = {
          'shuttleId':
              'shuttle_${cleanNum.isNotEmpty ? cleanNum : shuttleKey}',
          'name': sName.isNotEmpty ? sName : 'Shuttle #$cleanNum',
          'number': sNum,
          'cleanNum': cleanNum,
          'badgeText': badgeText,
          'driverName':
              uDriverName.isNotEmpty ? uDriverName : 'คนขับรถประจำคัน',
          'driverAvatar': uDriverAvatar,
          'isOnline': false,
        };
      }
    }

    List<Map<String, dynamic>> list = shuttleMap.values.toList();

    // จัดเรียงลำดับ: รถที่ออนไลน์ (isOnline == true) อยู่ด้านบนสุดเสมอ!
    list.sort((a, b) {
      bool aOnline = a['isOnline'] == true;
      bool bOnline = b['isOnline'] == true;
      if (aOnline && !bOnline) return -1; // a อยู่บน
      if (!aOnline && bOnline) return 1; // b อยู่บน
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
    _driversSub?.cancel();
    _rtdbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมเขียวมิ้นต์อ่อนๆ สบายตา
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
                      height: 100,
                    ), // เว้นที่ด้านล่างเผื่อ Bottom Navigation Bar แบบลอย
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ส่วนหัวข้อแบบ Curved Bottom Edge เหมือน student_home
  Widget _buildHeader(BuildContext context) {
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

  // ส่วนหัวข้อ Messages (อยู่ด้านบนช่องค้นหา Search conversations)
  Widget _buildMessagesTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'กล่องข้อความคนขับ',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2F30),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF81C784).withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF176a21), size: 14),
                SizedBox(width: 4),
                Text(
                  'CHAT ROOMS',
                  style: TextStyle(
                    color: Color(0xFF176a21),
                    fontSize: 10.5,
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

  // ช่องค้นหา Search conversations...
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF81C784).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: const InputDecoration(
          icon: Icon(Icons.search_rounded, color: Color(0xFF176a21)),
          hintText: 'ค้นหาคนขับหรือเบอร์รถรับส่ง...',
          hintStyle: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  // ส่วนรายการห้องแชทรถแต่ละคัน
  Widget _buildShuttleList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60.0),
        child: AppLoadingView(message: 'กำลังโหลดรายการห้องแชท...'),
      );
    }

    final items = _shuttleList.where((item) {
      final String name = (item['name'] ?? item['shuttleId']).toString();
      final String number = (item['number'] ?? '').toString();
      final String driverName = (item['driverName'] ?? '').toString();
      final q = _searchQuery;
      return name.toLowerCase().contains(q) ||
          number.toLowerCase().contains(q) ||
          driverName.toLowerCase().contains(q);
    }).toList();

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'ไม่พบห้องสนทนาที่ค้นหา',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildChatCard(
          context: context,
          shuttleId: item['shuttleId'],
          shuttleName: item['name'],
          driverName: item['driverName'],
          driverAvatar: item['driverAvatar'],
          badgeText: item['badgeText'],
          isOnline: item['isOnline'],
        );
      },
    );
  }

  String _getCanonicalRoomId(String? rawId, String? rawName) {
    String cleanNum = (rawName ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNum.isEmpty && rawId != null && !rawId.startsWith('-')) {
      cleanNum = rawId.replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (cleanNum.isNotEmpty) {
      int numVal = int.tryParse(cleanNum) ?? 1;
      String formattedNum = numVal.toString().padLeft(2, '0');
      return 'shuttle_$formattedNum';
    }
    if (rawId != null && rawId.isNotEmpty && !rawId.startsWith('-')) {
      return rawId;
    }
    return 'shuttle_01';
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
    final String baseRoom = _getCanonicalRoomId(shuttleId, shuttleName);
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String targetRoom = '${baseRoom}_$todayDate';

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
              onTap: () async {
                if (prefSnapshot.hasData) {
                  prefSnapshot.data!.setInt('last_read_$targetRoom', DateTime.now().millisecondsSinceEpoch);
                  setState(() {});
                }

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentChatScreen(
                      shuttleId: shuttleId,
                      shuttleName: shuttleName,
                      driverName: driverName,
                      driverAvatar: driverAvatar,
                      onSelectTab: widget.onSelectTab,
                    ),
                  ),
                );
                if (mounted) {
                  setState(() {});
                }
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
                              if (timeString.isNotEmpty)
                                Text(
                                  timeString,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                    color: isUnread ? const Color(0xFF176a21) : const Color(0xFF757778),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF176a21).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF176a21),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lastMessage,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              color: isUnread ? Colors.black87 : const Color(0xFF595C5D),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
