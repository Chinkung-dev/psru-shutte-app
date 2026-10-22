import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isGoogleLoading = false;
  bool _isLoginHovered = false;
  bool _isGoogleHovered = false;
  bool _isRegisterHovered = false;

  // ระบบความปลอดภัย: ป้องกัน Brute-force Attack
  static const int _maxFailedAttempts = 5;
  static const int _lockoutDurationSeconds = 30;

  int _failedAttempts = 0;
  int _remainingLockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _checkLockoutState();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// ตรวจสอบว่าแอปกำลังอยู่ในช่วงระงับการล็อกอินชั่วคราวหรือไม่
  Future<void> _checkLockoutState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutEndTimeMs = prefs.getInt('login_lockout_end_time') ?? 0;
      final savedAttempts = prefs.getInt('login_failed_attempts') ?? 0;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (lockoutEndTimeMs > nowMs) {
        final remainingSec = ((lockoutEndTimeMs - nowMs) / 1000).ceil();
        if (mounted) {
          setState(() {
            _failedAttempts = savedAttempts;
            _remainingLockoutSeconds = remainingSec;
          });
          _startLockoutCountdown(remainingSec);
        }
      } else {
        if (mounted) {
          setState(() {
            _failedAttempts = savedAttempts;
            _remainingLockoutSeconds = 0;
          });
        }
        if (lockoutEndTimeMs > 0) {
          await prefs.remove('login_lockout_end_time');
        }
      }
    } catch (_) {}
  }

  /// เริ่มนับเวลาถอยหลังการระงับการล็อกอิน
  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    _remainingLockoutSeconds = seconds;

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingLockoutSeconds <= 1) {
        timer.cancel();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('login_lockout_end_time');
          await prefs.remove('login_failed_attempts');
        } catch (_) {}

        if (mounted) {
          setState(() {
            _remainingLockoutSeconds = 0;
            _failedAttempts = 0;
          });
          TopToast.show(
            context,
            'ปลดล็อกระบบแล้ว คุณสามารถเข้าสู่ระบบได้อีกครั้ง',
            isError: false,
          );
        }
      } else {
        setState(() {
          _remainingLockoutSeconds--;
        });
      }
    });
  }

  /// บันทึกจำนวนครั้งที่กรอกรหัสผ่านผิด และสั่งล็อกหากครบ 5 ครั้ง
  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('login_failed_attempts', _failedAttempts);

      if (_failedAttempts >= _maxFailedAttempts) {
        final lockoutEndTime = DateTime.now().add(
          const Duration(seconds: _lockoutDurationSeconds),
        );
        await prefs.setInt(
          'login_lockout_end_time',
          lockoutEndTime.millisecondsSinceEpoch,
        );

        if (mounted) {
          _startLockoutCountdown(_lockoutDurationSeconds);
          TopToast.show(
            context,
            'คุณกรอกรหัสผ่านผิดครบ $_maxFailedAttempts ครั้งแล้ว ระบบถูกระงับชั่วคราว $_lockoutDurationSeconds วินาที',
            isError: true,
          );
        }
      } else {
        final remainingChances = _maxFailedAttempts - _failedAttempts;
        if (mounted) {
          TopToast.show(
            context,
            'อีเมลหรือรหัสผ่านไม่ถูกต้อง (เหลือโอกาสอีก $remainingChances ครั้ง)',
            isError: true,
          );
        }
      }
    } catch (_) {}
  }

  /// รีเซ็ตประวัติการกรอกผิดเมื่อเข้าสู่ระบบสำเร็จ
  Future<void> _resetFailedAttempts() async {
    _lockoutTimer?.cancel();
    _failedAttempts = 0;
    _remainingLockoutSeconds = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_failed_attempts');
      await prefs.remove('login_lockout_end_time');
    } catch (_) {}
  }

  /// สร้างและบันทึกรหัสเซสชันใหม่สำหรับอุปกรณ์ปัจจุบันเพื่อป้องกันการเข้าสู่ระบบซ้ำ
  Future<void> _registerNewSession(String uid) async {
    try {
      final sessionId = '${DateTime.now().millisecondsSinceEpoch}_$uid';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_session_id', sessionId);

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'current_session_id': sessionId,
        'last_login_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error registering new session: $e");
    }
  }

  Future<void> _login() async {
    if (_remainingLockoutSeconds > 0) {
      TopToast.show(
        context,
        'ระบบถูกระงับการเข้าสู่ระบบชั่วคราว กรุณารออีก $_remainingLockoutSeconds วินาที',
        isError: true,
      );
      return;
    }

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

      // ล็อกอินสำเร็จ -> บันทึก Session ID สำหรับอุปกรณ์นี้
      await _registerNewSession(userCredential.user!.uid);

      if (!mounted) return;

      // รีเซ็ตประวัติการกรอกผิด
      await _resetFailedAttempts();

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

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_role', role);

        if (role == 'driver') {
          Navigator.pushReplacementNamed(context, '/driverHome');
        } else if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/adminDashboard');
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
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        await _recordFailedAttempt();
      } else if (e.code == 'too-many-requests') {
        TopToast.show(
          context,
          'มีการพยายามเข้าสู่ระบบผิดพลาดหลายครั้ง กรุณารอสักครู่แล้วลองใหม่',
          isError: true,
        );
      } else if (e.code == 'network-request-failed') {
        TopToast.show(
          context,
          'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ',
          isError: true,
        );
      } else {
        TopToast.show(
          context,
          'เกิดข้อผิดพลาดในการเข้าสู่ระบบ (${e.message ?? e.code})',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // บน Web: ใช้ signInWithPopup ของ Firebase Auth โดยตรง ซึ่งเสถียรและรองรับมาตรฐานล่าสุด
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await FirebaseAuth.instance.signInWithPopup(
          googleProvider,
        );
      } else {
        // บน Android / iOS: ใช้ GoogleSignIn SDK
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          // ผู้ใช้กดยกเลิกการเลือกบัญชี Google
          if (mounted) setState(() => _isGoogleLoading = false);
          return;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
      }

      final User? user = userCredential.user;
      if (user == null || !mounted) return;

      // ล็อกอินสำเร็จ -> บันทึก Session ID สำหรับอุปกรณ์นี้
      await _registerNewSession(user.uid);

      if (!mounted) return;

      // รีเซ็ตประวัติการกรอกผิด
      await _resetFailedAttempts();
      if (!mounted) return;

      if (user.email == 'admin-shuttle@gmail.com') {
        Navigator.pushReplacementNamed(context, '/adminDashboard');
        return;
      }

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final DocumentSnapshot userDoc = await userDocRef.get();

      if (!mounted) return;

      if (!userDoc.exists) {
        // สกัดรหัสนักศึกษา 10 หลักอัตโนมัติหากใช้อีเมลสถาบันรูปแบบ @psru.ac.th
        String extractedStudentId = '';
        final emailStr = user.email ?? '';
        final match = RegExp(r'^(\d{10})@psru\.ac\.th$').firstMatch(emailStr);
        if (match != null) {
          extractedStudentId = match.group(1) ?? '';
        }

        // สร้าง Document ผู้ใช้ใหม่ให้ครบถ้วนทั้ง 9 fields
        final Map<String, dynamic> newUserData = {
          'uid': user.uid,
          'name': (user.displayName != null && user.displayName!.isNotEmpty)
              ? user.displayName!
              : 'นักศึกษา',
          'email': emailStr,
          'student_id': extractedStudentId,
          'phone': user.phoneNumber ?? '',
          'role': 'student',
          'avatar': 'assets/images/man1.png',
          'hasSeenOnboarding': false,
          'created_at': FieldValue.serverTimestamp(),
        };

        await userDocRef.set(newUserData);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/studentOnboarding');
      } else {
        // บัญชีเดิมในระบบ
        final data = userDoc.data() as Map<String, dynamic>?;
        String role = (data != null && data.containsKey('role'))
            ? data['role']
            : 'student';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_role', role);

        if (role == 'driver') {
          Navigator.pushReplacementNamed(context, '/driverHome');
        } else if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/adminDashboard');
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
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message =
          'เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย Google (${e.message ?? e.code})';
      if (e.code == 'account-exists-with-different-credential') {
        message = 'มีบัญชีที่ใช้อีเมลนี้อยู่แล้วด้วยวิธีเข้าสู่ระบบอื่น';
      } else if (e.code == 'network-request-failed') {
        message =
            'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อของคุณ';
      }
      TopToast.show(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ลบฟังก์ชัน _forgotPassword แบบโชว์ Dialog ออกไปแล้ว เพราะเราจะใช้การเปลี่ยนหน้าแทน

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(
        0xFFF2F6F3,
      ), // สีพื้นหลังเทาอมมิ้นต์อ่อนๆ สะอาดตา สบายตา
      body: Stack(
        children: [
          // 1. พื้นหลังลวดลาย Dot Grid Pattern และเส้นทางเดินรถ Transit Route จำลอง
          const Positioned.fill(
            child: CustomPaint(painter: _LoginBackgroundPainter()),
          ),

          // 2. Ambient Gradient Glow Orbs ทรงกลมกระจายแสงนุ่มนวล
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
                subtitle: 'ให้บริการจันทร์ - ศุกร์',
              ),
            ),
          ],

          // 4. ส่วนเนื้อหาหลัก จัดกึ่งกลางหน้าจออย่างสมดุล (Responsive Layout)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 24.0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ส่วนหัวแบรนด์ (Logo + ชื่อแอป + คำโปรย)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF176a21).withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/LOGO02.png',
                          height: 68,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Column(
                              children: [
                                Icon(
                                  Icons.directions_bus_rounded,
                                  size: 56,
                                  color: Color(0xFF176a21),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'PSRU Shuttle',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF176a21),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'ระบบติดตามและเรียกรถรับส่งภายในมหาวิทยาลัย แบบเรียลไทม์',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF436B49),
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // การ์ดสีขาวสำหรับกรอกข้อมูลเข้าสู่ระบบ (Floating White Card)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.04),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF176A21).withOpacity(0.09),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // แถบเส้นไล่ระดับสีด้านบนการ์ด (Top Gradient Accent Bar)
                              Container(
                                height: 5,
                                width: double.infinity,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF176a21),
                                      Color(0xFF66BB6A),
                                      Color(0xFF9DF197),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(28.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ข้อความ Login ด้านบนฟอร์ม
                                    const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF176a21),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'กรอกข้อมูลเพื่อเข้าใช้งานระบบรถรับส่ง',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 22),

                                    // ช่องกรอกอีเมล
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'อีเมล (Email)',
                                        labelStyle: const TextStyle(
                                          fontSize: 15,
                                        ),
                                        hintText: 'example@psru.ac.th',
                                        hintStyle: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 14,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.email_outlined,
                                          size: 20,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 18,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // ช่องกรอกรหัสผ่าน
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'รหัสผ่าน (Password)',
                                        labelStyle: const TextStyle(
                                          fontSize: 15,
                                        ),
                                        hintText: '••••••••',
                                        hintStyle: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 14,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                          size: 20,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: Colors.grey.shade600,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 18,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    // การ์ดแจ้งเตือนเมื่อระบบถูกระงับชั่วคราวจากการกรอกรหัสผิด
                                    if (_remainingLockoutSeconds > 0) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFDE8E8),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFF98080),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.lock_clock,
                                              color: Color(0xFFE02424),
                                              size: 24,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'ระงับการเข้าสู่ระบบชั่วคราว\nกรุณารออีก $_remainingLockoutSeconds วินาที',
                                                style: const TextStyle(
                                                  color: Color(0xFF9B1C1C),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    // ปุ่มลืมรหัสผ่าน
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
                                    const SizedBox(height: 18),

                                    // ปุ่มเข้าสู่ระบบ
                                    MouseRegion(
                                      cursor:
                                          (_isLoading ||
                                              _remainingLockoutSeconds > 0)
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                      onEnter: (_) => setState(
                                        () => _isLoginHovered = true,
                                      ),
                                      onExit: (_) => setState(
                                        () => _isLoginHovered = false,
                                      ),
                                      child: GestureDetector(
                                        onTap:
                                            (_isLoading ||
                                                _remainingLockoutSeconds > 0)
                                            ? null
                                            : _login,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          width: double.infinity,
                                          height: 54,
                                          transform: Matrix4.identity()
                                            ..translate(
                                              0.0,
                                              (_isLoginHovered &&
                                                      !_isLoading &&
                                                      _remainingLockoutSeconds <=
                                                          0)
                                                  ? -2.0
                                                  : 0.0,
                                            ),
                                          decoration: BoxDecoration(
                                            gradient:
                                                _remainingLockoutSeconds > 0
                                                ? LinearGradient(
                                                    colors: [
                                                      Colors.grey.shade400,
                                                      Colors.grey.shade500,
                                                    ],
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                  )
                                                : LinearGradient(
                                                    colors: _isLoginHovered
                                                        ? const [
                                                            Color(0xFF94DC97),
                                                            Color(0xFF2E7D32),
                                                          ]
                                                        : const [
                                                            Color(0xFF81C784),
                                                            Color(0xFF388E3C),
                                                          ],
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color:
                                                    _remainingLockoutSeconds > 0
                                                    ? Colors.black.withOpacity(
                                                        0.05,
                                                      )
                                                    : (_isLoginHovered
                                                          ? const Color(
                                                              0xFF2E7D32,
                                                            ).withOpacity(0.45)
                                                          : Colors.green
                                                                .withOpacity(
                                                                  0.3,
                                                                )),
                                                blurRadius: _isLoginHovered
                                                    ? 16
                                                    : 10,
                                                offset: Offset(
                                                  0,
                                                  _isLoginHovered ? 6 : 4,
                                                ),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 3,
                                                        ),
                                                  )
                                                : const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.login,
                                                        color: Colors.white,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'เข้าสู่ระบบ',
                                                        style: TextStyle(
                                                          fontSize: 17,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // เส้นคั่น "หรือเข้าสู่ระบบด้วย"
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: Colors.grey.shade300,
                                            thickness: 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            'หรือเข้าสู่ระบบด้วย',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: Colors.grey.shade300,
                                            thickness: 1,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // ปุ่มเข้าสู่ระบบด้วย Google
                                    MouseRegion(
                                      cursor: (_isLoading || _isGoogleLoading)
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                      onEnter: (_) => setState(
                                        () => _isGoogleHovered = true,
                                      ),
                                      onExit: (_) => setState(
                                        () => _isGoogleHovered = false,
                                      ),
                                      child: GestureDetector(
                                        onTap: (_isLoading || _isGoogleLoading)
                                            ? null
                                            : _signInWithGoogle,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          width: double.infinity,
                                          height: 54,
                                          transform: Matrix4.identity()
                                            ..translate(
                                              0.0,
                                              (_isGoogleHovered &&
                                                      !_isGoogleLoading)
                                                  ? -2.0
                                                  : 0.0,
                                            ),
                                          decoration: BoxDecoration(
                                            color: _isGoogleHovered
                                                ? const Color(0xFFF9FCF9)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                            border: Border.all(
                                              color: _isGoogleHovered
                                                  ? const Color(0xFF66BB6A)
                                                  : Colors.grey.shade300,
                                              width: _isGoogleHovered
                                                  ? 1.5
                                                  : 1.2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _isGoogleHovered
                                                    ? const Color(
                                                        0xFF66BB6A,
                                                      ).withOpacity(0.25)
                                                    : Colors.black.withOpacity(
                                                        0.04,
                                                      ),
                                                blurRadius: _isGoogleHovered
                                                    ? 14
                                                    : 10,
                                                offset: Offset(
                                                  0,
                                                  _isGoogleHovered ? 5 : 3,
                                                ),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: _isGoogleLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Color(
                                                            0xFF176a21,
                                                          ),
                                                          strokeWidth: 2.5,
                                                        ),
                                                  )
                                                : const FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          _GoogleIcon(size: 22),
                                                          SizedBox(width: 12),
                                                          Text(
                                                            'เข้าสู่ระบบด้วย Google',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Color(
                                                                0xFF37474F,
                                                              ),
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
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ส่วนท้าย: ลิงก์สร้างบัญชีใหม่
                      Column(
                        children: [
                          const Text(
                            'ยังไม่มีบัญชีผู้ใช้?',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          MouseRegion(
                            cursor: _isLoading
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            onEnter: (_) =>
                                setState(() => _isRegisterHovered = true),
                            onExit: (_) =>
                                setState(() => _isRegisterHovered = false),
                            child: GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : () {
                                      Navigator.pushNamed(context, '/register');
                                    },
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 150),
                                style: TextStyle(
                                  color: _isRegisterHovered
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFF176a21),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  decoration: _isRegisterHovered
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                                child: const Text('สร้างบัญชีใหม่'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Version 1.0.7',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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

// วิดเจ็ตไอคอน Google สีสันสมจริง (Custom Painted 4-Color Google G Logo)
class _GoogleIcon extends StatelessWidget {
  final double size;
  const _GoogleIcon({this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _GoogleLogoPainter());
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // ปรับสเกลให้เข้ากับ viewBox ขนาด 24x24 หน่วยของโลโก้ Google มาตรฐาน
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. สีน้ำเงิน (Blue) - แถบตรงกลางและส่วนโค้งขวาล่าง
    paint.color = const Color(0xFF4285F4);
    final bluePath = Path()
      ..moveTo(23.745, 12.27)
      ..cubicTo(23.745, 11.57, 23.685, 10.87, 23.555, 10.2)
      ..lineTo(12.0, 10.2)
      ..lineTo(12.0, 14.71)
      ..lineTo(18.6, 14.71)
      ..cubicTo(18.31, 16.23, 17.46, 17.53, 16.2, 18.39)
      ..lineTo(16.2, 21.44)
      ..lineTo(20.08, 21.44)
      ..cubicTo(22.35, 19.35, 23.745, 16.27, 23.745, 12.27)
      ..close();
    canvas.drawPath(bluePath, paint);

    // 2. สีเขียว (Green) - ส่วนโค้งด้านล่าง
    paint.color = const Color(0xFF34A853);
    final greenPath = Path()
      ..moveTo(12.0, 24.0)
      ..cubicTo(15.24, 24.0, 17.95, 22.92, 19.93, 21.09)
      ..lineTo(16.05, 18.04)
      ..cubicTo(14.97, 18.76, 13.6, 19.2, 12.0, 19.2)
      ..cubicTo(8.88, 19.2, 6.23, 17.1, 5.28, 14.27)
      ..lineTo(1.26, 14.27)
      ..lineTo(1.26, 17.42)
      ..cubicTo(3.25, 21.36, 7.34, 24.0, 12.0, 24.0)
      ..close();
    canvas.drawPath(greenPath, paint);

    // 3. สีเหลือง (Yellow) - ส่วนโค้งด้านซ้าย
    paint.color = const Color(0xFFFBBC05);
    final yellowPath = Path()
      ..moveTo(5.28, 14.27)
      ..cubicTo(5.03, 13.55, 4.9, 12.78, 4.9, 12.0)
      ..cubicTo(4.9, 11.22, 5.03, 10.45, 5.28, 9.73)
      ..lineTo(5.28, 6.58)
      ..lineTo(1.26, 6.58)
      ..cubicTo(0.46, 8.16, 0.0, 9.97, 0.0, 12.0)
      ..cubicTo(0.0, 14.03, 0.46, 15.84, 1.26, 17.42)
      ..lineTo(5.28, 14.27)
      ..close();
    canvas.drawPath(yellowPath, paint);

    // 4. สีแดง (Red) - ส่วนโค้งด้านบน
    paint.color = const Color(0xFFEA4335);
    final redPath = Path()
      ..moveTo(12.0, 4.8)
      ..cubicTo(13.77, 4.8, 15.35, 5.41, 16.6, 6.6)
      ..lineTo(20.02, 3.18)
      ..cubicTo(17.95, 1.19, 15.24, 0.0, 12.0, 0.0)
      ..cubicTo(7.34, 0.0, 3.25, 2.64, 1.26, 6.58)
      ..lineTo(5.28, 9.73)
      ..cubicTo(6.23, 6.9, 8.88, 4.8, 12.0, 4.8)
      ..close();
    canvas.drawPath(redPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// พื้นหลังลวดลาย Dot Grid Pattern และเส้นทางเดินรถ Transit Route จำลอง
class _LoginBackgroundPainter extends CustomPainter {
  const _LoginBackgroundPainter();

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
