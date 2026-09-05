import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../widgets/top_toast.dart';
import '../../widgets/app_loading_view.dart';

class AdminProfileDialog extends StatefulWidget {
  const AdminProfileDialog({super.key});

  @override
  State<AdminProfileDialog> createState() => _AdminProfileDialogState();
}

class _AdminProfileDialogState extends State<AdminProfileDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _emailController.text = user.email ?? '';

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          _firstNameController.text = data['first_name'] ?? '';
          _lastNameController.text = data['last_name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
        }
      }
    } catch (e) {
      debugPrint("Error loading admin data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': 'admin',
        'email': user.email,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (_passwordController.text.isNotEmpty) {
        await user.updatePassword(_passwordController.text);
      }

      if (mounted) {
        Navigator.pop(context);
        TopToast.show(context, 'อัปเดตข้อมูลผู้ดูแลระบบสำเร็จ', isError: false);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showError(
            'การเปลี่ยนรหัสผ่านจำเป็นต้องเข้าสู่ระบบใหม่ กรุณาล็อกเอาต์แล้วเข้าสู่ระบบอีกครั้ง');
      } else {
        _showError('เกิดข้อผิดพลาด: ${e.message}');
      }
    } catch (e) {
      _showError('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      TopToast.show(context, message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double maxDialogHeight = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width < 600 ? double.maxFinite : 480,
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF176a21).withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF176a21),
                      Color(0xFF66BB6A),
                      Color(0xFF9DF197),
                    ],
                  ),
                ),
              ),
              _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: AppLoadingView(
                        message: 'กำลังโหลดข้อมูลผู้ดูแลระบบ...',
                      ),
                    )
                  : Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5E9),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.admin_panel_settings_rounded,
                                          color: Color(0xFF176a21),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ข้อมูลผู้ดูแลระบบ',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF1E2923),
                                            ),
                                          ),
                                          Text(
                                            'จัดการโปรไฟล์และรหัสผ่านเข้าใช้งาน',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF718076),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Color(0xFF718076),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  )
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildField(
                                label: 'อีเมลผู้ดูแลระบบ',
                                controller: _emailController,
                                icon: Icons.alternate_email_rounded,
                                readOnly: true,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildField(
                                      label: 'ชื่อ',
                                      controller: _firstNameController,
                                      icon: Icons.person_rounded,
                                      validator: (val) =>
                                          val == null || val.isEmpty
                                              ? 'กรุณากรอกชื่อ'
                                              : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildField(
                                      label: 'นามสกุล',
                                      controller: _lastNameController,
                                      icon: Icons.person_outline_rounded,
                                      validator: (val) =>
                                          val == null || val.isEmpty
                                              ? 'กรุณากรอกนามสกุล'
                                              : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildField(
                                label: 'เบอร์โทรศัพท์',
                                controller: _phoneController,
                                icon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (val) {
                                  if (val != null &&
                                      val.isNotEmpty &&
                                      val.length < 10) {
                                    return 'กรุณากรอกเบอร์ให้ครบ 10 หลัก';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Color(0xFFEFF2F0)),
                              const SizedBox(height: 10),
                              const Text(
                                'เปลี่ยนรหัสผ่าน (เว้นว่างไว้หากไม่ต้องการเปลี่ยน)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF718076),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildField(
                                label: 'รหัสผ่านใหม่',
                                controller: _passwordController,
                                icon: Icons.lock_rounded,
                                isPassword: true,
                                isObscure: _obscurePassword,
                                onToggleVisibility: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                                validator: (val) {
                                  if (val != null && val.isNotEmpty) {
                                    if (val.length < 8) {
                                      return 'รหัสผ่านต้องมีความยาวอย่างน้อย 8 ตัวอักษร';
                                    }
                                    if (!RegExp(r'(?=.*[a-zA-Z])')
                                        .hasMatch(val)) {
                                      return 'ต้องมีตัวอักษรภาษาอังกฤษอย่างน้อย 1 ตัว';
                                    }
                                    if (!RegExp(r'(?=.*[0-9])').hasMatch(val)) {
                                      return 'ต้องมีตัวเลขอย่างน้อย 1 ตัว';
                                    }
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildField(
                                label: 'ยืนยันรหัสผ่านใหม่',
                                controller: _confirmPasswordController,
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                                isObscure: _obscureConfirmPassword,
                                onToggleVisibility: () => setState(() =>
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword),
                                validator: (val) {
                                  if (_passwordController.text.isNotEmpty &&
                                      val != _passwordController.text) {
                                    return 'รหัสผ่านทั้งสองช่องไม่ตรงกัน';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _saveData,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF176a21),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Text(
                                          'บันทึกข้อมูล',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool readOnly = false,
    bool isPassword = false,
    bool isObscure = false,
    VoidCallback? onToggleVisibility,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1E2923),
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: readOnly
                ? const Color(0xFFEFEFEF)
                : const Color(0xFFF2F6F3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.12),
            ),
          ),
          child: TextFormField(
            controller: controller,
            readOnly: readOnly,
            obscureText: isPassword && isObscure,
            keyboardType: keyboardType,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            validator: validator,
            style: TextStyle(
              color: readOnly
                  ? const Color(0xFF718076)
                  : const Color(0xFF1E2923),
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              counterText: '',
              prefixIcon: Icon(
                icon,
                color: readOnly
                    ? const Color(0xFF718076)
                    : const Color(0xFF176a21),
                size: 18,
              ),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        isObscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: const Color(0xFF718076),
                        size: 18,
                      ),
                      onPressed: onToggleVisibility,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
