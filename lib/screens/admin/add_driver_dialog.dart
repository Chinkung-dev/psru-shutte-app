import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../widgets/top_toast.dart';

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

  // Shuttle selection
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
      // ดึงข้อมูลรถรับส่ง
      final shuttlesSnapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      final allData = shuttlesSnapshot.docs.map((doc) => doc.data()).toList();

      // ค้นหารถที่ยังไม่มีคนขับ (ไม่มี driver_uid)
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
          _shuttleNames = availableData.map((s) => s['name'] as String).toSet().toList();
          _shuttleNumbers = availableData.map((s) => s['number'] as String).toSet().toList();
          _isLoadingShuttles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingShuttles = false);
        _showSnackBar('โหลดข้อมูลรถรับส่งไม่สำเร็จ', Colors.red);
      }
    }
  }

  Future<void> _createDriver() async {
    final name = _nameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || employeeId.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    if (_selectedShuttleName == null || _selectedShuttleNumber == null) {
      _showSnackBar('กรุณาเลือกรถรับส่งและหมายเลขรถ', Colors.red);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (ไม่มีตัวเลข)', Colors.red);
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(employeeId)) {
      _showSnackBar('รหัสพนักงานต้องเป็นตัวเลข 10 หลักเท่านั้น', Colors.red);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showSnackBar('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0', Colors.red);
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      _showSnackBar('รูปแบบอีเมลไม่ถูกต้อง', Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', Colors.orange);
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
        'student_id': employeeId, // ใช้ฟิลด์นี้เก็บรหัสพนักงานชั่วคราว
        'phone': phone,
        'email': email,
        'role': 'driver',
        'avatar': 'assets/images/man1.png', 
        'shuttleName': _selectedShuttleName,
        'shuttleNumber': _selectedShuttleNumber,
        'hasSeenOnboarding': false,
        'status': 'offline', // สถานะเริ่มต้นของคนขับ
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set(userData);

      // อัปเดตข้อมูลคนขับลงใน collection shuttles ด้วย
      final shuttleDoc = await FirebaseFirestore.instance
          .collection('shuttles')
          .where('name', isEqualTo: _selectedShuttleName)
          .limit(1)
          .get();

      if (shuttleDoc.docs.isNotEmpty) {
        await FirebaseFirestore.instance.collection('shuttles').doc(shuttleDoc.docs.first.id).update({
          'driver_uid': userCredential.user!.uid,
          'driver_name': name,
          'driver_avatar': 'assets/images/man1.png',
          'status': 'offline', // สถานะเริ่มต้น
          'passenger_status': 'available', // เตรียมพร้อมรับผู้โดยสาร
          'last_updated': FieldValue.serverTimestamp(),
        });
      }

      // ลบ App ชั่วคราวทิ้ง
      await tempApp.delete();

      if (mounted) {
        _showSnackBar('เพิ่มคนขับรถสำเร็จ!', Colors.green);
        Navigator.pop(context, true); // ส่ง true กลับไปบอกว่าเพิ่มสำเร็จ
      }

    } on FirebaseAuthException catch (e) {
      String message = 'เกิดข้อผิดพลาดในการสร้างบัญชี';
      if (e.code == 'email-already-in-use') {
        message = 'อีเมลนี้ถูกใช้งานแล้ว';
      } else if (e.code == 'invalid-email') {
        message = 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      _showSnackBar(message, Colors.red);
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    TopToast.show(context, message, isError: color != Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FA),
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'เพิ่มพนักงานขับรถ',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF176a21)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 24),

              _buildInputField(
                label: 'ชื่อ-นามสกุล',
                hint: 'Somchai Driver',
                icon: Icons.person_outline,
                controller: _nameController,
              ),
              const SizedBox(height: 16),

              _buildInputField(
                label: 'รหัสพนักงาน',
                hint: 'กรอกรหัสพนักงาน 10 หลัก',
                icon: Icons.badge_outlined,
                controller: _employeeIdController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
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

              _buildDropdownField(
                label: 'ชื่อรถรับส่ง',
                value: _selectedShuttleName,
                items: _shuttleNames,
                hint: _isLoadingShuttles
                    ? 'กำลังโหลด...'
                    : _shuttleNames.isEmpty
                    ? 'ไม่มีรถรับส่งว่าง'
                    : 'เลือกรถรับส่ง',
                onChanged: (val) {
                  setState(() {
                    _selectedShuttleName = val;
                    final matchedShuttle = _shuttlesData.firstWhere(
                      (s) => s['name'] == val,
                      orElse: () => <String, dynamic>{},
                    );
                    if (matchedShuttle.isNotEmpty && matchedShuttle['number'] != null) {
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
                items: _selectedShuttleName != null
                    ? _shuttlesData
                        .where((s) => s['name'] == _selectedShuttleName)
                        .map((s) => s['number'] as String)
                        .toSet()
                        .toList()
                    : _shuttleNumbers,
                hint: _isLoadingShuttles
                    ? 'กำลังโหลด...'
                    : _shuttleNumbers.isEmpty
                    ? 'ไม่มีหมายเลขรถว่าง'
                    : 'เลือกหมายเลขรถ',
                onChanged: (val) => setState(() => _selectedShuttleNumber = val),
              ),
              const SizedBox(height: 16),

              _buildInputField(
                label: 'อีเมล (สำหรับเข้าระบบ)',
                hint: 'driver@university.ac.th',
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
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createDriver,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text('ยืนยันสร้างบัญชี', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                icon: Icon(isObscure ? Icons.lock_outline : Icons.visibility, color: Colors.grey.shade400),
                onPressed: onToggleVisibility,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
