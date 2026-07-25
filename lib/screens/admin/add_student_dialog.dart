import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../widgets/top_toast.dart';

class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({super.key});

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _addStudent() async {
    final name = _nameController.text.trim();
    final studentId = _studentIdController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || studentId.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      TopToast.show(context, 'กรุณากรอกข้อมูลให้ครบทุกช่อง', isError: true);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      TopToast.show(context, 'กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (ไม่มีตัวเลข)', isError: true);
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(studentId)) {
      TopToast.show(context, 'รหัสนักศึกษาต้องเป็นตัวเลข 10 หลักเท่านั้น', isError: true);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      TopToast.show(context, 'เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0', isError: true);
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      TopToast.show(context, 'รูปแบบอีเมลไม่ถูกต้อง', isError: true);
      return;
    }

    if (password.length < 6) {
      TopToast.show(context, 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // สร้าง Firebase App ชั่วคราวเพื่อไม่ให้แอดมินหลุดออกจากระบบ
      FirebaseApp tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      UserCredential userCredential = await FirebaseAuth.instanceFor(app: tempApp).createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // บันทึกข้อมูลลง Firestore ใน App หลัก
      Map<String, dynamic> userData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'student_id': studentId,
        'phone': phone,
        'email': email,
        'role': 'student',
        'avatar': 'assets/images/man1.png', 
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(userData);

      // ลบ App ชั่วคราวทิ้ง
      await tempApp.delete();

      if (mounted) {
        TopToast.show(context, 'เพิ่มข้อมูลนักศึกษาเรียบร้อยแล้ว', isError: false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        TopToast.show(context, 'เกิดข้อผิดพลาด: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FA),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF176a21).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add, color: Color(0xFF176a21)),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'เพิ่มนักศึกษาใหม่',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: Colors.grey.shade500),
                    splashRadius: 24,
                  ),
                ],
              ),
            ),

            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('ข้อมูลส่วนตัว'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _nameController,
                      label: 'ชื่อ-นามสกุล',
                      hint: 'กรอกชื่อ-นามสกุล',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _studentIdController,
                      label: 'รหัสนักศึกษา',
                      hint: 'กรอกรหัสนักศึกษา 10 หลัก',
                      icon: Icons.badge_outlined,
                      isNumber: true,
                      maxLength: 10,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'เบอร์โทรศัพท์',
                      hint: 'กรอกเบอร์โทรศัพท์ 10 หลัก',
                      icon: Icons.phone_outlined,
                      isNumber: true,
                      maxLength: 10,
                    ),
                    
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    
                    _buildSectionTitle('ข้อมูลการเข้าสู่ระบบ (บัญชีผู้ใช้)'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailController,
                      label: 'อีเมล / Gmail',
                      hint: 'example@psru.ac.th',
                      icon: Icons.email_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _passwordController,
                      label: 'รหัสผ่าน',
                      hint: 'อย่างน้อย 6 ตัวอักษร',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'ยกเลิก',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _addStudent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF176a21),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'เพิ่มนักศึกษา',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF176a21),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
    bool isPassword = false,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber 
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
                ] 
              : null,
          obscureText: isPassword && _obscurePassword,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 22),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF7F9FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF176a21), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }
}
