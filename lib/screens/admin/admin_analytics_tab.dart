import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'admin_profile_dialog.dart';

class AdminAnalyticsTab extends StatelessWidget {
  const AdminAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 960;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            if (!isDesktop)
              SliverAppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF176a21)),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                title: const Text(
                  'รายงานและสถิติ',
                  style: TextStyle(
                    color: Color(0xFF176a21),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            if (isDesktop)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                  child: _buildHeader(context),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const AnalyticsTitleRow(),
                  const SizedBox(height: 24),
                  const AnalyticsTopCharts(),
                  const SizedBox(height: 24),
                  const WaitTimeTrendsChart(),
                ]),
              ),
            ),
          ],
        ),

        // แถบลอยสรุปความพร้อมของรถ (ล่างขวา)
        Positioned(
          bottom: 24,
          right: 28,
          child: StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref('shuttles').onValue,
            builder: (context, snapshot) {
              int activeCount = 0;
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                final now = DateTime.now();
                final data =
                    snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

                int count = 0;
                data.forEach((key, value) {
                  if (value is Map && value['status'] == 'online') {
                    if (value.containsKey('last_updated') &&
                        value['last_updated'] != null) {
                      final lastUpdated = DateTime.fromMillisecondsSinceEpoch(
                        (value['last_updated'] as num).toInt(),
                      );
                      if (now.difference(lastUpdated).inMinutes <= 4) {
                        count++;
                      }
                    }
                  }
                });
                activeCount = count;
              }

              int avgWaitTime = activeCount > 0 ? (25 / activeCount).ceil() : 0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFF176a21).withOpacity(0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF176a21).withOpacity(0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: activeCount > 0
                            ? const Color(0xFF176a21)
                            : const Color(0xFF757575),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'รถวิ่ง $activeCount คัน',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E2923),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 1,
                      height: 18,
                      color: const Color(0xFFEFF2F0),
                    ),
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Color(0xFF176a21),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      avgWaitTime > 0
                          ? 'รอเฉลี่ย ~$avgWaitTime นาที'
                          : 'ไม่มีรถออนไลน์',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Color(0xFF5A605B),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Color(0xFF176a21),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'รายงานและสถิติการเดินรถ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF176a21),
                ),
              ),
              Text(
                'วิเคราะห์ประสิทธิภาพ ปริมาณการใช้งาน และความหนาแน่นรายจุดจอด',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5A605B),
                ),
              ),
            ],
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const AdminProfileDialog(),
              );
            },
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF176a21),
                  width: 2,
                ),
              ),
              child: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                radius: 18,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF176a21),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnalyticsTitleRow extends StatelessWidget {
  const AnalyticsTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สถิติและประสิทธิภาพการเดินรถ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2923),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ข้อมูลเรียลไทม์เพื่อนำไปวางแผนปรับปรุงการจัดสรรรถรับส่งมหาวิทยาลัย',
              style: TextStyle(
                color: const Color(0xFF5A605B).withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.15),
            ),
          ),
          child: const Text(
            'สถิติประจำวันนี้',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF176a21),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class AnalyticsTopCharts extends StatelessWidget {
  const AnalyticsTopCharts({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 850) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildPeakUsageCard()),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: _buildEfficiencyCard()),
            ],
          );
        } else {
          return Column(
            children: [
              _buildPeakUsageCard(),
              const SizedBox(height: 20),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF176a21),
                    Color(0xFF66BB6A),
                    Color(0xFF9DF197),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '5 อันดับจุดจอดที่มีการเรียกรถสูงสุด',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'จำนวนคำขอเรียกรถสะสมรายป้ายวันนี้',
                        style: TextStyle(
                          color: Color(0xFF718076),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Live',
                      style: TextStyle(
                        color: Color(0xFF176a21),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
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
                    child: CircularProgressIndicator(
                      color: Color(0xFF176a21),
                    ),
                  );
                }

                Map<String, int> stopCounts = {};
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data =
                      snapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null && data['stop_counts'] != null) {
                    final map =
                        Map<String, dynamic>.from(data['stop_counts']);
                    map.forEach((key, value) {
                      stopCounts[key] = (value as num).toInt();
                    });
                  }
                }

                if (stopCounts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 60.0),
                      child: Text(
                        "ยังไม่มีข้อมูลการเรียกรถในวันนี้",
                        style: TextStyle(
                          color: Color(0xFF718076),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }

                var sortedEntries = stopCounts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                var topStops = sortedEntries.take(5).toList();

                int maxCount = 0;
                for (var entry in topStops) {
                  if (entry.value > maxCount) maxCount = entry.value;
                }
                if (maxCount == 0) maxCount = 1;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: topStops.map((entry) {
                      double heightFactor = entry.value / maxCount;
                      bool isPeak = entry.value == maxCount && entry.value > 0;
                      if (heightFactor == 0) heightFactor = 0.08;

                      return _buildBar(
                        heightFactor,
                        entry.key,
                        isPeak: isPeak,
                        count: entry.value,
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(
    double heightFactor,
    String label, {
    bool isPeak = false,
    int count = 0,
  }) {
    String shortLabel = label;
    if (label.contains(' ')) {
      shortLabel = label.split(' ')[0];
    } else if (label.length > 8) {
      shortLabel = '${label.substring(0, 8)}..';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isPeak ? const Color(0xFF176a21) : const Color(0xFFF2F6F3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 11,
              color: isPeak ? Colors.white : const Color(0xFF5A605B),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 38,
          height: 160 * heightFactor,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isPeak
                  ? [const Color(0xFF176a21), const Color(0xFF2E7D32)]
                  : [
                      const Color(0xFF176a21).withOpacity(0.35),
                      const Color(0xFF176a21).withOpacity(0.15),
                    ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 54,
          child: Text(
            shortLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: isPeak
                  ? const Color(0xFF176a21)
                  : const Color(0xFF718076),
              fontWeight: isPeak ? FontWeight.bold : FontWeight.w500,
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

    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF176a21),
                    Color(0xFF66BB6A),
                    Color(0xFF9DF197),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ประสิทธิภาพการเดินรถ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2923),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'อัตราความตรงต่อเวลาและการบริการวันนี้',
                    style: TextStyle(
                      color: Color(0xFF718076),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('analytics')
                        .doc('daily_stats_$dateStr')
                        .snapshots(),
                    builder: (context, snapshot) {
                      int onTime = 0;
                      int delayed = 0;
                      int cancelled = 0;

                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        if (data != null) {
                          onTime = ((data['on_time_trips'] ?? 0) as num).toInt();
                          delayed = ((data['delayed_trips'] ?? 0) as num).toInt();
                          cancelled =
                              ((data['cancelled_trips'] ?? 0) as num).toInt();
                        }
                      }

                      int total = onTime + delayed + cancelled;
                      double onTimePct = total > 0 ? (onTime / total) * 100 : 100;
                      double delayedPct = total > 0 ? (delayed / total) * 100 : 0;
                      double cancelledPct =
                          total > 0 ? (cancelled / total) * 100 : 0;
                      double indicatorValue = onTimePct / 100.0;

                      return Column(
                        children: [
                          Center(
                            child: SizedBox(
                              width: 120,
                              height: 120,
                              child: Stack(
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: indicatorValue,
                                      strokeWidth: 12,
                                      backgroundColor: const Color(0xFFF2F6F3),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF176a21),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${onTimePct.toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF1E2923),
                                          ),
                                        ),
                                        const Text(
                                          'ตรงเวลา',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF718076),
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
                          const SizedBox(height: 24),
                          _buildEfficiencyLegend(
                            'วิ่งตรงเวลา (On-time)',
                            '${onTimePct.toStringAsFixed(1)}%',
                            const Color(0xFF176a21),
                          ),
                          const SizedBox(height: 10),
                          _buildEfficiencyLegend(
                            'ล่าช้ากว่ากำหนด (Delayed)',
                            '${delayedPct.toStringAsFixed(1)}%',
                            const Color(0xFFF57C00),
                          ),
                          const SizedBox(height: 10),
                          _buildEfficiencyLegend(
                            'ยกเลิกเที่ยววิ่ง (Cancelled)',
                            '${cancelledPct.toStringAsFixed(1)}%',
                            const Color(0xFFE53935),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEfficiencyLegend(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C2F30),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: color,
          ),
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black.withOpacity(0.04)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF176a21).withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF176a21),
                            Color(0xFF66BB6A),
                            Color(0xFF9DF197),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'เปรียบเทียบปริมาณคำขอเรียกรถรายชั่วโมง',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1E2923),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'เปรียบเทียบระหว่างวันนี้และสัปดาห์ก่อนหน้า (07:00 - 19:00 น.)',
                                    style: TextStyle(
                                      color: Color(0xFF718076),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildLegendItem(
                                    'วันนี้',
                                    const Color(0xFF176a21),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildLegendItem(
                                    'สัปดาห์ก่อน',
                                    const Color(0xFFB0BEC5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 180,
                            child: CustomPaint(
                              size:
                                  const Size(double.infinity, double.infinity),
                              painter: AnalyticsLinePainter(
                                todayData,
                                lastWeekData,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: List.generate(13, (index) {
                              final hour = index + 7;
                              return Text(
                                '${hour.toString().padLeft(2, '0')}:00',
                                style: const TextStyle(
                                  color: Color(0xFF718076),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A605B),
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
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1.5
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

    // Draw last week dashed line
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

    // Draw today curve with gradient fill
    final fillPath = Path.from(path1);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF176a21).withOpacity(0.20),
          const Color(0xFF176a21).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path1, paint1);

    // Draw today data dots
    final dotBgPaint = Paint()..color = Colors.white;
    final double xStep = size.width / (todayData.length - 1);

    for (int i = 0; i < todayData.length; i++) {
      if (todayData[i] > 0 || i % 3 == 0) {
        final x = i * xStep;
        final y = size.height - ((todayData[i] / maxVal) * size.height);
        final offset = Offset(x, y);

        canvas.drawCircle(offset, 5, dotBgPaint);
        canvas.drawCircle(
          offset,
          3.5,
          Paint()
            ..color = const Color(0xFF176a21)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnalyticsLinePainter oldDelegate) => true;
}
