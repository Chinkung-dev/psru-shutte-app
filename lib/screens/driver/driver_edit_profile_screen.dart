import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool _isLoadingShuttles = false;

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

  String? _selectedShuttleName;
  String? _selectedShuttleNumber;

  List<String> _shuttleNames = [];
  List<String> _shuttleNumbers = [];
  List<Map<String, dynamic>> _shuttlesData = [];

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
          _selectedShuttleName = data['shuttle_name']?.toString();
          _selectedShuttleNumber = data['shuttle_number']?.toString();

          final String currentAvatar = data['avatar']?.toString() ?? 'assets/images/man1.png';
          final int index = _avatarList.indexOf(currentAvatar);
          if (index != -1) {
            _selectedAvatarIndex = index;
          }

          _pageController = PageController(viewportFraction: 0.5, initialPage: _selectedAvatarIndex);
        }
      }
      await _fetchShuttles();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchShuttles() async {
    setState(() => _isLoadingShuttles = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final snapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      final usedShuttleNames = <String>{};
      final usedShuttleNumbers = <String>{};

      for (var doc in driversSnapshot.docs) {
        if (currentUser != null && doc.id == currentUser.uid) {
          continue; // ไม่นับรถของตัวเองเป็นรถที่ถูกจองแล้ว
        }
        final data = doc.data();
        final sName = (data['shuttle_name'] ?? '').toString().trim();
        final sNum = (data['shuttle_number'] ?? '').toString().trim();
        if (sName.isNotEmpty) usedShuttleNames.add(sName);
        if (sNum.isNotEmpty) usedShuttleNumbers.add(sNum);
      }

      if (snapshot.docs.isNotEmpty) {
        final allData = snapshot.docs.map<Map<String, dynamic>>((doc) => {
          'id': doc.id,
          'name': doc.data()['name']?.toString().trim() ?? '',
          'number': doc.data()['number']?.toString().trim() ?? '',
        }).toList();

        final availableData = allData.where((s) {
          final name = s['name'] as String;
          final number = s['number'] as String;
          return name.isNotEmpty &&
              number.isNotEmpty &&
              !usedShuttleNames.contains(name) &&
              !usedShuttleNumbers.contains(number);
        }).toList();

        if (mounted) {
          setState(() {
            _shuttlesData = availableData;
            _shuttleNames = availableData.map((s) => s['name'] as String).toSet().toList();
            _shuttleNumbers = availableData.map((s) => s['number'] as String).toSet().toList();

            // หากชื่อรถของตัวเองไม่มีในรายการ ให้เพิ่มเข้าไปเพื่อให้เลือกต่อได้
            if (_selectedShuttleName != null && !_shuttleNames.contains(_selectedShuttleName)) {
              _shuttleNames.add(_selectedShuttleName!);
            }
            if (_selectedShuttleNumber != null && !_shuttleNumbers.contains(_selectedShuttleNumber)) {
              _shuttleNumbers.add(_selectedShuttleNumber!);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching shuttles: $e');
    } finally {
      if (mounted) setState(() => _isLoadingShuttles = false);
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

    if (name.isEmpty || driverId.isEmpty || phone.isEmpty || _selectedShuttleName == null || _selectedShuttleNumber == null) {
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
        // ตรวจสอบซ้ำว่ารถไม่ได้ถูกคนอื่นแย่งจองในระหว่างแก้ไข
        final checkExisting = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'driver')
            .get();

        for (var doc in checkExisting.docs) {
          if (doc.id == user.uid) continue;
          final data = doc.data();
          final existingName = (data['shuttle_name'] ?? '').toString().trim();
          final existingNumber = (data['shuttle_number'] ?? '').toString().trim();
          if (existingName == _selectedShuttleName || existingNumber == _selectedShuttleNumber) {
            _showSnackBar('ชื่อรถหรือหมายเลขรถนี้ถูกเลือกโดยคนขับท่านอื่นแล้ว กรุณาเลือกคันใหม่', Colors.orange);
            await _fetchShuttles();
            return;
          }
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'name': name,
          'student_id': driverId,
          'phone': phone,
          'shuttle_name': _selectedShuttleName,
          'shuttle_number': _selectedShuttleNumber,
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF176a21)))
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

                            _buildDropdownField(
                              label: 'ชื่อรถรับส่ง',
                              value: _selectedShuttleName,
                              items: _shuttleNames,
                              hint: _isLoadingShuttles
                                  ? 'กำลังตรวจสอบข้อมูลรถ...'
                                  : _shuttleNames.isEmpty
                                      ? 'ไม่มีรถรับส่งว่างในขณะนี้'
                                      : 'เลือกชื่อรถรับส่ง',
                              onChanged: (val) {
                                setState(() {
                                  _selectedShuttleName = val;
                                  final matchedShuttle = _shuttlesData.firstWhere(
                                    (s) => s['name'] == val,
                                    orElse: () => <String, dynamic>{},
                                  );
                                  if (matchedShuttle.isNotEmpty &&
                                      matchedShuttle['number'] != null &&
                                      matchedShuttle['number'].toString().isNotEmpty) {
                                    _selectedShuttleNumber = matchedShuttle['number'].toString();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            _buildDropdownField(
                              label: 'หมายเลขรถ',
                              value: _selectedShuttleNumber,
                              items: _shuttleNumbers,
                              hint: _isLoadingShuttles
                                  ? 'กำลังตรวจสอบข้อมูลรถ...'
                                  : _shuttleNumbers.isEmpty
                                      ? 'ไม่มีหมายเลขรถว่างในขณะนี้'
                                      : 'เลือกหมายเลขรถ',
                              onChanged: (val) => setState(() => _selectedShuttleNumber = val),
                            ),
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

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(
                hint,
                style: TextStyle(
                  color: items.isEmpty ? Colors.red.shade300 : Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: items.isEmpty ? Colors.red.shade300 : const Color(0xFF176a21),
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2F30),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
