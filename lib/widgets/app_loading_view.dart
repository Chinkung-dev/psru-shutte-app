import 'package:flutter/material.dart';

class AppLoadingView extends StatelessWidget {
  final String message;
  final bool isScaffold;
  final Color? backgroundColor;
  final double logoHeight;

  const AppLoadingView({
    super.key,
    this.message = 'กำลังโหลดข้อมูล...',
    this.isScaffold = false,
    this.backgroundColor,
    this.logoHeight = 52.0,
  });

  Widget _buildContent(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.black.withOpacity(0.04),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF176a21).withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // โลโก้แอปพลิเคชัน PSRU S2 Tracker
            Image.asset(
              'assets/images/LOGO02.png',
              height: logoHeight,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_bus_rounded,
                      color: Color(0xFF176a21),
                      size: 28,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'PSRU Shuttle',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // แถบหลอดโหลดสีเขียว
            SizedBox(
              width: 140,
              height: 4.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: const LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF176a21)),
                  backgroundColor: Color(0xFFE8F5E9),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ข้อความแจ้งเตือนสถานะการโหลด
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF335738),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isScaffold) {
      return Scaffold(
        backgroundColor: backgroundColor ?? const Color(0xFFF2F6F3),
        body: _buildContent(context),
      );
    }
    return _buildContent(context);
  }
}
