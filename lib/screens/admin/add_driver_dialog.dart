import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../widgets/top_toast.dart';
import '../../services/shuttle_access.dart';

class AddDriverDialog extends StatefulWidget {
  const AddDriverDialog({super.key});

  @override
  State<AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends State<AddDriverDialog> {
  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _selectedShuttleName;
  String? _selectedShuttleNumber;
  List<String> _shuttleNames = [];
  List<String> _shuttleNumbers = [];
  List<Map<String, dynamic>> _shuttlesData = [];
  bool _isLoadingShuttles = true;

  @override
  void initState() {
    super.initState();
    _fetchShuttles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _fetchShuttles() async {
    try {
      final shuttlesSnapshot =
          await FirebaseFirestore.instance.collection('shuttles').get();
      final allData = shuttlesSnapshot.docs.map((doc) => doc.data()).toList();

      final availableData = allData.where((s) {
        final name = s['name'] as String? ?? '';
        final number = s['number'] as String? ?? '';
        final driverUid = s['driver_uid'] as String?;
        return name.isNotEmpty &&
            number.isNotEmpty &&
            (driverUid == null || driverUid.isEmpty);
      }).toList();

      if (mounted) {
        setState(() {
          _shuttlesData = availableData;
          _shuttleNames =
              availableData.map((s) => s['name'] as String).toSet().toList();
          _shuttleNumbers =
              availableData.map((s) => s['number'] as String).toSet().toList();
          _isLoadingShuttles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingShuttles = false);
        _showToast('โหลดข้อมูลรถรับส่งไม่สำเร็จ', isError: true);
      }
    }
  }

  Future<void> _createDriver() async {
    final name = _nameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty ||
        employeeId.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showToast('กรุณากรอกข้อมูลให้ครบทุกช่อง', isError: true);
      return;
    }

    if (_selectedShuttleName == null || _selectedShuttleNumber == null) {
      _showToast('กรุณาเลือกรถรับส่งและหมายเลขรถ', isError: true);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showToast('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (ไม่มีตัวเลข)', isError: true);
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(employeeId)) {
      _showToast('รหัสพนักงานต้องเป็นตัวเลข 10 หลักเท่านั้น', isError: true);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showToast('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0',
          isError: true);
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email)) {
      _showToast('รูปแบบอีเมลไม่ถูกต้อง', isError: true);
      return;
    }

    if (password.length < 6) {
      _showToast('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    FirebaseApp? tempApp;
    try {
      await ShuttleAccess.requireAdmin();
      tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      UserCredential userCredential =
          await FirebaseAuth.instanceFor(app: tempApp)
              .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      Map<String, dynamic> userData = {
        'uid': userCredential.user!.uid,
        'name': name,
        'student_id': employeeId,
        'phone': phone,
        'email': email,
        'role': 'driver',
        'avatar': 'assets/images/man1.png',
        'shuttleName': _selectedShuttleName,
        'shuttleNumber': _selectedShuttleNumber,
        'shuttle_name': _selectedShuttleName,
        'shuttle_number': _selectedShuttleNumber,
        'hasSeenOnboarding': false,
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(userData);

      final shuttleDoc = await FirebaseFirestore.instance
          .collection('shuttles')
          .where('name', isEqualTo: _selectedShuttleName)
          .limit(1)
          .get();

      if (shuttleDoc.docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('shuttles')
            .doc(shuttleDoc.docs.first.id)
            .update({
          'driver_uid': userCredential.user!.uid,
          'driver_name': name,
          'driver_avatar': 'assets/images/man1.png',
        });
        final shuttle = shuttleDoc.docs.first;
        await ShuttleAccess.assignDriver(
          driverUid: userCredential.user!.uid,
          documentId: shuttle.id,
          name: shuttle.data()['name']?.toString() ?? '',
          number: shuttle.data()['number']?.toString() ?? '',
        );
      } else {
        throw StateError('ไม่พบรถที่เลือก กรุณาตรวจสอบข้อมูลรถ');
      }

      if (mounted) {
        _showToast('เพิ่มพนักงานขับรถสำเร็จ', isError: false);
        Navigator.pop(context, true);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'เกิดข้อผิดพลาดในการสร้างบัญชี';
      if (e.code == 'email-already-in-use') {
        message = 'อีเมลนี้ถูกใช้งานในระบบแล้ว';
      } else if (e.code == 'invalid-email') {
        message = 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      _showToast(message, isError: true);
    } catch (e) {
      _showToast('เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      try {
        await tempApp?.delete();
      } catch (e) {
        debugPrint('ปิดการเชื่อมต่อบัญชีชั่วคราวไม่สำเร็จ: $e');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String message, {required bool isError}) {
    TopToast.show(context, message, isError: isError);
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
        width: MediaQuery.of(context).size.width < 600 ? double.maxFinite : 520,
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
                                  Icons.person_add_rounded,
                                  color: Color(0xFF176a21),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'เพิ่มพนักงานขับรถ',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1E2923),
                                    ),
                                  ),
                                  Text(
                                    'สร้างบัญชีคนขับและมอบหมายรถรับส่ง',
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
                      const SizedBox(height: 24),
                      _buildInputField(
                        label: 'ชื่อ-นามสกุล',
                        hint: 'สมชาย ขยันขับ',
                        icon: Icons.person_rounded,
                        controller: _nameController,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        label: 'รหัสพนักงาน (10 หลัก)',
                        hint: '6501234567',
                        icon: Icons.badge_rounded,
                        controller: _employeeIdController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        label: 'เบอร์โทรศัพท์',
                        hint: '0812345678',
                        icon: Icons.phone_rounded,
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildDropdownField(
                        label: 'เลือกรถรับส่ง',
                        value: _selectedShuttleName,
                        items: _shuttleNames,
                        hint: _isLoadingShuttles
                            ? 'กำลังโหลดข้อมูลรถ...'
                            : _shuttleNames.isEmpty
                                ? 'ไม่มีรถรับส่งที่ว่าง'
                                : 'เลือกรถรับส่ง',
                        onChanged: (val) {
                          setState(() {
                            _selectedShuttleName = val;
                            final matchedShuttle = _shuttlesData.firstWhere(
                              (s) => s['name'] == val,
                              orElse: () => <String, dynamic>{},
                            );
                            if (matchedShuttle.isNotEmpty &&
                                matchedShuttle['number'] != null) {
                              _selectedShuttleNumber =
                                  matchedShuttle['number'].toString();
                            } else {
                              _selectedShuttleNumber = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _buildDropdownField(
                        label: 'หมายเลขรถ',
                        value: _selectedShuttleNumber,
                        items: _selectedShuttleName != null
                            ? _shuttlesData
                                .where(
                                    (s) => s['name'] == _selectedShuttleName)
                                .map((s) => s['number'] as String)
                                .toSet()
                                .toList()
                            : _shuttleNumbers,
                        hint: _isLoadingShuttles
                            ? 'กำลังโหลด...'
                            : _shuttleNumbers.isEmpty
                                ? 'ไม่มีหมายเลขรถว่าง'
                                : 'เลือกหมายเลขรถ',
                        onChanged: (val) =>
                            setState(() => _selectedShuttleNumber = val),
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        label: 'อีเมลเข้าใช้งาน',
                        hint: 'driver@psru.ac.th',
                        icon: Icons.alternate_email_rounded,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _buildPasswordField(
                        label: 'รหัสผ่านเริ่มต้น',
                        hint: 'อย่างน้อย 6 ตัวอักษร',
                        controller: _passwordController,
                        isObscure: _obscurePassword,
                        onToggleVisibility: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createDriver,
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
                                  'บันทึกข้อมูลพนักงาน',
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

  Widget _buildInputField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
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
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(
              color: Color(0xFF1E2923),
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF8A938C), fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF176a21), size: 18),
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
            color: Color(0xFF1E2923),
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6F3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.12),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(
                hint,
                style: const TextStyle(
                  color: Color(0xFF8A938C),
                  fontSize: 13,
                ),
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF176a21),
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF1E2923),
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

  Widget _buildPasswordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isObscure,
    required VoidCallback onToggleVisibility,
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
          child: TextField(
            controller: controller,
            obscureText: isObscure,
            style: const TextStyle(
              color: Color(0xFF1E2923),
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF8A938C), fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              prefixIcon: const Icon(
                Icons.lock_rounded,
                color: Color(0xFF176a21),
                size: 18,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: const Color(0xFF718076),
                  size: 18,
                ),
                onPressed: onToggleVisibility,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
