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
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3), // สีพื้นหลังเทาอมมิ้นต์อ่อนๆ สะอาดตา สบายตา
      body: Stack(
        children: [
          // พื้นหลังตกแต่งด้วย Ambient Gradient Orbs ทรงกลมมุมจอ (ขนาดคงที่ ไม่ยืดหรือผิดสัดส่วนบนจอคอม/แท็บเล็ต)
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF81C784).withOpacity(0.35),
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
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF66BB6A).withOpacity(0.20),
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
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFA5D6A7).withOpacity(0.30),
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
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFC8E6C9).withOpacity(0.35),
                    const Color(0xFFC8E6C9).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // ส่วนเนื้อหาหลัก จัดกึ่งกลางหน้าจออย่างสมดุล (Responsive Layout)
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
                      Image.asset(
                        'lib/screens/driver/logo.png',
                        height: 76,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Column(
                            children: [
                              Icon(
                                Icons.directions_bus_rounded,
                                size: 54,
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
                      const SizedBox(height: 12),
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
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.04),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF176A21).withOpacity(0.08),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
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
                                labelStyle: const TextStyle(fontSize: 15),
                                hintText: 'example@psru.ac.th',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
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
                                labelStyle: const TextStyle(fontSize: 15),
                                hintText: '••••••••',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
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
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
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
                                  borderRadius: BorderRadius.circular(16),
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
                                  (_isLoading || _remainingLockoutSeconds > 0)
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              onEnter: (_) =>
                                  setState(() => _isLoginHovered = true),
                              onExit: (_) =>
                                  setState(() => _isLoginHovered = false),
                              child: GestureDetector(
                                onTap:
                                    (_isLoading || _remainingLockoutSeconds > 0)
                                    ? null
                                    : _login,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  width: double.infinity,
                                  height: 54,
                                  transform: Matrix4.identity()
                                    ..translate(
                                      0.0,
                                      (_isLoginHovered &&
                                              !_isLoading &&
                                              _remainingLockoutSeconds <= 0)
                                          ? -2.0
                                          : 0.0,
                                    ),
                                  decoration: BoxDecoration(
                                    gradient: _remainingLockoutSeconds > 0
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
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _remainingLockoutSeconds > 0
                                            ? Colors.black.withOpacity(0.05)
                                            : (_isLoginHovered
                                                  ? const Color(
                                                      0xFF2E7D32,
                                                    ).withOpacity(0.45)
                                                  : Colors.green.withOpacity(
                                                      0.3,
                                                    )),
                                        blurRadius: _isLoginHovered ? 16 : 10,
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
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
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
                              onEnter: (_) =>
                                  setState(() => _isGoogleHovered = true),
                              onExit: (_) =>
                                  setState(() => _isGoogleHovered = false),
                              child: GestureDetector(
                                onTap: (_isLoading || _isGoogleLoading)
                                    ? null
                                    : _signInWithGoogle,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  width: double.infinity,
                                  height: 54,
                                  transform: Matrix4.identity()
                                    ..translate(
                                      0.0,
                                      (_isGoogleHovered && !_isGoogleLoading)
                                          ? -2.0
                                          : 0.0,
                                    ),
                                  decoration: BoxDecoration(
                                    color: _isGoogleHovered
                                        ? const Color(0xFFF9FCF9)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: _isGoogleHovered
                                          ? const Color(0xFF66BB6A)
                                          : Colors.grey.shade300,
                                      width: _isGoogleHovered ? 1.5 : 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _isGoogleHovered
                                            ? const Color(
                                                0xFF66BB6A,
                                              ).withOpacity(0.25)
                                            : Colors.black.withOpacity(0.04),
                                        blurRadius: _isGoogleHovered ? 14 : 10,
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
                                            child: CircularProgressIndicator(
                                              color: Color(0xFF176a21),
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              _GoogleIcon(size: 22),
                                              SizedBox(width: 12),
                                              Text(
                                                'เข้าสู่ระบบด้วย Google',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF37474F),
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
                            'Version 1.0.4',
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
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double strokeWidth = w * 0.22;
    final center = Offset(w / 2, h / 2);
    final radius = (w / 2) - (strokeWidth / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Red: Top arc (from 225 deg to 315 deg)
    arcPaint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -2.356, 1.571, false, arcPaint);

    // Yellow: Left arc (from 135 deg to 225 deg)
    arcPaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, -3.927, 1.571, false, arcPaint);

    // Green: Bottom arc (from 45 deg to 135 deg)
    arcPaint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.785, 1.571, false, arcPaint);

    // Blue: Right arc (from -45 deg to 45 deg)
    arcPaint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.785, 1.571, false, arcPaint);

    // Blue: Horizontal center bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.46, h * 0.5 - strokeWidth / 2, w * 0.54, strokeWidth),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
