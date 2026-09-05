import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import '../../widgets/app_loading_view.dart';

class StudentChatScreen extends StatefulWidget {
  final String? shuttleId;
  final String? shuttleName;
  final String? driverName;
  final String? driverAvatar;
  final Function(int)? onSelectTab;

  const StudentChatScreen({
    super.key,
    this.shuttleId,
    this.shuttleName,
    this.driverName,
    this.driverAvatar,
    this.onSelectTab,
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

  String _getCanonicalRoomId() {
    String? rawId = widget.shuttleId;
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

  void _initChatStream() {
    final String baseRoom = _getCanonicalRoomId();
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

    final String baseRoom = _getCanonicalRoomId();
    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final String targetRoom = '${baseRoom}_$todayDate';

    try {
      Map<String, dynamic> messageData = {
        'text': text,
        'senderId': currentUserId,
        'sender_id': currentUserId,
        'senderName': 'นักศึกษา',
        'sender_name': 'นักศึกษา',
        'senderRole': 'student',
        'sender_role': 'student',
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl != null) {
        messageData['imageUrl'] = imageUrl;
        messageData['image_url'] = imageUrl;
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
            content: Text(' ไม่สามารถส่งข้อความได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      XFile? image;
      try {
        image = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
      } catch (cameraError) {
        // กรณีอุปกรณ์/เบราว์เซอร์ไม่รองรับ Camera API ตรงๆ ให้ fallback เป็นคลังภาพ/ไฟล์
        image = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
      }
      
      if (image == null) return;

      setState(() {
        _isUploadingImage = true;
      });

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final Reference ref = FirebaseStorage.instance.ref().child('chat_images').child(fileName);
      
      // ใช้อ่านเป็นไบต์ (Uint8List) เพื่อให้รองรับทั้ง Flutter Web (Hosting), Android และ iOS
      final Uint8List bytes = await image.readAsBytes();
      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await _sendMessage(imageUrl: downloadUrl);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' ไม่สามารถส่งรูปภาพได้: $e'),
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
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมเขียวมิ้นต์อ่อนๆ สบายตา
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ส่วนแสดงข้อความแชทและช่องพิมพ์ข้อความ (เว้นระยะด้านล่างไม่ให้ถูก Nav Bar บัง)
            Positioned.fill(
              bottom: isDesktop ? 95 : 75,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // แถบ Bottom Navigation Bar โค้งเว้า (Curved Notch) ล็อคอยู่ที่ขอบล่างสุดของหน้าจอแบบเดียวกับ StudentHome
            Positioned(
              bottom: isDesktop ? 20 : 0,
              left: 0,
              right: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _buildBottomNav(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แถบ Bottom Navigation Bar ดีไซน์โค้งเว้าพร้อมปุ่มวงกลมลอย (Curved Notch) แบบเดียวกับ StudentHome
  Widget _buildBottomNav() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map_outlined, 'activeIcon': Icons.map, 'label': 'Map'},
      {
        'icon': Icons.directions_bus_outlined,
        'activeIcon': Icons.directions_bus,
        'label': 'Live Status'
      },
      {'icon': Icons.chat_bubble_outline, 'activeIcon': Icons.chat_bubble, 'label': 'Chat'},
      {'icon': Icons.person_outline, 'activeIcon': Icons.person, 'label': 'Profile'},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFF9FBF9),
              ],
            ),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.04),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF176a21).withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // เมนู 4 ปุ่ม
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(navItems.length, (index) {
                    final bool isChatTab = index == 2;

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (widget.onSelectTab != null) {
                            widget.onSelectTab!(index);
                            Navigator.pop(context);
                          }
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isChatTab) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  navItems[index]['icon'],
                                  color: const Color(0xFF5A605B),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF757778),
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF81C784).withValues(alpha: 0.5),
                                    width: 1.0,
                                  ),
                                ),
                                child: Icon(
                                  navItems[index]['activeIcon'],
                                  color: const Color(0xFF176a21),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF176a21),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ส่วนหัว (Header) สรุปข้อมูลรถและคนขับ พร้อมปุ่มย้อนกลับ (ดีไซน์ Curved Bottom Edge)
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 14),
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
          bottom: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.03),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF176a21), size: 22),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF176a21).withOpacity(0.1),
                backgroundImage: (widget.driverAvatar != null && widget.driverAvatar!.isNotEmpty)
                    ? (widget.driverAvatar!.startsWith('http')
                        ? NetworkImage(widget.driverAvatar!) as ImageProvider
                        : AssetImage(widget.driverAvatar!))
                    : null,
                child: (widget.driverAvatar == null || widget.driverAvatar!.isEmpty)
                    ? const Icon(Icons.directions_bus_rounded, color: Color(0xFF176a21), size: 24)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2F30),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.shuttleName != null ? 'รถรับส่ง : ${widget.shuttleName}' : 'ห้องสนทนาสาย A',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF176a21),
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
          return const AppLoadingView(
            message: 'กำลังโหลดข้อความสนทนา...',
          );
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
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: text.isNotEmpty ? 8.0 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.black12, // ใส่สีพื้นหลังกันรูปโปร่งใส หรือกันโหลดไม่ขึ้น
                        child: Image.network(
                          imageUrl,
                          width: 200,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              width: 200,
                              height: 200,
                              child: Center(child: CircularProgressIndicator(color: Color(0xFF176a21))),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => const SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                          ),
                        ),
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