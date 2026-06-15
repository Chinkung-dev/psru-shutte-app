import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key});

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  bool _isLoading = false;
  String _statusMessage = 'กดปุ่มด้านล่างเพื่ออัปโหลด 16 จุดจอดขึ้น Firebase';

  // ข้อมูล 16 จุด (เอาไว้ดันขึ้น Firebase แค่ครั้งเดียว)
  final List<Map<String, dynamic>> busStops = [
    {'stop_id': 'stop_01', 'name': 'อาคารทีปวิชญ์', 'lat': 16.828722, 'lng': 100.205001},
    {'stop_id': 'stop_02', 'name': 'หอประชุมศรีวชิรโชติ', 'lat': 16.829734, 'lng': 100.207205},
    {'stop_id': 'stop_03', 'name': 'ตึก IT', 'lat': 16.827511, 'lng': 100.206932},
    {'stop_id': 'stop_04', 'name': 'อาคารมหาวชิราลงกรณ', 'lat': 16.827641, 'lng': 100.209692},
    {'stop_id': 'stop_05', 'name': 'สระว่ายน้ำ มรพส.', 'lat': 16.828648, 'lng': 100.206653},
    {'stop_id': 'stop_06', 'name': 'อาคารหอสมุดอิเล็กทรอนิกส์', 'lat': 16.827896, 'lng': 100.206422},
    {'stop_id': 'stop_07', 'name': 'HUSO มะนุดพิบูล', 'lat': 16.826397, 'lng': 100.206634},
    {'stop_id': 'stop_08', 'name': 'อาคารพิบูลวิชญ์', 'lat': 16.828308, 'lng': 100.210770},
    {'stop_id': 'stop_09', 'name': 'คณะวิทยาการจัดการ', 'lat': 16.828270, 'lng': 100.211427},
    {'stop_id': 'stop_10', 'name': 'คณะวิทยาศาสตร์', 'lat': 16.827988, 'lng': 100.214270},
    {'stop_id': 'stop_11', 'name': 'ศูนย์อาหารทะเลแก้ว', 'lat': 16.826982, 'lng': 100.215864},
    {'stop_id': 'stop_12', 'name': 'หอพักทะเลแก้ว อาคาร 1', 'lat': 16.827084, 'lng': 100.216510},
    {'stop_id': 'stop_13', 'name': 'หอพักทะเลแก้ว อาคาร 2', 'lat': 16.826566, 'lng': 100.216625},
    {'stop_id': 'stop_14', 'name': 'หอพักทะเลแก้ว อาคาร 3', 'lat': 16.825799, 'lng': 100.216475},
    {'stop_id': 'stop_15', 'name': 'ศูนย์กีฬาในร่ม', 'lat': 16.826288, 'lng': 100.214313},
    {'stop_id': 'stop_16', 'name': 'คณะเทคโนโลยีการเกษตรและอาหาร', 'lat': 16.825385, 'lng': 100.212055},
  ];

  Future<void> migrateStopsToFirebase() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'กำลังอัปโหลด...';
    });

    final firestore = FirebaseFirestore.instance;
    int successCount = 0;

    try {
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
            )
          ],
        ),
      ),
    );
  }
}