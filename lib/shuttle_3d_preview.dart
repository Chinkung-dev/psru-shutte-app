import 'package:flutter/material.dart';
import 'screens/test/shuttle_3d_poc_screen.dart';

/// Standalone simulated map: no Firebase initialization or account required.
/// flutter run -t lib/shuttle_3d_preview.dart -d chrome
void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF176A21)),
    home: const Shuttle3DPocScreen(),
  ));
}
