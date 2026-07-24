import 'package:flutter/material.dart';
import 'add_driver_dialog.dart';

class AdminDriversTab extends StatelessWidget {
  const AdminDriversTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return CustomScrollView(
      slivers: [
        if (!isDesktop)
          SliverAppBar(
            backgroundColor: Colors.white,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Colors.black87),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            title: const Text(
              'ศูนย์ควบคุม',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ),
        if (isDesktop)
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: const DriversHeader(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const DriversTitleRow(),
              const SizedBox(height: 32),
              const DriversTableCard(),
              const SizedBox(height: 32),
              const DriversAlertsRow(),
            ]),
          ),
        ),
      ],
    );
  }
}

class DriversHeader extends StatelessWidget {
  const DriversHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'ข้อมูลพนักงานขับรถ',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        Container(
          width: 300,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'ค้นหาคนขับ, รหัสพนักงาน...',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
        const CircleAvatar(
          backgroundColor: Color(0xFF176a21),
          radius: 18,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

class DriversTitleRow extends StatelessWidget {
  const DriversTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 400,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ข้อมูลพนักงานขับรถ',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              SizedBox(height: 8),
              Text(
                'จัดการพนักงานขับรถของมหาวิทยาลัย ติดตามผลการทำงาน และตรวจสอบสถานะใบอนุญาตและตารางเดินรถ',
                style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatCard('กำลังทำงาน', '42', '+4%', true),
            const SizedBox(width: 16),
            _buildStatCard('คะแนนเฉลี่ย', '4.88', '', false, icon: Icons.star_border),
          ],
        )
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String trend, bool isPositive, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
              if (trend.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? const Color(0xFF176a21) : Colors.red,
                  ),
                ),
              ],
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: const Color(0xFF176a21), size: 24),
              ]
            ],
          ),
        ],
      ),
    );
  }
}

