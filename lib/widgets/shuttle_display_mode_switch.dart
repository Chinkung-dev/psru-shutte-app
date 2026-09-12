import 'package:flutter/material.dart';

/// เลือกรูปแบบรถโดยเห็นทั้งโหมดปัจจุบันและตัวเลือกที่เปลี่ยนได้ทันที
class ShuttleDisplayModeSwitch extends StatelessWidget {
  final bool use3D;
  final ValueChanged<bool> onChanged;

  const ShuttleDisplayModeSwitch({
    super.key,
    required this.use3D,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176A21);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: green.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final is3D in [false, true])
              Semantics(
                button: true,
                selected: use3D == is3D,
                label: is3D ? 'แสดงรถแบบโมเดล 3 มิติ' : 'แสดงรถแบบหมุด 2 มิติ',
                child: Tooltip(
                  message: is3D ? 'โมเดลรถ 3 มิติ' : 'หมุดรถ 2 มิติ',
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(21),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: BoxDecoration(
                        color: use3D == is3D ? green : Colors.transparent,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: InkWell(
                        onTap: () {
                          if (use3D != is3D) onChanged(is3D);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 36),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    is3D ? Icons.view_in_ar_rounded : Icons.directions_bus_outlined,
                                    size: 18,
                                    color: use3D == is3D ? Colors.white : green,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    is3D ? '3D' : '2D',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: use3D == is3D ? Colors.white : green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
