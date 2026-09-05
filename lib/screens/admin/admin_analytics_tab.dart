import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'admin_profile_dialog.dart';
import '../../widgets/app_loading_view.dart';

// ประเภทช่วงเวลาสำหรับดูสถิติ
enum AnalyticsPeriod { today, week, month }

// ข้อมูลรวมสำหรับแสดงผลในหน้าสถิติ
class AnalyticsDataBundle {
  final Map<String, int> stopCounts;
  final int onTimeTrips;
  final int delayedTrips;
  final int cancelledTrips;
  final List<int> currentData;
  final List<int> previousData;
  final List<String> labels;
  final String periodBadgeText;
  final String peakSubtitle;
  final String efficiencySubtitle;
  final String trendTitle;
  final String trendSubtitle;
  final String currentLegend;
  final String previousLegend;
  final String hoverPrefix;

  // ข้อมูลสถิติเวลารอและเวลาเดินทาง
  final num totalWaitSeconds;
  final int boardedCount;
  final num totalTripSeconds;
  final int completedTripsCount;

  AnalyticsDataBundle({
    required this.stopCounts,
    required this.onTimeTrips,
    required this.delayedTrips,
    required this.cancelledTrips,
    required this.currentData,
    required this.previousData,
    required this.labels,
    required this.periodBadgeText,
    required this.peakSubtitle,
    required this.efficiencySubtitle,
    required this.trendTitle,
    required this.trendSubtitle,
    required this.currentLegend,
    required this.previousLegend,
    required this.hoverPrefix,
    this.totalWaitSeconds = 0,
    this.boardedCount = 0,
    this.totalTripSeconds = 0,
    this.completedTripsCount = 0,
  });

  // เวลารอรถเฉลี่ย (วินาที)
  double get avgWaitSeconds {
    if (boardedCount > 0 && totalWaitSeconds > 0) {
      return totalWaitSeconds / boardedCount;
    }
    return 0.0;
  }

  // ข้อความแสดงเวลารอรถเฉลี่ย
  String get avgWaitTimeFormatted {
    final sec = avgWaitSeconds.round();
    if (sec <= 0) return 'ยังไม่มีข้อมูล';
    final mins = sec ~/ 60;
    final remSec = sec % 60;
    if (mins > 0 && remSec > 0) {
      return '$mins นาที $remSec วินาที';
    } else if (mins > 0) {
      return '$mins นาที';
    } else {
      return '$sec วินาที';
    }
  }

  // เวลาเดินทางถึงจุดหมายเฉลี่ย (วินาที)
  double get avgTripSeconds {
    if (completedTripsCount > 0 && totalTripSeconds > 0) {
      return totalTripSeconds / completedTripsCount;
    }
    return 0.0;
  }

  // ข้อความแสดงเวลาเดินทางเฉลี่ย
  String get avgTripTimeFormatted {
    final sec = avgTripSeconds.round();
    if (sec <= 0) return 'ยังไม่มีข้อมูล';
    final mins = sec ~/ 60;
    final remSec = sec % 60;
    if (mins > 0 && remSec > 0) {
      return '$mins นาที $remSec วินาที';
    } else if (mins > 0) {
      return '$mins นาที';
    } else {
      return '$sec วินาที';
    }
  }

  factory AnalyticsDataBundle.empty(AnalyticsPeriod period) {
    String badge = 'Live';
    String peakSub = 'จำนวนคำขอเรียกรถสะสมรายป้ายวันนี้';
    String effSub = 'อัตราความตรงต่อเวลาและการบริการวันนี้';
    String trendT = 'เปรียบเทียบปริมาณคำขอเรียกรถรายชั่วโมง';
    String trendSub = 'เปรียบเทียบระหว่างวันนี้และสัปดาห์ก่อนหน้า (07:00 - 19:00 น.)';
    String curLeg = 'วันนี้';
    String prevLeg = 'สัปดาห์ก่อน';
    String hPrefix = 'เวลา';
    List<String> lbls = List.generate(13, (i) => '${(i + 7).toString().padLeft(2, '0')}:00');

    if (period == AnalyticsPeriod.week) {
      badge = '7 วัน';
      peakSub = 'จำนวนคำขอเรียกรถสะสมรายป้ายสัปดาห์นี้';
      effSub = 'อัตราความตรงต่อเวลาและการบริการสัปดาห์นี้';
      trendT = 'เปรียบเทียบปริมาณคำขอเรียกรถรายวัน';
      trendSub = 'เปรียบเทียบระหว่างสัปดาห์นี้และสัปดาห์ก่อนหน้า (จันทร์ - อาทิตย์)';
      curLeg = 'สัปดาห์นี้';
      prevLeg = 'สัปดาห์ก่อน';
      hPrefix = 'วัน';
      lbls = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสฯ', 'ศุกร์', 'เสาร์', 'อาทิตย์'];
    } else if (period == AnalyticsPeriod.month) {
      badge = 'รายเดือน';
      peakSub = 'จำนวนคำขอเรียกรถสะสมรายป้ายเดือนนี้';
      effSub = 'อัตราความตรงต่อเวลาและการบริการเดือนนี้';
      trendT = 'เปรียบเทียบปริมาณคำขอเรียกรถรายสัปดาห์';
      trendSub = 'เปรียบเทียบระหว่างเดือนนี้และเดือนก่อนหน้า (รายสัปดาห์)';
      curLeg = 'เดือนนี้';
      prevLeg = 'เดือนก่อน';
      hPrefix = '';
      lbls = ['สัปดาห์ 1', 'สัปดาห์ 2', 'สัปดาห์ 3', 'สัปดาห์ 4'];
    }

    return AnalyticsDataBundle(
      stopCounts: {},
      onTimeTrips: 0,
      delayedTrips: 0,
      cancelledTrips: 0,
      currentData: List.filled(lbls.length, 0),
      previousData: List.filled(lbls.length, 0),
      labels: lbls,
      periodBadgeText: badge,
      peakSubtitle: peakSub,
      efficiencySubtitle: effSub,
      trendTitle: trendT,
      trendSubtitle: trendSub,
      currentLegend: curLeg,
      previousLegend: prevLeg,
      hoverPrefix: hPrefix,
      totalWaitSeconds: 0,
      boardedCount: 0,
      totalTripSeconds: 0,
      completedTripsCount: 0,
    );
  }
}

