import 'dart:io';
import 'dart:math';

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  var p = 0.017453292519943295;
  var c = cos;
  var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a)) * 1000;
}

void main() {
  var routeDataLines = File('lib/route_data.dart').readAsLinesSync();
  List<LatLng> routePoints = [];
  for (var line in routeDataLines) {
    if (line.contains("const LatLng(")) {
      var parts = line.split("const LatLng(")[1].split(")")[0].split(",");
      routePoints.add(LatLng(double.parse(parts[0].trim()), double.parse(parts[1].trim())));
    }
  }

  var migrationPage = File('lib/migration_page.dart').readAsLinesSync();
  
  String? name;
  double? lat;
  double? lng;
  
  for (var line in migrationPage) {
    if (line.contains("'name':")) {
      name = line.split("'")[3];
    }
    if (line.contains("'lat':")) {
      lat = double.parse(line.split(":")[1].trim().replaceAll(",", ""));
    }
    if (line.contains("'lng':")) {
      lng = double.parse(line.split(":")[1].trim().replaceAll(",", ""));
      
      var isExact = routePoints.any((p) => p.lat == lat && p.lng == lng);
      if (!isExact) {
        LatLng? closest;
        double minDistance = double.infinity;
        for (var p in routePoints) {
          double d = calculateDistance(lat!, lng!, p.lat, p.lng);
          if (d < minDistance) {
            minDistance = d;
            closest = p;
          }
        }
        print("Mismatched stop: \$name");
        print("Current: \$lat, \$lng");
        print("Closest: \${closest!.lat}, \${closest.lng} (Distance: \${minDistance.toStringAsFixed(2)}m)");
        print("---");
      }
    }
  }
}
