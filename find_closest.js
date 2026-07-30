const fs = require('fs');

const routeData = fs.readFileSync('lib/route_data.dart', 'utf8');
const migrationPage = fs.readFileSync('lib/migration_page.dart', 'utf8');

const routePoints = [];
const regex = /const LatLng\(([\d\.]+),\s*([\d\.]+)\)/g;
let match;
while ((match = regex.exec(routeData)) !== null) {
  routePoints.push({ lat: parseFloat(match[1]), lng: parseFloat(match[2]) });
}

function calcDistance(lat1, lon1, lat2, lon2) {
  const p = 0.017453292519943295;
  const c = Math.cos;
  const a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
  return 12742 * Math.asin(Math.sqrt(a)) * 1000;
}

const lines = migrationPage.split('\n');
let currentName, currentLat, currentLng;

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  if (line.includes("'name':")) {
    currentName = line.split("'")[3];
  }
  if (line.includes("'lat':")) {
    currentLat = parseFloat(line.split(":")[1].trim().replace(",", ""));
  }
  if (line.includes("'lng':")) {
    currentLng = parseFloat(line.split(":")[1].trim().replace(",", ""));
    
    const isExact = routePoints.some(p => p.lat === currentLat && p.lng === currentLng);
    if (!isExact) {
      let minDistance = Infinity;
      let closest = null;
      for (const p of routePoints) {
        const d = calcDistance(currentLat, currentLng, p.lat, p.lng);
        if (d < minDistance) {
          minDistance = d;
          closest = p;
        }
      }
      console.log(`Mismatched stop: ${currentName}`);
      console.log(`Current: ${currentLat}, ${currentLng}`);
      console.log(`Closest: ${closest.lat}, ${closest.lng} (Distance: ${minDistance.toFixed(2)}m)`);
      console.log('---');
    }
  }
}
