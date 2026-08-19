import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/top_toast.dart';

class EditDriverDialog extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> driverData;

  const EditDriverDialog({
    super.key,
    required this.docId,
    required this.driverData,
  });

  @override
  State<EditDriverDialog> createState() => _EditDriverDialogState();
}

class _EditDriverDialogState extends State<EditDriverDialog> {
  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;

  // Shuttle selection
  String? _selectedShuttleName;
  String? _selectedShuttleNumber;
  List<String> _shuttleNames = [];
  List<String> _shuttleNumbers = [];
  List<Map<String, dynamic>> _shuttlesData = [];
  bool _isLoadingShuttles = true;
  String? _originalShuttleName;
  String? _originalShuttleNumber;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.driverData['name'] ?? '';
    _employeeIdController.text = widget.driverData['employee_id'] ?? widget.driverData['student_id'] ?? '';
    _phoneController.text = widget.driverData['phone'] ?? '';
    _selectedShuttleName = widget.driverData['shuttleName'];
    _selectedShuttleNumber = widget.driverData['shuttleNumber'];
    _originalShuttleName = _selectedShuttleName;
    _originalShuttleNumber = _selectedShuttleNumber;

    _fetchShuttles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchShuttles() async {
    try {
      final shuttlesSnapshot = await FirebaseFirestore.instance.collection('shuttles').get();
      final allData = shuttlesSnapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();

      // Find shuttles that are either available OR currently assigned to this driver
      final availableData = allData.where((s) {
        final name = s['name'] as String? ?? '';
        final number = s['number'] as String? ?? '';
        final driverUid = s['driver_uid'] as String?;
        return name.isNotEmpty &&
            number.isNotEmpty &&
            (driverUid == null || driverUid.isEmpty || driverUid == widget.docId);
      }).toList();

      if (mounted) {
        setState(() {
          _shuttlesData = availableData;
          _shuttleNames = availableData.map((s) => s['name'] as String).toSet().toList();
          _shuttleNumbers = availableData.map((s) => s['number'] as String).toSet().toList();
          
          if (_selectedShuttleName != null && !_shuttleNames.contains(_selectedShuttleName)) {
            _shuttleNames.add(_selectedShuttleName!);
          }
          if (_selectedShuttleNumber != null && !_shuttleNumbers.contains(_selectedShuttleNumber)) {
            _shuttleNumbers.add(_selectedShuttleNumber!);
          }
          
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

  Future<void> _updateDriver() async {
    final name = _nameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || employeeId.isEmpty || phone.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบทุกช่อง', Colors.red);
      return;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(employeeId)) {
      _showSnackBar('รหัสพนักงานต้องเป็นตัวเลข 10 หลักเท่านั้น', Colors.red);
      return;
    }

    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุลที่ถูกต้อง (ไม่มีตัวเลข)', Colors.red);
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showSnackBar('เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วยเลข 0', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Update User Document
      await FirebaseFirestore.instance.collection('users').doc(widget.docId).update({
        'name': name,
        'student_id': employeeId,
        'phone': phone,
        'shuttleName': _selectedShuttleName,
        'shuttleNumber': _selectedShuttleNumber,
      });

      // 2. Update Shuttle Document if changed
      if (_originalShuttleName != _selectedShuttleName || _originalShuttleNumber != _selectedShuttleNumber) {
        // Remove from old shuttle
        if (_originalShuttleName != null) {
          final oldShuttle = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: _originalShuttleName)
              .limit(1)
              .get();
          if (oldShuttle.docs.isNotEmpty) {
            await FirebaseFirestore.instance.collection('shuttles').doc(oldShuttle.docs.first.id).update({
              'driver_uid': FieldValue.delete(),
              'driver_name': FieldValue.delete(),
              'driver_avatar': FieldValue.delete(),
              // 'status': 'offline',
              // 'passenger_status': 'offline',
            });
          }
        }

        // Add to new shuttle
        if (_selectedShuttleName != null) {
          final newShuttle = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: _selectedShuttleName)
              .limit(1)
              .get();
          if (newShuttle.docs.isNotEmpty) {
            await FirebaseFirestore.instance.collection('shuttles').doc(newShuttle.docs.first.id).update({
              'driver_uid': widget.docId,
              'driver_name': name,
              'driver_avatar': widget.driverData['avatar'] ?? 'assets/images/man1.png',
              // removed status from firestore
              // removed passenger_status from firestore
              // 'last_updated': FieldValue.serverTimestamp(),
            });
          }
        }
      } else {
        // Just update name in current shuttle if it didn't change assignment
        if (_selectedShuttleName != null) {
          final currentShuttle = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: _selectedShuttleName)
              .limit(1)
              .get();
          if (currentShuttle.docs.isNotEmpty) {
            await FirebaseFirestore.instance.collection('shuttles').doc(currentShuttle.docs.first.id).update({
              'driver_name': name,
            });
          }
        }
      }

      if (mounted) {
        _showSnackBar('อัปเดตข้อมูลสำเร็จ!', Colors.green);
        Navigator.pop(context, true);
      }
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
        width: MediaQuery.of(context).size.width < 600 ? double.maxFinite : 500,
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
                    'แก้ไขข้อมูลคนขับรถ',
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
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateDriver,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text('บันทึกข้อมูล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
}
