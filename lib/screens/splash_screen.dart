import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'driver/driver_home.dart';
import 'student/student_home.dart';
import 'student/student_onboarding_screen.dart';
import 'admin/admin_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _statusText = 'กำลังเตรียมระบบ...';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();

    // รอให้เฟรมแรกวาดเสร็จก่อน เพื่อให้ Navigator พร้อมทำงานอย่างปลอดภัย
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAuthAndNavigate();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// ตรวจสอบสถานะการเข้าสู่ระบบและนำทางไปยังหน้าจอที่ถูกต้อง
  Future<void> _checkAuthAndNavigate() async {
    // หน่วงเวลาเพื่อให้แสดงอนิเมชันเปิดแอปอย่างนุ่มนวลและ Firebase Auth พร้อมทำงาน
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _navigateTo('/login');
        return;
      }

      if (mounted) {
        setState(() {
          _statusText = 'กำลังตรวจสอบสิทธิ์การใช้งาน...';
        });
      }

      if (user.email == 'admin-shuttle@gmail.com') {
        _navigateTo('/adminDashboard');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final localSessionId = prefs.getString('current_session_id');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        final serverSessionId = data['current_session_id'] as String?;

        // ตรวจสอบความถูกต้องของ Session
        if (localSessionId == null || localSessionId == serverSessionId) {
          if (serverSessionId != null && localSessionId == null) {
            await prefs.setString('current_session_id', serverSessionId);
          }

          final String role = (data['role'] as String?) ?? 'student';
          if (role == 'driver') {
            _navigateTo('/driverHome');
          } else if (role == 'admin') {
            _navigateTo('/adminDashboard');
          } else {
            final bool hasSeenOnboarding = data['hasSeenOnboarding'] == true;
            if (hasSeenOnboarding) {
              _navigateTo('/studentHome');
            } else {
              _navigateTo('/studentOnboarding');
            }
          }
          return;
        }
      }

      // หากไม่พบข้อมูลหรือเซสชันไม่ตรง ให้ไปยังหน้าเข้าสู่ระบบ
      _navigateTo('/login');
    } catch (e) {
      debugPrint("Splash check error: $e");
      if (mounted) {
        _navigateTo('/login');
      }
    }
  }

  /// เปลี่ยนหน้าจออย่างนุ่มนวลด้วย Fade Transition (ลดอาการกระตุก/เด้งทันที)
  void _navigateTo(String routeName) {
    if (!mounted) return;

    Widget targetWidget;
    switch (routeName) {
      case '/login':
        targetWidget = const LoginScreen();
        break;
      case '/driverHome':
        targetWidget = const DriverHome();
        break;
      case '/studentHome':
        targetWidget = const StudentHome();
        break;
      case '/studentOnboarding':
        targetWidget = const StudentOnboardingScreen();
        break;
      case '/adminDashboard':
        targetWidget = const AdminDashboardScreen();
        break;
      default:
        Navigator.of(context).pushReplacementNamed(routeName);
        return;
    }

    try {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => targetWidget,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      debugPrint("Navigation error: $e");
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(routeName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(
        0xFFF2F6F3,
      ), // สีพื้นหลังเทาอมมิ้นต์เดียวกับหน้า Login
      body: Stack(
        children: [
          // 1. พื้นหลังลวดลาย Dot Grid Pattern และเส้นทางเดินรถ Transit Route จำลอง
          const Positioned.fill(
            child: CustomPaint(painter: _SplashBackgroundPainter()),
          ),

          // 2. พื้นหลัง Ambient Gradient Orbs ตกแต่ง 4 มุม
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF81C784).withOpacity(0.38),
                    const Color(0xFF81C784).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: -80,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF66BB6A).withOpacity(0.25),
                    const Color(0xFF66BB6A).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFA5D6A7).withOpacity(0.35),
                    const Color(0xFFA5D6A7).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFC8E6C9).withOpacity(0.40),
                    const Color(0xFFC8E6C9).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Decorative Badges ตกแต่งด้านข้างสำหรับจอคอมพิวเตอร์/จอใหญ่
          if (screenWidth > 900) ...[
            Positioned(
              top: 120,
              left: 48,
              child: _buildDecorativeSideBadge(
                icon: Icons.directions_bus_filled_rounded,
                title: 'PSRU Campus Route',
                subtitle: 'เส้นทางรถรับส่งรอบมหาวิทยาลัย',
              ),
            ),
            Positioned(
              bottom: 120,
              right: 48,
              child: _buildDecorativeSideBadge(
                icon: Icons.my_location_rounded,
                title: 'Live GPS Tracking',
                subtitle: 'ติดตามพิกัดรถแบบเรียลไทม์',
              ),
            ),
            Positioned(
              bottom: 120,
              left: 48,
              child: _buildDecorativeSideBadge(
                icon: Icons.access_time_filled_rounded,
                title: 'Operating Hours',
                subtitle: 'ให้บริการจันทร์ - อาทิตย์',
              ),
            ),
            Positioned(
              top: 120,
              right: 48,
              child: _buildDecorativeSideBadge(
                icon: Icons.verified_user_rounded,
                title: 'Smart Campus',
                subtitle: 'ระบบเดินทางอัจฉริยะ PSRU',
              ),
            ),
          ],

          // 4. ส่วนเนื้อหาหลัก จัดกึ่งกลางหน้าจอในการ์ด Floating Card สวยงาม
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 24.0,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // โลโก้และข้อมูลหน้าโหลดโดยไม่มีกรอบการ์ดสีขาวซ้อน
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 16.0,
                            ),
                            child: Column(
                              children: [
                                // โลโก้แอป
                                Image.asset(
                                  'assets/images/LOGO01.png',
                                  height: 135,
                                  fit: BoxFit.contain,
                                  errorBuilder:
                                      (context, error, stackTrace) {
                                        return const Icon(
                                          Icons
                                              .directions_bus_rounded,
                                          size: 64,
                                          color: Color(0xFF176a21),
                                        );
                                      },
                                ),
                                const SizedBox(height: 18),

                                // ชื่อแอป
                                const Text(
                                  'PSRU S² Tracker',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF176a21),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // คำโปรย
                                const Text(
                                  'ระบบติดตามและเรียกรถรับส่งภายในมหาวิทยาลัย',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF436B49),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // หลอดดาวน์โหลดโมเดิร์นสีเขียว
                                Container(
                                  width: 180,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF176a21,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                    child:
                                        const LinearProgressIndicator(
                                          valueColor:
                                              AlwaysStoppedAnimation<
                                                Color
                                              >(Color(0xFF176a21)),
                                          backgroundColor:
                                              Colors.transparent,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // กล่องแสดงข้อความสถานะการโหลดแบบ Pill Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(
                                      20,
                                    ),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF176a21,
                                      ).withOpacity(0.15),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF176A21,
                                        ).withOpacity(0.06),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF176a21),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _statusText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF2C2F30),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ข้อความลิขสิทธิ์มหาวิทยาลัยด้านล่าง
                          const Text(
                            'มหาวิทยาลัยราชภัฏพิบูลสงคราม',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF718076),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// การ์ดลอยประดับด้านข้างสำหรับจอคอมพิวเตอร์ (Decorative Side Badge)
  Widget _buildDecorativeSideBadge({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176A21).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF176a21).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF176a21), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2F30),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5A605B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// พื้นหลังลวดลาย Dot Grid Pattern และเส้นทางเดินรถ Transit Route จำลอง
