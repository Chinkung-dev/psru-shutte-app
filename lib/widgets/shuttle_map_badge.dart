import 'package:flutter/material.dart';

/// Upright label; body branding stays green regardless of occupancy.
class ShuttleMapBadge extends StatelessWidget {
  final String number;
  final String status;
  final bool showFallback;
  final bool selected;
  const ShuttleMapBadge({
    super.key,
    required this.number,
    required this.status,
    this.showFallback = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      'available' => ('ว่าง', const Color(0xFF176A21)),
      'full' => ('เต็ม', const Color(0xFF616466)),
      'break' => ('พัก', const Color(0xFF9C5100)),
      'offline' => ('ออฟไลน์', const Color(0xFFB3261E)),
      _ => ('ไม่ทราบสถานะ', const Color(0xFF616466)),
    };
    final title = number.isEmpty ? 'รถ' : 'รถ $number';
    return Semantics(
      label: '$title $text${selected ? ' คันที่เลือก' : ''}',
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showFallback)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.amber : Colors.white,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3),
                  ],
                ),
                child: Text(
                  '$title · $text',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
