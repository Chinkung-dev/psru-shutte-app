import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/top_toast.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;



  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      TopToast.show(
        context,
        'กรุณากรอกอีเมลและรหัสผ่านให้ครบถ้วน',
        isError: true,
      );
      return;
    }

    if (!RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email)) {
      TopToast.show(
        context,
        'กรุณากรอกรูปแบบอีเมลให้ถูกต้อง (เช่น user@example.com)',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (!mounted) return;

      if (userCredential.user != null) {
        // ย้ายไปทำงานที่หน้า Home แทนแล้ว
      }

      if (!mounted) return;

      if (email == 'admin-shuttle@gmail.com') {
        Navigator.pushReplacementNamed(context, '/adminDashboard');
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!mounted) return;

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        String role = (data != null && data.containsKey('role'))
            ? data['role']
            : 'student';

        if (role == 'driver') {
          Navigator.pushReplacementNamed(context, '/driverHome');
        } else {
          final bool hasSeenOnboarding =
              data != null &&
              data.containsKey('hasSeenOnboarding') &&
              data['hasSeenOnboarding'] == true;

          if (hasSeenOnboarding) {
            Navigator.pushReplacementNamed(context, '/studentHome');
          } else {
            Navigator.pushReplacementNamed(context, '/studentOnboarding');
          }
        }
      } else {
        Navigator.pushReplacementNamed(context, '/studentOnboarding');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message =
          'เกิดข้อผิดพลาดในการเข้าสู่ระบบ (${e.message ?? e.code})';
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        message = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง';
      } else if (e.code == 'too-many-requests') {
        message =
            'มีการพยายามเข้าสู่ระบบผิดพลาดหลายครั้ง กรุณารอสักครู่แล้วลองใหม่';
      } else if (e.code == 'network-request-failed') {
        message =
            'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ';
      }
      TopToast.show(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ❌ ลบฟังก์ชัน _forgotPassword แบบโชว์ Dialog ออกไปแล้ว เพราะเราจะใช้การเปลี่ยนหน้าแทน

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: Stack(
        children: [
          // 🌊 Layer 1: พื้นหลัง Wave / Organic Blob ด้านหลังสุด สีเขียวอ่อนโปร่งแสงเพื่อมิติความลึก (Fluid Depth)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _HeaderWaveClipperLayer1(),
              child: Container(
                height: 270,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF81C784).withOpacity(0.45),
                      const Color(0xFFC8E6C9).withOpacity(0.45),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),

          // 🌊 Layer 2: ส่วนหัวหลัก (Header Blob Wave) สีเขียวอ่อนสดใสเพื่อให้ Logo โดดเด่นขึ้น
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _HeaderWaveClipperLayer2(),
              child: Container(
                height: 270,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF66BB6A), // Fresh Light Green
                      Color(0xFF81C784), // Soft Mint Green
                      Color(0xFFA5D6A7), // Pastel Light Green
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Stack(
                  children: [
                    // ✨ วงกลมประดับทรง Organic เพื่อเพิ่มมิติความพริ้วไหว
                    Positioned(
                      top: -25,
                      right: -30,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 100,
                      left: -20,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),

                    // 🚌 ไอคอนและข้อความส่วนหัว Header (PSRU Shuttle)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 16.0,
                          left: 24.0,
                          right: 24.0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            Image.asset(
                              'lib/screens/driver/logo.png',
                              height: 80,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Column(
                                  children: [
                                    Icon(
                                      Icons.directions_bus_rounded,
                                      size: 60,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'PSRU Shuttle',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'ระบบติดตามและเรียกรถรับส่งภายในมหาวิทยาลัย',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF176a21),
                                fontWeight: FontWeight.bold,
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

          // 📄 Layer 3: ส่วนการ์ดฟอร์มเข้าสู่ระบบ (Login Form Card)
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(
                        height: 220,
                      ), // ระยะห่างเพื่อให้การ์ดป๊อปอัพลอยทับ Wave Header เล็กน้อย
                      // 📄 กล่องป๊อปอัพการ์ดสีขาว (Floating White Popup Card)
                      Container(
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ข้อความ Login ด้านบนฟอร์ม
                            const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF176a21),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ช่องกรอกอีเมล
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F5F6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.15),
                                ),
                              ),
                              child: TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'อีเมล (Email)',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: Color(0xFF176a21),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ช่องกรอกรหัสผ่าน
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F5F6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.15),
                                ),
                              ),
                              child: TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'รหัสผ่าน (Password)',
                                  hintStyle: const TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFF176a21),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ✨ ปรับปรุงปุ่ม "ลืมรหัสผ่าน?" ให้เปลี่ยนหน้าจอแทนการเปิดป๊อปอัป
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        Navigator.pushNamed(
                                          context,
                                          '/forgotPassword',
                                        );
                                      },
                                child: const Text(
                                  'ลืมรหัสผ่าน?',
                                  style: TextStyle(
                                    color: Color(0xFF176a21),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ปุ่มเข้าสู่ระบบ
                            GestureDetector(
                              onTap: _isLoading ? null : _login,
                              child: Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF81C784),
                                      Color(0xFF388E3C),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.login,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'เข้าสู่ระบบ',
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
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      Column(
                        children: [
                          const Text(
                            'ยังไม่มีบัญชีผู้ใช้?',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _isLoading
                                ? null
                                : () {
                                    Navigator.pushNamed(context, '/register');
                                  },
                            child: const Text(
                              'สร้างบัญชีใหม่',
                              style: TextStyle(
                                color: Color(0xFF176a21),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Version 1.0.2', // ✨ เปลี่ยนเลขเวอร์ชันตรงนี้เวลามีอัปเดต
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
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
}

// 🎨 CustomClipper สำหรับ Layer 1 (ชั้นหลัง: Organic Blob คลื่นโปร่งแสงเพื่อความมีมิติ)
class _HeaderWaveClipperLayer1 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 40);

    var firstControlPoint = Offset(size.width * 0.35, size.height - 110);
    var firstEndPoint = Offset(size.width * 0.65, size.height - 25);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 0.88, size.height + 25);
    var secondEndPoint = Offset(size.width, size.height - 60);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// 🎨 CustomClipper สำหรับ Layer 2 (ชั้นหน้า: Organic Blob Wave หลัก สีเขียวเข้ม)
class _HeaderWaveClipperLayer2 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 75);

    var firstControlPoint = Offset(size.width * 0.28, size.height + 15);
    var firstEndPoint = Offset(size.width * 0.58, size.height - 45);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 0.85, size.height - 100);
    var secondEndPoint = Offset(size.width, size.height - 35);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
