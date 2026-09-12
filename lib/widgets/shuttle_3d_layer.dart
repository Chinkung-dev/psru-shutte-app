import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:three_js/three_js.dart' as three;
import '../services/shuttle_heading.dart';

class Shuttle3DObjectData {
  final String id;
  final LatLng position;
  final double bearing;
  final String? status;
  final String? label;
  const Shuttle3DObjectData({
    required this.id,
    required this.position,
    this.bearing = 0,
    this.status = 'available',
    this.label,
  });
}

/// Place directly inside FlutterMap.children, before the upright MarkerLayer.
/// One renderer and GLB per map; vehicles share geometry and materials.
class Shuttle3DLayer extends StatelessWidget {
  // ทดสอบการซิงก์เฟรมด้วย renderer จำลอง โดยยังใช้ widget และการคำนวณจริง
  final three.ThreeJS Function(Size, Future<void> Function())? rendererFactory;
  final Future<three.Object3D> Function()? modelLoader;
  final MapCamera mapCamera;
  final List<Shuttle3DObjectData> shuttles;
  final bool showWireframe;
  final ValueChanged<bool>? onReadyChanged;
  const Shuttle3DLayer({
    super.key,
    required this.mapCamera,
    required this.shuttles,
    this.showWireframe = false,
    this.onReadyChanged,
    @visibleForTesting this.rendererFactory,
    @visibleForTesting this.modelLoader,
  });
  @override
  Widget build(BuildContext context) {
    final size = mapCamera.nonRotatedSize;
    if (size.width <= 1 || size.height <= 1) {
      return const SizedBox.shrink();
    }
    return _ShuttleScene(
      // จัดสรรเฟรมบัฟเฟอร์ใหม่เฉพาะเมื่อขนาดของแผนที่เปลี่ยน
      key: ValueKey(size),
      data: this,
    );
  }
}

class _ShuttleScene extends StatefulWidget {
  final Shuttle3DLayer data;
  const _ShuttleScene({super.key, required this.data});
  @override
  State<_ShuttleScene> createState() => _ShuttleSceneState();
}

