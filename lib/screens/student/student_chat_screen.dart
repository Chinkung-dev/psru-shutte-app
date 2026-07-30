import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentChatScreen extends StatefulWidget {
  final String? shuttleId;
  final String? shuttleName;
  final String? driverName;
  final String? driverAvatar;

  const StudentChatScreen({
    super.key,
    this.shuttleId,
    this.shuttleName,
    this.driverName,
    this.driverAvatar,
  });

  @override
  State<StudentChatScreen> createState() => _StudentChatScreenState();
}

class _StudentChatScreenState extends State<StudentChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  Stream<QuerySnapshot>? _messagesStream;
  String? _currentRoomId;
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _initChatStream();
  }

  @override
  void didUpdateWidget(covariant StudentChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shuttleId != widget.shuttleId) {
      _initChatStream();
    }
  }

  void _initChatStream() {
    final String baseRoom = widget.shuttleId ?? 'shuttle_line_a';
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    _currentRoomId = '${baseRoom}_$todayDate'; // แยกห้องตามวัน
    
    _updateLastReadTime();

    
    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(_currentRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _updateLastReadTime() async {
    if (_currentRoomId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_read_${_currentRoomId!}', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _updateLastReadTime();
    _messageController.dispose();
    super.dispose();
  }


  // ส่งข้อความขึ้น Firestore
  Future<void> _sendMessage({String? imageUrl}) async {
    if (_messageController.text.trim().isEmpty && imageUrl == null) return;

    final String text = _messageController.text.trim();
    _messageController.clear(); // ล้างช่องพิมพ์ทันที

    final String baseRoom = widget.shuttleId ?? 'shuttle_line_a';
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String targetRoom = '${baseRoom}_$todayDate';

    try {
      Map<String, dynamic> messageData = {
        'text': text,
        'senderId': currentUserId,
        'senderRole': 'student', // ✨ ระบุสิทธิ์ว่าเป็นนักศึกษาส่ง
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl != null) {
        messageData['imageUrl'] = imageUrl;
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(targetRoom)
          .collection('messages')
          .add(messageData);
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

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera, // ✨ บังคับเปิดกล้องถ่ายสดเท่านั้น
        imageQuality: 50, // บีบอัดรูปให้ประหยัดเน็ต
      );
      
      if (image == null) return;

      setState(() {
        _isUploadingImage = true;
      });

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final Reference ref = FirebaseStorage.instance.ref().child('chat_images').child(fileName);
      
      final bytes = await image.readAsBytes();
      final UploadTask uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await _sendMessage(imageUrl: downloadUrl);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถส่งรูปภาพได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // สีพื้นหลังเทาอ่อนตามแบบ
      body: SafeArea(
        bottom: false, // ปล่อย bottom ไว้เพื่อให้ไม่บังพื้นที่ด้านล่าง
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      Expanded(
              child: _buildMessageList(),
            ),
            _buildMessageInput(),
            const SizedBox(height: 20), // เว้นระยะช่องพิมพ์ข้อความด้านล่างเล็กน้อย
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ส่วนหัว (Header) สรุปข้อมูลรถและคนขับ พร้อมปุ่มย้อนกลับ
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF176a21), size: 26),
            onPressed: () => Navigator.pop(context),
          ),
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF176a21).withOpacity(0.1),
                backgroundImage: (widget.driverAvatar != null && widget.driverAvatar!.isNotEmpty)
                    ? (widget.driverAvatar!.startsWith('http') ? NetworkImage(widget.driverAvatar!) as ImageProvider : AssetImage(widget.driverAvatar!))
                    : null,
                child: (widget.driverAvatar == null || widget.driverAvatar!.isEmpty)
                    ? const Icon(Icons.directions_bus, color: Color(0xFF176a21), size: 24)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              )
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.driverName != null ? 'คนขับ : ${widget.driverName}' : 'คนขับรถประจำคัน',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF176a21),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.shuttleName != null ? 'รถรับส่ง : ${widget.shuttleName}' : 'ห้องสนทนาสาย A',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
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
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF176a21)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('เริ่มการสนทนากับคนขับรถคันนี้', style: TextStyle(color: Colors.grey)),
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
            final String? imageUrl = data['imageUrl'] as String?;
            
            // แปลงเวลาให้เป็นฟอร์แมต HH:mm
            final String timeString = timestamp != null 
                ? DateFormat('HH:mm').format(timestamp.toDate()) 
                : 'กำลังส่ง...';

            return _buildMessageBubble(text, timeString, isMe, senderRole, imageUrl);
          },
        );
      },
    );
  }

  // ส่วนกล่องข้อความแชท (สีเขียว และ สีขาว)
  Widget _buildMessageBubble(String text, String time, bool isMe, String senderRole, String? imageUrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    senderRole == 'driver' ? Icons.directions_bus : Icons.school,
                    size: 14,
                    color: senderRole == 'driver' ? const Color(0xFF176a21) : Colors.blueGrey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    senderRole == 'driver' ? 'คนขับรถ (ประกาศ)' : 'นักศึกษา',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: senderRole == 'driver' ? const Color(0xFF176a21) : Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? null : Colors.white,
              gradient: isMe 
                  ? const LinearGradient(
                      colors: [Color(0xFF67B26F), Color(0xFF4CA2CD)], // สีเขียว Gradient ตามแบบ
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 0), // ฝั่งคนอื่น มุมล่างซ้ายเหลี่ยม
                bottomRight: Radius.circular(isMe ? 0 : 20), // ฝั่งเรา มุมล่างขวาเหลี่ยม
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: text.isNotEmpty ? 8.0 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            width: 200,
                            height: 200,
                            color: Colors.black12,
                            child: const Center(child: CircularProgressIndicator(color: Color(0xFF176a21))),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      ),
                    ),
                  ),
                if (text.isNotEmpty)
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isMe ? Colors.white : const Color(0xFF2C2F30),
                    ),
                  ),
              ],
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
                const Icon(Icons.done_all, size: 14, color: Colors.green), // ขีดถูกอ่านแล้ว
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
          IconButton(
            icon: _isUploadingImage 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.camera_alt, color: Colors.grey, size: 28),
            onPressed: _isUploadingImage ? null : _pickAndSendImage,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
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
                color: Color(0xFF67B26F),
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