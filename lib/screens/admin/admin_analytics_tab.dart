import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';

class AdminAnalyticsTab extends StatelessWidget {
  const AdminAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            if (!isDesktop)
              SliverAppBar(
                backgroundColor: Colors.white,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.menu, color: Colors.black87),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                title: const Text(
                  'ศูนย์ควบคุม',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                ),
              ),
            if (isDesktop)
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: const AnalyticsHeader(),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const AnalyticsTitleRow(),
                  const SizedBox(height: 32),
                  const AnalyticsTopCharts(),
                  const SizedBox(height: 24),
                  const WaitTimeTrendsChart(),
                  const SizedBox(height: 24),
                  const DriverPerformanceTable(),
                  const SizedBox(height: 80), // Space for floating bottom bar
                ]),
              ),
            ),
          ],
        ),

        // Bottom Floating Status
        Positioned(
          bottom: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('รถกำลังวิ่ง 14 คัน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 16),
                Container(width: 1, height: 20, color: Colors.grey.shade300),
                const SizedBox(width: 16),
                const Icon(Icons.speed, size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                const Text('รอเฉลี่ย 12 นาที', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFF176a21), shape: BoxShape.circle),
                  child: const Icon(Icons.refresh, color: Colors.white, size: 16),
                )
              ],
            ),
          ),
        )
      ],
    );
  }
}

class AnalyticsHeader extends StatelessWidget {
  const AnalyticsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'ศูนย์ควบคุม',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const Spacer(),
        Container(
          width: 300,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'ค้นหาจุดจอด, สถานี...',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.black87), onPressed: () {}),
        const SizedBox(width: 8),
        const CircleAvatar(
          backgroundColor: Color(0xFF176a21),
          radius: 18,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

class AnalyticsTitleRow extends StatelessWidget {
  const AnalyticsTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'เส้นทางและสถิติ',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            SizedBox(height: 8),
            Text(
              'การเพิ่มประสิทธิภาพการเดินรถแบบเรียลไทม์',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTimeTab('วันนี้', true),
                  _buildTimeTab('สัปดาห์', false),
                  _buildTimeTab('เดือน', false),
                ],
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.directions_bus, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    const Text('ทุกเส้นทาง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_down, size: 16),
                  ],
                ),
              )
            ]
          ],
        )
      ],
    );
  }

  Widget _buildTimeTab(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isActive ? const Color(0xFF176a21) : Colors.black54,
          fontSize: 13,
        ),
      ),
    );
  }
}

