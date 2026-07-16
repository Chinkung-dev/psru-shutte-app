import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController(); // ✨ เบอร์โทรศัพท์

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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

  // ✨ ตัวแปรสำหรับเก็บว่ากำลังสมัครเป็นใคร (ค่าเริ่มต้นคือ นักศึกษา)
  String _selectedRole = 'student'; 
  
  // ✨ ตัวแปรสำหรับข้อมูล Driver
  String? _selectedShuttleName;
  String? _selectedShuttleNumber;

  List<String> _shuttleNames = [];
  List<String> _shuttleNumbers = [];
  List<Map<String, dynamic>> _shuttlesData = [];
  bool _isLoadingShuttles = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.5, initialPage: _selectedAvatarIndex);
    _fetchShuttles();
  }

  Future<void> _fetchShuttles() async {
    setState(() => _isLoadingShuttles = true);
    try {
      // ดึงรายชื่อรถทั้งหมดในระบบ
      final snapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      // ดึงรายชื่อคนขับที่มีอยู่ในระบบแล้วเพื่อเช็คว่ารถคันไหนถูกจองไปแล้ว
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      final usedShuttleNames = <String>{};
      final usedShuttleNumbers = <String>{};

      for (var doc in driversSnapshot.docs) {
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

        // กรองเอาเฉพาะรถที่ยังไม่มีคนขับลงทะเบียนใช้
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
            _shuttleNames = availableData
                .map((s) => s['name'] as String)
                .toSet()
                .toList();
            _shuttleNumbers = availableData
                .map((s) => s['number'] as String)
                .toSet()
                .toList();

            // รีเซ็ตค่าหากค่าที่เลือกไว้ก่อนหน้าไม่มีในตัวเลือกแล้ว
            if (_selectedShuttleName != null &&
                !_shuttleNames.contains(_selectedShuttleName)) {
              _selectedShuttleName = null;
            }
            if (_selectedShuttleNumber != null &&
                !_shuttleNumbers.contains(_selectedShuttleNumber)) {
              _selectedShuttleNumber = null;
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
    _studentIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final studentId = _studentIdController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || studentId.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    // 1. ตรวจสอบชื่อ-นามสกุล
    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (อย่างน้อย 2 ตัวอักษร และไม่มีตัวเลข)', Colors.red);
      return;
    }

    // 2. ตรวจสอบรหัสนักศึกษา/รหัสคนขับรถ
    if (_selectedRole == 'student') {
      if (!RegExp(r'^\d{8,11}$').hasMatch(studentId)) {
        _showSnackBar('รหัสนักศึกษาต้องเป็นตัวเลข 8-11 หลักเท่านั้น (ห้ามกรอกตัวอักษร)', Colors.red);
        return;
      }
    } else {
      if (studentId.length < 3) {
        _showSnackBar('รหัสพนักงานขับรถต้องมีอย่างน้อย 3 ตัวอักษร', Colors.red);
        return;
      }
    }

    // 3. ตรวจสอบเบอร์โทรศัพท์ (10 หลัก ขึ้นต้นด้วย 0)
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showSnackBar('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0 เท่านั้น', Colors.red);
      return;
    }

    // 4. ตรวจสอบรูปแบบอีเมล
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      _showSnackBar('กรุณากรอกรูปแบบอีเมลให้ถูกต้อง (เช่น name@example.com)', Colors.red);
      return;
    }

    if (_selectedRole == 'driver') {
      if (_selectedShuttleName == null || _selectedShuttleNumber == null) {
        _showSnackBar('กรุณาเลือกรถรับส่งสำหรับคนขับให้ครบถ้วน', Colors.red);
        return;
      }

      // ตรวจสอบซ้ำอีกครั้งว่ารถคันที่เลือกเพิ่งถูกสมัครใช้งานไปหรือไม่
      try {
        final checkExisting = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'driver')
            .get();

        for (var doc in checkExisting.docs) {
          final data = doc.data();
          final existingName = (data['shuttle_name'] ?? '').toString().trim();
          final existingNumber = (data['shuttle_number'] ?? '').toString().trim();
          if (existingName == _selectedShuttleName || existingNumber == _selectedShuttleNumber) {
            _showSnackBar('ชื่อรถหรือหมายเลขรถนี้เพิ่งถูกสมัครโดยคนขับท่านอื่นแล้ว กรุณาเลือกคันใหม่', Colors.orange);
            await _fetchShuttles();
            return;
          }
        }
      } catch (e) {
        debugPrint('Error checking duplicate shuttle: $e');
      }
    }

    if (password != confirmPassword) {
      _showSnackBar('รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน!', Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // บันทึกข้อมูลลง Firestore
      Map<String, dynamic> userData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'student_id': studentId,
        'phone': phone,
        'email': email,
        'role': _selectedRole, // ✨ บันทึกตามสิทธิ์ที่ผู้ใช้เลือกใน Dropdown
        'avatar': _avatarList[_selectedAvatarIndex], 
        'hasSeenOnboarding': _selectedRole == 'student' ? false : true,
        'created_at': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'driver') {
        userData['shuttle_name'] = _selectedShuttleName;
        userData['shuttle_number'] = _selectedShuttleNumber;
      }

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set(userData);

      _showSnackBar('สร้างบัญชีสำเร็จ! กรุณาเข้าสู่ระบบ', Colors.green);
      
      if (mounted) {
        Navigator.pop(context); 
      }

    } on FirebaseAuthException catch (e) {
      String message = 'เกิดข้อผิดพลาดในการสร้างบัญชี';
      if (e.code == 'email-already-in-use') {
        message = 'อีเมลนี้ถูกใช้งานแล้ว';
      } else if (e.code == 'invalid-email') {
        message = 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      _showSnackBar(message, Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      backgroundColor: const Color(0xFFF7F9FA), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF176a21)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'สร้างบัญชีใหม่',
          style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
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
                    icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF176a21)),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 140,
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
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              margin: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: isSelected ? 5 : 25,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF176a21) : Colors.transparent,
                                  width: isSelected ? 4 : 0,
                                ),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]
                                    : [],
                                image: DecorationImage(
                                  image: AssetImage(_avatarList[index]),
                                  fit: BoxFit.cover,
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
                    icon: const Icon(Icons.arrow_forward_ios, color: Color(0xFF176a21)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  '👈 คลิกปุ่มลูกศร, คลิกที่รูป หรือลากเมาส์เลื่อนเพื่อเลือกรูป 👉',
                  style: TextStyle(color: Color(0xFF757778), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 30),

              // ✨ เพิ่ม Dropdown เลือกประเภทผู้ใช้งานตรงนี้
              _buildRoleSelector(),
              const SizedBox(height: 16),

              _buildInputField(
                label: 'ชื่อ-นามสกุล',
                hint: 'John Doe',
                icon: Icons.person_outline,
                controller: _nameController,
              ),
              const SizedBox(height: 16),

              // ✨ เปลี่ยนชื่อ Label ตามประเภทที่เลือก
              _buildInputField(
                label: _selectedRole == 'student' ? 'รหัสนักศึกษา' : 'รหัสพนักงานขับรถ',
                hint: _selectedRole == 'student' ? '64xxxxxxx' : 'DRV-001',
                icon: Icons.badge_outlined,
                controller: _studentIdController,
                keyboardType: _selectedRole == 'student' ? TextInputType.number : TextInputType.text,
                inputFormatters: _selectedRole == 'student'
                    ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]
                    : [LengthLimitingTextInputFormatter(20)],
              ),
              const SizedBox(height: 16),

              _buildInputField(
                label: 'เบอร์โทรศัพท์',
                hint: '08xxxxxxxx',
                icon: Icons.phone_android,
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              ),
              const SizedBox(height: 16),

              if (_selectedRole == 'driver') ...[
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
                      if (matchedShuttle.isNotEmpty && matchedShuttle['number'] != null && matchedShuttle['number'].toString().isNotEmpty) {
                        _selectedShuttleNumber = matchedShuttle['number'].toString();
                      } else {
                        _selectedShuttleNumber = null;
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
                const SizedBox(height: 16),
              ],

              _buildInputField(
                label: 'อีเมล',
                hint: 'example@university.ac.th',
                icon: Icons.alternate_email,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              _buildPasswordField(
                label: 'รหัสผ่าน',
                hint: '••••••••',
                controller: _passwordController,
                isObscure: _obscurePassword,
                onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 16),

              _buildPasswordField(
                label: 'ยืนยันรหัสผ่าน',
                hint: '••••••••',
                controller: _confirmPasswordController,
                isObscure: _obscureConfirmPassword,
                onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                customIcon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 32),

              GestureDetector(
                onTap: _isLoading ? null : _register,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF81C784), Color(0xFF388E3C)], 
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : const Text(
                            'สร้างบัญชี',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('มีบัญชีอยู่แล้ว? ', style: TextStyle(color: Colors.grey)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context), 
                    child: const Text(
                      'เข้าสู่ระบบ',
                      style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ✨ ฟังก์ชันสำหรับสร้าง Dropdown เลือกสิทธิ์
  Widget _buildRoleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ประเภทผู้ใช้งาน', style: TextStyle(color: Color(0xFF595C5D), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRole,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('นักศึกษา (Student)')),
                DropdownMenuItem(value: 'driver', child: Text('คนขับรถรับส่ง (Driver)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRole = value;
                  });
                  if (value == 'driver') {
                    _fetchShuttles();
                  }
                }
              },
            ),
          ),
        ),
      ],
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
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF595C5D), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            obscureText: obscureText,
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
        Text(label, style: const TextStyle(color: Color(0xFF595C5D), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(hint, style: TextStyle(color: items.isEmpty ? Colors.red.shade300 : Colors.grey.shade400)),
              icon: Icon(Icons.arrow_drop_down, color: items.isEmpty ? Colors.red.shade300 : Colors.grey.shade400),
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label, 
    required String hint, 
    required TextEditingController controller,
    required bool isObscure,
    required VoidCallback onToggleVisibility,
    IconData customIcon = Icons.lock_outline,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF595C5D), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: TextField(
            controller: controller,
            obscureText: isObscure,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              suffixIcon: IconButton(
                icon: Icon(isObscure ? customIcon : Icons.visibility, color: Colors.grey.shade400),
                onPressed: onToggleVisibility,
              ),
            ),
          ),
        ),
      ],
    );
  }
}