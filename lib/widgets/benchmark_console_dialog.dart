import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/benchmark_service.dart';

/// หน้าต่างควบคุมและสรุปผลการทดสอบประสิทธิภาพอัตโนมัติ (Automated Benchmark Console)
/// รองรับการขับขี่ 10 รอบ ครอบคลุมป้าย 1 ถึง 23 และคำนวณสถิติ MAE, RMSE, Latency, Dispatch
class BenchmarkConsoleDialog extends StatefulWidget {
  final List<Map<String, dynamic>> busStops;

  const BenchmarkConsoleDialog({
    super.key,
    this.busStops = const [],
  });

  static Future<void> show(BuildContext context, {List<Map<String, dynamic>> busStops = const []}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => BenchmarkConsoleDialog(busStops: busStops),
    );
  }

  @override
  State<BenchmarkConsoleDialog> createState() => _BenchmarkConsoleDialogState();
}

class _BenchmarkConsoleDialogState extends State<BenchmarkConsoleDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BenchmarkService _bm = BenchmarkService.instance;
  int _selectedViewRound = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    int initialRound = _bm.currentRoundNumber;
    if (_bm.rounds.isNotEmpty) {
      final roundsWithData = _bm.rounds.where(
        (r) => r.mapMatchingErrors.isNotEmpty || r.etaMilestones.isNotEmpty || r.latencyValues.isNotEmpty,
      ).toList();
      if (roundsWithData.isNotEmpty) {
        initialRound = roundsWithData.last.roundNumber;
      }
    }
    _selectedViewRound = initialRound;
    _bm.addListener(_onBenchmarkUpdated);
  }

  @override
  void dispose() {
    _bm.removeListener(_onBenchmarkUpdated);
    _tabController.dispose();
    super.dispose();
  }

  void _onBenchmarkUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF176A21),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isSmall = screenSize.width < 720;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isSmall ? 14 : 20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 16,
        vertical: isSmall ? 10 : 24,
      ),
      child: Container(
        width: isSmall ? double.infinity : 850,
        height: isSmall ? screenSize.height * 0.94 : 650,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isSmall ? 14 : 20),
        ),
        child: Column(
          children: [
            // ส่วนหัว (Header)
            _buildHeader(theme, isSmall),

            // แถบควบคุมรอบและการทดสอบ (Control Bar)
            _buildControlBar(isSmall),

            // แถบแท็บ (Tab Bar)
            Container(
              color: const Color(0xFFF0F2F5),
              child: TabBar(
                controller: _tabController,
                isScrollable: isSmall,
                tabAlignment: isSmall ? TabAlignment.start : TabAlignment.fill,
                indicatorColor: const Color(0xFF176A21),
                indicatorWeight: 3,
                labelColor: const Color(0xFF176A21),
                unselectedLabelColor: Colors.black54,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmall ? 12 : 13),
                tabs: [
                  Tab(text: isSmall ? "สรุปรวม 10 รอบ" : "สรุปรวม 10 รอบ (Grand Summary)"),
                  Tab(text: isSmall ? "เปรียบเทียบรายรอบ" : "เปรียบเทียบรายรอบ 1-10 (Rounds Table)"),
                  Tab(text: isSmall ? "แจกแจงรายป้าย" : "แจกแจงรายป้าย 1-23 (Stops Breakdown)"),
                ],
              ),
            ),

            // เนื้อหาแท็บ (Tab Content)
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGrandSummaryTab(isSmall),
                  _buildRoundsTableTab(isSmall),
                  _buildStopsBreakdownTab(isSmall),
                ],
              ),
            ),

            // แถบปุ่มด้านล่าง (Footer Actions)
            _buildFooterActions(isSmall),
          ],
        ),
      ),
    );
  }

  /// ส่วนหัวของไดอะล็อก
  Widget _buildHeader(ThemeData theme, bool isSmall) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 20, vertical: isSmall ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF176A21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(isSmall ? 14 : 20)),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, color: Colors.white, size: isSmall ? 20 : 24),
          SizedBox(width: isSmall ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ระบบทดสอบและคำนวณผลการทดลองอัตโนมัติ (PSRU S² Benchmark)",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: isSmall ? 13 : 15,
                  ),
                ),
                Text(
                  "รองรับการขับทดสอบ 10 รอบ ครอบคลุมป้าย 1-23 คำนวณ MAE, RMSE และสถิติบทที่ 5",
                  style: TextStyle(color: Colors.white70, fontSize: isSmall ? 10 : 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // สถานะการบันทึก
          Container(
            padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 10, vertical: 4),
            decoration: BoxDecoration(
              color: _bm.isRecording ? Colors.greenAccent.shade700 : Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _bm.isRecording ? Icons.fiber_manual_record : Icons.pause_circle_outline,
                  color: Colors.white,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  isSmall
                      ? (_bm.isRecording ? "บันทึก" : "หยุด")
                      : (_bm.isRecording ? "กำลังบันทึกสด" : "หยุดบันทึก"),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SizedBox(width: isSmall ? 4 : 10),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: isSmall ? 20 : 24,
            onPressed: () => Navigator.of(context).pop(),
            tooltip: "ปิด",
          ),
        ],
      ),
    );
  }

  /// แถบควบคุมรอบและการเปิด-ปิดการบันทึก
  Widget _buildControlBar(bool isSmall) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: isSmall ? 8 : 10),
      color: const Color(0xFFEFF1F2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // แสดงหมายเลขรอบปัจจุบัน
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF176A21),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "รอบที่ ${_bm.currentRoundNumber} / ${_bm.maxRounds}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),

              // ปุ่ม เริ่ม / หยุด
              ElevatedButton.icon(
                onPressed: () {
                  if (_bm.isRecording) {
                    _bm.stopRecording();
                  } else {
                    _bm.startRecording();
                  }
                },
                icon: Icon(_bm.isRecording ? Icons.pause : Icons.play_arrow, size: 16),
                label: Text(
                  _bm.isRecording
                      ? "หยุดชั่วคราว"
                      : (isSmall ? "เริ่มรอบ ${_bm.currentRoundNumber}" : "เริ่มบันทึกรอบที่ ${_bm.currentRoundNumber}"),
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bm.isRecording ? Colors.orange.shade800 : const Color(0xFF176A21),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),

              // ปุ่มจบรอบเพื่อขึ้นรอบถัดไป
              OutlinedButton.icon(
                onPressed: _bm.currentRoundNumber < _bm.maxRounds
                    ? () {
                        _bm.completeCurrentRound();
                        setState(() {
                          _selectedViewRound = _bm.currentRoundNumber;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("จบรอบที่ ${_bm.currentRoundNumber - 1} เริ่มต้นรอบที่ ${_bm.currentRoundNumber}"),
                            backgroundColor: const Color(0xFF176A21),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(
                  _bm.currentRoundNumber < _bm.maxRounds
                      ? (isSmall ? "ขึ้นรอบใหม่" : "จบรอบแล้วขึ้นรอบใหม่")
                      : "ครบทดสอบ 10 รอบแล้ว",
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF176A21),
                  side: const BorderSide(color: Color(0xFF176A21)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),

              // ปุ่มจำลองข้อมูลครบ 1 รอบ (สำหรับทดสอบในร่ม / เบราว์เซอร์)
              ElevatedButton.icon(
                onPressed: () {
                  _bm.simulateCompleteRoundData(busStops: widget.busStops);
                  setState(() {
                    _selectedViewRound = _bm.currentRoundNumber;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("จำลองข้อมูลการทดสอบรอบที่ ${_bm.currentRoundNumber} ครบถ้วนแล้ว"),
                      backgroundColor: const Color(0xFF176A21),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_mode_outlined, size: 16),
                label: Text(
                  isSmall ? "จำลองข้อมูล" : "จำลองข้อมูลรอบนี้",
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),

          // สวิตช์จำลองคำขอเรียกรถอัตโนมัติ
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSmall ? "จำลองอัตโนมัติ: " : "จำลองคำขอป้าย 1-23 อัตโนมัติ: ",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _bm.autoSimulateDispatch,
                  activeThumbColor: const Color(0xFF176A21),
                  onChanged: (val) {
                    setState(() {
                      _bm.autoSimulateDispatch = val;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// แท็บ 1: สรุปรวม 10 รอบ สำหรับนำไปใส่ตารางที่ 2 ในบทความ
  Widget _buildGrandSummaryTab(bool isSmall) {
    final card1 = _buildMetricCard(
      title: "1. Map Matching (ดึงพิกัดเข้าถนน)",
      subTitle: "ทดสอบ ${_bm.totalMapMatchingSamples} พิกัด",
      metrics: [
        {"label": "MAE (คลาดเคลื่อนเฉลี่ย)", "value": "${_bm.grandMapMatchingMAE.toStringAsFixed(2)} ม."},
        {"label": "RMSE (ผลกระทบ Outlier)", "value": "${_bm.grandMapMatchingRMSE.toStringAsFixed(2)} ม."},
      ],
      highlightColor: Colors.blue.shade700,
    );

    final card2 = _buildMetricCard(
      title: "2. เวลาถึงโดยประมาณจริง (Real-World ETA)",
      subTitle: "วัดผล 2 ช่วง: เวลารถมารับ และ เวลาเดินทางบนรถถึงจุดหมาย",
      metrics: [
        {
          "label": "ช่วง 1 รถกำลังมารับ (Pick-up MAE)",
          "value": "${_bm.grandPickUpMAE.toStringAsFixed(2)} วิ (${_bm.totalPickUpSamples} คำขอ)"
        },
        {
          "label": "ช่วง 1 Pick-up RMSE",
          "value": "${_bm.grandPickUpRMSE.toStringAsFixed(2)} วิ"
        },
        {
          "label": "ช่วง 2 นั่งรถถึงจุดหมาย (Dest MAE)",
          "value": "${_bm.grandDestinationMAE.toStringAsFixed(2)} วิ (${_bm.totalDestinationSamples} เที่ยว)"
        },
        {
          "label": "ช่วง 2 Destination RMSE",
          "value": "${_bm.grandDestinationRMSE.toStringAsFixed(2)} วิ"
        },
        {
          "label": "รวมการเดินทางจริง (Overall MAE)",
          "value": "${_bm.grandOverallRealEtaMAE.toStringAsFixed(2)} วิ (${_bm.totalRealEtaSamples} ตัวอย่าง)"
        },
        {
          "label": "รวมการเดินทางจริง (Overall RMSE)",
          "value": "${_bm.grandOverallRealEtaRMSE.toStringAsFixed(2)} วิ"
        },
      ],
      highlightColor: Colors.teal.shade700,
    );

    final card3 = _buildMetricCard(
      title: "3. ความหน่วงสตรีมมิง (Latency)",
      subTitle: "Firebase RTDB สตรีมมิง",
      metrics: [
        {"label": "ค่าเฉลี่ย (Mean)", "value": "${_bm.grandMeanLatency.toStringAsFixed(1)} ms"},
        {"label": "มัธยฐาน (Median)", "value": "${_bm.grandMedianLatency.toStringAsFixed(1)} ms"},
      ],
      highlightColor: Colors.deepPurple.shade700,
    );

    final card4 = _buildMetricCard(
      title: "4. การตอบสนองเรียกรถ (Dispatch & TTS)",
      subTitle: "คำขอจนเริ่มขานเสียง ป้าย 1-23",
      metrics: [
        {"label": "เวลาตอบสนองเฉลี่ย (Mean)", "value": "${_bm.grandMeanDispatchTime.toStringAsFixed(2)} วิ"},
        {"label": "ส่วนเบี่ยงเบนมาตรฐาน (S.D.)", "value": "${_bm.grandSdDispatchTime.toStringAsFixed(2)} วิ"},
      ],
      highlightColor: Colors.orange.shade800,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(isSmall ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                isSmall ? "ตารางสรุปผลการทดลองรวม" : "ตารางสรุปผลการทดลองรวม (Grand Pooled Statistics)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isSmall ? 13 : 15,
                  color: const Color(0xFF176A21),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _copyToClipboard(_bm.generateTable2SummaryText(), "คัดลอกตารางที่ 2 ลงคลิปบอร์ดแล้ว");
                },
                icon: const Icon(Icons.copy, size: 14),
                label: Text(
                  isSmall ? "คัดลอกตารางที่ 2" : "คัดลอกข้อความตารางที่ 2 (สำหรับ Word)",
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF176A21),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ตารางการ์ด 4 มิติ แบบ responsive
          if (isSmall) ...[
            card1,
            const SizedBox(height: 10),
            card2,
            const SizedBox(height: 10),
            card3,
            const SizedBox(height: 10),
            card4,
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: card1),
                const SizedBox(width: 12),
                Expanded(child: card2),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: card3),
                const SizedBox(width: 12),
                Expanded(child: card4),
              ],
            ),
          ],

          const SizedBox(height: 16),
          // กล่องพรีวิวข้อความตารางสำหรับบทความ
          const Text("พรีวิวข้อความตารางที่ 2 ในบทความวิจัย:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(
              _bm.generateTable2SummaryText(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// การ์ดแสดงผลสถิติแต่ละมิติ
  Widget _buildMetricCard({
    required String title,
    required String subTitle,
    required List<Map<String, String>> metrics,
    required Color highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: highlightColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: highlightColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subTitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const Divider(height: 14),
          ...metrics.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      m["label"]!,
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    m["value"]!,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// แท็บ 2: ตารางเปรียบเทียบผลลัพธ์รายรอบ (Rounds 1–10)
  Widget _buildRoundsTableTab(bool isSmall) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isSmall ? 10 : 16, 12, isSmall ? 10 : 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                isSmall ? "เปรียบเทียบรายรอบ 1-10:" : "ข้อมูลเปรียบเทียบรายรอบการขับขี่ (รอบที่ 1 ถึง 10):",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmall ? 12 : 13),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _copyToClipboard(_bm.exportRoundsSummaryCSV(), "คัดลอก CSV สรุปรายรอบแล้ว");
                },
                icon: const Icon(Icons.download, size: 14),
                label: const Text("คัดลอกไฟล์ CSV รายรอบ", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF176A21),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFEFF1F2)),
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text("รอบ")),
                  DataColumn(label: Text("จำนวน GPS")),
                  DataColumn(label: Text("GPS MAE (ม.)")),
                  DataColumn(label: Text("GPS RMSE (ม.)")),
                  DataColumn(label: Text("Pick-up MAE (วิ)")),
                  DataColumn(label: Text("Pick-up RMSE (วิ)")),
                  DataColumn(label: Text("Dest MAE (วิ)")),
                  DataColumn(label: Text("Dest RMSE (วิ)")),
                  DataColumn(label: Text("รวมจริง MAE (วิ)")),
                  DataColumn(label: Text("รวมจริง RMSE (วิ)")),
                  DataColumn(label: Text("Latency เฉลี่ย")),
                  DataColumn(label: Text("Dispatch เฉลี่ย")),
                ],
                rows: [
                  ..._bm.rounds.map((r) {
                    final isCurrent = r.roundNumber == _bm.currentRoundNumber;
                    return DataRow(
                      color: WidgetStateProperty.all(isCurrent ? Colors.green.shade50 : null),
                      cells: [
                        DataCell(Text("รอบที่ ${r.roundNumber} ${isCurrent ? '(กำลังรัน)' : ''}", style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text("${r.mapMatchingErrors.length}")),
                        DataCell(Text(r.mapMatchingMAE.toStringAsFixed(2))),
                        DataCell(Text(r.mapMatchingRMSE.toStringAsFixed(2))),
                        DataCell(Text(r.studentRequestErrors.isEmpty ? "-" : r.pickUpMAE.toStringAsFixed(2))),
                        DataCell(Text(r.studentRequestErrors.isEmpty ? "-" : r.pickUpRMSE.toStringAsFixed(2))),
                        DataCell(Text(r.destinationErrors.isEmpty ? "-" : r.destinationMAE.toStringAsFixed(2))),
                        DataCell(Text(r.destinationErrors.isEmpty ? "-" : r.destinationRMSE.toStringAsFixed(2))),
                        DataCell(Text(r.allRealEtaErrors.isEmpty ? "-" : r.overallRealEtaMAE.toStringAsFixed(2))),
                        DataCell(Text(r.allRealEtaErrors.isEmpty ? "-" : r.overallRealEtaRMSE.toStringAsFixed(2))),
                        DataCell(Text("${r.meanLatency.toStringAsFixed(1)} ms")),
                        DataCell(Text("${r.meanDispatchTime.toStringAsFixed(2)} วิ")),
                      ],
                    );
                  }),
                  // แถว Grand Total
                  if (_bm.rounds.isNotEmpty)
                    DataRow(
                      color: WidgetStateProperty.all(const Color(0xFFD4EEDB)),
                      cells: [
                        const DataCell(Text("รวมเฉลี่ย 10 รอบ", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF176A21)))),
                        DataCell(Text("${_bm.totalMapMatchingSamples}", style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandMapMatchingMAE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandMapMatchingRMSE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandPickUpMAE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandPickUpRMSE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandDestinationMAE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandDestinationRMSE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandOverallRealEtaMAE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_bm.grandOverallRealEtaRMSE.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text("${_bm.grandMeanLatency.toStringAsFixed(1)} ms", style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text("${_bm.grandMeanDispatchTime.toStringAsFixed(2)} วิ", style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// แท็บ 3: แจกแจงผลลัพธ์รายป้าย 1 ถึง 23
  Widget _buildStopsBreakdownTab(bool isSmall) {
    // เลือกรอบที่จะดู
    final availableRounds = _bm.rounds.map((r) => r.roundNumber).toList();
    if (availableRounds.isEmpty) availableRounds.add(1);

    final roundData = _bm.rounds.firstWhere(
      (r) => r.roundNumber == _selectedViewRound,
      orElse: () => _bm.currentRound,
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isSmall ? 10 : 16, 12, isSmall ? 10 : 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("เลือกรอบ: ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  DropdownButton<int>(
                    value: _selectedViewRound,
                    isDense: true,
                    items: availableRounds.map((rn) {
                      final rData = _bm.rounds.firstWhere((r) => r.roundNumber == rn, orElse: () => _bm.currentRound);
                      final hasData = rData.mapMatchingErrors.isNotEmpty || rData.etaMilestones.isNotEmpty;
                      final isCurrent = rn == _bm.currentRoundNumber;
                      String statusText = "";
                      if (isCurrent && _bm.isRecording) {
                        statusText = " (กำลังบันทึก)";
                      } else if (hasData) {
                        statusText = " (มีข้อมูล)";
                      } else {
                        statusText = " (รอเริ่ม)";
                      }
                      return DropdownMenuItem<int>(
                        value: rn,
                        child: Text("รอบที่ $rn$statusText", style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedViewRound = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _copyToClipboard(_bm.exportStopsDetailCSV(), "คัดลอก CSV ละเอียดป้าย 1-23 แล้ว");
                },
                icon: const Icon(Icons.file_copy_outlined, size: 14),
                label: Text(
                  isSmall ? "คัดลอก CSV ป้าย 1-23" : "คัดลอก CSV ละเอียดป้าย 1-23",
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF176A21),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: 6),
            itemCount: 23,
            itemBuilder: (context, index) {
              final stopOrder = index + 1;
              // ค้นหาข้อมูลป้ายนี้ในรอบที่เลือก
              final dispatch = roundData.dispatchRecords.where((d) => d.stopOrder == stopOrder).toList();

              String stopName = "ป้ายที่ $stopOrder";
              if (widget.busStops.isNotEmpty) {
                final match = widget.busStops.firstWhere(
                  (s) => ((s['order'] ?? 0) as num).toInt() == stopOrder,
                  orElse: () => {},
                );
                if (match.containsKey('name')) {
                  stopName = match['name'].toString();
                }
              }

              final studentReq = roundData.studentRideRequests.where((req) => req.stopOrder == stopOrder && req.errorSeconds != null).firstOrNull;
              final pendingStudentReq = roundData.studentRideRequests.where((req) => req.stopOrder == stopOrder && req.errorSeconds == null).firstOrNull;
              final destTrip = roundData.destinationTrips.where((d) => d.destinationStopOrder == stopOrder && d.errorSeconds != null).firstOrNull;
              final pendingDestTrip = roundData.destinationTrips.where((d) => d.destinationStopOrder == stopOrder && d.errorSeconds == null).firstOrNull;
              final isSkipped = roundData.skippedStops.contains(stopOrder);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: isSmall
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: isSkipped ? Colors.amber.shade700 : const Color(0xFF176A21),
                                  child: Text(
                                    "$stopOrder",
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    stopName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSkipped)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.shade400, width: 0.5),
                                    ),
                                    child: const Text("ข้ามป้าย (Bypass)", style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            const Divider(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _buildStopStatItem(
                                  "ช่วง 1 Pick-up ETA",
                                  isSkipped
                                      ? "ข้ามป้าย"
                                      : (studentReq != null
                                          ? "${studentReq.errorSeconds!.toStringAsFixed(1)} วิ (คลาดเคลื่อน)"
                                          : (pendingStudentReq != null ? "รอรถเข้าป้าย" : "ไม่มีคำขอ")),
                                ),
                                _buildStopStatItem(
                                  "ช่วง 2 Dest ETA",
                                  isSkipped
                                      ? "ข้ามป้าย"
                                      : (destTrip != null
                                          ? "${destTrip.errorSeconds!.toStringAsFixed(1)} วิ (คลาดเคลื่อน)"
                                          : (pendingDestTrip != null ? "กำลังเดินทาง" : "ไม่มีเที่ยวลง")),
                                ),
                                _buildStopStatItem(
                                  "Dispatch TTS",
                                  isSkipped
                                      ? "ข้ามป้าย"
                                      : (dispatch.isNotEmpty ? "${dispatch.first.responseTimeSeconds.toStringAsFixed(2)} วิ" : "รอทดสอบ"),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isSkipped ? Colors.amber.shade700 : const Color(0xFF176A21),
                              child: Text(
                                "$stopOrder",
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      stopName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSkipped)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber.shade400, width: 0.5),
                                      ),
                                      child: const Text("ข้ามป้าย (Bypass)", style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("ช่วง 1: รถกำลังมารับ (Pick-up ETA)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    isSkipped
                                        ? "ข้ามป้าย"
                                        : (studentReq != null
                                            ? "Error ${studentReq.errorSeconds!.toStringAsFixed(1)} วิ (บอก ${studentReq.initialPredictedEtaSeconds.round()}วิ / รอจริง ${studentReq.actualWaitSeconds?.round() ?? 0}วิ)"
                                            : (pendingStudentReq != null ? "มีคำขอแล้ว (รอรถแล่นเข้าเทียบป้าย)" : "ไม่มีคำขอเรียกรถ")),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSkipped
                                          ? Colors.amber.shade800
                                          : (studentReq != null
                                              ? Colors.teal.shade800
                                              : (pendingStudentReq != null ? Colors.blue.shade700 : Colors.black38)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("ช่วง 2: เดินทางถึงจุดหมาย (Dest ETA)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    isSkipped
                                        ? "ข้ามป้าย"
                                        : (destTrip != null
                                            ? "Error ${destTrip.errorSeconds!.toStringAsFixed(1)} วิ (บอก ${destTrip.initialPredictedDestinationEtaSeconds.round()}วิ / วิ่งจริง ${destTrip.actualTravelSeconds?.round() ?? 0}วิ)"
                                            : (pendingDestTrip != null ? "กำลังเดินทางบนรถ (มุ่งหน้ามายังป้ายนี้)" : "ไม่มีผู้โดยสารลง")),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSkipped
                                          ? Colors.amber.shade800
                                          : (destTrip != null
                                              ? Colors.purple.shade800
                                              : (pendingDestTrip != null ? Colors.deepOrange.shade700 : Colors.black38)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Dispatch TTS:", style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    dispatch.isNotEmpty ? "${dispatch.first.responseTimeSeconds.toStringAsFixed(2)} วิ" : "รอทดสอบ",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: dispatch.isNotEmpty ? Colors.blue.shade800 : Colors.black38,
                                    ),
                                  ),
                                ],
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

  Widget _buildStopStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF176A21)),
        ),
      ],
    );
  }

  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ยืนยันการล้างข้อมูลทั้งหมด"),
        content: const Text("คุณต้องการล้างข้อมูลการทดสอบทั้ง 10 รอบหรือไม่? ข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () {
              _bm.resetAll();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("ล้างข้อมูล", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// แถบปุ่มด้านล่าง
  Widget _buildFooterActions(bool isSmall) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: isSmall ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(isSmall ? 14 : 20)),
      ),
      child: isSmall
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final csv = _bm.exportStudentRequestsCSV();
                          _copyToClipboard(csv, "คัดลอก CSV ช่วงที่ 1 (Pick-up ETA) แล้ว");
                        },
                        icon: const Icon(Icons.person_pin_circle_outlined, size: 13, color: Color(0xFF176A21)),
                        label: const Text("CSV รถรับ", style: TextStyle(color: Color(0xFF176A21), fontSize: 10)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final csv = _bm.exportDestinationTripsCSV();
                          _copyToClipboard(csv, "คัดลอก CSV ช่วงที่ 2 (Destination ETA) แล้ว");
                        },
                        icon: const Icon(Icons.directions_bus_filled_outlined, size: 13, color: Color(0xFF176A21)),
                        label: const Text("CSV จุดหมาย", style: TextStyle(color: Color(0xFF176A21), fontSize: 10)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF176A21),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("ปิด", style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _showResetConfirmDialog,
                  icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 16),
                  label: const Text("ล้างข้อมูลทั้งหมด", style: TextStyle(color: Colors.red, fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                TextButton.icon(
                  onPressed: _showResetConfirmDialog,
                  icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 18),
                  label: const Text("ล้างข้อมูลทั้งหมด", style: TextStyle(color: Colors.red)),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    final csv = _bm.exportStudentRequestsCSV();
                    _copyToClipboard(csv, "คัดลอก CSV ช่วงที่ 1 (Pick-up ETA) แล้ว");
                  },
                  icon: const Icon(Icons.person_pin_circle_outlined, size: 16, color: Color(0xFF176A21)),
                  label: const Text("CSV รถรับ (Pick-up)", style: TextStyle(color: Color(0xFF176A21))),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final csv = _bm.exportDestinationTripsCSV();
                    _copyToClipboard(csv, "คัดลอก CSV ช่วงที่ 2 (Destination ETA) แล้ว");
                  },
                  icon: const Icon(Icons.directions_bus_filled_outlined, size: 16, color: Color(0xFF176A21)),
                  label: const Text("CSV ปลายทาง (Dest)", style: TextStyle(color: Color(0xFF176A21))),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176A21),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("เสร็จสิ้น / ปิดหน้าต่าง"),
                ),
              ],
            ),
    );
  }
}
