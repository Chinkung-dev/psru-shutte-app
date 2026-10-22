import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_angle/flutter_angle.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/services/shuttle_heading.dart';
import 'package:psru_shuttle_app/widgets/shuttle_3d_layer.dart';
import 'package:psru_shuttle_app/widgets/shuttle_map_badge.dart';
import 'package:three_js/three_js.dart' as three;

void main() {
  const origin = LatLng(16.83, 100.21);
  const distance = Distance();
  final time = DateTime.utc(2026, 9, 10);

  test('GPS heading follows all cardinal directions', () {
    for (final bearing in [0.0, 90.0, 180.0, 270.0]) {
      expect(
        shuttleBearing(origin, distance.offset(origin, 20, bearing)),
        closeTo(bearing, .02),
      );
    }
  });
  test('rotation crosses north by the shortest arc', () {
    expect(shortestHeadingDelta(359, 1), 2);
    expect(shortestHeadingDelta(1, 359), -2);
    expect(shortestHeadingDelta(10, 50), 40);
  });
  test('stopped GPS noise preserves heading, slow movement accumulates', () {
    final tracker = ShuttleHeadingTracker();
    tracker.update(origin, time);
    tracker.update(
      distance.offset(origin, 2, 90),
      time.add(const Duration(seconds: 1)),
    );
    expect(tracker.bearing, 0);
    final east = distance.offset(origin, 6, 90);
    tracker.update(east, time.add(const Duration(seconds: 2)));
    expect(tracker.bearing, closeTo(90, .02));
    for (var i = 3; i < 10; i++) {
      tracker.update(
        distance.offset(east, 1, i * 30),
        time.add(Duration(seconds: i)),
      );
      expect(tracker.bearing, closeTo(90, .02));
    }
  });
  test(
    'stale fixes and jumps cannot turn the vehicle; valid data recovers',
    () {
      final tracker = ShuttleHeadingTracker();
      tracker.update(origin, time);
      final east = distance.offset(origin, 10, 90);
      tracker.update(east, time.add(const Duration(seconds: 2)));
      tracker.update(distance.offset(east, 10, 180), time);
      tracker.update(
        distance.offset(east, 1000, 270),
        time.add(const Duration(seconds: 3)),
      );
      expect(tracker.bearing, closeTo(90, .02));
      tracker.update(
        distance.offset(east, 10, 180),
        time.add(const Duration(seconds: 4)),
      );
      expect(tracker.bearing, closeTo(180, .02));
    },
  );
  test(
    'reconnect resets anchor without rotating across the missing interval',
    () {
      final tracker = ShuttleHeadingTracker();
      tracker.update(origin, time);
      tracker.update(
        distance.offset(origin, 10, 90),
        time.add(const Duration(seconds: 2)),
      );
      final reconnected = distance.offset(origin, 300, 270);
      tracker.update(reconnected, time.add(const Duration(seconds: 60)));
      expect(tracker.bearing, closeTo(90, .02));
      tracker.update(
        distance.offset(reconnected, 10, 0),
        time.add(const Duration(seconds: 62)),
      );
      expect(tracker.bearing, closeTo(0, .02));
    },
  );

  test(
    'รถจอดนิ่งที่จุดจอดแล้วมี GPS Jitter ถอยหลังกลับทิศ 180 องศา ต้องไม่หมุนกลับหลังไปมา',
    () {
      final tracker = ShuttleHeadingTracker();
      tracker.update(origin, time);
      // รถวิ่งไปทางทิศเหนือ (0 องศา) เป็นระยะ 10 เมตร
      final northStop = distance.offset(origin, 10, 0);
      tracker.update(northStop, time.add(const Duration(seconds: 2)));
      expect(tracker.bearing, closeTo(0, .02));

      // รถจอดนิ่งที่จุดจอด มี GPS Jitter ส่ายถอยหลังลงมาทางทิศใต้ (180 องศา) 4.5 เมตร
      final jitterSouth = distance.offset(northStop, 4.5, 180);
      tracker.update(jitterSouth, time.add(const Duration(seconds: 6)));
      // ต้องไม่กลับหลังหันไปทางทิศใต้ (180 องศา) ยังคงรักษาทิศเหนือ (0 องศา) เดิมไว้
      expect(tracker.bearing, closeTo(0, .02));

      // GPS Jitter ส่ายกลับขึ้นมาที่จุดเดิม
      tracker.update(northStop, time.add(const Duration(seconds: 9)));
      expect(tracker.bearing, closeTo(0, .02));

      // GPS Jitter ส่ายซ้ำๆ ขณะจอดนิ่งเป็นเวลา 1 นาที
      for (int sec = 12; sec <= 60; sec += 3) {
        final wobblePos = distance.offset(northStop, 5.0, (sec % 6 == 0) ? 180 : 0);
        tracker.update(wobblePos, time.add(Duration(seconds: sec)));
        expect(tracker.bearing, closeTo(0, .02));
      }

      // เมื่อรถเริ่มออกตัววิ่งกลับรถจริงไปทางทิศใต้ต่อเนื่อง 16 เมตรด้วยความเร็วปกติ
      final driveSouth = distance.offset(northStop, 16, 180);
      tracker.update(driveSouth, time.add(const Duration(seconds: 64)));
      // หมุนตามทิศทางใหม่ 180 องศาได้อย่างถูกต้องเมื่อมีการวิ่งจริง
      expect(tracker.bearing, closeTo(180, .02));
    },
  );

  test(
    'เมื่อรถเคลื่อนที่ช้ามากต่ำกว่า 0.8 ม./วินาที จะรักษาทิศทางเดิมไว้เสมอ',
    () {
      final tracker = ShuttleHeadingTracker();
      tracker.update(origin, time);
      final eastPos = distance.offset(origin, 10, 90);
      tracker.update(eastPos, time.add(const Duration(seconds: 2)));
      expect(tracker.bearing, closeTo(90, .02));

      // จำลอง GPS drift เดินช้ามาก 2 เมตรในเวลา 10 วินาที (0.2 ม./วินาที)
      final slowDrift = distance.offset(eastPos, 2, 270);
      tracker.update(slowDrift, time.add(const Duration(seconds: 12)));
      expect(tracker.bearing, closeTo(90, .02));
    },
  );
  testWidgets(
    'number/status stay visible with fallback and unknown status is explicit',
    (tester) async {
      for (final entry in {
        'available': 'ว่าง',
        'full': 'เต็ม',
        'break': 'พัก',
        'offline': 'ออฟไลน์',
        'unexpected': 'ไม่ทราบสถานะ',
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 150,
                height: 100,
                child: ShuttleMapBadge(
                  number: '05',
                  status: entry.key,
                  showFallback: true,
                ),
              ),
            ),
          ),
        );
        expect(find.text('รถ 05 · ${entry.value}'), findsOneWidget);
        expect(find.byIcon(Icons.directions_bus), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 150,
            height: 100,
            child: ShuttleMapBadge(number: '05', status: 'full'),
          ),
        ),
      );
      expect(find.text('รถ 05 · เต็ม'), findsOneWidget);
      expect(find.byIcon(Icons.directions_bus), findsNothing);
    },
  );

  testWidgets(
    'Shuttle3DLayer: ตรวจสอบการซิงก์ตำแหน่งในเฟรมเดียวกันระหว่างโมเดล 3D และ Marker เมื่อรถขยับ',
    (tester) async {
      late _FakeThreeJS fakeEngine;
      const initialPos = LatLng(16.8300, 100.2050);
      const newPos = LatLng(16.8320, 100.2070);

      await tester.pumpWidget(
        Builder(
          builder: (ctx) {
            fakeEngine = _FakeThreeJS(
              size: const Size(800, 600),
            );
            return _TestShuttleHarness(
              initialCenter: initialPos,
              initialPosition: initialPos,
              initialStatus: 'available',
              fakeEngine: fakeEngine,
            );
          },
        ),
      );

      // รัน microtask เพื่อให้ setup และ frame แรกทำงาน
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<_TestShuttleHarnessState>(
        find.byType(_TestShuttleHarness),
      );

      three.Group? findShuttleGroup() {
        return fakeEngine.scene.children.whereType<three.Group>().firstOrNull;
      }

      final initialGroup = findShuttleGroup();
      expect(initialGroup, isNotNull);

      Offset getModelAnchor(three.Group group) {
        return Offset(group.position.x + 800 / 2, 600 / 2 - group.position.y);
      }

      final initialAnchor = getModelAnchor(initialGroup!);
      final initialMarkerCenter = tester.getCenter(
        find.byKey(const ValueKey('marker_shuttle_1')),
      );
      expect((initialAnchor - initialMarkerCenter).distance, lessThan(3.0));

      // เมื่อตำแหน่งรถเปลี่ยนผ่าน parent rebuild
      state.updateShuttle(pos: newPos);
      await tester.pump(); // เฟรมเดียวกับที่ MarkerLayer วาดตำแหน่งใหม่

      final updatedMarkerCenter = tester.getCenter(
        find.byKey(const ValueKey('marker_shuttle_1')),
      );
      final currentAnchor = getModelAnchor(initialGroup);

      // ตรวจสอบว่าจุดยึดโมเดล 3D ซิงก์ตรงกับ Marker ทันทีในเฟรมเดียวกัน ไม่รอ Ticker ภายนอก
      expect(
        (currentAnchor - updatedMarkerCenter).distance,
        lessThan(3.0),
        reason: 'ตำแหน่งโมเดล 3D ต้องอัปเดตตรงกับ Marker ทันทีในเฟรม rebuild',
      );
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'Shuttle3DLayer: ตรวจสอบการซิงก์ตำแหน่งเมื่อเลื่อนกล้องแผนที่ (Camera Pan)',
    (tester) async {
      late _FakeThreeJS fakeEngine;
      const initialCenter = LatLng(16.8300, 100.2050);
      const shuttlePos = LatLng(16.8300, 100.2050);
      const newCenter = LatLng(16.8330, 100.2080);

      await tester.pumpWidget(
        Builder(
          builder: (ctx) {
            fakeEngine = _FakeThreeJS(
              size: const Size(800, 600),
            );
            return _TestShuttleHarness(
              initialCenter: initialCenter,
              initialPosition: shuttlePos,
              initialStatus: 'available',
              fakeEngine: fakeEngine,
            );
          },
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<_TestShuttleHarnessState>(
        find.byType(_TestShuttleHarness),
      );

      final group = fakeEngine.scene.children.whereType<three.Group>().firstOrNull;
      expect(group, isNotNull);

      Offset getModelAnchor() {
        return Offset(group!.position.x + 800 / 2, 600 / 2 - group.position.y);
      }

      // เลื่อนกล้องแผนที่
      state.moveCamera(newCenter);
      await tester.pump();

      final markerCenter = tester.getCenter(
        find.byKey(const ValueKey('marker_shuttle_1')),
      );
      final modelAnchor = getModelAnchor();

      expect(
        (modelAnchor - markerCenter).distance,
        lessThan(3.0),
        reason: 'ตำแหน่งโมเดล 3D ต้องเกาะกับ Marker เมื่อเลื่อนกล้องแผนที่',
      );
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'Shuttle3DLayer: ไม่สร้าง widget engine build ซ้ำเมื่อ rebuild ด้วยสถานะเดิม',
    (tester) async {
      late _FakeThreeJS fakeEngine;
      const pos = LatLng(16.8300, 100.2050);

      await tester.pumpWidget(
        Builder(
          builder: (ctx) {
            fakeEngine = _FakeThreeJS(
              size: const Size(800, 600),
            );
            return _TestShuttleHarness(
              initialCenter: pos,
              initialPosition: pos,
              initialStatus: 'available',
              fakeEngine: fakeEngine,
            );
          },
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final state = tester.state<_TestShuttleHarnessState>(
        find.byType(_TestShuttleHarness),
      );

      final initialBuildCount = fakeEngine.buildCallCount;

      // อัปเดตสถานะรถ
      state.updateShuttle(newStatus: 'full');
      await tester.pump();

      expect(
        fakeEngine.buildCallCount,
        equals(initialBuildCount),
        reason: 'ไม่ควรเรียก engine.build() ซ้ำเมื่อ platform view identity ควรคงเดิม',
      );
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}

class _FakeThreeJS extends three.ThreeJS {
  Future<void> Function()? setupCallback;
  int renderCallCount = 0;
  int buildCallCount = 0;
  bool isDisposed = false;
  Ticker? _testTicker;

  _FakeThreeJS({
    required super.size,
  }) : super(
         setup: () async {},
         onSetupComplete: () {},
       );

  @override
  Future<void> initPlatformState() async {
    screenSize = const Size(800, 600);
    texture = FlutterAngleTexture(
      FlutterAngle(),
      1,
      0,
      0,
      0,
      const AngleOptions(width: 800, height: 600, dpr: 1.0),
    );
    if (setupCallback != null) {
      await setupCallback!();
    }
    _testTicker = Ticker((elapsed) async {
      final dt = clock.getDelta();
      if (customRenderer != null && texture != null) {
        await customRenderer!(scene, camera, texture!, dt);
      }
    });
    _testTicker?.start();
    onSetupComplete();
  }

  @override
  Future<void> render([
    three.Scene? scene,
    three.Camera? camera,
    dynamic texture,
    double? dt,
  ]) async {
    renderCallCount++;
  }

  @override
  Widget build() {
    buildCallCount++;
    return Builder(builder: (context) {
      if (screenSize == null) {
        screenSize = const Size(800, 600);
        Future.microtask(() async {
          await initPlatformState();
        });
      }
      return const SizedBox.expand();
    });
  }

  @override
  void dispose() {
    isDisposed = true;
    _testTicker?.dispose();
    _testTicker = null;
    try {
      super.dispose();
    } catch (_) {}
  }
}

Future<three.Object3D> _fakeModelLoader() async {
  final group = three.Group();
  group.add(three.Mesh(three.BoxGeometry(1, 1, 1), three.MeshBasicMaterial()));
  return group;
}

class _TestShuttleHarness extends StatefulWidget {
  final LatLng initialCenter;
  final LatLng initialPosition;
  final String initialStatus;
  final _FakeThreeJS fakeEngine;

  const _TestShuttleHarness({
    required this.initialCenter,
    required this.initialPosition,
    required this.initialStatus,
    required this.fakeEngine,
  });

  @override
  State<_TestShuttleHarness> createState() => _TestShuttleHarnessState();
}

class _TestShuttleHarnessState extends State<_TestShuttleHarness> {
  late LatLng center;
  late LatLng shuttlePos;
  late String status;
  final MapController mapController = MapController();

  @override
  void initState() {
    super.initState();
    center = widget.initialCenter;
    shuttlePos = widget.initialPosition;
    status = widget.initialStatus;
  }

  void updateShuttle({LatLng? pos, String? newStatus}) {
    setState(() {
      if (pos != null) shuttlePos = pos;
      if (newStatus != null) status = newStatus;
    });
  }

  void moveCamera(LatLng newCenter) {
    mapController.move(newCenter, mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16.0,
              ),
              children: [
                Builder(
                  builder: (ctx) => Shuttle3DLayer(
                    mapCamera: MapCamera.of(ctx),
                    rendererFactory: (size, setup) {
                      widget.fakeEngine.setupCallback = setup;
                      return widget.fakeEngine;
                    },
                    modelLoader: _fakeModelLoader,
                    shuttles: [
                      Shuttle3DObjectData(
                        id: 'shuttle_1',
                        position: shuttlePos,
                        bearing: 90,
                        status: status,
                      ),
                    ],
                  ),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      key: const ValueKey('marker_shuttle_1'),
                      point: shuttlePos,
                      width: 150,
                      height: 100,
                      child: ShuttleMapBadge(
                        number: '01',
                        status: status,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
