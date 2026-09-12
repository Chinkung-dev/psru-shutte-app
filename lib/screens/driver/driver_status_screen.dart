import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../widgets/top_toast.dart';
import '../../services/shuttle_access.dart';
import '../../widgets/app_loading_view.dart';

class DriverStatusScreen extends StatefulWidget {
  final String? shuttleDocId;

  const DriverStatusScreen({
    super.key,
    this.shuttleDocId,
  });

  @override
  State<DriverStatusScreen> createState() => _DriverStatusScreenState();
}

class _DriverStatusScreenState extends State<DriverStatusScreen> {
  // ค่าเริ่มต้นของสถานะ (ใช้ 'available', 'full', 'break', 'offline')
  String _currentStatus = 'available';
  bool _isLoading = true;
  String? _shuttleDocId;
  String? _shuttleName;
  String? _shuttleNumber;

  @override
  void initState() {
    super.initState();
    _shuttleDocId = widget.shuttleDocId;
    _fetchCurrentStatus();
  }

  @override
  void didUpdateWidget(covariant DriverStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shuttleDocId != widget.shuttleDocId) {
      _shuttleDocId = widget.shuttleDocId;
      _fetchCurrentStatus();
    }
  }

  Future<void> _fetchCurrentStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String? keyToUse = _shuttleDocId;

        if (keyToUse == null || keyToUse.isEmpty) {
          String? docId;
          String? sName;
          String? sNumber;

          // 1. ดึงข้อมูลจาก Realtime Database (RTDB) shuttles ก่อน
          try {
            final rtdbShuttlesSnap = await FirebaseDatabase.instance
                .ref('shuttles')
                .get()
                .timeout(const Duration(seconds: 5));

            if (rtdbShuttlesSnap.exists) {
              for (final child in rtdbShuttlesSnap.children) {
                final val = child.value;
                if (val is Map && val['driver_uid']?.toString() == user.uid) {
                  docId = child.key;
                  sName = val['name']?.toString();
                  sNumber = val['number']?.toString();
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint("Error querying RTDB in DriverStatusScreen: $e");
          }

          // 2. ถ้าไม่พบ ให้ค้นจาก users/{uid}
          if (sName == null || sName.isEmpty) {
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get()
                  .timeout(const Duration(seconds: 5));
              final uData = userDoc.data();
              sName = uData?['shuttle_name']?.toString() ?? uData?['name']?.toString();
              sNumber = uData?['shuttle_number']?.toString() ?? uData?['number']?.toString();
            } catch (e) {
              debugPrint("Error querying user doc in DriverStatusScreen: $e");
            }
          }

          _shuttleName = sName;
          _shuttleNumber = sNumber;

          // 3. กำหนด Key ในรูปแบบเดียวกับ driver_home.dart
          keyToUse = shuttleDatabaseKey(
            documentId: docId != null && docId.isNotEmpty ? docId : user.uid,
            name: sName ?? '',
            number: sNumber ?? '',
          );
        }

        _shuttleDocId = keyToUse;

        // 4. ดึงสถานะเดิมมาแสดง (จาก RTDB)
        if (_shuttleDocId != null) {
          final rtdbSnapshot = await FirebaseDatabase.instance
              .ref('shuttles')
              .child(_shuttleDocId!)
              .get()
              .timeout(const Duration(seconds: 5));
          if (rtdbSnapshot.exists) {
            final rtdbData = rtdbSnapshot.value as Map<dynamic, dynamic>;
            if (rtdbData.containsKey('passenger_status')) {
              if (mounted) {
                setState(() {
                  _currentStatus = rtdbData['passenger_status'].toString();
                  if (rtdbData.containsKey('name')) {
                    _shuttleName = rtdbData['name']?.toString();
                  }
                  if (rtdbData.containsKey('number')) {
                    _shuttleNumber = rtdbData['number']?.toString();
                  }
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching status: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    String? keyToUpdate = _shuttleDocId ?? widget.shuttleDocId;

    if (keyToUpdate == null || keyToUpdate.isEmpty) {
      await _fetchCurrentStatus();
      keyToUpdate = _shuttleDocId ?? widget.shuttleDocId;
    }

    if (keyToUpdate == null || keyToUpdate.isEmpty) {
      if (mounted) {
        TopToast.show(context, 'ไม่พบข้อมูลรถของคุณ กรุณาลองใหม่อีกครั้ง', isError: true);
      }
      return;
    }

    setState(() {
      _currentStatus = newStatus;
    });

    try {
      await FirebaseDatabase.instance
          .ref('shuttles')
          .child(keyToUpdate)
          .update({
            'passenger_status': newStatus,
            'last_updated': ServerValue.timestamp,
          });

      if (mounted) {
        TopToast.show(context, 'อัปเดตสถานะเป็น "$newStatus" สำเร็จ', isError: false);
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
      if (mounted) {
        TopToast.show(context, 'เกิดข้อผิดพลาดในการอัปเดตสถานะ', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F2), // สีพื้นหลังเทาอมมิ้นต์เดียวกับฝั่งนักศึกษา
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const AppLoadingView(
                    message: 'กำลังโหลดข้อมูลสถานะรถรับส่ง...',
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hero Status Card (สรุปสถานะรถปัจจุบัน)
                            _buildHeroStatusCard(),
                            const SizedBox(height: 20),

                            // Section Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'เลือกสถานะการให้บริการ',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C2F30),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF81C784).withValues(alpha: 0.5),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.sync_rounded, color: Color(0xFF176a21), size: 13),
                                      SizedBox(width: 4),
                                      Text(
                                        'REAL-TIME',
                                        style: TextStyle(
                                          color: Color(0xFF176a21),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // สถานะ 1: ว่าง (Available)
                            _buildStatusCard(
                              statusKey: 'available',
                              title: 'ว่าง / พร้อมรับผู้โดยสาร',
                              subtitle: 'Available - มีที่นั่งว่างสำหรับนักศึกษา',
                              icon: Icons.check_circle_outline_rounded,
                              activeColor: const Color(0xFF176a21),
                              activeBgColor: const Color(0xFFE8F5E9),
                              accentGradient: const [Color(0xFF81C784), Color(0xFF176a21)],
                            ),

                            // สถานะ 2: เต็ม (Full)
                            _buildStatusCard(
                              statusKey: 'full',
                              title: 'เต็ม / งดรับชั่วคราว',
                              subtitle: 'Full - ที่นั่งเต็ม กำลังเดินทางไปส่ง',
                              icon: Icons.people_alt_rounded,
                              activeColor: const Color(0xFF5A605B),
                              activeBgColor: const Color(0xFFECEFF1),
                              accentGradient: const [Color(0xFF90A4AE), Color(0xFF455A64)],
                            ),

                            // สถานะ 3: พัก (Break)
                            _buildStatusCard(
                              statusKey: 'break',
                              title: 'พักรอบ / จอดพักรถ',
                              subtitle: 'Break - พักประจำจุด รอออกรอบถัดไป',
                              icon: Icons.pause_circle_outline_rounded,
                              activeColor: const Color(0xFFE65100),
                              activeBgColor: const Color(0xFFFFF3E0),
                              accentGradient: const [Color(0xFFFFB74D), Color(0xFFF57C00)],
                            ),

                            // สถานะ 4: เลิกงาน (Offline / Off Duty)
                            _buildStatusCard(
                              statusKey: 'offline',
                              title: 'เลิกงาน / ไม่พร้อมให้บริการ',
                              subtitle: 'Off Duty - สิ้นสุดรอบการวิ่งประจำวัน',
                              icon: Icons.power_settings_new_rounded,
                              activeColor: const Color(0xFFC62828),
                              activeBgColor: const Color(0xFFFFEBEE),
                              accentGradient: const [Color(0xFFE57373), Color(0xFFD32F2F)],
                            ),

                            const SizedBox(height: 100), // เว้นที่ว่างด้านล่างเพื่อไม่ให้ Bottom Dock บัง
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

  // Header ดีไซน์ Curved Bottom Edge แบบเดียวกับฝั่งนักศึกษา
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF8FAF8),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.03),
          width: 1.0,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(
                'assets/images/LOGO02.png',
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      color: Color(0xFF176a21),
                      size: 26,
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
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF81C784).withValues(alpha: 0.4),
                    width: 1.0,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_rounded, color: Color(0xFF176a21), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'DRIVER',
                      style: TextStyle(
                        color: Color(0xFF176a21),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Hero Status Card แสดงข้อมูลรถและสถานะปัจจุบัน
  Widget _buildHeroStatusCard() {
    String statusTitle = 'ว่าง (พร้อมรับ)';
    Color statusColor = const Color(0xFF176a21);
    IconData statusIcon = Icons.check_circle_rounded;

    if (_currentStatus == 'full') {
      statusTitle = 'เต็ม (งดรับ)';
      statusColor = const Color(0xFF5A605B);
      statusIcon = Icons.people_alt_rounded;
    } else if (_currentStatus == 'break') {
      statusTitle = 'พักรอบรถ';
      statusColor = const Color(0xFFE65100);
      statusIcon = Icons.pause_circle_rounded;
    } else if (_currentStatus == 'offline') {
      statusTitle = 'เลิกงาน';
      statusColor = const Color(0xFFC62828);
      statusIcon = Icons.power_settings_new_rounded;
    }

    final String displayShuttle = _shuttleName ?? (_shuttleNumber != null ? 'Shuttle #$_shuttleNumber' : 'Shuttle #01');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFEAF5ED),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF81C784).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_bus_rounded, color: Color(0xFF176a21), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      displayShuttle,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF2C2F30),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'สถานะการให้บริการที่แสดงให้นักศึกษาเห็น:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF757778),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String statusKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required Color activeBgColor,
    required List<Color> accentGradient,
  }) {
    final bool isActive = _currentStatus == statusKey;

    return GestureDetector(
      onTap: () => _updateStatus(statusKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor : Colors.black.withValues(alpha: 0.05),
            width: isActive ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? activeColor.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: isActive ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        colors: accentGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive ? null : const Color(0xFFF1F5F2),
                shape: BoxShape.circle,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 24,
                color: isActive ? Colors.white : const Color(0xFF5A605B),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: isActive ? activeColor : const Color(0xFF2C2F30),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? activeColor.withValues(alpha: 0.85)
                          : const Color(0xFF757778),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
