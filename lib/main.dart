import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';

// Import หน้าจอทั้งหมดมารวมไว้ที่นี่
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/driver/driver_home.dart';
import 'screens/student/student_home.dart';
import 'screens/student/student_onboarding_screen.dart';
import 'screens/admin/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String initialRoute = '/login';

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Firebase Initialized Successfully");

    // ตรวจสอบ Session การเข้าสู่ระบบทันทีเพื่อเข้าหน้าเป้าหมายโดยตรงโดยไม่ต้องมีหน้าโหลดซ้ำ
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance.authStateChanges().first.timeout(
          const Duration(milliseconds: 300),
        );
      } catch (_) {}
    }

    if (user != null) {
      if (user.email == 'admin-shuttle@gmail.com') {
        initialRoute = '/adminDashboard';
      } else {
        final prefs = await SharedPreferences.getInstance();
        final localSessionId = prefs.getString('current_session_id');

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 3));

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
              initialRoute = '/driverHome';
            } else {
              final bool hasSeenOnboarding = data['hasSeenOnboarding'] == true;
              if (hasSeenOnboarding) {
                initialRoute = '/studentHome';
              } else {
                initialRoute = '/studentOnboarding';
              }
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Error initializing Firebase or session: $e");
    initialRoute = '/login';
  }

  runApp(MyApp(initialRoute: initialRoute));
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, this.initialRoute = '/login'});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PSRU Shuttle App',
      scrollBehavior: MyCustomScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        textTheme: GoogleFonts.kanitTextTheme(Theme.of(context).textTheme),
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotPassword': (context) => const ForgotPasswordScreen(),
        '/driverHome': (context) => const DriverHome(),
        '/studentHome': (context) => const StudentHome(),
        '/studentOnboarding': (context) => const StudentOnboardingScreen(),
        '/adminDashboard': (context) => const AdminDashboardScreen(),
      },
    );
  }
}
