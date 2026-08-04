import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../widgets/top_toast.dart';

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
        // 1. ดึงข้อมูลคนขับ
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));
        final shuttleName = userDoc.data()?['shuttle_name'];

        if (shuttleName != null) {
          final shuttleQuery = await FirebaseDatabase.instance
              .ref('shuttles')
              .orderByChild('name')
              .equalTo(shuttleName)
              .limitToFirst(1)
              .get()
              .timeout(const Duration(seconds: 5));

          if (shuttleQuery.exists && shuttleQuery.value != null) {
            final data = shuttleQuery.value as Map<dynamic, dynamic>;
            _shuttleDocId = data.keys.first.toString();
            
            // 3. ดึงสถานะเดิมมาแสดง (จาก RTDB)
            final rtdbSnapshot = await FirebaseDatabase.instance
                .ref('shuttles')
                .child(_shuttleDocId!)
                .get()
                .timeout(const Duration(seconds: 5));
            if (rtdbSnapshot.exists) {
              final rtdbData = rtdbSnapshot.value as Map<dynamic, dynamic>;
              if (rtdbData.containsKey('passenger_status')) {
                if (mounted) {
                  setState(() {
                    _currentStatus = rtdbData['passenger_status'].toString();
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print("Error fetching status: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_shuttleDocId == null) return;

    setState(() {
      _currentStatus = newStatus;
    });

    try {
      await FirebaseDatabase.instance
          .ref('shuttles')
          .child(_shuttleDocId!)
          .update({
            'passenger_status': newStatus,
            'last_updated': ServerValue.timestamp,
          });

      if (mounted) {
        TopToast.show(context, 'อัปเดตสถานะสำเร็จ', isError: false);
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
        title: Image.asset(
          'lib/screens/driver/logo.png',
          height: 42,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Row(
            children: [
              Icon(Icons.directions_bus, color: Color(0xFF176a21), size: 28),
              SizedBox(width: 10),
              Text(
                'PSRU Shuttle',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF176a21),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF176a21)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'อัพเดตสถานะรถ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2F30),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildStatusCard(
                    statusKey: 'available',
                    title: 'ว่าง',
                    subtitle: 'Available',
                    icon: Icons.check_circle_outline,
                    activeColor: const Color(0xFF176a21),
                    activeBgColor: const Color(0xFFE8F5E9),
                  ),
                  _buildStatusCard(
                    statusKey: 'full',
                    title: 'เต็ม',
                    subtitle: 'Full',
                    icon: Icons.block,
                    activeColor: const Color(0xFF757778),
                    activeBgColor: const Color(0xFFE0E0E0),
                  ),
                  _buildStatusCard(
                    statusKey: 'break',
                    title: 'พัก',
                    subtitle: 'Break',
                    icon: Icons.pause_circle_outline,
                    activeColor: const Color(0xFFF28522),
                    activeBgColor: const Color(0xFFFBE9E7),
                  ),
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
              ),
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
                  color: isActive
                      ? activeColor.withOpacity(0.8)
                      : const Color(0xFF757778),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
