import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentOnboardingScreen extends StatefulWidget {
  const StudentOnboardingScreen({super.key});

  @override
  State<StudentOnboardingScreen> createState() =>
      _StudentOnboardingScreenState();
}

class _StudentOnboardingScreenState extends State<StudentOnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _floatController;
  late Animation<double> _imageFloatAnimation;
  late Animation<double> _cardFloatAnimation;
  int _totalUsers = 0;
  bool _isLoadingUsers = true;
  List<String> _sampleAvatars = [];

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _imageFloatAnimation = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _cardFloatAnimation = Tween<double>(begin: 4.0, end: -4.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final countQuery = await FirebaseFirestore.instance.collection('users').count().get();
      
      // ดึงตัวอย่างผู้ใช้มา 2 คนเพื่อเอารูปโปรไฟล์
      final sampleUsersQuery = await FirebaseFirestore.instance
          .collection('users')
          .limit(2)
          .get();

      List<String> avatars = [];
      for (var doc in sampleUsersQuery.docs) {
        if (doc.data().containsKey('avatar')) {
          avatars.add(doc['avatar'] as String);
        }
      }

      if (mounted) {
        setState(() {
          _totalUsers = countQuery.count ?? 0;
          _sampleAvatars = avatars;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
      debugPrint("Error fetching user data: $e");
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _onGetStartedPressed() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // อัปเดตสถานะใน Firestore ว่าเคยผ่านหน้าเริ่มต้นใช้งาน (Onboarding) สำหรับนักศึกษานี้แล้ว
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'hasSeenOnboarding': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating onboarding status: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // นำทางไปยังหน้าหลักของนักศึกษา
        Navigator.pushReplacementNamed(context, '/studentHome');
      }
    }
  }

  Widget _buildAvatarCircle(Widget child, {bool isPrimary = false}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFF176a21) : const Color(0xFFE0E3E4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF), // surface-container-lowest
      body: Stack(
        children: [
          // 1. Atmospheric Background Elements (ตาม DESIGN.md และ code.html)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.35,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFFE8F5E9), Colors.transparent],
                  center: Alignment.bottomCenter,
                  radius: 1.0,
                ),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF9DF197).withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF86FAAC).withOpacity(0.12),
              ),
            ),
          ),

          // 2. Main Content Container
          SafeArea(
            child: Column(
              children: [
                // Header Brand
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 12.0),
                  child: Center(
                    child: Image.asset(
                      'assets/images/LOGO02.png',
                      height: 50,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.directions_bus,
                              color: Color(0xFF176a21),
                              size: 36,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'PSRU Shuttle',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF176a21),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Central Illustration & Floating Glass Module
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 16),
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // Decorative concentric circles
                              Container(
                                width: 290,
                                height: 290,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFF9DF197,
                                    ).withOpacity(0.35),
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 226,
                                  height: 226,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(
                                        0xFF9DF197,
                                      ).withOpacity(0.55),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),

                              // Hero Image Card (w-64 h-64 rounded-2xl shadow-2xl)
                              AnimatedBuilder(
                                animation: _imageFloatAnimation,
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(0, _imageFloatAnimation.value),
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: 300,
                                  height: 256,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF2C2F30,
                                        ).withOpacity(0.12),
                                        blurRadius: 30,
                                        offset: const Offset(0, 15),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Image.asset(
                                      'lib/screens/driver/screen.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: const Color(0xFFEFF1F2),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.directions_bus_rounded,
                                            size: 80,
                                            color: Color(0xFF176a21),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),

                              // Floating Glass UI Snippet (Atmospheric Precision)
                              Positioned(
                                bottom: -12,
                                right: 6,
                                child: AnimatedBuilder(
                                  animation: _cardFloatAnimation,
                                  builder: (context, child) {
                                    return Transform.translate(
                                      offset: Offset(0, _cardFloatAnimation.value),
                                      child: child,
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 20,
                                        sigmaY: 20,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFF5F6F7,
                                          ).withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.6),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.08,
                                              ),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF176a21),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'มาถึงใน',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF595C5D),
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                Text(
                                                  '3 นาที',
                                                  style: TextStyle(
                                                    fontFamily: 'Manrope',
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF176a21),
                                                    height: 1.1,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 42),

                          // Typography Section
                          const Text(
                            'ยินดีต้อนรับสู่\nPSRU Shuttle',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF176a21),
                              height: 1.25,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20.0),
                            child: Text(
                              'ติดตามรถรับส่งภายในมหาวิทยาลัยแบบเรียลไทม์ และวางแผนการเดินทางของคุณได้แม่นยำยิ่งขึ้น',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF595C5D),
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Action Section & Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
                  child: Column(
                    children: [
                      // Kinetic Gradient Button (primary to primary_container)
                      Container(
                        width: 320, // ปรับให้ขนาดพอดีตามรูปที่วาดมา ไม่กว้างเต็มจอ
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF176a21), // Primary Green
                              Color(0xFF389742), // Emerald Green
                              Color(0xFF67B26F), // Bright Secondary Gradient (#67B26F)
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF389742).withOpacity(0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onGetStartedPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'เริ่มต้นใช้งาน',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Social/Status Indicators Footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 72,
                            height: 32,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 0,
                                  child: _buildAvatarCircle(
                                    _sampleAvatars.isNotEmpty
                                        ? ClipOval(
                                            child: Image.asset(
                                              _sampleAvatars[0],
                                              width: 32,
                                              height: 32,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person,
                                            size: 16,
                                            color: Color(0xFF595C5D),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  left: 20,
                                  child: _buildAvatarCircle(
                                    _sampleAvatars.length > 1
                                        ? ClipOval(
                                            child: Image.asset(
                                              _sampleAvatars[1],
                                              width: 32,
                                              height: 32,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.person,
                                            size: 16,
                                            color: Color(0xFF595C5D),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  left: 40,
                                  child: _buildAvatarCircle(
                                    Text(
                                      _isLoadingUsers ? '...' : '$_totalUsers',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    isPrimary: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'เข้าร่วมกับนิสิตท่านอื่นใช้งานอยู่ขณะนี้',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF757778),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