class AdminAnalyticsTab extends StatefulWidget {
  const AdminAnalyticsTab({super.key});

  @override
  State<AdminAnalyticsTab> createState() => _AdminAnalyticsTabState();
}

class _AdminAnalyticsTabState extends State<AdminAnalyticsTab> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.today;
  Future<AnalyticsDataBundle>? _aggregatedFuture;
  AnalyticsPeriod? _cachedPeriod;

  // จัดรูปแบบรหัสเอกสารตามวันที่ YYYY-MM-DD
  String _formatDocId(DateTime d) {
    final yearStr = d.year.toString();
    final monthStr = d.month.toString().padLeft(2, '0');
    final dayStr = d.day.toString().padLeft(2, '0');
    return 'daily_stats_$yearStr-$monthStr-$dayStr';
  }

  // ดึงข้อมูลสำหรับสัปดาห์หรือเดือนพร้อมการแคชชั่วคราว
  Future<AnalyticsDataBundle> _getAggregatedData(AnalyticsPeriod period) {
    if (_cachedPeriod == period && _aggregatedFuture != null) {
      return _aggregatedFuture!;
    }
    _cachedPeriod = period;
    _aggregatedFuture = _fetchAggregatedData(period);
    return _aggregatedFuture!;
  }

  // ฟังก์ชันคำนวณและดึงข้อมูลสถิติย้อนหลังจาก Firestore
  Future<AnalyticsDataBundle> _fetchAggregatedData(AnalyticsPeriod period) async {
    final now = DateTime.now();

    if (period == AnalyticsPeriod.week) {
      try {
        final currentMonday = DateTime(now.year, now.month, now.day).subtract(
          Duration(days: now.weekday - 1),
        );
        final currentSunday = currentMonday.add(const Duration(days: 6));
        final prevMonday = currentMonday.subtract(const Duration(days: 7));
        final prevSunday = currentMonday.subtract(const Duration(days: 1));

        final currentSnap = await FirebaseFirestore.instance
            .collection('analytics')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: _formatDocId(currentMonday))
            .where(FieldPath.documentId, isLessThanOrEqualTo: _formatDocId(currentSunday))
            .get();

        final prevSnap = await FirebaseFirestore.instance
            .collection('analytics')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: _formatDocId(prevMonday))
            .where(FieldPath.documentId, isLessThanOrEqualTo: _formatDocId(prevSunday))
            .get();

        Map<String, Map<String, dynamic>> currentDocsMap = {};
        for (var doc in currentSnap.docs) {
          if (doc.exists) {
            currentDocsMap[doc.id] = doc.data();
          }
        }

        Map<String, Map<String, dynamic>> prevDocsMap = {};
        for (var doc in prevSnap.docs) {
          if (doc.exists) {
            prevDocsMap[doc.id] = doc.data();
          }
        }

        List<int> currentData = List.filled(7, 0);
        List<int> prevData = List.filled(7, 0);
        Map<String, int> stopCounts = {};
        int onTime = 0;
        int delayed = 0;
        int cancelled = 0;
        num totalWaitSec = 0;
        int boardedCount = 0;
        num totalTripSec = 0;
        int completedTrips = 0;

        for (int i = 0; i < 7; i++) {
          final date = currentMonday.add(Duration(days: i));
          final docId = _formatDocId(date);
          final data = currentDocsMap[docId];

          if (data != null) {
            int requests = ((data['total_requests'] ?? data['total_passengers'] ?? 0) as num).toInt();
            if (requests == 0 && data['hourly_counts'] != null) {
              final hourly = Map<String, dynamic>.from(data['hourly_counts']);
              for (var val in hourly.values) {
                requests += ((val ?? 0) as num).toInt();
              }
            }
            currentData[i] = requests;

            if (data['stop_counts'] != null) {
              final map = Map<String, dynamic>.from(data['stop_counts']);
              map.forEach((k, v) {
                stopCounts[k] = (stopCounts[k] ?? 0) + ((v as num).toInt());
              });
            }

            onTime += ((data['on_time_trips'] ?? 0) as num).toInt();
            delayed += ((data['delayed_trips'] ?? 0) as num).toInt();
            cancelled += ((data['cancelled_trips'] ?? 0) as num).toInt();

            totalWaitSec += (data['total_wait_seconds'] ?? 0) as num;
            boardedCount += ((data['boarded_count'] ?? data['acknowledged_requests_count'] ?? 0) as num).toInt();
            totalTripSec += (data['total_trip_seconds'] ?? 0) as num;
            completedTrips += ((data['completed_trips_count'] ?? 0) as num).toInt();
          }
        }

        for (int i = 0; i < 7; i++) {
          final date = prevMonday.add(Duration(days: i));
          final docId = _formatDocId(date);
          final data = prevDocsMap[docId];

          if (data != null) {
            int requests = ((data['total_requests'] ?? data['total_passengers'] ?? 0) as num).toInt();
            if (requests == 0 && data['hourly_counts'] != null) {
              final hourly = Map<String, dynamic>.from(data['hourly_counts']);
              for (var val in hourly.values) {
                requests += ((val ?? 0) as num).toInt();
              }
            }
            prevData[i] = requests;
          }
        }

        return AnalyticsDataBundle(
          stopCounts: stopCounts,
          onTimeTrips: onTime,
          delayedTrips: delayed,
          cancelledTrips: cancelled,
          currentData: currentData,
          previousData: prevData,
          labels: const ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสฯ', 'ศุกร์', 'เสาร์', 'อาทิตย์'],
          periodBadgeText: '7 วัน',
          peakSubtitle: 'จำนวนคำขอเรียกรถสะสมรายป้ายสัปดาห์นี้',
          efficiencySubtitle: 'อัตราความตรงต่อเวลาและการบริการสัปดาห์นี้',
          trendTitle: 'เปรียบเทียบปริมาณคำขอเรียกรถรายวัน',
          trendSubtitle: 'เปรียบเทียบระหว่างสัปดาห์นี้และสัปดาห์ก่อนหน้า (จันทร์ - อาทิตย์)',
          currentLegend: 'สัปดาห์นี้',
          previousLegend: 'สัปดาห์ก่อน',
          hoverPrefix: 'วัน',
          totalWaitSeconds: totalWaitSec,
          boardedCount: boardedCount,
          totalTripSeconds: totalTripSec,
          completedTripsCount: completedTrips,
        );
      } catch (e) {
        debugPrint('Error fetching week analytics: $e');
        return AnalyticsDataBundle.empty(AnalyticsPeriod.week);
      }
    } else {
      // สำหรับรายเดือน
      try {
        final firstDayCurrentMonth = DateTime(now.year, now.month, 1);
        final lastDayCurrentMonth = DateTime(now.year, now.month + 1, 0);

        final firstDayPrevMonth = DateTime(now.year, now.month - 1, 1);
        final lastDayPrevMonth = DateTime(now.year, now.month, 0);

        final currentSnap = await FirebaseFirestore.instance
            .collection('analytics')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: _formatDocId(firstDayCurrentMonth))
            .where(FieldPath.documentId, isLessThanOrEqualTo: _formatDocId(lastDayCurrentMonth))
            .get();

        final prevSnap = await FirebaseFirestore.instance
            .collection('analytics')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: _formatDocId(firstDayPrevMonth))
            .where(FieldPath.documentId, isLessThanOrEqualTo: _formatDocId(lastDayPrevMonth))
            .get();

        List<int> currentData = List.filled(4, 0);
        List<int> prevData = List.filled(4, 0);
        Map<String, int> stopCounts = {};
        int onTime = 0;
        int delayed = 0;
        int cancelled = 0;
        num totalWaitSec = 0;
        int boardedCount = 0;
        num totalTripSec = 0;
        int completedTrips = 0;

        for (var doc in currentSnap.docs) {
          if (doc.exists) {
            final data = doc.data();
            final parts = doc.id.split('_');
            int day = 1;
            if (parts.length >= 3) {
              final dateParts = parts[2].split('-');
              if (dateParts.length == 3) {
                day = int.tryParse(dateParts[2]) ?? 1;
              }
            }

            int bucket = 0;
            if (day <= 7) {
              bucket = 0;
            } else if (day <= 14) {
              bucket = 1;
            } else if (day <= 21) {
              bucket = 2;
            } else {
              bucket = 3;
            }

            int requests = ((data['total_requests'] ?? data['total_passengers'] ?? 0) as num).toInt();
            if (requests == 0 && data['hourly_counts'] != null) {
              final hourly = Map<String, dynamic>.from(data['hourly_counts']);
              for (var val in hourly.values) {
                requests += ((val ?? 0) as num).toInt();
              }
            }
            currentData[bucket] += requests;

            if (data['stop_counts'] != null) {
              final map = Map<String, dynamic>.from(data['stop_counts']);
              map.forEach((k, v) {
                stopCounts[k] = (stopCounts[k] ?? 0) + ((v as num).toInt());
              });
            }

            onTime += ((data['on_time_trips'] ?? 0) as num).toInt();
            delayed += ((data['delayed_trips'] ?? 0) as num).toInt();
            cancelled += ((data['cancelled_trips'] ?? 0) as num).toInt();

            totalWaitSec += (data['total_wait_seconds'] ?? 0) as num;
            boardedCount += ((data['boarded_count'] ?? data['acknowledged_requests_count'] ?? 0) as num).toInt();
            totalTripSec += (data['total_trip_seconds'] ?? 0) as num;
            completedTrips += ((data['completed_trips_count'] ?? 0) as num).toInt();
          }
        }

        for (var doc in prevSnap.docs) {
          if (doc.exists) {
            final data = doc.data();
            final parts = doc.id.split('_');
            int day = 1;
            if (parts.length >= 3) {
              final dateParts = parts[2].split('-');
              if (dateParts.length == 3) {
                day = int.tryParse(dateParts[2]) ?? 1;
              }
            }

            int bucket = 0;
            if (day <= 7) {
              bucket = 0;
            } else if (day <= 14) {
              bucket = 1;
            } else if (day <= 21) {
              bucket = 2;
            } else {
              bucket = 3;
            }

            int requests = ((data['total_requests'] ?? data['total_passengers'] ?? 0) as num).toInt();
            if (requests == 0 && data['hourly_counts'] != null) {
              final hourly = Map<String, dynamic>.from(data['hourly_counts']);
              for (var val in hourly.values) {
                requests += ((val ?? 0) as num).toInt();
              }
            }
            prevData[bucket] += requests;
          }
        }

        return AnalyticsDataBundle(
          stopCounts: stopCounts,
          onTimeTrips: onTime,
          delayedTrips: delayed,
          cancelledTrips: cancelled,
          currentData: currentData,
          previousData: prevData,
          labels: const ['สัปดาห์ 1', 'สัปดาห์ 2', 'สัปดาห์ 3', 'สัปดาห์ 4'],
          periodBadgeText: 'รายเดือน',
          peakSubtitle: 'จำนวนคำขอเรียกรถสะสมรายป้ายเดือนนี้',
          efficiencySubtitle: 'อัตราความตรงต่อเวลาและการบริการเดือนนี้',
          trendTitle: 'เปรียบเทียบปริมาณคำขอเรียกรถรายสัปดาห์',
          trendSubtitle: 'เปรียบเทียบระหว่างเดือนนี้และเดือนก่อนหน้า (รายสัปดาห์)',
          currentLegend: 'เดือนนี้',
          previousLegend: 'เดือนก่อน',
          hoverPrefix: '',
          totalWaitSeconds: totalWaitSec,
          boardedCount: boardedCount,
          totalTripSeconds: totalTripSec,
          completedTripsCount: completedTrips,
        );
      } catch (e) {
        debugPrint('Error fetching month analytics: $e');
        return AnalyticsDataBundle.empty(AnalyticsPeriod.month);
      }
    }
  }

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
                  AnalyticsTitleRow(
                    selectedPeriod: _selectedPeriod,
                    onPeriodChanged: (period) {
                      if (_selectedPeriod != period) {
                        setState(() {
                          _selectedPeriod = period;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildContentBody(),
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

  // ตัวสร้างเนื้อหาชาร์ตตามช่วงเวลาที่เลือก
  Widget _buildContentBody() {
    if (_selectedPeriod == AnalyticsPeriod.today) {
      final now = DateTime.now();
      final todayStr = _formatDocId(now);
      final lastWeek = now.subtract(const Duration(days: 7));
      final lastWeekStr = _formatDocId(lastWeek);

      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('analytics')
            .doc(lastWeekStr)
            .get(),
        builder: (context, lastWeekSnap) {
          if (lastWeekSnap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60.0),
              child: AppLoadingView(
                message: 'กำลังโหลดข้อมูลสถิติประจำวัน...',
              ),
            );
          }
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
                .doc(todayStr)
                .snapshots(),
            builder: (context, todaySnap) {
              Map<String, int> stopCounts = {};
              int onTime = 0;
              int delayed = 0;
              int cancelled = 0;
              num totalWaitSec = 0;
              int boardedCount = 0;
              num totalTripSec = 0;
              int completedTrips = 0;
              List<int> todayData = List.filled(13, 0);

              if (todaySnap.hasData && todaySnap.data!.exists) {
                final data = todaySnap.data!.data() as Map<String, dynamic>?;
                if (data != null) {
                  if (data['stop_counts'] != null) {
                    final map = Map<String, dynamic>.from(data['stop_counts']);
                    map.forEach((key, value) {
                      stopCounts[key] = (value as num).toInt();
                    });
                  }

                  onTime = ((data['on_time_trips'] ?? 0) as num).toInt();
                  delayed = ((data['delayed_trips'] ?? 0) as num).toInt();
                  cancelled = ((data['cancelled_trips'] ?? 0) as num).toInt();
                  totalWaitSec = (data['total_wait_seconds'] ?? 0) as num;
                  boardedCount = ((data['boarded_count'] ?? data['acknowledged_requests_count'] ?? 0) as num).toInt();
                  totalTripSec = (data['total_trip_seconds'] ?? 0) as num;
                  completedTrips = ((data['completed_trips_count'] ?? 0) as num).toInt();

                  if (data['hourly_counts'] != null) {
                    final hourly = Map<String, dynamic>.from(data['hourly_counts']);
                    for (int i = 0; i < 13; i++) {
                      final hStr = (i + 7).toString().padLeft(2, '0');
                      todayData[i] = ((hourly[hStr] ?? 0) as num).toInt();
                    }
                  }
                }
              }

              final bundle = AnalyticsDataBundle(
                stopCounts: stopCounts,
                onTimeTrips: onTime,
                delayedTrips: delayed,
                cancelledTrips: cancelled,
                currentData: todayData,
                previousData: lastWeekData,
                labels: List.generate(
                  13,
                  (i) => '${(i + 7).toString().padLeft(2, '0')}:00',
                ),
                periodBadgeText: 'Live',
                peakSubtitle: 'จำนวนคำขอเรียกรถสะสมรายป้ายวันนี้',
                efficiencySubtitle: 'อัตราความตรงต่อเวลาและการบริการวันนี้',
                trendTitle: 'เปรียบเทียบปริมาณคำขอเรียกรถรายชั่วโมง',
                trendSubtitle: 'เปรียบเทียบระหว่างวันนี้และสัปดาห์ก่อนหน้า (07:00 - 19:00 น.)',
                currentLegend: 'วันนี้',
                previousLegend: 'สัปดาห์ก่อน',
                hoverPrefix: 'เวลา',
                totalWaitSeconds: totalWaitSec,
                boardedCount: boardedCount,
                totalTripSeconds: totalTripSec,
                completedTripsCount: completedTrips,
              );

              return Column(
                children: [
                  AnalyticsTimeMetricsRow(data: bundle, period: _selectedPeriod),
                  const SizedBox(height: 20),
                  AnalyticsTopCharts(data: bundle, period: _selectedPeriod),
                  const SizedBox(height: 24),
                  WaitTimeTrendsChart(data: bundle, period: _selectedPeriod),
                ],
              );
            },
          );
        },
      );
    } else {
      // สำหรับสัปดาห์และเดือน
      return FutureBuilder<AnalyticsDataBundle>(
        future: _getAggregatedData(_selectedPeriod),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60.0),
              child: AppLoadingView(
                message: 'กำลังประมวลผลข้อมูลสถิติ...',
              ),
            );
          }

          final bundle = snapshot.data ?? AnalyticsDataBundle.empty(_selectedPeriod);

          return Column(
            children: [
              AnalyticsTimeMetricsRow(data: bundle, period: _selectedPeriod),
              const SizedBox(height: 20),
              AnalyticsTopCharts(data: bundle, period: _selectedPeriod),
              const SizedBox(height: 24),
              WaitTimeTrendsChart(data: bundle, period: _selectedPeriod),
            ],
          );
        },
      );
    }
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