class _ShuttleSceneState extends State<_ShuttleScene>
    with WidgetsBindingObserver {
  static const _tilt = math.pi / 5;
  late final int _generation;
  late final three.ThreeJS _engine;
  three.Object3D? _template;
  final _roots = <String, three.Group>{};
  final _headings = <String, double>{};

  // จัดการเวลา Startup Timeout แบบหยุดนับขณะพักหน้าจอตาม REV-05
  Duration _remainingStartupBudget = const Duration(seconds: 20);
  Stopwatch? _startupStopwatch;
  Timer? _loadTimer;

  bool _ready = false;
  bool _failed = false;
  bool _foreground = true;
  Widget? _cachedEngineWidget;
  bool _rendering = false;
  bool _renderRequested = false;
  Shuttle3DLayer get data => widget.data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generation = RendererLifecycleCoordinator.nextGeneration();
    _notify(false);
    _engine = data.rendererFactory?.call(data.mapCamera.nonRotatedSize, _setup) ?? _GuardedThreeJS(
      size: data.mapCamera.nonRotatedSize,
      setup: _setup,
      onFailure: _fail,
      generation: _generation,
    );
    // Initialize before asynchronous startup so early disposal is safe.
    _engine.scene = three.Scene();
    _engine.camera = three.OrthographicCamera(-1, 1, 1, -1, .1, 2000);
    _engine.camera.position.setValues(0, 0, 500);
    _engine.customRenderer = (scene, camera, texture, [dt]) async {
      await _renderFrame(dt ?? 0);
    };
  }

  void _updateStartupTimer() {
    if (!mounted || _ready || _failed) {
      _stopStartupTimer();
      return;
    }

    final bool isRenderingActive =
        _foreground && TickerMode.valuesOf(context).enabled;

    if (isRenderingActive) {
      if (_loadTimer == null) {
        if (_remainingStartupBudget <= Duration.zero) {
          _fail('3D startup timeout');
          return;
        }
        _startupStopwatch = Stopwatch()..start();
        _loadTimer = Timer(_remainingStartupBudget, () {
          if (!_ready && !_failed && mounted) {
            _fail('3D startup timeout');
          }
        });
      }
    } else {
      _pauseStartupTimer();
    }
  }

  void _pauseStartupTimer() {
    if (_loadTimer != null) {
      _loadTimer!.cancel();
      _loadTimer = null;
    }
    if (_startupStopwatch != null) {
      final elapsed = _startupStopwatch!.elapsed;
      _remainingStartupBudget -= elapsed;
      if (_remainingStartupBudget.isNegative) {
        _remainingStartupBudget = Duration.zero;
      }
      _startupStopwatch!.stop();
      _startupStopwatch = null;
    }
  }

  void _stopStartupTimer() {
    _loadTimer?.cancel();
    _loadTimer = null;
    _startupStopwatch?.stop();
    _startupStopwatch = null;
  }

  void _notify(bool ready) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        data.onReadyChanged?.call(ready);
      }
    });
  }

  Future<void> _renderFrame([double dt = 0]) async {
    if (_failed || !mounted || !_engine.visible) return;
    if (_rendering) {
      _renderRequested = true;
      return;
    }
    _rendering = true;
    try {
      _update(dt);
      await _engine.render(
        _engine.scene,
        _engine.camera,
        _engine.texture,
        dt,
      );
      if (!_ready && mounted) {
        _ready = true;
        _stopStartupTimer();
        _notify(true);
        setState(() {});
      }
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _rendering = false;
      if (_renderRequested && mounted && !_failed && _engine.visible) {
        _renderRequested = false;
        unawaited(_renderFrame(0));
      }
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!mounted || _failed) return;
    debugPrint('Shuttle 3D fallback: $error');
    if (stack != null) debugPrint('Stack: $stack');
    _stopStartupTimer();
    _failed = true;
    _cachedEngineWidget = null;
    _engine.visible = false;
    _notify(false);
    setState(() {});
    try {
      _engine.dispose();
    } catch (e) {
      debugPrint('Engine dispose caught: $e');
    }
  }

  Future<void> _setup() async {
    final loader = three.GLTFLoader();
    try {
      final model = data.modelLoader != null
          ? await data.modelLoader!()
          : (await loader.fromAsset('assets/models/psru_shuttle.glb'))?.scene;
      if (model == null) throw StateError('Shuttle GLB is empty');
      if (!mounted || _failed || (_engine is _GuardedThreeJS && _engine.isClosed)) {
        model.dispose();
        return;
      }
      _template = model;
      // ลดแสงรอบทิศเพื่อให้ตัวถังขาวยังเห็นส่วนโค้งและด้านที่อยู่ในเงา
      _engine.scene.add(three.AmbientLight(0xffffff, 0.65));
      final light = three.DirectionalLight(0xffffff, 1.1);
      light.position.setValues(-100, 150, 300);
      _engine.scene.add(light);
      _syncVehicles();
      _update(0);
    } catch (e, stack) {
      debugPrint('_setup GLB loader error: $e\n$stack');
      rethrow;
    } finally {
      loader.dispose();
    }
  }

  // Package Mesh.clone duplicates buffers. Copy nodes/transforms explicitly.
  three.Object3D _instance(three.Object3D source) {
    final three.Object3D node = source is three.Mesh
        ? three.Mesh(source.geometry, source.material)
        : three.Group();
    node.position.setFrom(source.position);
    node.quaternion.setFrom(source.quaternion);
    node.scale.setFrom(source.scale);
    for (final child in source.children) {
      node.add(_instance(child));
    }
    return node;
  }

  void _syncVehicles() {
    if (_template == null || _failed) return;
    final ids = data.shuttles.map((s) => s.id).toSet();
    for (final id in _roots.keys.where((id) => !ids.contains(id)).toList()) {
      _engine.scene.remove(_roots.remove(id)!);
      _headings.remove(id);
    }
    _template!.traverse((node) {
      node.material?.wireframe = data.showWireframe;
    });
    for (final shuttle in data.shuttles) {
      if (_roots.containsKey(shuttle.id)) continue;
      final model = _instance(_template!);
      model.rotation.x = math.pi / 2; // glTF Y-up to scene Z-up.
      model.scale.setValues(12, 12, 12);
      final yaw = three.Group()..add(model);
      final tilt = three.Group()..rotation.x = _tilt;
      tilt.add(yaw);
      final root = three.Group()
        ..name = shuttle.id
        ..add(tilt);
      _roots[shuttle.id] = root;
      _headings[shuttle.id] = shuttle.bearing;
      _engine.scene.add(root);
    }
  }

  void _update(double dt) {
    final size = data.mapCamera.nonRotatedSize;
    // ซูมไกลลดเหลือครึ่งหนึ่ง แล้วค่อยเพิ่มถึงขนาดเดิมที่ซูม 18
    // จำกัดขนาดเพื่อให้อ่านรูปทรงได้และไม่โตบังแผนที่เมื่อซูมเข้าเพิ่ม
    final zoomProgress = ((data.mapCamera.zoom - 15.8) / 2.2).clamp(0.0, 1.0);
    final modelScale = 0.5 + 0.5 * zoomProgress;
    final camera = _engine.camera as three.OrthographicCamera;
    camera.left = -size.width / 2;
    camera.right = size.width / 2;
    camera.top = size.height / 2;
    camera.bottom = -size.height / 2;
    camera.updateProjectionMatrix();
    for (final shuttle in data.shuttles) {
      final root = _roots[shuttle.id];
      if (root == null) continue;
      root.scale.setValues(modelScale, modelScale, modelScale);
      final old = _headings[shuttle.id] ?? shuttle.bearing;
      final bearing =
          old +
          shortestHeadingDelta(old, shuttle.bearing) *
              (1 - math.exp(-dt.clamp(0, .1) * 12));
      _headings[shuttle.id] = bearing % 360;
      final point = data.mapCamera.latLngToScreenOffset(shuttle.position);
      final ahead = data.mapCamera.latLngToScreenOffset(
        const Distance().offset(shuttle.position, 10, bearing),
      );
      root.position.setValues(
        point.dx - size.width / 2,
        size.height / 2 - point.dy,
        0,
      );
      root.visible =
          point.dx > -90 &&
          point.dy > -90 &&
          point.dx < size.width + 90 &&
          point.dy < size.height + 90;
      // Include map rotation and compensate the orthographic display tilt.
      root.children.first.children.first.rotation.z = math.atan2(
        -(ahead.dx - point.dx),
        (point.dy - ahead.dy) / math.cos(_tilt),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ShuttleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVehicles();
    _update(0);
    if (_ready && !_failed && _engine.visible) {
      unawaited(_renderFrame(0));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine.visible =
        !_failed && _foreground && TickerMode.valuesOf(context).enabled;
    _updateStartupTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _engine.visible =
        !_failed && _foreground && TickerMode.valuesOf(context).enabled;
    _updateStartupTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStartupTimer();
    _cachedEngineWidget = null;
    for (final root in _roots.values) {
      _engine.scene.remove(root);
    }
    _roots.clear();
    _template?.dispose();
    try {
      _engine.dispose();
    } catch (e) {
      debugPrint('Engine dispose caught: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.shrink();
    }
    if (_ready) {
      _cachedEngineWidget ??= _engine.build();
      return IgnorePointer(
        child: SizedBox.expand(child: _cachedEngineWidget!),
      );
    }
    return IgnorePointer(
      child: SizedBox.expand(child: _engine.build()),
    );
  }
}

/// ตัวประสานจัดการลำดับ Teardown และ Initialization ของ 3D Renderer ข้ามทุก instance
/// เพื่อป้องกันปัญหา static EGL reference ถูกทำลายซ้ำซ้อนหรือเกิด Race condition ตาม REV-06
class RendererLifecycleCoordinator {
  static Future<void> _lifecycleChain = Future<void>.value();
  static int _globalGeneration = 0;

  static int nextGeneration() => ++_globalGeneration;
  static int get currentGeneration => _globalGeneration;

  /// รัน action ตามลำดับอย่างเคร่งครัด โดยงานใหม่จะเริ่มหลังงานเดิมเสร็จสมบูรณ์ 100%
  static Future<T> schedule<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lifecycleChain = _lifecycleChain.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// สำหรับใช้ในการทดสอบเพื่อรอให้คิวงาน Teardown ทั้งหมดจบลง
  @visibleForTesting
  static Future<void> get whenIdle => _lifecycleChain;
}

/// Catch platform startup errors and serialize initialization and teardown across instances.
class _GuardedThreeJS extends three.ThreeJS {
  final void Function(Object) onFailure;
  final int generation;
  bool _initializing = false;
  bool _closed = false;
  bool get isClosed => _closed;

  _GuardedThreeJS({
    required super.size,
    required super.setup,
    required this.onFailure,
    required this.generation,
  }) : super(
         onSetupComplete: () {},
         loadingWidget: const SizedBox.shrink(),
         settings: three.Settings(
           alpha: true,
           clearAlpha: 0,
           antialias: true,
           screenResolution: 1.5,
           enableShadowMap: false,
         ),
       );

  @override
  Future<void> initPlatformState() async {
    return RendererLifecycleCoordinator.schedule(() async {
      if (_closed) return;
      if (width <= 1 || height <= 1) {
        debugPrint('ข้ามการสร้างกราฟิกเนื่องจากขนาดยังไม่พร้อม: $width x $height');
        return;
      }
      _initializing = true;
      try {
        await super.initPlatformState();
      } catch (error, stack) {
        debugPrint('initPlatformState error: $error\n$stack');
        if (!_closed) {
          onFailure(error);
        }
      } finally {
        _initializing = false;
        if (_closed) {
          try {
            super.dispose();
          } catch (e) {
            debugPrint('Engine dispose on close caught: $e');
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _closed = true;
    visible = false;
    RendererLifecycleCoordinator.schedule(() async {
      if (!_initializing) {
        try {
          super.dispose();
        } catch (e) {
          debugPrint('Engine dispose caught: $e');
        }
      }
    });
  }
}

