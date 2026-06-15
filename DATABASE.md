🗄️ Firestore Database Schema

เอกสารนี้ใช้อธิบายโครงสร้างฐานข้อมูล Firebase Cloud Firestore ของโปรเจกต์ PSRU Shuttle App เพื่อเป็นข้อมูลอ้างอิงสำหรับการเขียนโค้ด

1. Collection: users

เก็บข้อมูลโปรไฟล์ของผู้ใช้งานทั้งหมด ทั้งนักศึกษาและคนขับรถ

Document ID: ใช้ uid ที่ได้จาก Firebase Authentication

Fields:

uid (String): รหัสผู้ใช้ (ตรงกับ Document ID)

name (String): ชื่อ-นามสกุล

email (String): อีเมลที่ใช้สมัคร

role (String): สิทธิ์การใช้งาน มี 2 ค่าคือ "student" หรือ "driver"

student_id (String): รหัสนักศึกษา หรือ รหัสพนักงานขับรถ

avatar (String): Path รูปโปรไฟล์ เช่น "assets/images/man1.png"

favorite_stops (Array of Strings): [Optional] รายชื่อป้ายรถที่นักศึกษากดดาวไว้ เช่น ["อาคารทีปวิชญ์", "ตึก IT"]

created_at (Timestamp): เวลาที่สร้างบัญชี

2. Collection: stops

เก็บข้อมูลป้ายรถรับส่ง (Bus Stops) เพื่อใช้แสดงหมุดบนแผนที่

Document ID: Auto-generated

Fields:

name (String): ชื่อจุดจอดรถ เช่น "ตึก IT"

lat (Number/Double): ละติจูด เช่น 16.828722

lng (Number/Double): ลองจิจูด เช่น 100.205001

(หมายเหตุ: พิกัดที่เก็บในตารางนี้ ต้องตรงกับพิกัดในไฟล์ route_data.dart แบบ 100% เพื่อให้ระบบ Pathfinding ทำงานได้)

3. Collection: ride_requests

เก็บสถานะการกด "แจ้งรอรถ" ของนักศึกษา

Document ID: Auto-generated

Fields:

student_uid (String): UID ของนักศึกษาที่กดเรียก

stop_name (String): ชื่อป้ายที่นักศึกษายืนรอ

status (String): สถานะการเรียก มี 2 ค่าคือ:

"waiting": นักศึกษากำลังรอ (เพิ่งกดเรียก)

"acknowledged": คนขับรถรับทราบแล้ว (ระบบจะส่งแจ้งเตือนให้นักศึกษาและลบ Request นี้ทิ้ง)

timestamp (Timestamp): เวลาที่กดเรียก

4. Collection: chats

เก็บประวัติการแชท (แบ่งเป็นห้องตามสายรถ)

Document ID: รหัสสายรถ เช่น "shuttle_line_a"

Sub-collection: messages (เก็บข้อความในห้องแชทนั้นๆ)

Document ID (ใน messages): Auto-generated

Fields:

text (String): ข้อความที่พิมพ์

senderId (String): UID ของคนที่ส่งข้อความ (ใช้อ้างอิงว่าเป็นฝั่งเรา หรือฝั่งคนขับ)

timestamp (Timestamp): เวลาที่ส่งข้อความ (ใช้สำหรับเรียงลำดับในหน้าแชท)

5. Collection: active_buses (สำหรับอนาคต)

ใช้เก็บพิกัด Real-time ของรถที่กำลังวิ่งอยู่ (แอปฝั่งคนขับจะเป็นคนอัปเดตข้อมูลนี้)

Document ID: uid ของคนขับ หรือ รหัสรถ

Fields:

driver_uid (String): UID ของคนขับ

line (String): สายที่วิ่ง เช่น "A", "B"

lat (Number/Double): ละติจูดปัจจุบันของรถ

lng (Number/Double): ลองจิจูดปัจจุบันของรถ

last_updated (Timestamp): เวลาอัปเดตล่าสุด