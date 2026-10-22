import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// ติดตามเฉพาะทางแยกป้าย 4–5–6 และ 15–16–17 โดยไม่เปลี่ยนสถานะผ่านป้ายของคนขับ
class StopFiveBypass {
  final Map<int, _Branch?> _branches = {};
  final Map<int, List<LatLng>?> _cachedStops = {};
  final Map<String, Map<int, _Progress>> _vehicleProgress = {};

  /// คืนป้ายถัดไป (เช่น 6 หรือ 17 หากข้ามป้าย; 5 หรือ 16 หากแวะเข้าป้าย); null ให้ใช้ลำดับเดิม
  int? nextStopOrder({
    required Map<LatLng, List<LatLng>> graph,
    required List<Map<String, dynamic>> stops,
    required String shuttleId,
    required LatLng position,
    required int? lastPassedStop,
  }) {
    // รองรับคู่ทางแยกบายพาส: ป้าย 4->5->6 และ ป้าย 15->16->17
    if (lastPassedStop != 4 && lastPassedStop != 15) {
      _vehicleProgress.remove(shuttleId);
      return null;
    }

    final int fromOrder = lastPassedStop!;
    final int skipOrder = fromOrder + 1;
    final int toOrder = fromOrder + 2;

    final locations = <LatLng>[];
    for (final order in [fromOrder, skipOrder, toOrder]) {
      final matches = stops.where((s) => s['order'] == order).toList();
      if (matches.length != 1) return null;
      final stop = matches.single;
      if (stop['lat'] is! num || stop['lng'] is! num) return null;
      locations.add(
        LatLng(
          (stop['lat'] as num).toDouble(),
          (stop['lng'] as num).toDouble(),
        ),
      );
    }
    final cached = _cachedStops[fromOrder];
    if (cached == null ||
        !List.generate(
          3,
          (i) => cached[i] == locations[i],
        ).every((same) => same)) {
      _cachedStops[fromOrder] = locations;
      _branches[fromOrder] = _Branch.build(graph, locations);
      _vehicleProgress.forEach((_, map) => map.remove(fromOrder));
    }
    final branch = _branches[fromOrder];
    if (branch == null) return null;
    final vehicleMap = _vehicleProgress.putIfAbsent(shuttleId, () => {});
    final progress = vehicleMap.putIfAbsent(fromOrder, _Progress.new);
    if (progress.skipped) return toOrder;

    final direct = _project(position, branch.direct);
    final detour = _project(position, branch.detour);
    // รอจนพ้นแยกอย่างน้อย 25 ม. และแนวถนนชัดเจนกว่าทางเข้าป้ายสาขา
    final onBypass =
        direct.distance <= 18 &&
        direct.along >= 25 &&
        detour.distance - direct.distance >= 15;
    if (!onBypass) {
      progress.candidate = null;
      return skipOrder;
    }
    final candidate = progress.candidate;
    if (candidate == null) {
      progress.candidate = direct.along;
    } else if (direct.along >= candidate + 5) {
      // ตำแหน่งเดิม/heartbeat ซ้ำไม่นับเป็นหลักฐานการเลี้ยวครั้งที่สอง
      progress.skipped = true;
    } else if (direct.along < candidate - 5) {
      progress.candidate = direct.along;
    }
    return progress.skipped ? toOrder : skipOrder;
  }

  void reset() => _vehicleProgress.clear();

  // ล้างผลของรถที่พ้นป้ายทางแยก หรือหายไป แม้ผู้ใช้ยังไม่ได้เลือกปลายทาง
  void retainApproachingVehicles(Iterable<String> ids) {
    final approaching = ids.toSet();
    _vehicleProgress.removeWhere((id, _) => !approaching.contains(id));
  }
}

class _Progress {
  double? candidate;
  bool skipped = false;
}

class _Branch {
  final List<LatLng> direct;
  final List<LatLng> detour;
  _Branch(this.direct, this.detour);

  static _Branch? build(Map<LatLng, List<LatLng>> graph, List<LatLng> stops) {
    if (graph.isEmpty) return null;
    const distance = Distance();
    LatLng nearest(LatLng point) => graph.keys.reduce(
      (a, b) =>
          distance.distance(point, a) < distance.distance(point, b) ? a : b,
    );
    final nodes = stops.map(nearest).toList();
    // หากพิกัดป้ายไม่ตรงกับถนนพอ จะไม่เดาว่ารถข้ามป้าย
    if (List.generate(
      3,
      (i) => distance.distance(stops[i], nodes[i]),
    ).any((d) => d > 25)) {
      return null;
    }
    final direct = _shortest(graph, nodes[0], nodes[2]);
    final viaFive = _shortest(graph, nodes[0], nodes[1]);
    if (direct.length < 2 || viaFive.length < 2 || direct.contains(nodes[1])) {
      return null;
    }
    var common = 0;
    while (common < direct.length &&
        common < viaFive.length &&
        direct[common] == viaFive[common]) {
      common++;
    }
    if (common == 0 || common == direct.length || common == viaFive.length) {
      return null;
    }
    final bypass = direct.sublist(common - 1);
    final detour = viaFive.sublist(common - 1);
    if (_length(bypass) < 40 || _length(detour) < 40) return null;
    return _Branch(bypass, detour);
  }
}

List<LatLng> _shortest(
  Map<LatLng, List<LatLng>> graph,
  LatLng start,
  LatLng end,
) {
  const distance = Distance();
  final remaining = graph.keys.toSet();
  final costs = <LatLng, double>{start: 0};
  final previous = <LatLng, LatLng>{};
  while (remaining.isNotEmpty) {
    LatLng? current;
    var best = double.infinity;
    for (final node in remaining) {
      final cost = costs[node] ?? double.infinity;
      if (cost < best) {
        best = cost;
        current = node;
      }
    }
    if (current == null) return [];
    if (current == end) {
      final path = <LatLng>[end];
      while (path.last != start) {
        path.add(previous[path.last]!);
      }
      return path.reversed.toList();
    }
    remaining.remove(current);
    for (final neighbor in graph[current] ?? <LatLng>[]) {
      if (!remaining.contains(neighbor)) continue;
      final cost = best + distance.distance(current, neighbor);
      if (cost < (costs[neighbor] ?? double.infinity)) {
        costs[neighbor] = cost;
        previous[neighbor] = current;
      }
    }
  }
  return [];
}

double _length(List<LatLng> line) {
  const distance = Distance();
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += distance.distance(line[i - 1], line[i]);
  }
  return total;
}

({double distance, double along}) _project(LatLng point, List<LatLng> line) {
  const distance = Distance();
  final scale = math.cos(point.latitude * math.pi / 180);
  var best = double.infinity;
  var along = 0.0;
  var traversed = 0.0;
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1];
    final b = line[i];
    final dx = (b.longitude - a.longitude) * scale;
    final dy = b.latitude - a.latitude;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) continue;
    final t =
        (((point.longitude - a.longitude) * scale * dx +
                    (point.latitude - a.latitude) * dy) /
                lengthSquared)
            .clamp(0.0, 1.0);
    final projected = LatLng(
      a.latitude + t * dy,
      a.longitude + t * (b.longitude - a.longitude),
    );
    final lateral = distance.distance(point, projected);
    final segmentLength = distance.distance(a, b);
    if (lateral < best) {
      best = lateral;
      along = traversed + t * segmentLength;
    }
    traversed += segmentLength;
  }
  return (distance: best, along: along);
}