// แถวหัวข้อพร้อมตัวเลือกช่วงเวลา วันนี้ / สัปดาห์ / เดือน
class AnalyticsTitleRow extends StatelessWidget {
  final AnalyticsPeriod selectedPeriod;
  final ValueChanged<AnalyticsPeriod> onPeriodChanged;

  const AnalyticsTitleRow({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    String subtitleText = 'ข้อมูลเรียลไทม์เพื่อนำไปวางแผนปรับปรุงการจัดสรรรถรับส่งมหาวิทยาลัย';
    if (selectedPeriod == AnalyticsPeriod.week) {
      subtitleText = 'ข้อมูลสถิติสะสมรอบสัปดาห์ เพื่อวิเคราะห์แนวโน้มการเดินทางรายวัน';
    } else if (selectedPeriod == AnalyticsPeriod.month) {
      subtitleText = 'ข้อมูลสถิติสะสมรอบเดือน เพื่อประเมินและวางแผนการบริการระยะยาว';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 650;

        final titleColumn = Column(
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
              subtitleText,
              style: TextStyle(
                color: const Color(0xFF5A605B).withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ],
        );

        final selector = Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF176a21).withOpacity(0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPeriodPill(
                label: 'วันนี้',
                period: AnalyticsPeriod.today,
              ),
              const SizedBox(width: 4),
              _buildPeriodPill(
                label: 'สัปดาห์',
                period: AnalyticsPeriod.week,
              ),
              const SizedBox(width: 4),
              _buildPeriodPill(
                label: 'เดือน',
                period: AnalyticsPeriod.month,
              ),
            ],
          ),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleColumn,
              const SizedBox(height: 16),
              selector,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleColumn),
            const SizedBox(width: 16),
            selector,
          ],
        );
      },
    );
  }

  Widget _buildPeriodPill({
    required String label,
    required AnalyticsPeriod period,
  }) {
    final bool isSelected = selectedPeriod == period;

    return InkWell(
      onTap: () => onPeriodChanged(period),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF176a21) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF176a21).withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF5A605B),
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