class AnalyticsTopCharts extends StatelessWidget {
  const AnalyticsTopCharts({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildPeakUsageCard()),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildEfficiencyCard()),
            ],
          );
        } else {
          return Column(
            children: [
              _buildPeakUsageCard(),
              const SizedBox(height: 24),
              _buildEfficiencyCard(),
            ],
          );
        }
      }
    );
  }

  Widget _buildPeakUsageCard() {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ช่วงเวลาเร่งด่วน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('จำนวนผู้โดยสารตามช่วงเวลา', style: TextStyle(color: Colors.black54, fontSize: 13)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('อัปเดตสด', style: TextStyle(color: Color(0xFF176a21), fontSize: 10, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const Spacer(),
          // Placeholder for Bar Chart
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(0.2, '08:00'),
              _buildBar(0.4, '09:00'),
              _buildBar(0.9, '10:00', isPeak: true),
              _buildBar(0.6, '11:00'),
              _buildBar(0.3, '12:00'),
              _buildBar(0.5, '13:00'),
              _buildBar(0.7, '14:00'),
              _buildBar(0.8, '15:00'),
              _buildBar(1.0, '16:00', isPeak: true),
              _buildBar(0.4, '17:00'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBar(double heightFactor, String label, {bool isPeak = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 32,
          height: 180 * heightFactor,
          decoration: BoxDecoration(
            color: isPeak ? const Color(0xFF176a21) : const Color(0xFF9DF197).withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 16),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEfficiencyCard() {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ประสิทธิภาพเส้นทาง', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('คะแนนประสิทธิภาพแบ่งตามสายรถ', style: TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                children: [
                  Center(
                    child: CircularProgressIndicator(
                      value: 0.92,
                      strokeWidth: 16,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF176a21)),
                    ),
                  ),
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('92%', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        Text('ประสิทธิภาพเฉลี่ย', style: TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const Spacer(),
          _buildEfficiencyLegend('สาย A (Express)', '96.4%', const Color(0xFF176a21)),
          const SizedBox(height: 12),
          _buildEfficiencyLegend('สาย B (Loop)', '88.2%', const Color(0xFF9DF197)),
          const SizedBox(height: 12),
          _buildEfficiencyLegend('สายเหนือ', '74.9%', const Color(0xFF00bcd4)),
        ],
      ),
    );
  }

  Widget _buildEfficiencyLegend(String label, String value, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class WaitTimeTrendsChart extends StatelessWidget {
  const WaitTimeTrendsChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('แนวโน้มเวลารอรถ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('เวลารอเฉลี่ยของผู้โดยสารในรอบ 24 ชั่วโมง', style: TextStyle(color: Colors.black54, fontSize: 13)),
                ],
              ),
              Row(
                children: [
                  _buildLegendItem('สัปดาห์ปัจจุบัน', const Color(0xFF176a21)),
                  const SizedBox(width: 16),
                  _buildLegendItem('สัปดาห์ก่อน', Colors.grey.shade400),
                ],
              )
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Stack(
              children: [
                // Horizontal lines (grid)
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(4, (index) => const Divider(color: Color(0xFFEEEEEE))),
                ),
                // Chart graphic placeholder
                CustomPaint(
                  size: const Size(double.infinity, double.infinity),
                  painter: MockWaitTimePainter(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('04:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('08:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('12:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('16:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('20:00', style: TextStyle(color: Colors.black54, fontSize: 11)),
              Text('23:59', style: TextStyle(color: Colors.black54, fontSize: 11)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
      ],
    );
  }
}

class MockWaitTimePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFF176a21)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
      
    final paint2 = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.8);
    path1.quadraticBezierTo(size.width * 0.15, size.height * 0.7, size.width * 0.3, size.height * 0.9);
    path1.quadraticBezierTo(size.width * 0.45, size.height * 0.2, size.width * 0.6, size.height * 0.4);
    path1.quadraticBezierTo(size.width * 0.75, size.height * 1.0, size.width * 0.85, size.height * 0.1);
    path1.quadraticBezierTo(size.width * 0.95, size.height * 0.5, size.width, size.height * 0.6);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.85);
    path2.quadraticBezierTo(size.width * 0.15, size.height * 0.8, size.width * 0.3, size.height * 0.95);
    path2.quadraticBezierTo(size.width * 0.45, size.height * 0.6, size.width * 0.6, size.height * 0.7);
    path2.quadraticBezierTo(size.width * 0.75, size.height * 0.95, size.width * 0.85, size.height * 0.5);
    path2.quadraticBezierTo(size.width * 0.95, size.height * 0.7, size.width, size.height * 0.8);
    
    // Draw dashed line for previous week
    double dashWidth = 5, dashSpace = 5, startX = 0;
    for (PathMetric measurePath in path2.computeMetrics()) {
      while (startX < measurePath.length) {
        canvas.drawPath(measurePath.extractPath(startX, startX + dashWidth), paint2);
        startX += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(path1, paint1);

    // Draw some points
    final dotPaint = Paint()..color = const Color(0xFF176a21);
    final dotBgPaint = Paint()..color = Colors.white;
    void drawDot(Offset offset) {
      canvas.drawCircle(offset, 6, dotBgPaint);
      canvas.drawCircle(offset, 4, dotPaint);
      canvas.drawCircle(offset, 4, Paint()..color = const Color(0xFF176a21)..style=PaintingStyle.stroke..strokeWidth=2);
    }
    
    // Need to get coordinates for dots (approximation for mock)
    drawDot(Offset(size.width * 0.48, size.height * 0.61));
    drawDot(Offset(size.width * 0.82, size.height * 0.36));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DriverPerformanceTable extends StatelessWidget {
  const DriverPerformanceTable({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('สรุปผลการทำงานคนขับ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download, color: Color(0xFF176a21), size: 16),
                  label: const Text('ส่งออก CSV', style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth > 800 ? constraints.maxWidth : 800,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                        child: Row(
                          children: [
                            _buildTableHeader('ชื่อคนขับ', flex: 3),
                            _buildTableHeader('สายรถหลัก', flex: 2),
                            _buildTableHeader('ตรงเวลา %', flex: 2),
                            _buildTableHeader('อุบัติเหตุ', flex: 2),
                            _buildTableHeader('สถานะ', flex: 1),
                          ],
                        ),
                      ),
                      _buildTableRow('Marcus Rivera', 'สาย A (Express)', '98.2%', '0', 'Active', 'https://i.pravatar.cc/150?img=11', true),
                      _buildTableRow('Sarah Jenkins', 'สาย B (Loop)', '94.5%', '1', 'Break', 'https://i.pravatar.cc/150?img=9', false),
                      _buildTableRow('Leo Chang', 'สายเหนือ', '99.1%', '0', 'Active', 'https://i.pravatar.cc/150?img=8', true),
                    ],
                  ),
                ),
              );
            }
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String title, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1),
      ),
    );
  }

  Widget _buildTableRow(String name, String route, String onTime, String incidents, String status, String avatar, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(radius: 16, backgroundImage: NetworkImage(avatar)),
                const SizedBox(width: 12),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(route, style: const TextStyle(color: Colors.black87, fontSize: 13))),
          Expanded(flex: 2, child: Text(onTime, style: const TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold, fontSize: 13))),
          Expanded(flex: 2, child: Text(incidents, style: const TextStyle(color: Colors.black87, fontSize: 13))),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF9DF197).withOpacity(0.3) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  status,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF176a21) : Colors.black54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
