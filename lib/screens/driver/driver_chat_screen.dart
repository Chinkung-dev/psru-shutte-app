import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_loading_view.dart';

class DriverChatScreen extends StatefulWidget {
  final String? shuttleDocId;
  final String? shuttleName;

  const DriverChatScreen({
    super.key,
    this.shuttleDocId,
    this.shuttleName,
  });

  @override
  State<DriverChatScreen> createState() => _DriverChatScreenState();
}

class _DriverChatScreenState extends State<DriverChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? 'unknown_driver';
  Stream<QuerySnapshot>? _messagesStream;
  String? _currentRoomId;
  Timer? _dayCheckTimer;

  // ข้อความด่วนสำหรับคนขับรถ (Quick Responses)
  final List<String> _quickResponses = [
    'กำลังไปถึงป้ายครับ ',
    'รถเต็มแล้ว กำลังเดินทาง ',
    'ติดสัญญาณไฟ รอสักครู่ ',
    'ฝนตก รถอาจล่าช้าเล็กน้อย ',
    'ถึงจุดจอดหลักแล้วครับ ',
  ];

  @override
  void initState() {
    super.initState();
    _initChatStream();
    _dayCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAndRefreshRoomIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant DriverChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shuttleDocId != widget.shuttleDocId) {
      _initChatStream();
    }
  }

  String _getCanonicalRoomId() {
    String? rawId = widget.shuttleDocId;
    String? rawName = widget.shuttleName;
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

  bool _checkAndRefreshRoomIfNeeded() {
    final String baseRoom = _getCanonicalRoomId();
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String targetRoom = '${baseRoom}_$todayDate';
    if (_currentRoomId != targetRoom) {
      if (mounted) {
        setState(() {
          _initChatStream();
        });
      } else {
        _initChatStream();
      }
      return true;
    }
    return false;
  }

  void _initChatStream() {
    final String baseRoom = _getCanonicalRoomId();
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    _currentRoomId = '${baseRoom}_$todayDate';

    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(_currentRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ส่งข้อความขึ้น Firestore
  Future<void> _sendMessage([String? presetText]) async {
    final String text = (presetText ?? _messageController.text).trim();
    if (text.isEmpty) return;

    if (presetText == null) {
      _messageController.clear();
    }

    _checkAndRefreshRoomIfNeeded();

    final String targetRoom = _currentRoomId ??
        '${_getCanonicalRoomId()}_${DateFormat('yyyy_MM_dd').format(DateTime.now())}';

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(targetRoom)
          .collection('messages')
          .add({
        'text': text,
        'senderId': currentUserId,
        'sender_id': currentUserId,
        'senderName': widget.shuttleName ?? 'คนขับรถ',
        'sender_name': widget.shuttleName ?? 'คนขับรถ',
        'senderRole': 'driver',
        'sender_role': 'driver',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' ไม่สามารถส่งข้อความได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _dayCheckTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมมิ้นต์เดียวกับฝั่งนักศึกษา
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Expanded(
                      child: _buildMessageList(),
                    ),
                    // แถบข้อความด่วนสำหรับคนขับ (Quick Chips)
                    _buildQuickChips(),
                    _buildMessageInput(),
                    const SizedBox(height: 95), // เว้นที่ว่างด้านล่างเผื่อ Floating Bottom Dock
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ส่วนหัว (Curved Bottom Header) สรุปสถานะห้องสนทนา
  Widget _buildHeader() {
    final String displayName = widget.shuttleName != null
        ? widget.shuttleName!
        : 'Shuttle #${_getCanonicalRoomId().replaceAll(RegExp(r'[^0-9]'), '')}';

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
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF81C784), Color(0xFF176a21)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF176a21).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ห้องสนทนา : $displayName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF22C55E),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'คุยกับผู้โดยสาร / นักศึกษาในสายรถนี้',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF5A605B),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    Icon(Icons.badge_rounded, color: Color(0xFF176a21), size: 13),
                    SizedBox(width: 4),
                    Text(
                      'DRIVER',
                      style: TextStyle(
                        color: Color(0xFF176a21),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // แถบข้อความด่วนสำหรับคนขับรถ (Quick Responses)
  Widget _buildQuickChips() {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickResponses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = _quickResponses[index];
          return GestureDetector(
            onTap: () => _sendMessage(text),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF81C784).withValues(alpha: 0.5),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF176a21),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ส่วนแสดงรายการแชทแบบ Real-time
  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            message: 'กำลังโหลดข้อความสนทนา...',
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'เกิดข้อผิดพลาด: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 40,
                    color: Color(0xFF81C784),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ยังไม่มีข้อความในห้องสนทนานี้',
                  style: TextStyle(
                    color: Color(0xFF2C2F30),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'พิมพ์ข้อความหรือกดข้อความด่วนด้านล่างเพื่อแจ้งนักศึกษา',
                  style: TextStyle(color: Color(0xFF757778), fontSize: 12.5),
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs;

        return ListView.builder(
          controller: _scrollController,
          reverse: true, // ให้ข้อความใหม่สุดอยู่ล่างสุด
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final data = messages[index].data() as Map<String, dynamic>;
            final bool isMe = data['senderId'] == currentUserId;
            final String senderRole = data['senderRole'] ?? 'student';
            final String text = data['text'] ?? '';
            final Timestamp? timestamp = data['timestamp'] as Timestamp?;
            final String? imageUrl = data['imageUrl'] as String?;

            final String timeString = timestamp != null
                ? DateFormat('HH:mm').format(timestamp.toDate())
                : 'กำลังส่ง...';

            return _buildMessageBubble(
              text,
              timeString,
              isMe,
              senderRole,
              imageUrl,
            );
          },
        );
      },
    );
  }

  // ส่วนกล่องข้อความแชท
  Widget _buildMessageBubble(
    String text,
    String time,
    bool isMe,
    String senderRole,
    String? imageUrl,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: senderRole == 'driver'
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          senderRole == 'driver'
                              ? Icons.directions_bus_rounded
                              : Icons.school_rounded,
                          size: 11,
                          color: senderRole == 'driver'
                              ? const Color(0xFF176a21)
                              : const Color(0xFF1976D2),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          senderRole == 'driver' ? 'คนขับรถ' : 'นักศึกษา',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: senderRole == 'driver'
                                ? const Color(0xFF176a21)
                                : const Color(0xFF1976D2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            decoration: BoxDecoration(
              color: isMe ? null : Colors.white,
              gradient: isMe
                  ? const LinearGradient(
                      colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: isMe
                      ? const Color(0xFF176a21).withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
              border: isMe
                  ? null
                  : Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                      width: 1.0,
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: text.isNotEmpty ? 8.0 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        imageUrl,
                        width: 220,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            width: 220,
                            height: 160,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF176a21),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const SizedBox(
                          width: 220,
                          height: 120,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              size: 40,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (text.isNotEmpty)
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: isMe ? Colors.white : const Color(0xFF2C2F30),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF757778),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.done_all_rounded,
                  size: 13,
                  color: Color(0xFF176a21),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ส่วนช่องพิมพ์ข้อความด้านล่าง (Floating Input Bar)
  Widget _buildMessageInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.05),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(
                fontSize: 14.5,
                color: Color(0xFF2C2F30),
              ),
              decoration: const InputDecoration(
                hintText: 'พิมพ์แจ้งนักศึกษา...',
                hintStyle: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _sendMessage(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF176a21).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
