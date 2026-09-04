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
      _showToast('กรุณากรอกข้อมูลให้ครบถ้วน', isError: true);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showToast('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (ไม่มีตัวเลข)', isError: true);
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(studentId)) {
      _showToast('รหัสนักศึกษาต้องเป็นตัวเลข 10 หลักเท่านั้น', isError: true);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showToast('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.docId)
          .update({
        'name': name,
        'student_id': studentId,
        'phone': phone,
      });
      if (mounted) {
        _showToast('อัปเดตข้อมูลนักศึกษาสำเร็จ', isError: false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showToast('เกิดข้อผิดพลาด: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showToast(String message, {required bool isError}) {
    TopToast.show(context, message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;
    final double maxDialogHeight = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.edit_note_rounded,
                                  color: Color(0xFF176a21),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'แก้ไขข้อมูลนักศึกษา',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1E2923),
                                    ),
                                  ),
                                  Text(
                                    'อัปเดตข้อมูลส่วนตัวและรหัสนักศึกษา',
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
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF718076),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _nameController,
                        label: 'ชื่อ-นามสกุล',
                        hint: 'สมหญิง รักเรียน',
                        icon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _studentIdController,
                        label: 'รหัสนักศึกษา (10 หลัก)',
                        hint: '6512345678',
                        icon: Icons.badge_rounded,
                        isNumber: true,
                        maxLength: 10,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'เบอร์โทรศัพท์',
                        hint: '0812345678',
                        icon: Icons.phone_rounded,
                        isNumber: true,
                        maxLength: 10,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _updateStudent,
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
                                  'บันทึกการแก้ไข',
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
            ],
          ),
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
            color: Color(0xFF1E2923),
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6F3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.12),
            ),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            inputFormatters: isNumber
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    if (maxLength != null)
                      LengthLimitingTextInputFormatter(maxLength),
                  ]
                : null,
            style: const TextStyle(
              color: Color(0xFF1E2923),
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF8A938C), fontSize: 13),
              prefixIcon: Icon(icon, color: const Color(0xFF176a21), size: 18),
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
}
