import 'dart:io';
void main() {
  var routeData = File('lib/route_data.dart').readAsStringSync();
  var migrationPage = File('lib/migration_page.dart').readAsLinesSync();
  
  String? name;
  String? lat;
  
  for (var line in migrationPage) {
    if (line.contains("'name':")) {
      name = line.split("'")[3];
    }
    if (line.contains("'lat':")) {
      lat = line.split(":")[1].trim().replaceAll(",", "");
      if (!routeData.contains(lat)) {
        print("Missing match for: ${name} (Lat: ${lat})");
      }
    }
  }
}
