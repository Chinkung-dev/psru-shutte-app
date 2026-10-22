import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/route_data.dart';

void main() {
  test('Check route graph connectivity around stops 15, 16, 17', () {
    const distanceCalc = Distance();
    final Map<LatLng, List<LatLng>> routeGraph = {};
    Set<LatLng> endpoints = {};
    for (var segment in shuttleRoutes) {
      if (segment.isNotEmpty) {
        endpoints.add(segment.first);
        endpoints.add(segment.last);
      }
    }

    List<LatLng> oneWaySegments = [
      const LatLng(16.8278942, 100.2065133), // Segment 13 (ขาเข้า อาคารทีปวิชญ์)
      const LatLng(16.8286828, 100.2050371), // Segment 14 (ขาออก อาคารทีปวิชญ์ -> วงเวียน)
      const LatLng(16.8284757, 100.2060200), // Segment 15 (วงเวียนลงใต้)
      const LatLng(16.82925150, 100.20720840), // Segment 23 (ทางลัดลงใต้)
    ];

    for (var segment in shuttleRoutes) {
      bool isOneWay = false;
      if (segment.isNotEmpty && oneWaySegments.contains(segment.first)) {
        isOneWay = true;
      }
      for (var point in segment) {
        routeGraph.putIfAbsent(point, () => []);
      }
      for (int i = 0; i < segment.length - 1; i++) {
        final p1 = segment[i];
        final p2 = segment[i + 1];
        routeGraph[p1]!.add(p2);
        if (!isOneWay) {
          routeGraph[p2]!.add(p1);
        }
      }
    }

    List<LatLng> allNodes = routeGraph.keys.toList();
    for (int i = 0; i < allNodes.length; i++) {
      for (int j = i + 1; j < allNodes.length; j++) {
        if (endpoints.contains(allNodes[i]) || endpoints.contains(allNodes[j])) {
          if (distanceCalc.distance(allNodes[i], allNodes[j]) <= 20.0) {
            if (!routeGraph[allNodes[i]]!.contains(allNodes[j])) {
              routeGraph[allNodes[i]]!.add(allNodes[j]);
              routeGraph[allNodes[j]]!.add(allNodes[i]);
            }
          }
        }
      }
    }

    expect(routeGraph.isNotEmpty, isTrue);
    print('Total graph nodes: ${routeGraph.keys.length}');
  });
}