class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. วาด Dot Grid Pattern นุ่มนวลทั่วพื้นหลัง
    final dotPaint = Paint()
      ..color = const Color(0xFF176a21).withOpacity(0.045)
      ..style = PaintingStyle.fill;

    const double spacing = 32.0;
    for (double x = 16; x < size.width; x += spacing) {
      for (double y = 16; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // 2. วาดเส้นทางรถรับส่งจำลอง (Curved Transit Route Lines)
    final routePaint1 = Paint()
      ..color = const Color(0xFF176a21).withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final routePath1 = Path()
      ..moveTo(-50, size.height * 0.22)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.12,
        size.width * 0.72,
        size.height * 0.38,
        size.width + 50,
        size.height * 0.18,
      );
    canvas.drawPath(routePath1, routePaint1);

    final routePaint2 = Paint()
      ..color = const Color(0xFF66BB6A).withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final routePath2 = Path()
      ..moveTo(-50, size.height * 0.78)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.90,
        size.width * 0.78,
        size.height * 0.62,
        size.width + 50,
        size.height * 0.82,
      );
    canvas.drawPath(routePath2, routePaint2);

    // 3. จุดจอดจำลองบนเส้นทาง (Transit Stop Nodes)
    final stopPaint = Paint()
      ..color = const Color(0xFF176a21).withOpacity(0.14)
      ..style = PaintingStyle.fill;

    final stopBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final List<Offset> stopPoints = [
      Offset(size.width * 0.16, size.height * 0.18),
      Offset(size.width * 0.84, size.height * 0.26),
      Offset(size.width * 0.20, size.height * 0.83),
      Offset(size.width * 0.80, size.height * 0.71),
    ];

    for (final pt in stopPoints) {
      canvas.drawCircle(pt, 5.5, stopPaint);
      canvas.drawCircle(pt, 5.5, stopBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
