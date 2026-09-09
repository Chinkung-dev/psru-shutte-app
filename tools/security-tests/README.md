# ทดสอบสิทธิ์ Realtime Database

ต้องมี Node.js และ Java 21 ขึ้นไปใน PATH จากโฟลเดอร์นี้รัน:

```powershell
npm ci
npm test
```

ใช้เฉพาะ Database Emulator ที่ 127.0.0.1:9000 และโปรเจกต์จำลอง
`demo-shuttle-security` ไม่ใช้ข้อมูลหรือบัญชี Firebase จริง
การทดสอบอ่าน `database.rules.json` ของโปรเจกต์โดยตรง

ครอบคลุมบัญชีนักศึกษา ผู้ไม่ล็อกอิน คนขับเจ้าของรถ คนขับคันอื่น
แอดมิน การสร้างรถครั้งแรก การปลอมเจ้าของ การยกระดับสิทธิ์
การถอนสิทธิ์ และ onDisconnect
