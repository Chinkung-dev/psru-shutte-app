import 'dart:io';
import 'package:latlong2/latlong.dart';
import '../lib/route_data.dart';

void main() {
  final Map<LatLng, List<LatLng>> _routeGraph = {};
  List<LatLng> endpoints = [];
  const distanceCalc = Distance();

  for (var segment in shuttleRoutes) {
    if (segment.isNotEmpty) {
      endpoints.add(segment.first);
      endpoints.add(segment.last);
    }
  }

  for (var segment in shuttleRoutes) {
    for (int i = 0; i < segment.length - 1; i++) {
      final p1 = segment[i];
      final p2 = segment[i + 1];
      _routeGraph.putIfAbsent(p1, () => []).add(p2);
      _routeGraph.putIfAbsent(p2, () => []).add(p1);
    }
  }

  List<LatLng> allNodes = _routeGraph.keys.toList();
  for (int i = 0; i < allNodes.length; i++) {
    for (int j = i + 1; j < allNodes.length; j++) {
      if (endpoints.contains(allNodes[i]) || endpoints.contains(allNodes[j])) {
        if (distanceCalc.distance(allNodes[i], allNodes[j]) <= 45.0) {
          if (!_routeGraph[allNodes[i]]!.contains(allNodes[j])) {
            _routeGraph[allNodes[i]]!.add(allNodes[j]);
            _routeGraph[allNodes[j]]!.add(allNodes[i]);
          }
        }
      }
    }
  }

  // Find connected components
  Set<LatLng> visited = {};
  List<List<LatLng>> components = [];

  for (var node in allNodes) {
    if (!visited.contains(node)) {
      List<LatLng> component = [];
      List<LatLng> queue = [node];
      visited.add(node);
      
      while (queue.isNotEmpty) {
        var curr = queue.removeAt(0);
        component.add(curr);
        for (var neighbor in _routeGraph[curr] ?? []) {
          if (!visited.contains(neighbor)) {
            visited.add(neighbor);
            queue.add(neighbor);
          }
        }
      }
      components.add(component);
    }
  }

  print('Total Nodes: ${allNodes.length}');
  print('Total Connected Components: ${components.length}');
  for (int i = 0; i < components.length; i++) {
    print('Component $i: ${components[i].length} nodes');
  }

  if (components.length > 1) {
    print('\nFinding closest points between components...');
    for (int i = 0; i < components.length; i++) {
      for (int j = i + 1; j < components.length; j++) {
        double minD = double.infinity;
        LatLng? best1;
        LatLng? best2;
        for (var n1 in components[i]) {
          for (var n2 in components[j]) {
            double d = distanceCalc.distance(n1, n2);
            if (d < minD) {
              minD = d;
              best1 = n1;
              best2 = n2;
            }
          }
        }
        print('Closest between Comp $i and Comp $j is $minD meters.');
        print('  Nodes: $best1  and  $best2');
      }
    }
  }
}
