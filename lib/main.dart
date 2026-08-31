import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';

// Import หน้าจอทั้งหมดมารวมไว้ที่นี่
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart'; // เพิ่ม Import หน้าลืมรหัสผ่าน
import 'screens/driver/driver_home.dart';
import 'screens/student/student_home.dart';
import 'screens/student/student_onboarding_screen.dart';
import 'screens/admin/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Firebase Initialized Successfully");
  } catch (e) {
    debugPrint("Error initializing Firebase: $e");
  }
  runApp(const MyApp());
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
  const MyApp({super.key});

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
      initialRoute: '/login', // หน้าแรกของแอป
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotPassword': (context) =>
            const ForgotPasswordScreen(), // เพิ่ม Route สำหรับหน้าลืมรหัสผ่าน
        '/driverHome': (context) => const DriverHome(),
        '/studentHome': (context) => const StudentHome(),
        '/studentOnboarding': (context) => const StudentOnboardingScreen(),
        '/adminDashboard': (context) => const AdminDashboardScreen(),
      },
    );
  }
}
