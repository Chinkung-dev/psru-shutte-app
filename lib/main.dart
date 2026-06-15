import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Import หน้าจอทั้งหมดมารวมไว้ที่นี่
import 'screens/login_screen.dart'; 
import 'screens/register_screen.dart'; 
import 'screens/forgot_password_screen.dart'; // ✨ เพิ่ม Import หน้าลืมรหัสผ่าน
import 'screens/driver/driver_home.dart';
import 'screens/student/student_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      title: 'PSRU Shuttle App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      
      initialRoute: '/login', 
      
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgotPassword': (context) => const ForgotPasswordScreen(), // ✨ เพิ่ม Route สำหรับหน้าลืมรหัสผ่าน
        '/driverHome': (context) => const DriverHome(),
        '/studentHome': (context) => const StudentHome(),
      },
    );
  }
} 