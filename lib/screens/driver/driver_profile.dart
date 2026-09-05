import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'driver_edit_profile_screen.dart';
import '../../widgets/app_loading_view.dart';

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
          debugPrint("Error listening to user data: $e");
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
      debugPrint("Error starting listener: $e");
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
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AppLoadingView(
        isScaffold: true,
        message: 'กำลังโหลดข้อมูลโปรไฟล์คนขับ...',
      );
    }

    final String name = userData?['name'] ?? 'ไม่ระบุชื่อ';
    final String driverId = userData?['student_id'] ?? '-';
    final String phone = userData?['phone'] ?? '-';
    final String email = userData?['email'] ?? '-';
    final String shuttleName = userData?['shuttle_name'] ?? '-';
    final String shuttleNumber = userData?['shuttle_number'] ?? '-';
    final String avatarPath = userData?['avatar'] ?? 'assets/images/man1.png';

    // คำนวณคะแนนดาวเฉลี่ยจากฐานข้อมูล
    final double totalScore = (userData?['total_rating_score'] ?? 0.0).toDouble();
    final int ratingCount = (userData?['rating_count'] ?? 0).toInt();

    String averageRatingStr = '-';
    if (ratingCount > 0) {
      double avg = totalScore / ratingCount;
      averageRatingStr = avg.toStringAsFixed(2);
    }

    // คำนวณจำนวนรอบที่วิ่งวันนี้
    int dailyRoundCount = 0;
    final now = DateTime.now();
    final String todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    if (userData?['last_round_date'] == todayStr) {
      dailyRoundCount = (userData?['daily_round_count'] ?? 0).toInt();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมมิ้นต์เดียวกับฝั่งนักศึกษา
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  child: Column(
                    children: [
                      // แถวหัวข้อและป้ายสิทธิ์
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ข้อมูลส่วนตัว',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C2F30),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF81C784).withValues(alpha: 0.4),
                                width: 1.0,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_rounded, color: Color(0xFF176a21), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'DRIVER',
                                  style: TextStyle(
                                    color: Color(0xFF176a21),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Avatar โปรไฟล์คนขับ
                      Center(
                        child: GestureDetector(
                          onTap: _navigateToEditProfile,
                          child: Stack(
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFF81C784).withValues(alpha: 0.6),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF176a21).withValues(alpha: 0.12),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  image: DecorationImage(
                                    image: AssetImage(avatarPath),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF176a21),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2F30),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'รหัสคนขับรถ: $driverId',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF757778),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // การ์ดสถิติ 2 คอลัมน์ (จำนวนรอบ & คะแนน)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF9FBF9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF81C784).withValues(alpha: 0.4),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF176a21).withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.route_rounded, size: 16, color: Color(0xFF176a21)),
                                      SizedBox(width: 5),
                                      Text(
                                        'รอบที่วิ่งวันนี้',
                                        style: TextStyle(
                                          color: Color(0xFF757778),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$dailyRoundCount รอบ',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF176a21),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF9FBF9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF81C784).withValues(alpha: 0.4),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF176a21).withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                                      SizedBox(width: 5),
                                      Text(
                                        'คะแนนประเมิน',
                                        style: TextStyle(
                                          color: Color(0xFF757778),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        averageRatingStr,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2C2F30),
                                        ),
                                      ),
                                      if (ratingCount > 0) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '($ratingCount)',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF757778),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Section Card 1: ข้อมูลคนขับรถ
                      _buildSectionCard(
                        title: 'ข้อมูลคนขับรถ',
                        icon: Icons.badge_outlined,
                        children: [
                          _buildInfoRow('รหัสคนขับรถ', driverId),
                          _buildInfoRow('อีเมล', email),
                          _buildInfoRow('เบอร์โทรศัพท์', phone, isLast: true),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section Card 2: ข้อมูลยานพาหนะ
                      _buildSectionCard(
                        title: 'ข้อมูลยานพาหนะประจำตัว',
                        icon: Icons.directions_bus_outlined,
                        children: [
                          _buildInfoRow('ชื่อรถ', shuttleName),
                          _buildInfoRow('หมายเลขรถ', shuttleNumber, isLast: true),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section Card 3: การจัดการ
                      _buildSectionCard(
                        title: 'การจัดการ',
                        icon: Icons.tune_rounded,
                        children: [
                          _buildActionRow(
                            'แก้ไขโปรไฟล์และเปลี่ยนรูปรถ',
                            Icons.edit_note_rounded,
                            onTap: _navigateToEditProfile,
                          ),
                          _buildActionRow(
                            'การแจ้งเตือน',
                            Icons.notifications_none_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ปุ่มออกจากระบบ
                      GestureDetector(
                        onTap: _logout,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF5350), Color(0xFFD32F2F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD32F2F).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'ออกจากระบบ',
                                style: TextStyle(
                                  fontSize: 16,
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
            ),
          ),
        ],
      ),
    );
  }

  // Header ดีไซน์ Curved Bottom Edge แบบเดียวกับฝั่งนักศึกษา
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF8FAF8),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.03),
          width: 1.0,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(
                'assets/images/LOGO02.png',
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      color: Color(0xFF176a21),
                      size: 26,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'PSRU Shuttle',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _navigateToEditProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings_outlined,
                        color: Color(0xFF5A605B),
                        size: 16,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ตั้งค่า',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A605B),
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

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.04),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF176a21), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF1F5F2), thickness: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF757778),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2F30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    String title,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF176a21), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C2F30),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF757778),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
