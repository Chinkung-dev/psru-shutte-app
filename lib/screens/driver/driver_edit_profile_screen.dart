import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../widgets/app_loading_view.dart';
import '../../services/shuttle_access.dart';

class DriverEditProfileScreen extends StatefulWidget {
  const DriverEditProfileScreen({super.key});

  @override
  State<DriverEditProfileScreen> createState() => _DriverEditProfileScreenState();
}

class _DriverEditProfileScreenState extends State<DriverEditProfileScreen> {
  final _nameController = TextEditingController();
  final _driverIdController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  int _selectedAvatarIndex = 0;
  late PageController _pageController;

  final List<String> _avatarList = [
    'assets/images/man1.png',
    'assets/images/man2.png',
    'assets/images/man3.png',
    'assets/images/woman1.png',
    'assets/images/woman2.png',
    'assets/images/woman3.png',
  ];

  String? _assignedShuttleName;
  String? _assignedShuttleNumber;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.5, initialPage: 0);
    _loadCurrentUserData();
  }

  Future<void> _loadCurrentUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _nameController.text = data['name']?.toString() ?? '';
          _driverIdController.text = data['student_id']?.toString() ?? '';
          _phoneController.text = data['phone']?.toString() ?? '';
          _assignedShuttleName = (data['shuttle_name'] ?? data['shuttleName'])?.toString();
          _assignedShuttleNumber = (data['shuttle_number'] ?? data['shuttleNumber'])?.toString();

          final String currentAvatar = data['avatar']?.toString() ?? 'assets/images/man1.png';
          final int index = _avatarList.indexOf(currentAvatar);
          if (index != -1) {
            _selectedAvatarIndex = index;
          }

          _pageController = PageController(viewportFraction: 0.5, initialPage: _selectedAvatarIndex);
        }

        // หากยังไม่มีข้อมูลรถใน users ให้ตรวจสอบจากโหนด shuttles ใน RTDB
        if (_assignedShuttleName == null || _assignedShuttleNumber == null) {
          final rtdbSnap = await FirebaseDatabase.instance.ref('shuttles').get();
          if (rtdbSnap.exists && rtdbSnap.value is Map) {
            final shuttles = Map<String, dynamic>.from(rtdbSnap.value as Map);
            for (final entry in shuttles.entries) {
              final val = Map<String, dynamic>.from(entry.value as Map);
              if (val['driver_uid'] == user.uid) {
                _assignedShuttleName = val['name']?.toString();
                _assignedShuttleNumber = val['number']?.toString();
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _driverIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final driverId = _driverIdController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || driverId.isEmpty || phone.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (อย่างน้อย 2 ตัวอักษร และไม่มีตัวเลข)', Colors.red);
      return;
    }

    if (driverId.length < 3) {
      _showSnackBar('รหัสพนักงานขับรถต้องมีอย่างน้อย 3 ตัวอักษร', Colors.red);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showSnackBar('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0 เท่านั้น', Colors.red);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final avatar = _avatarList[_selectedAvatarIndex];

        // 1. บันทึกข้อมูลส่วนตัวลงใน users ของ Firestore เป็นหลักก่อนตาม REV-01
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'name': name,
          'student_id': driverId,
          'phone': phone,
          'avatar': avatar,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // 2. พยายามซิงก์ชื่อและรูปลงโหนด shuttles ใน RTDB ของรถที่ตนเองเป็นเจ้าของ
        bool rtdbSyncSuccess = true;
        if (_assignedShuttleName != null && _assignedShuttleName!.isNotEmpty) {
          try {
            final key = shuttleDatabaseKey(
              documentId: _assignedShuttleName!,
              name: _assignedShuttleName!,
              number: _assignedShuttleNumber ?? '',
            );

            await FirebaseDatabase.instance.ref('shuttles/$key').update({
              'driver_name': name,
              'driver_avatar': avatar,
            });
          } catch (rtdbErr) {
            debugPrint('RTDB driver profile sync notice: $rtdbErr');
            rtdbSyncSuccess = false;
          }
        }

        if (mounted) {
          if (rtdbSyncSuccess) {
            _showSnackBar('อัปเดตโปรไฟล์เรียบร้อยแล้ว', Colors.green);
          } else {
            _showSnackBar('บันทึกโปรไฟล์สำเร็จแล้ว แต่ข้อมูลบนรถยังไม่อัปเดต', Colors.orange);
          }
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('เกิดข้อผิดพลาดในการอัปเดตโปรไฟล์', Colors.red);
      }
      debugPrint('Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเดียวกับฝั่งนักศึกษา
      body: Column(
        children: [
          // Header ขอบล่างโค้งมน Curved Bottom Edge ตรงตามฝั่งนักศึกษา
          Container(
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
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 20, 16),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF176a21), size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'แก้ไขโปรไฟล์คนขับรถ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const AppLoadingView(
                    message: 'กำลังโหลดข้อมูลโปรไฟล์คนขับ...',
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar Selector Carousel สไตล์เดียวกับฝั่งนักศึกษา
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    if (_selectedAvatarIndex > 0) {
                                      _pageController.animateToPage(
                                        _selectedAvatarIndex - 1,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF176a21)),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    height: 150,
                                    child: PageView.builder(
                                      controller: _pageController,
                                      itemCount: _avatarList.length,
                                      onPageChanged: (int index) {
                                        setState(() {
                                          _selectedAvatarIndex = index;
                                        });
                                      },
                                      itemBuilder: (context, index) {
                                        bool isSelected = index == _selectedAvatarIndex;
                                        return GestureDetector(
                                          onTap: () {
                                            _pageController.animateToPage(
                                              index,
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          },
                                          child: Center(
                                            child: AspectRatio(
                                              aspectRatio: 1,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeOut,
                                                margin: EdgeInsets.all(isSelected ? 4 : 18),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.white,
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? const Color(0xFF176a21)
                                                        : const Color(0xFF81C784).withValues(alpha: 0.3),
                                                    width: isSelected ? 3.5 : 1.5,
                                                  ),
                                                  boxShadow: isSelected
                                                      ? [
                                                          BoxShadow(
                                                            color: const Color(0xFF176a21).withValues(alpha: 0.18),
                                                            blurRadius: 14,
                                                            offset: const Offset(0, 6),
                                                          )
                                                        ]
                                                      : [],
                                                  image: DecorationImage(
                                                    image: AssetImage(_avatarList[index]),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    if (_selectedAvatarIndex < _avatarList.length - 1) {
                                      _pageController.animateToPage(
                                        _selectedAvatarIndex + 1,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF176a21)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Center(
                              child: Text(
                                'เลื่อนเพื่อเลือกรูปภาพประจำตัว',
                                style: TextStyle(color: Color(0xFF757778), fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(height: 24),

                            _buildInputField(
                              label: 'ชื่อ-นามสกุล',
                              hint: 'ระบุชื่อ-นามสกุล',
                              icon: Icons.person_outline_rounded,
                              controller: _nameController,
                            ),
                            const SizedBox(height: 16),

                            _buildInputField(
                              label: 'รหัสพนักงานขับรถ',
                              hint: 'DRV-001',
                              icon: Icons.badge_outlined,
                              controller: _driverIdController,
                              inputFormatters: [LengthLimitingTextInputFormatter(20)],
                            ),
                            const SizedBox(height: 16),

                            _buildInputField(
                              label: 'เบอร์โทรศัพท์',
                              hint: '08xxxxxxxx',
                              icon: Icons.phone_android_rounded,
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                            ),
                            const SizedBox(height: 16),

                            _buildAssignedShuttleCard(),
                            const SizedBox(height: 32),

                            // ปุ่มบันทึกข้อมูล สไตล์เดียวกับฝั่งนักศึกษา
                            GestureDetector(
                              onTap: _isSaving ? null : _saveProfile,
                              child: Container(
                                width: double.infinity,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF176a21), Color(0xFF0F4D17)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF176a21).withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : const Text(
                                          'บันทึกข้อมูล',
                                          style: TextStyle(
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5A605B),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF81C784).withValues(alpha: 0.35),
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
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2F30),
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
              border: InputBorder.none,
              counterText: "",
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              suffixIcon: Icon(icon, color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssignedShuttleCard() {
    final hasVehicle = _assignedShuttleName != null && _assignedShuttleName!.isNotEmpty;
    final displayText = hasVehicle
        ? '${_assignedShuttleNumber ?? ''} (${_assignedShuttleName ?? ''})'
        : 'ยังไม่ได้รับมอบหมายรถประจำ';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'รถรับส่งที่ได้รับมอบหมาย',
          style: TextStyle(
            color: Color(0xFF5A605B),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF81C784).withValues(alpha: 0.35),
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
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF176a21).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  color: Color(0xFF176a21),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: hasVehicle ? const Color(0xFF2C2F30) : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasVehicle
                          ? 'มอบหมายโดยผู้ดูแลระบบ (อ่านอย่างเดียว)'
                          : 'ติดต่อผู้ดูแลระบบเพื่อรับมอบหมายรถ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'อ่านอย่างเดียว',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
