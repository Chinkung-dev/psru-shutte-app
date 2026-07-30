import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'driver_edit_profile_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _startListeningUserData();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  void _startListeningUserData() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists && mounted) {
            setState(() {
              userData = doc.data();
              isLoading = false;
            });
          } else if (mounted) {
            setState(() => isLoading = false);
          }
        }, onError: (e) {
          print("Error listening to user data: $e");
          if (mounted) {
            setState(() => isLoading = false);
          }
        });
      } else {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      print("Error starting listener: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _navigateToEditProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DriverEditProfileScreen()),
    );
    // ไม่ต้องเรียก _fetchUserData() แล้ว เพราะใช้ Stream ฟังการเปลี่ยนแปลงอัตโนมัติ
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F9FA),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF176a21))),
      );
    }

    final String name = userData?['name'] ?? 'ไม่ระบุชื่อ';
    final String driverId = userData?['student_id'] ?? '-';
    final String phone = userData?['phone'] ?? '-';
    final String email = userData?['email'] ?? '-';
    final String shuttleName = userData?['shuttle_name'] ?? '-';
    final String shuttleNumber = userData?['shuttle_number'] ?? '-';
    final String avatarPath = userData?['avatar'] ?? 'assets/images/man1.png';

    // ✨ คำนวณคะแนนดาวเฉลี่ยจากฐานข้อมูล
    final double totalScore = (userData?['total_rating_score'] ?? 0.0).toDouble();
    final int ratingCount = (userData?['rating_count'] ?? 0).toInt();
    
    String averageRatingStr = '-';
    if (ratingCount > 0) {
      double avg = totalScore / ratingCount;
      averageRatingStr = avg.toStringAsFixed(2); // ทศนิยม 2 ตำแหน่ง
    }

    // ✨ คำนวณจำนวนรอบที่วิ่งวันนี้
    int dailyRoundCount = 0;
    final now = DateTime.now();
    final String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    if (userData?['last_round_date'] == todayStr) {
      dailyRoundCount = (userData?['daily_round_count'] ?? 0).toInt();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, 
        title: const Text('โปรไฟล์คนขับรถ', style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: const Icon(Icons.arrow_back, color: Color(0xFF176a21)), 
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF176a21)),
            onPressed: _navigateToEditProfile,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
        child: Column(
          children: [
            Center(
              child: GestureDetector(
                onTap: _navigateToEditProfile,
                child: Stack(
                  children: [
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF4CA2CD), width: 3),
                        image: DecorationImage(
                          image: AssetImage(avatarPath),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF176a21),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('จำนวนรอบที่วิ่งวันนี้', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text('$dailyRoundCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('คะแนน', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(averageRatingStr, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
                            const SizedBox(width: 8),
                            const Icon(Icons.star, color: Colors.amber),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildSectionCard(
              title: 'ข้อมูลคนขับรถ',
              icon: Icons.badge_outlined,
              children: [
                _buildInfoRow('รหัสคนขับรถ :', driverId),
                _buildInfoRow('เบอร์โทรศัพท์ :', phone, valueColor: const Color(0xFF176a21)),
                _buildInfoRow('อีเมล :', email, isLast: true),
              ],
            ),
            const SizedBox(height: 20),

            _buildSectionCard(
              title: 'ข้อมูลยานพาหนะ',
              icon: Icons.directions_bus_outlined,
              children: [
                _buildInfoRow('ชื่อรถ :', shuttleName),
                _buildInfoRow('หมายเลขรถ :', shuttleNumber, isLast: true),
              ],
            ),
            const SizedBox(height: 30),

            GestureDetector(
              onTap: _logout,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5722), 
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF5722).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.white),
                    SizedBox(width: 8),
                    Text('ออกจากระบบ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF176a21), size: 24),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFEFF1F2), thickness: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLast = false, Color valueColor = const Color(0xFF2C2F30)}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF757778))),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }
}
