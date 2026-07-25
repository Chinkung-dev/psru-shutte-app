import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_student_dialog.dart';
import 'add_student_dialog.dart';
import '../../widgets/top_toast.dart';

class AdminStudentsTab extends StatefulWidget {
  const AdminStudentsTab({super.key});

  @override
  State<AdminStudentsTab> createState() => _AdminStudentsTabState();
}

class _AdminStudentsTabState extends State<AdminStudentsTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black87),
              title: const Text(
                'ศูนย์ควบคุม',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StudentsTitleRow(),
            const SizedBox(height: 24),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'ค้นหานักศึกษา, รหัสนักศึกษา...',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey.shade500,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Students Table
            StudentsTableCard(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }
}

class StudentsTitleRow extends StatelessWidget {
  const StudentsTitleRow({super.key});

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
                'ข้อมูลนักศึกษา',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'จัดการข้อมูลนักศึกษาที่ใช้บริการรถรับส่งของมหาวิทยาลัย',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'student')
              .snapshots(),
          builder: (context, snapshot) {
            String studentCount = '0';
            if (snapshot.hasData) {
              studentCount = snapshot.data!.docs.length.toString();
            }
            return _buildStatCard('นักศึกษาทั้งหมด', studentCount, '', true, icon: Icons.school_outlined);
          },
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    String trend,
    bool isPositive, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (trend.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  trend,
                  style: TextStyle(
                    color: isPositive ? const Color(0xFF176a21) : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
              if (icon != null) ...[
                const SizedBox(width: 16),
                Icon(icon, color: const Color(0xFF176a21), size: 28),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class StudentsTableCard extends StatefulWidget {
  final String searchQuery;
  const StudentsTableCard({super.key, required this.searchQuery});

  @override
  State<StudentsTableCard> createState() => _StudentsTableCardState();
}

class _StudentsTableCardState extends State<StudentsTableCard> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Actions (If any needed in future, left blank for now)
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                 const Text(
                  'รายชื่อนักศึกษา',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AddStudentDialog(),
                    );
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text(
                    'เพิ่มนักศึกษา',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Content
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'student')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(64.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF176a21)),
                  ),
                );
              }

              var docs = snapshot.hasData ? snapshot.data!.docs.toList() : [];

              // Local Search Filtering
              if (widget.searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final studentId = (data['student_id'] ?? '').toString().toLowerCase();
                  final phone = (data['phone'] ?? '').toString().toLowerCase();
                  return name.contains(widget.searchQuery) ||
                         studentId.contains(widget.searchQuery) ||
                         phone.contains(widget.searchQuery);
                }).toList();
              }

              // Local Sorting by created_at (descending)
              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final dateA = dataA['created_at'] as Timestamp?;
                final dateB = dataB['created_at'] as Timestamp?;
                if (dateA == null && dateB == null) return 0;
                if (dateA == null) return 1;
                if (dateB == null) return -1;
                return dateB.compareTo(dateA); // descending
              });

              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: constraints.maxWidth > 800
                              ? constraints.maxWidth
                              : 800,
                          child: Column(
                            children: [
                              // Table Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade100,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildTableHeader('โปรไฟล์นักศึกษา', flex: 3),
                                    _buildTableHeader('รหัสนักศึกษา', flex: 2),
                                    _buildTableHeader('เบอร์โทรศัพท์', flex: 2),
                                    _buildTableHeader('วันที่สมัคร', flex: 2),
                                    _buildTableHeader('จัดการ', flex: 1, alignRight: true),
                                  ],
                                ),
                              ),

                              // Table Rows
                              if (docs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Center(
                                    child: Text(
                                      'ไม่มีข้อมูลนักศึกษา',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ),
                                )
                              else
                                ...docs.map((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  String joinedStr = 'N/A';
                                  if (data['created_at'] != null) {
                                    try {
                                      final date =
                                          (data['created_at'] as Timestamp)
                                              .toDate();
                                      joinedStr = '${date.day}/${date.month}/${date.year}';
                                    } catch (e) {}
                                  }

                                  final name = data['name'] ?? 'ไม่มีชื่อ';
                                  final id = data['student_id'] ?? 'N/A';
                                  final phone = data['phone'] ?? 'N/A';
                                  final imageUrl =
                                      data['avatar'] ??
                                      'assets/images/man1.png';

                                  return _buildStudentRow(
                                    name: name,
                                    id: id,
                                    phone: phone,
                                    joined: joinedStr,
                                    imageUrl: imageUrl,
                                    onEdit: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => EditStudentDialog(
                                          docId: doc.id,
                                          studentData: data,
                                        ),
                                      );
                                    },
                                    onDelete: () {
                                      _confirmDeleteStudent(context, doc.id, name);
                                    },
                                  );
                                }),
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
                        Text(
                          'แสดง ${docs.length} คน',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            _buildPageButton(Icons.chevron_left),
                            const SizedBox(width: 8),
                            _buildPageButton(Icons.chevron_right),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteStudent(BuildContext context, String docId, String name) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยืนยันการลบนักศึกษา'),
        content: Text('คุณต้องการลบข้อมูลของ $name ใช่หรือไม่? การกระทำนี้ไม่สามารถย้อนกลับได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await FirebaseFirestore.instance.collection('users').doc(docId).delete();
                if (mounted) {
                  TopToast.show(this.context, 'ลบข้อมูลนักศึกษาเรียบร้อยแล้ว', isError: false);
                }
              } catch (e) {
                if (mounted) {
                  TopToast.show(this.context, 'เกิดข้อผิดพลาดในการลบ: $e', isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบข้อมูล', style: TextStyle(color: Colors.white)),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Icon(icon, color: Colors.black54, size: 20),
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
        title.toUpperCase(),
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildStudentRow({
    required String name,
    required String id,
    required String phone,
    required String joined,
    required String imageUrl,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    ImageProvider imageProvider;
    if (imageUrl.startsWith('http')) {
      imageProvider = NetworkImage(imageUrl);
    } else {
      imageProvider = AssetImage(imageUrl);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // Profile
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(radius: 20, backgroundImage: imageProvider),
                const SizedBox(width: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // ID
          Expanded(
            flex: 2,
            child: Text(
              id,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),

          // Phone
          Expanded(
            flex: 2,
            child: Text(
              phone,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),

          // Joined Date
          Expanded(
            flex: 2,
            child: Text(
              joined,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),

          // Actions
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onEdit,
                  child: const Text(
                    'แก้ไข',
                    style: TextStyle(
                      color: Color(0xFF176a21),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDelete,
                  child: const Text(
                    'ลบ',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
