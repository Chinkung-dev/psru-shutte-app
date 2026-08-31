import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/top_toast.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  // Helper Function สำหรับแสดงแจ้งเตือน (ลดโค้ดซ้ำ)
  void _showSnackBar(String message, Color color) {
    TopToast.show(context, message, isError: color != Colors.green);
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    // 1. เช็คว่ากรอกข้อมูลหรือยัง
    if (email.isEmpty) {
      _showSnackBar('กรุณากรอกอีเมลของคุณ', Colors.orange);
      return;
    }

    // 2. เช็ครูปแบบอีเมลด้วย Regex (ต้องมี @ และ .)
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showSnackBar('รูปแบบอีเมลไม่ถูกต้อง (เช่น example@psru.ac.th)', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 3.  ไปเช็คในฐานข้อมูล Firestore ว่ามีอีเมลนี้อยู่จริงไหม
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1) // หาแค่คนแรกก็พอ
          .get();

      // ถ้าค้นหาแล้วไม่เจอ (List ว่างเปล่า)
      if (querySnapshot.docs.isEmpty) {
        _showSnackBar('ไม่พบบัญชีที่ใช้อีเมลนี้ในระบบ กรุณาตรวจสอบอีกครั้ง', Colors.red);
        setState(() => _isLoading = false);
        return; // หยุดการทำงาน ไม่ส่งคำสั่งให้ Auth
      }

      // 4. ถ้ามีข้อมูลอยู่จริง ค่อยสั่งให้ Firebase Auth ส่งลิงก์ไป
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      
      if (mounted) {
        _showSnackBar('ส่งลิงก์ตั้งรหัสผ่านใหม่ไปยังอีเมลแล้ว กรุณาตรวจสอบกล่องจดหมาย', Colors.green);
        Navigator.pop(context); // ปิดหน้านี้ กลับไปหน้า Login
      }
      
    } on FirebaseAuthException catch (e) {
      // ดักจับ Error อื่นๆ เผื่อไว้
      String message = 'เกิดข้อผิดพลาดในการส่งลิงก์';
      if (e.code == 'invalid-email') {
        message = 'รูปแบบอีเมลไม่ถูกต้อง';
      }
      _showSnackBar(message, Colors.red);
    } catch (e) {
      // ดักจับ Error ทั่วไป (เช่น เน็ตหลุด)
      _showSnackBar('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาลองใหม่', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF176a21)),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // ไอคอนแม่กุญแจ
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF9DF197).withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset, size: 80, color: Color(0xFF176a21)),
              ),
              const SizedBox(height: 30),

              const Text(
                'ลืมรหัสผ่าน?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF176a21)),
              ),
              const SizedBox(height: 16),
              
              const Text(
                'ไม่ต้องกังวล! เพียงกรอกอีเมลที่คุณใช้สมัครบัญชี เราจะส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปให้คุณทางอีเมล',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Color(0xFF595C5D), height: 1.5),
              ),
              const SizedBox(height: 40),

              // ช่องกรอกอีเมล
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'กรอกอีเมล (Email)',
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.email_outlined, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ปุ่มส่งลิงก์
              GestureDetector(
                onTap: _isLoading ? null : _resetPassword,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF81C784), Color(0xFF388E3C)], 
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('ส่งลิงก์รีเซ็ตรหัสผ่าน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 40), 
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}