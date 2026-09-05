import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_student_dialog.dart';
import 'add_student_dialog.dart';
import 'admin_profile_dialog.dart';
import '../../widgets/top_toast.dart';
import '../../widgets/app_loading_view.dart';

class AdminStudentsTab extends StatefulWidget {
  const AdminStudentsTab({super.key});

  @override
  State<AdminStudentsTab> createState() => _AdminStudentsTabState();
}

class _AdminStudentsTabState extends State<AdminStudentsTab> {
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
              'จัดการนักศึกษา',
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
              const StudentsTitleRow(),
              const SizedBox(height: 24),
              StudentsTableCard(
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
              Icons.school_rounded,
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
                'จัดการข้อมูลนักศึกษา',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF176a21),
                ),
              ),
              Text(
                'ระบบบัญชีผู้ใช้นักศึกษา ข้อมูลการลงทะเบียน และการเข้าใช้งาน',
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

class StudentsTitleRow extends StatelessWidget {
  const StudentsTitleRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รายชื่อนักศึกษาในระบบ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2923),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'จัดการข้อมูลนักศึกษาที่ลงทะเบียนใช้งานแอปพลิเคชัน PSRU Shuttle',
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
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'student')
                    .snapshots(),
                builder: (context, snapshot) {
                  int studentCount = 0;
                  if (snapshot.hasData) {
                    studentCount = snapshot.data!.docs.length;
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF176a21).withOpacity(0.15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF176a21).withOpacity(0.06),
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
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.groups_rounded,
                                color: Color(0xFF176a21),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'นักศึกษาทั้งหมด',
                                  style: TextStyle(
                                    color: Color(0xFF718076),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$studentCount คน',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF176a21),
                                  ),
                                ),
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
        );
      },
    );
  }
}

class StudentsTableCard extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const StudentsTableCard({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<StudentsTableCard> createState() => _StudentsTableCardState();
}

class _StudentsTableCardState extends State<StudentsTableCard> {
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

            // แถบค้นหาและปุ่มเพิ่มนักศึกษา
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
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
                          hintText: 'ค้นหาชื่อ, รหัสนักศึกษา, เบอร์โทร...',
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
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const AddStudentDialog(),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'เพิ่มนักศึกษา',
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
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEFF2F0)),

            // ตารางนักศึกษา
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'student')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: AppLoadingView(
                      message: 'กำลังโหลดข้อมูลนักศึกษา...',
                    ),
                  );
                }

                var docs = snapshot.hasData ? snapshot.data!.docs.toList() : [];

                if (widget.searchQuery.isNotEmpty) {
                  final q = widget.searchQuery.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name =
                        (data['name'] ?? '').toString().toLowerCase();
                    final studentId =
                        (data['student_id'] ?? '').toString().toLowerCase();
                    final phone =
                        (data['phone'] ?? '').toString().toLowerCase();
                    return name.contains(q) ||
                        studentId.contains(q) ||
                        phone.contains(q);
                  }).toList();
                }

                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final dateA = dataA['created_at'] as Timestamp?;
                  final dateB = dataB['created_at'] as Timestamp?;
                  if (dateA == null && dateB == null) return 0;
                  if (dateA == null) return 1;
                  if (dateB == null) return -1;
                  return dateB.compareTo(dateA);
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
                                Container(
                                  color: const Color(0xFFF8FAF9),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      _buildTableHeader('ข้อมูลนักศึกษา', flex: 4),
                                      _buildTableHeader('รหัสนักศึกษา', flex: 2),
                                      _buildTableHeader('เบอร์โทรศัพท์', flex: 2),
                                      _buildTableHeader('วันที่ลงทะเบียน', flex: 2),
                                      _buildTableHeader(
                                        'การจัดการ',
                                        flex: 2,
                                        alignRight: true,
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFEFF2F0),
                                ),
                                if (docs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(48.0),
                                    child: Center(
                                      child: Text(
                                        'ไม่พบข้อมูลนักศึกษาตามเงื่อนไข',
                                        style: TextStyle(
                                          color: Color(0xFF718076),
                                          fontSize: 14,
                                        ),
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
                                        joinedStr =
                                            '${date.day}/${date.month}/${date.year}';
                                      } catch (_) {}
                                    }

                                    final name = data['name'] ?? 'ไม่มีชื่อ';
                                    final id = data['student_id'] ?? 'N/A';
                                    final phone = data['phone'] ?? '-';
                                    final avatar = data['avatar'] ??
                                        'assets/images/man1.png';

                                    return _buildStudentRow(
                                      name: name,
                                      id: id,
                                      phone: phone,
                                      joined: joinedStr,
                                      avatar: avatar,
                                      onEdit: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) =>
                                              EditStudentDialog(
                                            docId: doc.id,
                                            studentData: data,
                                          ),
                                        );
                                      },
                                      onDelete: () {
                                        _confirmDeleteStudent(
                                          context,
                                          doc.id,
                                          name,
                                        );
                                      },
                                    );
                                  }),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 16.0,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFEFF2F0)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'แสดงนักศึกษาทั้งหมด ${docs.length} คน',
                            style: const TextStyle(
                              color: Color(0xFF718076),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
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
      ),
    );
  }

  void _confirmDeleteStudent(BuildContext context, String docId, String name) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text(
              'ยืนยันการลบนักศึกษา',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'คุณต้องการลบข้อมูลของ "$name" ใช่หรือไม่?\nการกระทำนี้ไม่สามารถย้อนกลับได้',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(docId)
                    .delete();
                if (mounted) {
                  TopToast.show(
                    this.context,
                    'ลบข้อมูลนักศึกษาเรียบร้อยแล้ว',
                    isError: false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  TopToast.show(
                    this.context,
                    'เกิดข้อผิดพลาดในการลบ: $e',
                    isError: true,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('ลบข้อมูล'),
          ),
        ],
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
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF5A605B),
        ),
      ),
    );
  }

  Widget _buildStudentRow({
    required String name,
    required String id,
    required String phone,
    required String joined,
    required String avatar,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    ImageProvider imageProvider;
    if (avatar.startsWith('http')) {
      imageProvider = NetworkImage(avatar);
    } else {
      imageProvider = AssetImage(avatar);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEFF2F0))),
      ),
      child: Row(
        children: [
          // โปรไฟล์
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF176a21).withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: imageProvider,
                    backgroundColor: const Color(0xFFE8F5E9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF1E2923),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // รหัสนักศึกษา
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF176a21).withOpacity(0.1),
                  ),
                ),
                child: Text(
                  id,
                  style: const TextStyle(
                    color: Color(0xFF176a21),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // เบอร์โทรศัพท์
          Expanded(
            flex: 2,
            child: Text(
              phone,
              style: const TextStyle(
                color: Color(0xFF5A605B),
                fontSize: 13,
              ),
            ),
          ),

          // วันที่ลงทะเบียน
          Expanded(
            flex: 2,
            child: Text(
              joined,
              style: const TextStyle(
                color: Color(0xFF718076),
                fontSize: 12.5,
              ),
            ),
          ),

          // การจัดการ
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    color: Color(0xFF176a21),
                    size: 22,
                  ),
                  tooltip: 'แก้ไข',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: 'ลบ',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
