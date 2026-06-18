import 'package:flutter/material.dart';
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
      final snapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.map<Map<String, dynamic>>((doc) => {
          'id': doc.id,
          'name': doc.data()['name']?.toString() ?? '',
          'number': doc.data()['number']?.toString() ?? '',
        }).toList();

        if (mounted) {
          setState(() {
            _shuttlesData = data;
            _shuttleNames = data.map((s) => s['name'] as String).where((n) => n.isNotEmpty).toSet().toList();
            _shuttleNumbers = data.map((s) => s['number'] as String).where((n) => n.isNotEmpty).toSet().toList();
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
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || studentId.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    if (_selectedRole == 'driver') {
      if (_phoneController.text.trim().isEmpty || _selectedShuttleName == null || _selectedShuttleNumber == null) {
        _showSnackBar('กรุณากรอกข้อมูลสำหรับคนขับรถให้ครบทุกช่อง', Colors.red);
        return;
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
        'email': email,
        'role': _selectedRole, // ✨ บันทึกตามสิทธิ์ที่ผู้ใช้เลือกใน Dropdown
        'avatar': _avatarList[_selectedAvatarIndex], 
        'created_at': FieldValue.serverTimestamp(),
      };

      if (_selectedRole == 'driver') {
        userData['phone'] = _phoneController.text.trim();
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
              
              SizedBox(
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
                    return AnimatedContainer(
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
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  '👈 เลื่อนซ้าย-ขวา เพื่อเลือกรูปโปรไฟล์ 👉',
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
              ),
              const SizedBox(height: 16),

              if (_selectedRole == 'driver') ...[
                _buildInputField(
                  label: 'เบอร์โทรศัพท์',
                  hint: '08xxxxxxxx',
                  icon: Icons.phone_android,
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                _buildDropdownField(
                  label: 'ชื่อรถรับส่ง',
                  value: _selectedShuttleName,
                  items: _shuttleNames,
                  hint: 'เลือกชื่อรถรับส่ง',
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
                  hint: 'เลือกหมายเลขรถ',
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
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
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
              hint: Text(hint, style: TextStyle(color: Colors.grey.shade400)),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: onChanged,
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