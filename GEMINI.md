🚌 PSRU Shuttle App - Project Context

📌 Project Overview

โปรเจกต์นี้คือแอปพลิเคชันสำหรับติดตามและเรียกรถรับส่งภายในมหาวิทยาลัย (PSRU Shuttle Bus) พัฒนาด้วย Flutter และใช้ Firebase เป็น Backend หลัก
แอปแบ่งออกเป็น 2 ฝั่งคือ ฝั่งนักศึกษา (Student) และ ฝั่งคนขับรถ (Driver)

🛠️ Tech Stack & Packages

Framework: Flutter (Dart)

Backend: Firebase (Authentication, Cloud Firestore)

Map & Location: * flutter_map (สำหรับแสดงแผนที่ OpenStreetMap)

latlong2 (สำหรับจัดการพิกัด LatLng)

Utilities: intl (สำหรับจัดการฟอร์แมตเวลา)

📁 Project Structure (โครงสร้างไฟล์หลัก)

lib/route_data.dart: เก็บตัวแปร shuttleRoutes ซึ่งเป็น List<List<LatLng>> (แบ่งเป็น Segment) สำหรับใช้คำนวณเส้นทางและวาดถนน

lib/screens/register_screen.dart: หน้าสมัครสมาชิก มีให้เลือกสิทธิ์ (Role) ระหว่าง student และ driver พร้อมเลือกรูป Avatar

lib/screens/student/student_home.dart: หน้าหลักของนักศึกษา ประกอบด้วยแผนที่ (flutter_map), ระบบคำนวณเส้นทาง (Pathfinding), ระบบเรียกรถ (Ride Request), และ Bottom Navigation

lib/screens/student/student_chat_screen.dart: หน้าแชทแบบ Real-time ระหว่างนักศึกษาและคนขับ

⚙️ Core Logic & Algorithms (ลอจิกสำคัญของแอป)

ระบบแผนที่และเส้นทาง (Map & Pathfinding):

ใช้ Graph Algorithm ในการคำนวณเส้นทางจากจุดที่รถอยู่ ไปยัง "จุดจอดรถ" (_calculateHighlightedPath)

⚠️ กฎเหล็กของเส้นทาง: พิกัด LatLng ของจุดจอดรถใน Firestore จะต้องมีตัวเลขตรงกันเป๊ะ กับพิกัดที่แทรกไว้ใน lib/route_data.dart เพื่อให้อัลกอริทึมมองเห็นว่าเป็นจุดเดียวกันและสามารถลากเส้น Highlight ไปหยุดที่ป้ายได้พอดี

จุดตัด/ทางแยกใน route_data.dart หากพิกัดห่างกันไม่เกิน 20 เมตร ระบบจะสร้าง Graph เชื่อมต่อกันให้อัตโนมัติ (_buildRouteGraph)

ระบบ Real-time Sync (Firestore):

จุดจอดรถที่ชอบ (Favorite Stops): ใช้ snapshots().listen ฟังการเปลี่ยนแปลงของ favorite_stops ในคอลเล็กชัน users ของผู้ใช้ปัจจุบัน เพื่ออัปเดต UI ดาวสีเหลืองทันที

สถานะการเรียกรถ: ฟังการเปลี่ยนแปลงจากคอลเล็กชัน ride_requests เพื่อเช็คสถานะจาก waiting เป็น acknowledged

ระบบแชท: ใช้ StreamBuilder ฟังคอลเล็กชัน chats/shuttle_line_a/messages และจัดเรียงจากใหม่ไปเก่า (descending: true)

🎨 UI/UX & Design System (แนวทางการออกแบบ)

แอปพลิเคชันเน้นความสะอาดตา ทันสมัย และมีโค้งมน (Rounded UI)

Primary Color (สีหลัก): เขียวเข้ม #176a21 (ใช้กับปุ่มหลัก, เส้นทาง Highlight, ข้อความสำคัญ)

Secondary Color (สีรอง): เขียวอ่อน #9DF197 หรือ Gradient #67B26F ไป #4CA2CD

Background Color: สีเทาอ่อน #EFF1F2, #F0F2F5, หรือ #F7F9FA

Shapes: ใช้ BorderRadius.circular(16) ถึง 32 สำหรับกล่องโต้ตอบ, ปุ่ม, กล่องข้อความแชท และ Bottom Sheet

Map Lines: เส้นทางปกติใช้สีเขียวเข้มโปร่งใส 30% (Color(0xFF176a21).withOpacity(0.3)) เส้นทาง Highlight ใช้สีทึบ 100%

🤖 AI Coding Guidelines (คำแนะนำสำหรับผู้ช่วย AI)

เมื่อมีการขอให้เขียนโค้ดเพิ่ม หรือแก้ไขโค้ดในโปรเจกต์นี้ กรุณาปฏิบัติตามกฎดังต่อไปนี้:

รักษาโครงสร้างเดิม: หากมีการแก้ไขไฟล์ที่มีอยู่ ให้ส่งคืนโค้ดแบบเต็มไฟล์ (Full file context) หรือระบุจุดที่แก้ให้ชัดเจน เพื่อไม่ให้ระบบเดิมพัง

ไม่ใช้ Package เพิ่มเติมโดยไม่จำเป็น: ให้ใช้เครื่องมือที่มีอยู่แล้ว (เช่น flutter_map, latlong2, cloud_firestore) หลีกเลี่ยงการเพิ่ม Dependency ใหม่นอกจากผู้ใช้จะร้องขอ

การจัดการ Error: ในการดึงข้อมูลจาก Firestore หรือ Authentication ต้องมีบล็อก try-catch เสมอ

ความปลอดภัยของ UI: ตรวจสอบให้แน่ใจว่า Widget มีการเช็ค if (mounted) ก่อนเรียกใช้ setState() หรือ Navigator หลังจากการทำฟังก์ชัน Asynchronous (Future)

ภาษา: คอมเมนต์ในโค้ดและข้อความใน UI ควรเป็น "ภาษาไทย" เพื่อให้ตรงกับกลุ่มผู้ใช้งานเป้าหมาย