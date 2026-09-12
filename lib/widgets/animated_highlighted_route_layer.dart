import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// เลเยอร์เส้นทางไฮไลท์แบบเคลื่อนไหว (Animated Highlighted Route Layer)
/// แสดงเส้นทางจากรถไปยังจุดจอดที่เลือก พร้อมเอฟเฟกต์แสงสีไล่ระดับวิ่งไปมาระหว่างต้นทางและปลายทาง
class AnimatedHighlightedRouteLayer extends StatefulWidget {
  final List<LatLng> path;
  final double strokeWidth;
  final double borderStrokeWidth;
  final Color borderColor;
  final Color baseColor;
  final Color midColor;
  final Color pulseColor;
  final Duration duration;

  const AnimatedHighlightedRouteLayer({
    super.key,
    required this.path,
    this.strokeWidth = 7.0,
    this.borderStrokeWidth = 2.0,
    this.borderColor = const Color(0xFFF9FFF9),
    this.baseColor = const Color(0xFF268B45),
    this.midColor = const Color(0xFF42C45C),
    this.pulseColor = const Color(0xFF6DF07C),
    this.duration = const Duration(milliseconds: 2000),
  });

  /// ช่วงตำแหน่งหยุดของเฉดสีตามสัดส่วนความยาวเส้นทาง (0.0 ถึง 1.0)
  static const List<double> defaultStops = [
    0.0,
    0.125,
    0.25,
    0.375,
    0.5,
    0.625,
    0.75,
    0.875,
    1.0,
  ];

  /// คำนวณชุดสีเฉดสีแบบพลวัตตามความก้าวหน้าของอนิเมชัน t (0.0 ถึง 1.0)
  static List<Color> calculateGradientColors(
    double t, {
    Color baseColor = const Color(0xFF268B45),
    Color midColor = const Color(0xFF42C45C),
    Color pulseColor = const Color(0xFF6DF07C),
    double pulseRadius = 0.28,
  }) {
    return defaultStops.map((p) {
      final double dist = (p - t).abs();
      if (dist >= pulseRadius) {
        return baseColor;
      }
      final double normalized = 1.0 - (dist / pulseRadius);
      // ความโค้งมนแบบ smoothstep ให้แสงนุ่มนวลเป็นธรรมชาติ
      final double intensity =
          normalized * normalized * (3.0 - 2.0 * normalized);
      if (intensity > 0.5) {
        final double factor = (intensity - 0.5) * 2.0;
        return Color.lerp(midColor, pulseColor, factor)!;
      } else {
        final double factor = intensity * 2.0;
        return Color.lerp(baseColor, midColor, factor)!;
      }
    }).toList();
  }

  @override
  State<AnimatedHighlightedRouteLayer> createState() =>
      _AnimatedHighlightedRouteLayerState();
}

class _AnimatedHighlightedRouteLayerState
    extends State<AnimatedHighlightedRouteLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedHighlightedRouteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path.length < 2) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final animatedColors =
            AnimatedHighlightedRouteLayer.calculateGradientColors(
              _animation.value,
              baseColor: widget.baseColor,
              midColor: widget.midColor,
              pulseColor: widget.pulseColor,
            );

        return PolylineLayer(
          polylines: [
            Polyline(
              points: widget.path,
              strokeWidth: widget.strokeWidth,
              color: widget.baseColor,
              borderStrokeWidth: widget.borderStrokeWidth,
              borderColor: widget.borderColor,
              gradientColors: animatedColors,
              colorsStop: AnimatedHighlightedRouteLayer.defaultStops,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ],
        );
      },
    );
  }
}