class DriversTableCard extends StatelessWidget {
  const DriversTableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Row
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    children: [
                      _buildFilterTab('ทั้งหมด', true),
                      _buildFilterTab('กำลังวิ่ง', false),
                      _buildFilterTab('พัก', false),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_list, color: Color(0xFF176a21), size: 20),
                  label: const Text('ตัวกรองเพิ่มเติม', style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AddDriverDialog(),
                    ).then((result) {
                      if (result == true) {
                        // Refresh drivers logic if needed
                      }
                    });
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text('เพิ่มคนขับรถ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
          
          // Table Content
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth > 900 ? constraints.maxWidth : 900,
                  child: Column(
                    children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                    child: Row(
                      children: [
                        _buildTableHeader('โปรไฟล์คนขับ', flex: 3),
                        _buildTableHeader('รหัสพนักงาน', flex: 2),
                        _buildTableHeader('สถานะ', flex: 2),
                        _buildTableHeader('รอบวิ่งวันนี้', flex: 2),
                        _buildTableHeader('คะแนน', flex: 1),
                        _buildTableHeader('จัดการ', flex: 1, alignRight: true),
                      ],
                    ),
                  ),
                  
                  // Table Rows
                  _buildDriverRow(
                    name: 'Somchai K.',
                    joined: 'เริ่มงานปี 2021',
                    id: 'US-99201',
                    isOnDuty: true,
                    trips: 14,
                    tripsProgress: 0.7,
                    rating: '4.95',
                    imageUrl: 'https://i.pravatar.cc/150?img=11',
                  ),
                  _buildDriverRow(
                    name: 'Alex Henderson',
                    joined: 'เริ่มงานปี 2022',
                    id: 'US-88432',
                    isOnDuty: false,
                    trips: 6,
                    tripsProgress: 0.3,
                    rating: '4.2',
                    imageUrl: 'https://i.pravatar.cc/150?img=12',
                  ),
                  _buildDriverRow(
                    name: 'Marcus D.',
                    joined: 'เริ่มงานปี 2019',
                    id: 'US-11029',
                    isOnDuty: true,
                    trips: 21,
                    tripsProgress: 0.9,
                    rating: '4.8',
                    imageUrl: 'https://i.pravatar.cc/150?img=13',
                  ),
                ],
              ),
            ),
          );
        },
      ),

          // Pagination Footer
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('แสดง 3 จาก 124 คน', style: TextStyle(color: Colors.black54, fontSize: 13)),
                Row(
                  children: [
                    _buildPageButton(Icons.chevron_left),
                    const SizedBox(width: 8),
                    _buildPageButton(Icons.chevron_right),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.black87 : Colors.black54,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTableHeader(String title, {required int flex, bool alignRight = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        title,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1),
      ),
    );
  }

  Widget _buildDriverRow({
    required String name,
    required String joined,
    required String id,
    required bool isOnDuty,
    required int trips,
    required double tripsProgress,
    required String rating,
    required String imageUrl,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(
        children: [
          // Profile
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(radius: 20, backgroundImage: NetworkImage(imageUrl)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(joined, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                )
              ],
            ),
          ),
          
          // ID
          Expanded(
            flex: 2,
            child: Text(id, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          
          // Status
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOnDuty ? const Color(0xFFE8F5E9) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: isOnDuty ? const Color(0xFF176a21) : Colors.grey.shade500,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnDuty ? 'กำลังวิ่ง' : 'พัก',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOnDuty ? const Color(0xFF176a21) : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Trips
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(trips.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: tripsProgress,
                      child: Container(decoration: BoxDecoration(color: const Color(0xFF176a21), borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          
          // Rating
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Text(rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 4),
                Icon(Icons.star, color: double.parse(rating) >= 4.5 ? const Color(0xFF176a21) : Colors.grey.shade400, size: 14),
              ],
            ),
          ),
          
          // Actions
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('ดูบันทึก', style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('แก้ไขข้อมูล', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.black54, size: 20),
    );
  }
}

class DriversAlertsRow extends StatelessWidget {
  const DriversAlertsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              Expanded(child: _buildAlertCard(Icons.verified, 'แจ้งเตือนใบอนุญาต', 'มีคนขับ 3 คนที่ใบอนุญาตจะหมดอายุในอีก 30 วัน โปรดดำเนินการ', 'ตรวจสอบวันหมดอายุ', const Color(0xFF00bcd4))),
              const SizedBox(width: 16),
              Expanded(child: _buildAlertCard(Icons.calendar_month, 'ตารางงานถัดไป', 'จัดตารางวันหยุดเสร็จสิ้น มีคนขับ 12 คนสำหรับรอบพิเศษเสาร์อาทิตย์นี้', 'ดูตารางงาน', const Color(0xFF176a21))),
              const SizedBox(width: 16),
              Expanded(child: _buildAlertCard(Icons.error_outline, 'รายงานอุบัติเหตุ', 'ไม่มีรายงานอุบัติเหตุรุนแรงในช่วง 24 ชั่วโมงที่ผ่านมา รักษามาตรฐานความปลอดภัยไว้', 'ดูบันทึกล่าสุด', Colors.redAccent)),
            ],
          );
        } else {
          return Column(
            children: [
              _buildAlertCard(Icons.verified, 'แจ้งเตือนใบอนุญาต', 'มีคนขับ 3 คนที่ใบอนุญาตจะหมดอายุในอีก 30 วัน โปรดดำเนินการ', 'ตรวจสอบวันหมดอายุ', const Color(0xFF00bcd4)),
              const SizedBox(height: 16),
              _buildAlertCard(Icons.calendar_month, 'ตารางงานถัดไป', 'จัดตารางวันหยุดเสร็จสิ้น มีคนขับ 12 คนสำหรับรอบพิเศษเสาร์อาทิตย์นี้', 'ดูตารางงาน', const Color(0xFF176a21)),
              const SizedBox(height: 16),
              _buildAlertCard(Icons.error_outline, 'รายงานอุบัติเหตุ', 'ไม่มีรายงานอุบัติเหตุรุนแรงในช่วง 24 ชั่วโมงที่ผ่านมา รักษามาตรฐานความปลอดภัยไว้', 'ดูบันทึกล่าสุด', Colors.redAccent),
            ],
          );
        }
      }
    );
  }

  Widget _buildAlertCard(IconData icon, String title, String description, String actionText, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(actionText, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward, color: color, size: 14),
            ],
          )
        ],
      ),
    );
  }
}
