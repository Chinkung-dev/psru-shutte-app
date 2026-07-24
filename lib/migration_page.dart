import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key});

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  bool _isLoading = false;
  String _statusMessage = 'กดปุ่มด้านล่างเพื่ออัปโหลด 23 จุดจอดขึ้น Firebase';

  // ข้อมูล 24 จุด (เอาไว้ดันขึ้น Firebase แค่ครั้งเดียว)
  final List<Map<String, dynamic>> busStops = [
    {
      'stop_id': 'stop_01',
      'name': 'หอพักทะเลแก้ว อาคาร 3',
      'lat': 16.825799,
      'lng': 100.216475,
      'order': 1,
    },
    {
      'stop_id': 'stop_02',
      'name': 'หอพักทะเลแก้ว อาคาร 2',
      'lat': 16.826566,
      'lng': 100.216625,
      'order': 2,
    },
    {
      'stop_id': 'stop_03',
      'name': 'หอพักทะเลแก้ว อาคาร 1',
      'lat': 16.827084,
      'lng': 100.216510,
      'order': 3,
    },
    {
      'stop_id': 'stop_04',
      'name': 'ศูนย์อาหารทะเลแก้ว',
      'lat': 16.826982,
      'lng': 100.215864,
      'order': 4,
    },
    {
      'stop_id': 'stop_05',
      'name': 'ศูนย์กีฬาในร่ม',
      'lat': 16.826288,
      'lng': 100.214313,
      'order': 5,
    },
    {
      'stop_id': 'stop_06',
      'name': 'คณะวิทยาศาสตร์',
      'lat': 16.827988,
      'lng': 100.214270,
      'order': 6,
    },
    {
      'stop_id': 'stop_07',
      'name': 'คณะวิทยาการจัดการ',
      'lat': 16.828599,
      'lng': 100.212165,
      'order': 7,
    },
    {
      'stop_id': 'stop_08',
      'name': 'อาคารพิบูลวิชญ์',
      'lat': 16.828308,
      'lng': 100.210770,
      'order': 8,
    },
    {
      'stop_id': 'stop_09',
      'name': 'คณะพยาบาลศาสตร์',
      'lat': 16.827549,
      'lng': 100.209783,
      'order': 9,
    },
    {
      'stop_id': 'stop_10',
      'name': 'คณะเทคโนโลยีการเกษตรและอาหาร',
      'lat': 16.825385,
      'lng': 100.212055,
      'order': 10,
    },
    {
      'stop_id': 'stop_11',
      'name': 'อาคารเกษตรและอาหาร',
      'lat': 16.82546539794387,
      'lng': 100.20745861926648,
      'order': 11,
    },
    {
      'stop_id': 'stop_12',
      'name': 'คณะมนุษยศาสตร์',
      'lat': 16.826352,
      'lng': 100.206594,
      'order': 12,
    },
    {
      'stop_id': 'stop_13',
      'name': '7-Eleven PSRU',
      'lat': 16.827362064109813,
      'lng': 100.20682525684464,
      'order': 13,
    },
    {
      'stop_id': 'stop_14',
      'name': 'สำนักวิทยบริการ',
      'lat': 16.827896,
      'lng': 100.206422,
      'order': 14,
    },
    {
      'stop_id': 'stop_15',
      'name': 'อาคารทีปวิชญ์',
      'lat': 16.828722,
      'lng': 100.205001,
      'order': 15,
    },
    {
      'stop_id': 'stop_16',
      'name': 'หอประชุมศรีวชิรโชติ',
      'lat': 16.829734,
      'lng': 100.207205,
      'order': 16,
    },
    {
      'stop_id': 'stop_17',
      'name': 'กองพัฒนานักศึกษา',
      'lat': 16.828648,
      'lng': 100.206653,
      'order': 17,
    },
    {
      'stop_id': 'stop_18',
      'name': 'ตึก IT ',
      'lat': 16.827511,
      'lng': 100.206932,
      'order': 18,
    },
    {
      'stop_id': 'stop_19',
      'name': 'คณะสังคมศาสตร์',
      'lat': 16.827639,
      'lng': 100.209708,
      'order': 19,
    },
    {
      'stop_id': 'stop_20',
      'name': 'คณะเทคโนโลยีอุตสาหกรรม',
      'lat': 16.835112,
      'lng': 100.213466,
      'order': 20,
    },
    {
      'stop_id': 'stop_21',
      'name': 'อาคารเครื่องกล',
      'lat': 16.835825276633656,
      'lng': 100.21420084713722,
      'order': 21,
    },
    {
      'stop_id': 'stop_22',
      'name': 'อัฒจรรย์ฝั่งไม่มีหลังคา',
      'lat': 16.832322,
      'lng': 100.213686,
      'order': 22,
    },
    {
      'stop_id': 'stop_23',
      'name': 'อาคารปฏิบัติการสาธารณสุขศาสตร์',
      'lat': 16.828487333453978,
      'lng': 100.21581287580348,
      'order': 23,
    },
  ];

  Future<void> migrateStopsToFirebase() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'กำลังลบข้อมูลจุดจอดเดิมในระบบ...';
    });

    final firestore = FirebaseFirestore.instance;

    try {
      final collection = firestore.collection('stops');

      // ลบข้อมูลเก่าทั้งหมดก่อน
      final snapshots = await collection.get();
      final batchDelete = firestore.batch();
      for (var doc in snapshots.docs) {
        batchDelete.delete(doc.reference);
      }
      await batchDelete.commit();

      setState(() {
        _statusMessage = 'กำลังอัปโหลดข้อมูลใหม่...';
      });

      // เพิ่มข้อมูลใหม่
      int successCount = 0;
      for (var stop in busStops) {
        await firestore.collection('stops').doc(stop['stop_id']).set(stop);
        successCount++;
      }

      setState(() {
        _statusMessage = '✅ อัปโหลดสำเร็จ $successCount จุดจอด!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('อัปโหลดข้อมูลชั่วคราว')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_upload, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            Text(_statusMessage, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 30),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: migrateStopsToFirebase,
                    child: const Text('1. เริ่มย้ายข้อมูลขึ้นคลาวด์'),
                  ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                // พอกดเสร็จ ให้เด้งกลับไปหน้า Login เพื่อเข้าระบบตามปกติ
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text('2. กลับไปหน้า Login'),
            ),
          ],
        ),
      ),
    );
  }
}
