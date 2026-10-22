import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';

// Import หน้าจอทั้งหมดมารวมไว้นี่
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/driver/driver_home.dart';
import 'screens/student/student_home.dart';
import 'screens/student/student_onboarding_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/test/shuttle_3d_poc_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const envRoute = String.fromEnvironment('INITIAL_ROUTE');
  final String initialRoute = envRoute.isNotEmpty ? envRoute : '/';

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint("Firebase initialization timed out after 5s");
        return Firebase.app();
      },
    );
    debugPrint("Firebase Initialized Successfully");
  } catch (e) {
    debugPrint("Error initializing Firebase: $e");
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
      title: 'PSRU S² Tracker',
      scrollBehavior: MyCustomScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        textTheme: GoogleFonts.kanitTextTheme(Theme.of(context).textTheme),
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => initialRoute == '/shuttle3DPoc'
            ? const Shuttle3DPocScreen()
            : const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotPassword': (context) => const ForgotPasswordScreen(),
        '/driverHome': (context) => const DriverHome(),
        '/studentHome': (context) => const StudentHome(),
        '/studentOnboarding': (context) => const StudentOnboardingScreen(),
        '/adminDashboard': (context) => const AdminDashboardScreen(),
        '/shuttle3DPoc': (context) => const Shuttle3DPocScreen(),
      },
    );
  }
}
