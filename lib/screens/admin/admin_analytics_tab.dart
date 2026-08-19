import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

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
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
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
          child: StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref('shuttles').onValue,
            builder: (context, snapshot) {
              int activeCount = 0;
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                final now = DateTime.now();
                final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                
                int count = 0;
                data.forEach((key, value) {
                  if (value is Map && value['status'] == 'online') {
                    if (value.containsKey('last_updated') && value['last_updated'] != null) {
                      final lastUpdated = DateTime.fromMillisecondsSinceEpoch((value['last_updated'] as num).toInt());
                      if (now.difference(lastUpdated).inMinutes <= 3) {
                        count++;
                      }
                    }
                  }
                });
                activeCount = count;
              }

              int avgWaitTime = activeCount > 0 ? (30 / activeCount).ceil() : 0;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: activeCount > 0 ? const Color(0xFF176a21) : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'รถกำลังวิ่ง $activeCount คัน',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 16),
                      Container(width: 1, height: 20, color: Colors.grey.shade300),
                      const SizedBox(width: 16),
                      const Icon(Icons.speed, size: 18, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        avgWaitTime > 0 ? 'รอเฉลี่ย $avgWaitTime นาที' : 'ยังไม่มีรถวิ่ง',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF176a21),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
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
              prefixIcon: Icon(
                Icons.search,
                color: Colors.grey.shade500,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          onPressed: () {},
        ),
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
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ทุกเส้นทาง',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_down, size: 16),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildTimeTab(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
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
      },
    );
  }

  Widget _buildPeakUsageCard() {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
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
                  Text(
                    'ปริมาณผู้โดยสารแยกตามจุดจอด',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '5 อันดับป้ายยอดฮิตที่มีคนเรียกรถมากที่สุดวันนี้',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Real-time',
                  style: TextStyle(
                    color: Color(0xFF176a21),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Real-time Bar Chart from Firestore
          StreamBuilder<DocumentSnapshot>(
            stream: () {
              final now = DateTime.now();
              final dateStr =
                  "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
              return FirebaseFirestore.instance
                  .collection('analytics')
                  .doc('daily_stats_$dateStr')
                  .snapshots();
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF176a21)),
                );
              }

              Map<String, int> stopCounts = {};
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data['stop_counts'] != null) {
                  final map = Map<String, dynamic>.from(data['stop_counts']);
                  map.forEach((key, value) {
                    stopCounts[key] = (value as num).toInt();
                  });
                }
              }

              if (stopCounts.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 50.0),
                    child: Text(
                      "ยังไม่มีข้อมูลการเรียกรถในวันนี้",
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }

              // Sort by count descending and take top 5
              var sortedEntries = stopCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              var topStops = sortedEntries.take(5).toList();

              int maxCount = 0;
              for (var entry in topStops) {
                if (entry.value > maxCount) maxCount = entry.value;
              }
              if (maxCount == 0) maxCount = 1;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: topStops.map((entry) {
                  double heightFactor = entry.value / maxCount;
                  bool isPeak = entry.value == maxCount && entry.value > 0;

                  if (heightFactor == 0) heightFactor = 0.05;

                  return _buildBar(
                    heightFactor,
                    entry.key,
                    isPeak: isPeak,
                    count: entry.value,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBar(
    double heightFactor,
    String label, {
    bool isPeak = false,
    int count = 0,
  }) {
    // Truncate long stop names to avoid overlapping
    String shortLabel = label;
    if (label.contains(' ')) {
      shortLabel = label.split(' ')[0]; // Take first word if it has spaces
    } else if (label.length > 10) {
      shortLabel = '${label.substring(0, 10)}...';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 12,
            color: isPeak ? const Color(0xFF176a21) : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 42,
          height: 180 * heightFactor,
          decoration: BoxDecoration(
            color: isPeak
                ? const Color(0xFF176a21)
                : const Color(0xFF9DF197).withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 60,
          child: Text(
            shortLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black54,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEfficiencyCard() {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('analytics')
          .doc('daily_stats_$dateStr')
          .snapshots(),
      builder: (context, snapshot) {
        int onTime = 0;
        int delayed = 0;
        int cancelled = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            onTime = ((data['on_time_trips'] ?? 0) as num).toInt();
            delayed = ((data['delayed_trips'] ?? 0) as num).toInt();
            cancelled = ((data['cancelled_trips'] ?? 0) as num).toInt();
          }
        }

        int total = onTime + delayed + cancelled;
        double onTimePct = 0;
        double delayedPct = 0;
        double cancelledPct = 0;
        double indicatorValue = 0;

        if (total > 0) {
          onTimePct = (onTime / total) * 100;
          delayedPct = (delayed / total) * 100;
          cancelledPct = (cancelled / total) * 100;
          indicatorValue = onTimePct / 100.0;
        }

        return Container(
          height: 380,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ประสิทธิภาพการเดินรถ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'อัตราความตรงต่อเวลาของรอบรถวันนี้',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: indicatorValue,
                          strokeWidth: 16,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF176a21),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${onTimePct.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}%',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'ตรงเวลา',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
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
              const Spacer(),
              _buildEfficiencyLegend(
                'วิ่งตรงเวลา (On-time)',
                '${onTimePct.toStringAsFixed(1)}%',
                const Color(0xFF176a21),
              ),
              const SizedBox(height: 12),
              _buildEfficiencyLegend(
                'ล่าช้ากว่ากำหนด (Delayed)',
                '${delayedPct.toStringAsFixed(1)}%',
                const Color(0xFFFFB300),
              ),
              const SizedBox(height: 12),
              _buildEfficiencyLegend(
                'ยกเลิกเที่ยววิ่ง (Cancelled)',
                '${cancelledPct.toStringAsFixed(1)}%',
                const Color(0xFFE53935),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEfficiencyLegend(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class WaitTimeTrendsChart extends StatelessWidget {
  const WaitTimeTrendsChart({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final lastWeek = now.subtract(const Duration(days: 7));
    final lastWeekStr =
        "${lastWeek.year}-${lastWeek.month.toString().padLeft(2, '0')}-${lastWeek.day.toString().padLeft(2, '0')}";

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('analytics')
          .doc('daily_stats_$lastWeekStr')
          .get(),
      builder: (context, lastWeekSnap) {
        List<int> lastWeekData = List.filled(13, 0);
        if (lastWeekSnap.hasData && lastWeekSnap.data!.exists) {
          final data = lastWeekSnap.data!.data() as Map<String, dynamic>?;
          if (data != null && data['hourly_counts'] != null) {
            final hourly = Map<String, dynamic>.from(data['hourly_counts']);
            for (int i = 0; i < 13; i++) {
              final hStr = (i + 7).toString().padLeft(2, '0');
              lastWeekData[i] = ((hourly[hStr] ?? 0) as num).toInt();
            }
          }
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('analytics')
              .doc('daily_stats_$todayStr')
              .snapshots(),
          builder: (context, todaySnap) {
            List<int> todayData = List.filled(13, 0);
            if (todaySnap.hasData && todaySnap.data!.exists) {
              final data = todaySnap.data!.data() as Map<String, dynamic>?;
              if (data != null && data['hourly_counts'] != null) {
                final hourly = Map<String, dynamic>.from(data['hourly_counts']);
                for (int i = 0; i < 13; i++) {
                  final hStr = (i + 7).toString().padLeft(2, '0');
                  todayData[i] = ((hourly[hStr] ?? 0) as num).toInt();
                }
              }
            }

            return Container(
              height: 350,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
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
                          Text(
                            'เปรียบเทียบปริมาณผู้โดยสารที่กดเรียดรถรับ-ส่ง',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'จำนวนผู้โดยสารแยกตามชั่วโมง',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            4,
                            (index) => const Divider(color: Color(0xFFEEEEEE)),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: AnalyticsLinePainter(
                            todayData,
                            lastWeekData,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(13, (index) {
                      final hour = index + 7;
                      return Text(
                        '${hour.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

class AnalyticsLinePainter extends CustomPainter {
  final List<int> todayData;
  final List<int> lastWeekData;

  AnalyticsLinePainter(this.todayData, this.lastWeekData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = const Color(0xFF176a21)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paint2 = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    int maxVal = 5;
    for (int v in todayData) {
      if (v > maxVal) maxVal = v;
    }
    for (int v in lastWeekData) {
      if (v > maxVal) maxVal = v;
    }
    maxVal = (maxVal * 1.2).ceil();

    Path createPath(List<int> data) {
      final path = Path();
      if (data.isEmpty) return path;

      final double xStep = size.width / (data.length - 1);
      for (int i = 0; i < data.length; i++) {
        final x = i * xStep;
        final y = size.height - ((data[i] / maxVal) * size.height);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          final prevX = (i - 1) * xStep;
          final prevY = size.height - ((data[i - 1] / maxVal) * size.height);
          final controlX1 = prevX + (x - prevX) / 2;
          final controlX2 = prevX + (x - prevX) / 2;
          path.cubicTo(controlX1, prevY, controlX2, y, x, y);
        }
      }
      return path;
    }

    final path1 = createPath(todayData);
    final path2 = createPath(lastWeekData);

    double dashWidth = 5, dashSpace = 5, startX = 0;
    for (PathMetric measurePath in path2.computeMetrics()) {
      while (startX < measurePath.length) {
        canvas.drawPath(
          measurePath.extractPath(startX, startX + dashWidth),
          paint2,
        );
        startX += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(path1, paint1);

    final dotBgPaint = Paint()..color = Colors.white;
    final double xStep = size.width / (todayData.length - 1);

    for (int i = 0; i < todayData.length; i++) {
      if (todayData[i] > 0 || i % 4 == 0) {
        final x = i * xStep;
        final y = size.height - ((todayData[i] / maxVal) * size.height);
        final offset = Offset(x, y);

        canvas.drawCircle(offset, 6, dotBgPaint);
        canvas.drawCircle(
          offset,
          4,
          Paint()
            ..color = const Color(0xFF176a21)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnalyticsLinePainter oldDelegate) {
    return true;
  }
}




