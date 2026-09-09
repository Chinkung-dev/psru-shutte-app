// ดึงบล็อกเลือก waypoint และสร้าง graph จากหน้าจอจริงมาทดสอบนอก Firebase
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const source = readFileSync(new URL('../../lib/screens/student/student_home.dart', import.meta.url), 'utf8');
const marker = /    const distanceCalc = Distance\(\);\r?\n    List<LatLng> waypoints = \[closestBusLoc!\];/.exec(source);
if (!marker) throw new Error('ไม่พบบล็อก waypoint');
const end = source.indexOf('    _calculateHighlightedPath(waypoints);', marker.index);
const graphStart = source.indexOf('  void _buildRouteGraph()');
const graphEnd = source.indexOf('  LatLng? _getClosestNode', graphStart);
if (end < 0 || graphStart < 0 || graphEnd < 0) throw new Error('ไม่พบจุดเชื่อมการทดสอบ');
const dartSource = `
import 'package:latlong2/latlong.dart';
import '../../lib/services/stop_five_bypass.dart';
import '../../lib/route_data.dart';

class Replay {
  final _stopFiveBypass = StopFiveBypass();
  final Map<LatLng, List<LatLng>> _routeGraph = {};
  final List<Map<String, dynamic>> busStops;
  Replay(this.busStops) { _buildRouteGraph(); }
${source.slice(graphStart, graphEnd)}
  ({List<LatLng> path, int? remaining}) plan(LatLng closestBusLoc, int targetOrder) {
    String? closestBusId = 'replay-bus';
    int? closestBusLastPassed = 4;
    final stop = busStops.firstWhere((s) => s['order'] == targetOrder);
    final target = LatLng(stop['lat'], stop['lng']);
    bool isOnBoard = targetOrder != 4;
    int? remainingStops;
    void _handleAutoArrive() => throw StateError('ห้ามแจ้งถึงปลายทางจากการข้ามป้าย');
    late ({List<LatLng> path, int? remaining}) result;
    void calculate() {
${source.slice(marker.index, end)}
      result = (path: waypoints, remaining: remainingStops);
    }
    calculate();
    return result;
  }
}
void check(bool ok, String message) { if (!ok) throw StateError(message); }
void main() {
  // พิกัดสาธารณะจาก stops ที่ตรวจสอบแบบอ่านอย่างเดียววันที่ 2026-09-09
  final replay = Replay([
    {'order': 4, 'lat': 16.82722400, 'lng': 100.21595120},
    {'order': 5, 'lat': 16.82614630, 'lng': 100.21425830},
    {'order': 6, 'lat': 16.82793400, 'lng': 100.21418200},
    // ป้ายหลังจาก 6 ใช้ fixture เพื่อทดสอบว่าป้ายอื่นไม่ถูกข้าม
    {'order': 7, 'lat': 16.82822490, 'lng': 100.21394170},
  ]);
  const five = LatLng(16.82614630, 100.21425830);
  const six = LatLng(16.82793400, 100.21418200);
  const fork = LatLng(16.82674620, 100.21518880);
  const nextNode = LatLng(16.82740010, 100.21463520);
  LatLng onDirect(double t) => LatLng(fork.latitude + t * (nextNode.latitude - fork.latitude), fork.longitude + t * (nextNode.longitude - fork.longitude));
  check(replay.plan(const LatLng(16.82695680, 100.21552590), 6).path.contains(five), 'ก่อนถึงแยกต้องคงป้าย 5');
  check(replay.plan(const LatLng(16.82655000, 100.21488000), 6).path.contains(five), 'เลี้ยวเข้าศูนย์กีฬาต้องคงป้าย 5');
  check(replay.plan(onDirect(0.40), 6).path.contains(five), 'ตำแหน่งแรกยังไม่ยืนยันการข้าม');
  final afterTurn = replay.plan(onDirect(0.55), 6);
  check(!afterTurn.path.contains(five) && afterTurn.path.last == six, 'รถไปป้าย 6 แล้วห้ามบังคับย้อนกลับ 5');
  check(afterTurn.remaining == 0, 'ต้องตัดป้าย 5 ออกจากจำนวนป้ายที่เหลือ');
  check(!replay.plan(fork, 6).path.contains(five), 'GPS แกว่งหลังยืนยันแล้วต้องไม่สลับกลับ');
  check(replay.plan(onDirect(0.60), 5).path.last == five, 'ห้ามตัดปลายทางป้าย 5');
  final later = replay.plan(onDirect(0.65), 7);
  check(later.path.contains(six) && !later.path.contains(five), 'ข้ามได้เฉพาะ 5 ต้องคงป้าย 6 ก่อนไปป้ายถัดไป');
  check(!replay.plan(onDirect(0.65), 4).path.contains(five), 'คำขอป้าย 4 ต้องไม่ถูกบังคับให้วนรอบใหม่');
  print('PASS: 9 assertions using production waypoints, graph, and real stops 4/5/6');
  print('After turn: ' + afterTurn.path.toString() + ', remaining: ' + afterTurn.remaining.toString());
}
`;
const generated = new URL('./.replay.dart', import.meta.url);
writeFileSync(generated, dartSource);
try {
  const result = spawnSync(process.env.DART_EXE ?? 'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe', [
    `--packages=${fileURLToPath(new URL('../../.dart_tool/package_config.json', import.meta.url))}`,
    fileURLToPath(generated),
  ], { stdio: 'inherit' });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally { unlinkSync(generated); }
