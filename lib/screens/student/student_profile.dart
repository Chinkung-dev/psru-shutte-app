import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'favorite_stops_screen.dart';
import 'student_edit_profile_screen.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
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
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            userData = doc.data();
            isLoading = false;
          });
        }
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
      MaterialPageRoute(builder: (context) => const StudentEditProfileScreen()),
    );
    if (result == true || mounted) {
      _fetchUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF176a21)),
      );
    }

    final String name = userData?['name'] ?? 'ไม่ระบุชื่อ';
    final String studentId = userData?['student_id'] ?? '-';
    final String email = userData?['email'] ?? '-';
    final String phone = userData?['phone'] ?? 'ไม่ระบุเบอร์โทร';
    final String avatarPath = userData?['avatar'] ?? 'assets/images/man1.png';

    // เช็คว่ามีดาวกี่ดวง เพื่อเอาไปโชว์ในหน้าโปรไฟล์
    List<String> favStops = [];
    if (userData != null && userData!.containsKey('favorite_stops')) {
      favStops = List<String>.from(userData!['favorite_stops']);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              child: Column(
                children: [
                  const Center(
                    child: Text(
                      'Student Profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                onTap: _navigateToEditProfile,
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                        image: DecorationImage(
                          image: AssetImage(avatarPath),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF176a21),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2F30),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'รหัสนักศึกษา: $studentId',
              style: const TextStyle(fontSize: 14, color: Color(0xFF757778)),
            ),
            const SizedBox(height: 30),

            _buildSectionCard(
              title: 'ข้อมูลบัญชี',
              icon: Icons.person_outline,
              children: [
                _buildInfoRow('ชื่อ-นามสกุล', name),
                _buildInfoRow('อีเมล', email),
                _buildInfoRow('เบอร์โทรศัพท์', phone),
              ],
            ),
            const SizedBox(height: 20),

            _buildSectionCard(
              title: 'การจัดการ',
              icon: Icons.tune,
              children: [
                // ✨ ใส่ await เพื่อรอให้หน้า Favorite ปิดลงมา แล้วดึงข้อมูลใหม่ทันที
                _buildActionRow(
                  'จุดจอดที่ใช้บ่อย',
                  Icons.star,
                  iconColor: Colors.amber,
                  trailingText: '${favStops.length} จุด',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FavoriteStopsScreen(),
                      ),
                    );
                    _fetchUserData(); // ดึงข้อมูลใหม่หลังจากปิดหน้าจุดจอด
                  },
                ),
                _buildActionRow('การแจ้งเตือน', Icons.notifications_none),
              ],
            ),
            const SizedBox(height: 20),

            _buildSectionCard(
              title: 'เกี่ยวกับเรา',
              icon: Icons.help_outline,
              children: [
                _buildActionRow('แบบประเมิน', Icons.open_in_new),
                _buildActionRow('ติดต่อเรา', Icons.mail_outline),
              ],
            ),
            const SizedBox(height: 30),

            GestureDetector(
              onTap: _logout,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF28522),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF28522).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
  ],
),
);
}

  // ส่วนหัวข้อแบบแถบสีขาวเหมือน student_home
  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(
                'lib/screens/driver/logo.png',
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.menu, color: Color(0xFF176a21), size: 28),
              ),
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Color(0xFF176a21),
                  size: 26,
                ),
                onPressed: _navigateToEditProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF9DF197).withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF176a21), size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF757778)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2F30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    String label,
    IconData icon, {
    VoidCallback? onTap,
    Color? iconColor,
    String? trailingText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor ?? Colors.grey.shade400, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2F30),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (trailingText != null)
                  Text(
                    trailingText,
                    style: const TextStyle(
                      color: Color(0xFF176a21),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (trailingText != null) const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade300,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
