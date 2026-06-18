import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverStatusScreen extends StatefulWidget {
  const DriverStatusScreen({super.key});

  @override
  State<DriverStatusScreen> createState() => _DriverStatusScreenState();
}

class _DriverStatusScreenState extends State<DriverStatusScreen> {
  // ค่าเริ่มต้นของสถานะ (ใช้ 'available', 'full', 'break', 'offline')
  String _currentStatus = 'available'; 
  bool _isLoading = true;
  String? _shuttleDocId;

  @override
  void initState() {
    super.initState();
    _fetchCurrentStatus();
  }

  Future<void> _fetchCurrentStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 1. ดึงข้อมูลคนขับ เพื่อดูว่าขับรถคันไหน
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final shuttleName = userDoc.data()?['shuttle_name'];

        if (shuttleName != null) {
          // 2. ค้นหา Document ID ของรถคันนั้นในคอลเล็กชัน shuttles
          final shuttleQuery = await FirebaseFirestore.instance
              .collection('shuttles')
              .where('name', isEqualTo: shuttleName)
              .limit(1)
              .get();
              
          if (shuttleQuery.docs.isNotEmpty) {
            _shuttleDocId = shuttleQuery.docs.first.id;
            final docData = shuttleQuery.docs.first.data();
            
            // 3. ดึงสถานะเดิมมาแสดง (ถ้ามี)
            if (docData.containsKey('passenger_status')) {
              setState(() {
                _currentStatus = docData['passenger_status'];
              });
            }
          }
        }
      }
      setState(() => _isLoading = false);
    } catch (e) {
      print("Error fetching status: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_shuttleDocId == null) return; // ถ้ายงไม่พบ ID รถ จะไม่อัปเดต

    setState(() {
      _currentStatus = newStatus;
    });

    try {
      // อัปเดตไปที่คอลเล็กชัน shuttles โดยใช้ SetOptions(merge: true) เพื่อไม่ให้ทับข้อมูลเดิม (name, number)
      await FirebaseFirestore.instance.collection('shuttles').doc(_shuttleDocId).set({
        'passenger_status': newStatus,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตสถานะสำเร็จ'), 
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, 
        title: const Row(
          children: [
            Icon(Icons.directions_bus, color: Color(0xFF176a21), size: 28),
            SizedBox(width: 10),
            Text('PSRU Shuttle', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF176a21))),
          ],
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF176a21)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Current Status',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30)),
                  ),
                  const SizedBox(height: 24),
                  
                  // ปุ่ม: ว่าง (Available)
                  _buildStatusCard(
                    statusKey: 'available',
                    title: 'ว่าง',
                    subtitle: 'Available',
                    icon: Icons.check_circle_outline,
                    activeColor: const Color(0xFF176a21),
                    activeBgColor: const Color(0xFFE8F5E9),
                  ),
                  
                  // ปุ่ม: เต็ม (Full)
                  _buildStatusCard(
                    statusKey: 'full',
                    title: 'เต็ม',
                    subtitle: 'Full',
                    icon: Icons.block,
                    activeColor: const Color(0xFF757778),
                    activeBgColor: const Color(0xFFE0E0E0),
                  ),

                  // ปุ่ม: พัก (Break)
                  _buildStatusCard(
                    statusKey: 'break',
                    title: 'พัก',
                    subtitle: 'Break',
                    icon: Icons.pause_circle_outline,
                    activeColor: const Color(0xFFF28522),
                    activeBgColor: const Color(0xFFFBE9E7), 
                  ),

                  // ปุ่ม: เลิกงาน (Off Duty)
                  _buildStatusCard(
                    statusKey: 'offline',
                    title: 'เลิกงาน',
                    subtitle: 'Off Duty',
                    icon: Icons.exit_to_app,
                    activeColor: Colors.red,
                    activeBgColor: const Color(0xFFFFEBEE),
                  ),
                  
                  const SizedBox(height: 80), 
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard({
    required String statusKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required Color activeBgColor,
  }) {
    bool isActive = _currentStatus == statusKey;

    return GestureDetector(
      onTap: () => _updateStatus(statusKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? activeColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (!isActive)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isActive ? activeColor : const Color(0xFFEFF1F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: isActive ? Colors.white : const Color(0xFF757778),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isActive ? activeColor : const Color(0xFF2C2F30),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? activeColor.withOpacity(0.8) : const Color(0xFF757778),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
