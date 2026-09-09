import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_stop_dialog.dart';
import 'edit_stop_dialog.dart';
import 'admin_profile_dialog.dart';
import '../../widgets/top_toast.dart';
import '../../widgets/app_loading_view.dart';

class AdminStopsTab extends StatefulWidget {
  const AdminStopsTab({super.key});

  @override
  State<AdminStopsTab> createState() => _AdminStopsTabState();
}

class _AdminStopsTabState extends State<AdminStopsTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 960;

    return CustomScrollView(
      slivers: [
        if (!isDesktop)
          SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF176a21)),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            title: const Text(
              'จัดการจุดจอดรถ',
              style: TextStyle(
                color: Color(0xFF176a21),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        if (isDesktop)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: _buildHeader(context),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const StopsTitleRow(),
              const SizedBox(height: 24),
              StopsTableCard(
                searchQuery: _searchQuery,
                onSearchChanged: (q) => setState(() => _searchQuery = q),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.signpost_rounded,
              color: Color(0xFF176a21),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'จัดการข้อมูลจุดจอดรถรับส่ง',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF176a21),
                ),
              ),
              Text(
                'ระบบจัดการตำแหน่งป้ายหยุดรถ กำหนดพิกัด และสถานะการให้บริการ',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5A605B),
                ),
              ),
            ],
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const AdminProfileDialog(),
              );
            },
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF176a21),
                  width: 2,
                ),
              ),
              child: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                radius: 18,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF176a21),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StopsTitleRow extends StatelessWidget {
  const StopsTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 750;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รายชื่อจุดจอดรถทั้งหมด',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2923),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'จุดจอดรถรับส่งในเครือข่าย PSRU Shuttle พร้อมสถานะเปิด-ปิดให้บริการ',
                    style: TextStyle(
                      color: const Color(0xFF5A605B).withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (!isMobile)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('stops').snapshots(),
                builder: (context, snapshot) {
                  int total = 0;
                  int active = 0;
                  int inactive = 0;

                  if (snapshot.hasData) {
                    final docs = snapshot.data!.docs;
                    total = docs.length;
                    for (var doc in docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final isActive = data['is_active'] != false;
                      if (isActive) {
                        active++;
                      } else {
                        inactive++;
                      }
                    }
                  }

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatBadge(
                        'จุดจอดทั้งหมด',
                        '$total จุด',
                        const Color(0xFF176a21),
                        const Color(0xFFE8F5E9),
                        Icons.location_on_rounded,
                      ),
                      const SizedBox(width: 12),
                      _buildStatBadge(
                        'เปิดให้บริการ',
                        '$active จุด',
                        const Color(0xFF2E7D32),
                        const Color(0xFFE8F5E9),
                        Icons.check_circle_rounded,
                      ),
                      const SizedBox(width: 12),
                      _buildStatBadge(
                        'ปิดปรับปรุง',
                        '$inactive จุด',
                        const Color(0xFFD9534F),
                        const Color(0xFFFFEBEE),
                        Icons.pause_circle_filled_rounded,
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatBadge(
    String label,
    String value,
    Color color,
    Color bgColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF718076),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StopsTableCard extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const StopsTableCard({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<StopsTableCard> createState() => _StopsTableCardState();
}

class _StopsTableCardState extends State<StopsTableCard> {
  String _activeFilter = 'ทั้งหมด';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176a21).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // แถบเส้นสีหัวการ์ด
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF176a21),
                    Color(0xFF66BB6A),
                    Color(0xFF9DF197),
                  ],
                ),
              ),
            ),

            // แถบค้นหา ตัวกรอง และปุ่มเพิ่มจุดจอด
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Wrap(
                spacing: 16,
                runSpacing: 14,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // ตัวกรองสถานะ
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F6F3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFilterTab('ทั้งหมด', _activeFilter == 'ทั้งหมด'),
                          _buildFilterTab('เปิดให้บริการ', _activeFilter == 'เปิดให้บริการ'),
                          _buildFilterTab('ปิดปรับปรุง', _activeFilter == 'ปิดปรับปรุง'),
                        ],
                      ),
                    ),
                  ),

                  // ช่องค้นหาและปุ่มเพิ่มจุดจอด
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 220,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6F3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.1),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: widget.onSearchChanged,
                          style: const TextStyle(
                            color: Color(0xFF2C2F30),
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'ค้นหาชื่อจุดจอด...',
                            hintStyle: TextStyle(
                              color: Color(0xFF718076),
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Color(0xFF176a21),
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('stops').snapshots(),
                        builder: (context, snapshot) {
                          final currentCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                          return ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AddStopDialog(
                                  nextOrder: currentCount + 1,
                                ),
                              );
                            },
                            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                            label: const Text(
                              'เพิ่มจุดจอด',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF176a21),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEFF2F0)),

            // ตารางและรายการจุดจอด
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('stops').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: AppLoadingView(
                      message: 'กำลังโหลดข้อมูลจุดจอดรถ...',
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'เกิดข้อผิดพลาดในการโหลดข้อมูล: ${snapshot.error}',
                        style: const TextStyle(color: Color(0xFFD9534F)),
                      ),
                    ),
                  );
                }

                var docs = snapshot.hasData ? snapshot.data!.docs.toList() : [];

                // กรองข้อความค้นหา
                if (widget.searchQuery.isNotEmpty) {
                  final q = widget.searchQuery.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final desc = (data['description'] ?? '').toString().toLowerCase();
                    return name.contains(q) || desc.contains(q);
                  }).toList();
                }

                // กรองสถานะ
                if (_activeFilter == 'เปิดให้บริการ') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['is_active'] != false;
                  }).toList();
                } else if (_activeFilter == 'ปิดปรับปรุง') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['is_active'] == false;
                  }).toList();
                }

                // จัดเรียงตาม order
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final orderA = (dataA['order'] is num ? (dataA['order'] as num).toInt() : 999);
                  final orderB = (dataB['order'] is num ? (dataB['order'] as num).toInt() : 999);
                  return orderA.compareTo(orderB);
                });

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth > 860 ? constraints.maxWidth : 860,
                        child: Column(
                          children: [
                            // ส่วนหัวตาราง
                            Container(
                              color: const Color(0xFFF8FAF9),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  _buildTableHeader('ลำดับ', flex: 1),
                                  _buildTableHeader('ข้อมูลจุดจอดรถ', flex: 4),
                                  _buildTableHeader('พิกัด (Lat, Lng)', flex: 3),
                                  _buildTableHeader('สถานะให้บริการ', flex: 3),
                                  _buildTableHeader(
                                    'การจัดการ',
                                    flex: 2,
                                    alignRight: true,
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFEFF2F0)),

                            if (docs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(48.0),
                                child: Center(
                                  child: Text(
                                    'ไม่พบข้อมูลจุดจอดรถตามเงื่อนไข',
                                    style: TextStyle(
                                      color: Color(0xFF718076),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ...docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final docId = doc.id;
                                final name = data['name'] ?? 'ไม่มีชื่อ';
                                final desc = data['description'] ?? '';
                                final order = data['order'] ?? 1;
                                final lat = data['lat'] ?? 0.0;
                                final lng = data['lng'] ?? 0.0;
                                final isActive = data['is_active'] != false;

                                return _buildStopRow(
                                  context: context,
                                  docId: docId,
                                  data: data,
                                  name: name.toString(),
                                  description: desc.toString(),
                                  order: order is num ? order.toInt() : 1,
                                  lat: (lat is num ? lat.toDouble() : 0.0),
                                  lng: (lng is num ? lng.toDouble() : 0.0),
                                  isActive: isActive,
                                );
                              }),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String title, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _activeFilter = title),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF176a21) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF718076),
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(
    String title, {
    required int flex,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          color: Color(0xFF718076),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStopRow({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> data,
    required String name,
    required String description,
    required int order,
    required double lat,
    required double lng,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFF2F6F3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // ลำดับ Order
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '#$order',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF176a21),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ข้อมูลจุดจอด
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: isActive ? const Color(0xFF176a21) : const Color(0xFFD9534F),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E2923),
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718076),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // พิกัด
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: '$lat, $lng'));
                TopToast.show(context, 'คัดลอกพิกัด $lat, $lng แล้ว', isError: false);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      size: 14,
                      color: Color(0xFF718076),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2C2F30),
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // สถานะให้บริการ + สวิตช์
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF176a21).withOpacity(0.2)
                          : const Color(0xFFD9534F).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF176a21) : const Color(0xFFD9534F),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isActive ? 'เปิดให้บริการ' : 'ปิดปรับปรุง',
                        style: TextStyle(
                          color: isActive ? const Color(0xFF176a21) : const Color(0xFFD9534F),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: isActive,
                    activeColor: const Color(0xFF176a21),
                    onChanged: (newVal) async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('stops')
                            .doc(docId)
                            .update({
                          'is_active': newVal,
                          'updated_at': FieldValue.serverTimestamp(),
                        });
                        if (!context.mounted) return;
                        TopToast.show(
                          context,
                          newVal ? 'เปิดให้บริการจุดจอด $name แล้ว' : 'ปิดปรับปรุงจุดจอด $name แล้ว',
                          isError: false,
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        TopToast.show(context, 'เกิดข้อผิดพลาดในการอัปเดตสถานะ: $e', isError: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // การจัดการ (แก้ไข / ลบ)
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF176a21),
                    size: 18,
                  ),
                  tooltip: 'แก้ไขข้อมูลจุดจอด',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => EditStopDialog(
                        docId: docId,
                        stopData: data,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFD9534F),
                    size: 18,
                  ),
                  tooltip: 'ลบจุดจอด',
                  onPressed: () => _confirmDeleteStop(context, docId, name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStop(BuildContext context, String docId, String stopName) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFD9534F),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ยืนยันการลบจุดจอด',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2923),
                ),
              ),
            ],
          ),
          content: Text(
            'คุณแน่ใจหรือไม่ว่าต้องการลบจุดจอด "$stopName" ? การดำเนินการนี้ไม่สามารถยกเลิกได้',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5A605B),
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(color: Color(0xFF718076)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await FirebaseFirestore.instance.collection('stops').doc(docId).delete();
                  if (!context.mounted) return;
                  TopToast.show(context, 'ลบจุดจอด $stopName เรียบร้อยแล้ว', isError: false);
                } catch (e) {
                  if (!context.mounted) return;
                  TopToast.show(context, 'เกิดข้อผิดพลาดในการลบ: $e', isError: true);
                }
              },
              child: const Text(
                'ยืนยันการลบ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}
