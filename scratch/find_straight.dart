import 'dart:io';
import 'package:latlong2/latlong.dart';
import '../lib/route_data.dart';

void main() {
  const distanceCalc = Distance();
  for (int i = 0; i < shuttleRoutes.length; i++) {
    var segment = shuttleRoutes[i];
    for (int j = 0; j < segment.length - 1; j++) {
      double d = distanceCalc.distance(segment[j], segment[j+1]);
      if (d > 45.0) {
        print('Segment $i, jump $j to ${j+1}: $d meters');
        print('  ${segment[j]} -> ${segment[j+1]}');
      }
    }
  }
}
