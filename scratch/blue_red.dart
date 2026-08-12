import 'dart:io';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../lib/route_data.dart';

void main() {
  var features = [];
  for (int i = 0; i < shuttleRoutes.length; i++) {
    var coords = shuttleRoutes[i].map((ll) => [ll.longitude, ll.latitude]).toList();
    features.add({
      "type": "Feature",
      "properties": {"segment": i},
      "geometry": {
        "type": "LineString",
        "coordinates": coords
      }
    });
  }
  var fc = {"type": "FeatureCollection", "features": features};
  File('scratch/map.geojson').writeAsStringSync(jsonEncode(fc));
  print("Wrote scratch/map.geojson");
}
