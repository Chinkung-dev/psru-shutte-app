import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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
  final String currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? 'unknown_driver';

  // ส่งข้อความขึ้น Firestore
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String text = _messageController.text.trim();
    _messageController.clear(); // ล้างช่องพิมพ์ทันที

    final String targetRoom = widget.shuttleDocId ?? 'shuttle_line_a'; // แยกห้องตาม ID รถคันนั้นๆ

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(targetRoom)
          .collection('messages')
          .add({
        'text': text,
        'senderId': currentUserId,
        'senderRole': 'driver', // ✨ ระบุสิทธิ์ว่าเป็นคนขับส่ง
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถส่งข้อความได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        bottom: false, // ปล่อย bottom ไว้เพื่อให้ไม่บัง BottomNavBar ของหน้า Home
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildMessageList(),
            ),
            _buildMessageInput(),
            const SizedBox(height: 80), // เว้นที่ว่างด้านล่างเผื่อ BottomNavBar
          ],
        ),
      ),
    );
  }

  // ส่วนหัว (Header) สรุปสถานะห้องสนทนา
  Widget _buildHeader() {
    final String displayName = widget.shuttleName != null ? 'ห้องสนทนาประจำรถ : ${widget.shuttleName}' : 'ห้องสนทนารถรับส่ง';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF176a21).withOpacity(0.1),
            child: const Icon(Icons.directions_bus, color: Color(0xFF176a21), size: 28),
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
                const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 10),
                    SizedBox(width: 4),
                    Text(
                      'คุยกับผู้โดยสาร / นักศึกษาในสายรถนี้',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ส่วนแสดงรายการแชทแบบ Real-time
  Widget _buildMessageList() {
    final String targetRoom = widget.shuttleDocId ?? 'shuttle_line_a'; // แยกห้องตาม ID รถคันนั้นๆ

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(targetRoom)
          .collection('messages')
          .orderBy('timestamp', descending: true) // เรียงจากใหม่ไปเก่า (ให้อยู่ล่างสุด)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF176a21)));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('เกิดข้อผิดพลาด: ${snapshot.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('ยังไม่มีข้อความในห้องสนทนานี้',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 4),
                Text('พิมพ์ข้อความเพื่อแจ้งข่าวสารแก่นักศึกษา',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs;

        return ListView.builder(
          reverse: true, // ให้ข้อความใหม่สุดอยู่ล่างสุด
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final data = messages[index].data() as Map<String, dynamic>;
            final bool isMe = data['senderId'] == currentUserId;
            final String senderRole = data['senderRole'] ?? 'student';
            final String text = data['text'] ?? '';
            final Timestamp? timestamp = data['timestamp'] as Timestamp?;

            final String timeString = timestamp != null
                ? DateFormat('HH:mm').format(timestamp.toDate())
                : 'กำลังส่ง...';

            return _buildMessageBubble(text, timeString, isMe, senderRole);
          },
        );
      },
    );
  }

  // ส่วนกล่องข้อความแชท
  Widget _buildMessageBubble(
      String text, String time, bool isMe, String senderRole) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
                  const Icon(Icons.school, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text(
                    senderRole == 'driver' ? 'คนขับรถคันอื่น' : 'นักศึกษา',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? null : Colors.white,
              gradient: isMe
                  ? const LinearGradient(
                      colors: [Color(0xFF176a21), Color(0xFF67B26F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: isMe ? Colors.white : const Color(0xFF2C2F30),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                const Icon(Icons.done_all, size: 14, color: Colors.green),
              ]
            ],
          ),
        ],
      ),
    );
  }

  // ส่วนช่องพิมพ์ข้อความด้านล่าง
  Widget _buildMessageInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: 'พิมพ์แจ้งนักศึกษา...',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF176a21),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
