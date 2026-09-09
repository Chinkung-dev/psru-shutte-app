import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/top_toast.dart';

class AddStopDialog extends StatefulWidget {
  final int nextOrder;

  const AddStopDialog({
    super.key,
    this.nextOrder = 1,
  });

  @override
  State<AddStopDialog> createState() => _AddStopDialogState();
}

class _AddStopDialogState extends State<AddStopDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _orderController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _orderController.text = widget.nextOrder.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _orderController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _saveStop() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      TopToast.show(context, 'กรุณาระบุชื่อจุดจอดรถ', isError: true);
      return;
    }

    final order = int.tryParse(_orderController.text.trim()) ?? widget.nextOrder;
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    if (lat == null || lng == null) {
      TopToast.show(context, 'กรุณาระบุพิกัดละติจูดและลองจิจูดให้ถูกต้อง', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('stops').add({
        'name': name,
        'description': _descriptionController.text.trim(),
        'order': order,
        'lat': lat,
        'lng': lng,
        'is_active': _isActive,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
      TopToast.show(context, 'เพิ่มจุดจอดรถเรียบร้อยแล้ว', isError: false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        TopToast.show(context, 'เกิดข้อผิดพลาดในการบันทึก: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // หัวข้อ Dialog
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
                          Icons.add_location_alt_rounded,
                          color: Color(0xFF176a21),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'เพิ่มจุดจอดรถใหม่',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF718076)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // กล่องแจ้งเตือนความสำคัญเรื่องพิกัด
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD54F)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFF57F17),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'พิกัดของจุดจอดต้องตรงกับเส้นทางเดินรถในระบบคำนวณเส้นทาง (route_data.dart) เพื่อให้การนำทางทำงานได้อย่างถูกต้อง',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5D4037),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ฟิลด์ชื่อจุดจอด
              _buildInputField(
                label: 'ชื่อจุดจอดรถ',
                hint: 'เช่น ตึก IT, คณะพยาบาลศาสตร์',
                icon: Icons.location_on_rounded,
                controller: _nameController,
              ),
              const SizedBox(height: 14),

              // ฟิลด์จุดสังเกต
              _buildInputField(
                label: 'จุดสังเกต / คำอธิบายเพิ่มเติม',
                hint: 'เช่น หน้า 7-Eleven, ฝั่งโรงอาหาร',
                icon: Icons.notes_rounded,
                controller: _descriptionController,
              ),
              const SizedBox(height: 14),

              // ฟิลด์ลำดับ
              _buildInputField(
                label: 'ลำดับการเดินรถ (Order)',
                hint: '1',
                icon: Icons.format_list_numbered_rounded,
                controller: _orderController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 14),

              // พิกัดละติจูดและลองจิจูด
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      label: 'ละติจูด (Lat)',
                      hint: '16.828722',
                      icon: Icons.my_location_rounded,
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInputField(
                      label: 'ลองจิจูด (Lng)',
                      hint: '100.205001',
                      icon: Icons.my_location_rounded,
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // สวิตช์สถานะเปิด-ปิดให้บริการ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAF9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isActive ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                          color: _isActive ? const Color(0xFF176a21) : const Color(0xFFD9534F),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'สถานะการให้บริการ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E2923),
                              ),
                            ),
                            Text(
                              _isActive ? 'เปิดให้บริการตามปกติ' : 'ปิดปรับปรุงชั่วคราว',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isActive ? const Color(0xFF176a21) : const Color(0xFFD9534F),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: _isActive,
                      activeColor: const Color(0xFF176a21),
                      onChanged: (value) => setState(() => _isActive = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ปุ่มดำเนินการ
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(
                          color: Color(0xFF718076),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveStop,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF176a21),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'เพิ่มจุดจอด',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
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
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4A5568),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E2923)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF718076)),
            filled: true,
            fillColor: const Color(0xFFF9FAF9),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF176a21), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
