import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentEditProfileScreen extends StatefulWidget {
  const StudentEditProfileScreen({super.key});

  @override
  State<StudentEditProfileScreen> createState() => _StudentEditProfileScreenState();
}

class _StudentEditProfileScreenState extends State<StudentEditProfileScreen> {
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
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
          _studentIdController.text = data['student_id']?.toString() ?? '';
          _phoneController.text = data['phone']?.toString() ?? '';

          final String currentAvatar = data['avatar']?.toString() ?? 'assets/images/man1.png';
          final int index = _avatarList.indexOf(currentAvatar);
          if (index != -1) {
            _selectedAvatarIndex = index;
          }

          _pageController = PageController(viewportFraction: 0.5, initialPage: _selectedAvatarIndex);
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
    _studentIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final studentId = _studentIdController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || studentId.isEmpty || phone.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    if (name.length < 2) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (อย่างน้อย 2 ตัวอักษร)', Colors.red);
      return;
    }

    if (!RegExp(r'^\d{8,11}$').hasMatch(studentId)) {
      _showSnackBar('รหัสนักศึกษาต้องเป็นตัวเลข 8-11 หลักเท่านั้น (ห้ามกรอกตัวอักษร)', Colors.red);
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
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'name': name,
          'student_id': studentId,
          'phone': phone,
          'avatar': _avatarList[_selectedAvatarIndex],
          'updated_at': FieldValue.serverTimestamp(),
        });

        _showSnackBar('อัปเดตโปรไฟล์เรียบร้อยแล้ว!', Colors.green);
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาดในการอัปเดตโปรไฟล์', Colors.red);
      debugPrint('Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2),
      body: Column(
        children: [
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
                      'แก้ไขโปรไฟล์นักศึกษา',
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF176a21)))
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                                    color: isSelected ? const Color(0xFF176a21) : const Color(0xFF81C784).withValues(alpha: 0.3),
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
                              label: 'รหัสนักศึกษา',
                              hint: '6xxxxxxxxx',
                              icon: Icons.badge_outlined,
                              controller: _studentIdController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
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
                            const SizedBox(height: 32),
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
                                    )
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
                                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Colors.white),
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
        Text(label, style: const TextStyle(color: Color(0xFF5A605B), fontWeight: FontWeight.w600, fontSize: 13.5)),
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
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
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
}
