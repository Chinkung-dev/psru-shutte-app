import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'driver_edit_profile_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            userData = doc.data();
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Error fetching user data: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _navigateToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DriverEditProfileScreen()),
    );
    if (result == true || mounted) {
      _fetchUserData();
    }
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('จำนวนรอบที่วิ่งวันนี้', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        SizedBox(height: 8),
                        Text('5', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('คะแนน', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Text('4.95', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C2F30))),
                            SizedBox(width: 8),
                            Icon(Icons.star_border, color: Colors.amber),
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
