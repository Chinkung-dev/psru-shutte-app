import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/top_toast.dart';

class EditStudentDialog extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> studentData;

  const EditStudentDialog({
    super.key,
    required this.docId,
    required this.studentData,
  });

  @override
  State<EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<EditStudentDialog> {
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.studentData['name'] ?? '';
    _studentIdController.text = widget.studentData['student_id'] ?? '';
    _phoneController.text = widget.studentData['phone'] ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _updateStudent() async {
    final name = _nameController.text.trim();
    final studentId = _studentIdController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || studentId.isEmpty || phone.isEmpty) {
      TopToast.show(context, 'กรุณากรอกข้อมูลให้ครบถ้วน', isError: true);
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

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.docId).update({
        'name': name,
        'student_id': studentId,
        'phone': phone,
      });
      if (mounted) {
        TopToast.show(context, 'อัปเดตข้อมูลนักศึกษาสำเร็จ', isError: false);
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
                    child: const Icon(Icons.edit, color: Color(0xFF176a21)),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'แก้ไขข้อมูลนักศึกษา',
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

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'ชื่อ-นามสกุล',
                      hint: 'กรอกชื่อ-นามสกุล',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _studentIdController,
                      label: 'รหัสนักศึกษา',
                      hint: 'กรอกรหัสนักศึกษา 10 หลัก',
                      icon: Icons.badge_outlined,
                      isNumber: true,
                      maxLength: 10,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'เบอร์โทรศัพท์',
                      hint: 'กรอกเบอร์โทรศัพท์ 10 หลัก',
                      icon: Icons.phone_outlined,
                      isNumber: true,
                      maxLength: 10,
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
                    onPressed: _isLoading ? null : _updateStudent,
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
                            'บันทึกข้อมูล',
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
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
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 22),
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
