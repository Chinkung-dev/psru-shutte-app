import 'package:latlong2/latlong.dart';
import 'lib/route_data.dart';

void main() {
  const distanceCalc = Distance();
  Map<LatLng, List<LatLng>> _routeGraph = {};
  Set<LatLng> endpoints = {};
  for (var segment in shuttleRoutes) {
    if (segment.isNotEmpty) {
      endpoints.add(segment.first);
      endpoints.add(segment.last);
    }
  }
  List<LatLng> oneWaySegments = [
    const LatLng(16.8278942, 100.2065133),
    const LatLng(16.8286828, 100.2050371),
    const LatLng(16.8284757, 100.2060200),
    const LatLng(16.82925150, 100.20720840),
  ];
  for (var segment in shuttleRoutes) {
    bool isOneWay = false;
    if (segment.isNotEmpty) {
      if (oneWaySegments.any((element) => element.latitude == segment.first.latitude && element.longitude == segment.first.longitude)) {
        isOneWay = true;
      }
    }
    for (var point in segment) {
      _routeGraph.putIfAbsent(point, () => []);
    }
    for (int i = 0; i < segment.length - 1; i++) {
      final p1 = segment[i];
      final p2 = segment[i + 1];
      _routeGraph[p1]!.add(p2);
      if (!isOneWay) {
        _routeGraph[p2]!.add(p1);
      }
    }
  }
  List<LatLng> allNodes = _routeGraph.keys.toList();
  for (int i = 0; i < allNodes.length; i++) {
    for (int j = i + 1; j < allNodes.length; j++) {
      if (endpoints.any((e) => e.latitude == allNodes[i].latitude && e.longitude == allNodes[i].longitude) ||
          endpoints.any((e) => e.latitude == allNodes[j].latitude && e.longitude == allNodes[j].longitude)) {
        if (distanceCalc.distance(allNodes[i], allNodes[j]) <= 20.0) {
          if (!_routeGraph[allNodes[i]]!.any((e) => e.latitude == allNodes[j].latitude && e.longitude == allNodes[j].longitude)) {
            _routeGraph[allNodes[i]]!.add(allNodes[j]);
            _routeGraph[allNodes[j]]!.add(allNodes[i]);
          }
        }
      }
    }
  }
  LatLng startNode = allNodes.firstWhere((n) => distanceCalc.distance(n, const LatLng(16.8293284, 100.2073433)) < 1.0);
  LatLng endNode = allNodes.firstWhere((n) => distanceCalc.distance(n, const LatLng(16.82689590, 100.20734920)) < 1.0);
  Map<LatLng, double> distances = {};
  Map<LatLng, LatLng> previous = {};
  for (var node in _routeGraph.keys) {
    distances[node] = double.infinity;
  }
  distances[startNode] = 0.0;
  Set<LatLng> unvisited = Set.from(_routeGraph.keys);
  while (unvisited.isNotEmpty) {
    LatLng? current;
    double minDist = double.infinity;
    for (var node in unvisited) {
      if (distances[node]! < minDist) {
        minDist = distances[node]!;
        current = node;
      }
    }
    if (current == null || (current.latitude == endNode.latitude && current.longitude == endNode.longitude)) break;
    unvisited.remove(current);
    for (var neighbor in _routeGraph[current] ?? []) {
      if (!unvisited.any((e) => e.latitude == neighbor.latitude && e.longitude == neighbor.longitude)) continue;
      double alt = distances[current]! + distanceCalc.distance(current, neighbor);
      LatLng actualNeighbor = unvisited.firstWhere((e) => e.latitude == neighbor.latitude && e.longitude == neighbor.longitude);
      if (alt < distances[actualNeighbor]!) {
        distances[actualNeighbor] = alt;
        previous[actualNeighbor] = current;
      }
    }
  }
  List<LatLng> path = [];
  LatLng? curr = endNode;
  if (previous.keys.any((e) => e.latitude == curr!.latitude && e.longitude == curr!.longitude) ||
      (curr!.latitude == startNode.latitude && curr!.longitude == startNode.longitude)) {
    while (curr != null) {
      path.insert(0, curr);
      final currentRef = curr;
      try {
        curr = previous.keys.firstWhere((e) => e.latitude == currentRef.latitude && e.longitude == currentRef.longitude);
        curr = previous[curr];
      } catch (e) {
        curr = null;
      }
    }
  }
  print("Path length: ${path.length}");
}