// การ์ดสรุปเวลารอรถเฉลี่ย และเวลาเดินทางเฉลี่ย
class AnalyticsTimeMetricsRow extends StatelessWidget {
  final AnalyticsDataBundle data;
  final AnalyticsPeriod period;

  const AnalyticsTimeMetricsRow({
    super.key,
    required this.data,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    String periodLabel = 'วันนี้';
    if (period == AnalyticsPeriod.week) {
      periodLabel = 'สัปดาห์นี้';
    } else if (period == AnalyticsPeriod.month) {
      periodLabel = 'เดือนนี้';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 750) {
          return Row(
            children: [
              Expanded(
                child: _buildTimeMetricCard(
                  title: 'เวลารอรถเฉลี่ย',
                  badgeText: 'เฉลี่ย$periodLabel',
                  valueText: data.avgWaitTimeFormatted,
                  subText: data.boardedCount > 0
                      ? 'คำนวณจากการเรียกรถ ${data.boardedCount} ครั้ง (จากกดเรียกจนถึงขึ้นรถ)'
                      : 'คำนวณจากเวลานักศึกษากดเรียกรถจนถึงขึ้นรถ',
                  icon: Icons.hourglass_top_rounded,
                  iconBgColor: const Color(0xFFE8F5E9),
                  iconColor: const Color(0xFF176a21),
                  hasData: data.avgWaitSeconds > 0,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildTimeMetricCard(
                  title: 'เวลาเดินทางถึงจุดหมายเฉลี่ย',
                  badgeText: 'เฉลี่ย$periodLabel',
                  valueText: data.avgTripTimeFormatted,
                  subText: data.completedTripsCount > 0
                      ? 'คำนวณจากการเดินทางสำเร็จ ${data.completedTripsCount} ครั้ง'
                      : 'คำนวณจากเวลานักศึกษาขึ้นรถจนถึงจุดหมาย',
                  icon: Icons.departure_board_rounded,
                  iconBgColor: const Color(0xFFE0F2F1),
                  iconColor: const Color(0xFF00796B),
                  hasData: data.avgTripSeconds > 0,
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildTimeMetricCard(
                title: 'เวลารอรถเฉลี่ย',
                badgeText: 'เฉลี่ย$periodLabel',
                valueText: data.avgWaitTimeFormatted,
                subText: data.boardedCount > 0
                    ? 'คำนวณจากการเรียกรถ ${data.boardedCount} ครั้ง (จากกดเรียกจนถึงขึ้นรถ)'
                    : 'คำนวณจากเวลานักศึกษากดเรียกรถจนถึงขึ้นรถ',
                icon: Icons.hourglass_top_rounded,
                iconBgColor: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF176a21),
                hasData: data.avgWaitSeconds > 0,
              ),
              const SizedBox(height: 16),
              _buildTimeMetricCard(
                title: 'เวลาเดินทางถึงจุดหมายเฉลี่ย',
                badgeText: 'เฉลี่ย$periodLabel',
                valueText: data.avgTripTimeFormatted,
                subText: data.completedTripsCount > 0
                    ? 'คำนวณจากการเดินทางสำเร็จ ${data.completedTripsCount} ครั้ง'
                    : 'คำนวณจากเวลานักศึกษาขึ้นรถจนถึงจุดหมาย',
                icon: Icons.departure_board_rounded,
                iconBgColor: const Color(0xFFE0F2F1),
                iconColor: const Color(0xFF00796B),
                hasData: data.avgTripSeconds > 0,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildTimeMetricCard({
    required String title,
    required String badgeText,
    required String valueText,
    required String subText,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required bool hasData,
  }) {
    return Container(
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: iconBgColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, color: iconColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E2923),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4F1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.12),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF176a21),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    valueText,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: hasData
                          ? const Color(0xFF176a21)
                          : const Color(0xFF718076),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF718076),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ชาร์ตด้านบน 2 คอลัมน์ (5 อันดับจุดจอด และ ประสิทธิภาพการเดินรถ)
class AnalyticsTopCharts extends StatelessWidget {
  final AnalyticsDataBundle data;
  final AnalyticsPeriod period;

  const AnalyticsTopCharts({
    super.key,
    required this.data,
    required this.period,
  });

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
    final stopCounts = data.stopCounts;

    Widget chartContent;
    if (stopCounts.isEmpty) {
      String emptyText = 'ยังไม่มีข้อมูลการเรียกรถในวันนี้';
      if (period == AnalyticsPeriod.week) {
        emptyText = 'ยังไม่มีข้อมูลการเรียกรถในสัปดาห์นี้';
      } else if (period == AnalyticsPeriod.month) {
        emptyText = 'ยังไม่มีข้อมูลการเรียกรถในเดือนนี้';
      }

      chartContent = Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 60.0),
          child: Text(
            emptyText,
            style: const TextStyle(
              color: Color(0xFF718076),
              fontSize: 13,
            ),
          ),
        ),
      );
    } else {
      var sortedEntries = stopCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      var topStops = sortedEntries.take(5).toList();

      int maxCount = 0;
      for (var entry in topStops) {
        if (entry.value > maxCount) maxCount = entry.value;
      }
      if (maxCount == 0) maxCount = 1;

      chartContent = Padding(
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
    }

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '5 อันดับจุดจอดที่มีการเรียกรถสูงสุด',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.peakSubtitle,
                        style: const TextStyle(
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
                    child: Text(
                      data.periodBadgeText,
                      style: const TextStyle(
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
            chartContent,
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

    return Tooltip(
      message: '$label\nคำขอเรียกรถ: $count ครั้ง',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2923),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      waitDuration: Duration.zero,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isPeak ? const Color(0xFF176a21) : const Color(0xFFF2F6F3),
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
        ),
      ),
    );
  }

  Widget _buildEfficiencyCard() {
    int onTime = data.onTimeTrips;
    int delayed = data.delayedTrips;
    int cancelled = data.cancelledTrips;

    int total = onTime + delayed + cancelled;
    double onTimePct = total > 0 ? (onTime / total) * 100 : 100;
    double delayedPct = total > 0 ? (delayed / total) * 100 : 0;
    double cancelledPct = total > 0 ? (cancelled / total) * 100 : 0;
    double indicatorValue = onTimePct / 100.0;

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
                  Text(
                    data.efficiencySubtitle,
                    style: const TextStyle(
                      color: Color(0xFF718076),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF176a21),
                              ),
                            ),
                          ),
                          Center(
                            child: Tooltip(
                              message:
                                  'วิ่งตรงเวลา $onTime จากทั้งหมด $total เที่ยววิ่ง',
                              waitDuration: Duration.zero,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2923),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                    count: onTime,
                  ),
                  const SizedBox(height: 10),
                  _buildEfficiencyLegend(
                    'ล่าช้ากว่ากำหนด (Delayed)',
                    '${delayedPct.toStringAsFixed(1)}%',
                    const Color(0xFFF57C00),
                    count: delayed,
                  ),
                  const SizedBox(height: 10),
                  _buildEfficiencyLegend(
                    'ยกเลิกเที่ยววิ่ง (Cancelled)',
                    '${cancelledPct.toStringAsFixed(1)}%',
                    const Color(0xFFE53935),
                    count: cancelled,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEfficiencyLegend(
    String label,
    String value,
    Color color, {
    int? count,
  }) {
    final row = Row(
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

    if (count != null) {
      return Tooltip(
        message: '$label: $count เที่ยววิ่ง ($value)',
        waitDuration: Duration.zero,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2923),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: row,
        ),
      );
    }
    return row;
  }
}

// กราฟแนวโน้มและเปรียบเทียบสถิติการเรียกรถ
class WaitTimeTrendsChart extends StatefulWidget {
  final AnalyticsDataBundle data;
  final AnalyticsPeriod period;

  const WaitTimeTrendsChart({
    super.key,
    required this.data,
    required this.period,
  });

  @override
  State<WaitTimeTrendsChart> createState() => _WaitTimeTrendsChartState();
}

class _WaitTimeTrendsChartState extends State<WaitTimeTrendsChart> {
  int? _hoveredIndex;
  Offset? _hoveredOffset;

  @override
  Widget build(BuildContext context) {
    final currentData = widget.data.currentData;
    final previousData = widget.data.previousData;
    final labels = widget.data.labels;
    final int pointsCount = currentData.length;

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.data.trendTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E2923),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.data.trendSubtitle,
                            style: const TextStyle(
                              color: Color(0xFF718076),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildLegendItem(
                            widget.data.currentLegend,
                            const Color(0xFF176a21),
                          ),
                          const SizedBox(width: 14),
                          _buildLegendItem(
                            widget.data.previousLegend,
                            const Color(0xFFB0BEC5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onHover: (event) {
                          if (pointsCount <= 1) return;
                          final width = constraints.maxWidth;
                          final dx = event.localPosition.dx.clamp(0.0, width);
                          final double step = width / (pointsCount - 1);
                          final int index = (dx / step).round().clamp(0, pointsCount - 1);

                          final double x = width * (index / (pointsCount - 1));

                          int maxVal = 5;
                          for (int v in currentData) {
                            if (v > maxVal) maxVal = v;
                          }
                          for (int v in previousData) {
                            if (v > maxVal) maxVal = v;
                          }
                          maxVal = (maxVal * 1.2).ceil();

                          final double normY = currentData[index] / maxVal;
                          final double y = 180.0 - (180.0 * normY);

                          if (mounted) {
                            setState(() {
                              _hoveredIndex = index;
                              _hoveredOffset = Offset(x, y);
                            });
                          }
                        },
                        onExit: (_) {
                          if (mounted) {
                            setState(() {
                              _hoveredIndex = null;
                              _hoveredOffset = null;
                            });
                          }
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: CustomPaint(
                                size: const Size(
                                  double.infinity,
                                  double.infinity,
                                ),
                                painter: AnalyticsLinePainter(
                                  currentData,
                                  previousData,
                                  hoveredIndex: _hoveredIndex,
                                ),
                              ),
                            ),
                            if (_hoveredIndex != null &&
                                _hoveredOffset != null &&
                                _hoveredIndex! < labels.length)
                              Positioned(
                                left: (_hoveredOffset!.dx - 75).clamp(
                                  8.0,
                                  constraints.maxWidth - 170.0,
                                ),
                                top: (_hoveredOffset!.dy - 95).clamp(
                                  0.0,
                                  85.0,
                                ),
                                child: IgnorePointer(
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                      milliseconds: 100,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E2923),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 14,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.period == AnalyticsPeriod.today
                                              ? 'เวลา ${labels[_hoveredIndex!]} น.'
                                              : (widget.period == AnalyticsPeriod.week
                                                  ? 'วัน${labels[_hoveredIndex!]}'
                                                  : labels[_hoveredIndex!]),
                                          style: const TextStyle(
                                            color: Color(0xFF9DF197),
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF176a21),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${widget.data.currentLegend}: ${currentData[_hoveredIndex!]} ครั้ง',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFB0BEC5),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${widget.data.previousLegend}: ${previousData[_hoveredIndex!]} ครั้ง',
                                              style: const TextStyle(
                                                color: Color(0xFFCFD8DC),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(labels.length, (index) {
                      final bool isHovered = _hoveredIndex == index;
                      return Text(
                        labels[index],
                        style: TextStyle(
                          color: isHovered
                              ? const Color(0xFF176a21)
                              : const Color(0xFF718076),
                          fontSize: isHovered ? 11 : 10.5,
                          fontWeight: isHovered
                              ? FontWeight.bold
                              : FontWeight.w500,
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

// ผู้วาดกราฟเส้นเปรียบเทียบ
class AnalyticsLinePainter extends CustomPainter {
  final List<int> todayData;
  final List<int> lastWeekData;
  final int? hoveredIndex;

  AnalyticsLinePainter(
    this.todayData,
    this.lastWeekData, {
    this.hoveredIndex,
  });

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

    // วาดเส้นประสำหรับข้อมูลช่วงเวลาก่อนหน้า
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

    // วาดพื้นที่แรเงาใต้เส้นกราฟของช่วงเวลาปัจจุบัน
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

    final double xStep = size.width / (todayData.length - 1);

    // วาดเส้นไกด์ไลน์แนวดิ่งเมื่อมีการ Hover
    if (hoveredIndex != null &&
        hoveredIndex! >= 0 &&
        hoveredIndex! < todayData.length) {
      final hX = hoveredIndex! * xStep;
      final guidePaint = Paint()
        ..color = const Color(0xFF176a21).withOpacity(0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(hX, 0),
        Offset(hX, size.height),
        guidePaint,
      );
    }

    // วาดจุดข้อมูลบนเส้นกราฟของช่วงเวลาปัจจุบัน
    final dotBgPaint = Paint()..color = Colors.white;

    for (int i = 0; i < todayData.length; i++) {
      final bool isHovered = (i == hoveredIndex);
      if (todayData[i] > 0 || isHovered || todayData.length <= 7 || i % 3 == 0) {
        final x = i * xStep;
        final y = size.height - ((todayData[i] / maxVal) * size.height);
        final offset = Offset(x, y);

        if (isHovered) {
          final glowPaint = Paint()
            ..color = const Color(0xFF176a21).withOpacity(0.22)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(offset, 11.0, glowPaint);
          canvas.drawCircle(offset, 6.0, dotBgPaint);
          canvas.drawCircle(
            offset,
            4.0,
            Paint()
              ..color = const Color(0xFF176a21)
              ..style = PaintingStyle.fill,
          );
        } else {
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

    // วาดจุดเน้นของช่วงเวลาก่อนหน้าเมื่อมีการ Hover
    if (hoveredIndex != null &&
        hoveredIndex! >= 0 &&
        hoveredIndex! < lastWeekData.length) {
      final x = hoveredIndex! * xStep;
      final yLast =
          size.height - ((lastWeekData[hoveredIndex!] / maxVal) * size.height);
      final offsetLast = Offset(x, yLast);

      canvas.drawCircle(offsetLast, 5.0, dotBgPaint);
      canvas.drawCircle(
        offsetLast,
        3.0,
        Paint()
          ..color = const Color(0xFFB0BEC5)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnalyticsLinePainter oldDelegate) =>
      oldDelegate.todayData != todayData ||
      oldDelegate.lastWeekData != lastWeekData ||
      oldDelegate.hoveredIndex != hoveredIndex;
}
