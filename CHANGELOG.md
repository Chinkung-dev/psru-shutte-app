# 📝 PSRU Shuttle App - Changelog / Progress

ไฟล์นี้ใช้สำหรับบันทึกความคืบหน้าของการพัฒนาโปรเจกต์ ว่ามีการทำระบบอะไรไปแล้วบ้าง เพื่อให้ง่ายต่อการติดตามงาน

## 🚀 ฟีเจอร์ที่พัฒนาเสร็จแล้ว (Completed Features)

### 🔐 ระบบบัญชีและการยืนยันตัวตน (Authentication)
- [x] ออกแบบและสร้างหน้า Login / Register
- [x] ระบบสมัครสมาชิกแบ่งตาม Role (`student` และ `driver`)
- [x] หน้าสมัครสมาชิกของคนขับ สามารถเลือกรถรับส่งที่ตัวเองรับผิดชอบได้
- [x] เชื่อมต่อ Firebase Authentication (Email/Password)
- [x] บันทึกข้อมูลผู้ใช้ลง Firestore (`users` collection)
- [x] ระบบ Logout สำหรับทั้งนักศึกษาและคนขับ

### 🧑‍🎓 ฝั่งนักศึกษา (Student)
- [x] **หน้า Home (Map):** แสดงแผนที่โดยใช้ `flutter_map` และ OpenStreetMap
- [x] **ระบบเส้นทาง (Pathfinding):** แสดงเส้นทางเดินรถและ Highlight เส้นทางไปยังจุดจอดที่เลือก (คำนวณจาก Graph)
- [x] **ระบบค้นหาจุดจอดรถ:** มีช่องค้นหาและแสดงรายการจุดจอด พร้อมการจัดเรียง (จุดที่ชอบขึ้นก่อน)
- [x] **ระบบเรียกรถ (Ride Request):** กด "แจ้งรอรถที่จุดนี้" สถานะจะเด้งไปหาคนขับแบบ Real-time และรอคนขับกดรับทราบ
- [x] **จุดจอดที่ชอบ (Favorite Stops):** กดติดดาวจุดจอดที่ใช้บ่อยได้ และบันทึกลง Firestore
- [x] **หน้าโปรไฟล์ (Profile):** แสดงข้อมูลส่วนตัว, รหัสนักศึกษา, และลิงก์ไปยังหน้าจัดการจุดจอดที่ใช้บ่อย
- [x] **หน้าแชท (Chat):** พัฒนาระบบแชท Real-time คุยกับคนขับรถประจำสายผ่าน Firestore (สร้างหน้า `StudentChatListScreen` และ `StudentChatScreen`)
- [x] **ระบบติดตามรถทุกคันแบบ Live & แสดงสถานะสีรถ:** ติดตามพิกัดรถทุกคันแบบ Real-time พร้อมอนิเมชันเคลื่อนที่นุ่มนวล และระบบกรองรถค้าง (Timeout Filter) ป้องกันการแสดงหมุดรถที่หลุดการเชื่อมต่อหรือไม่อัปเดตพิกัดเกิน 3 นาที
- [x] **ระบบคำนวณเวลาถึงโดยประมาณ (ETA):** ค้นหาตำแหน่งรถคันที่อยู่ใกล้ป้ายที่สุด แล้วคำนวณเส้นทางและเวลาถึงป้ายแสดงผลบนจอ

### 🚌 ฝั่งคนขับรถ (Driver)
- [x] **หน้า Home (Map):** แสดงแผนที่และตำแหน่งของตัวเอง
- [x] **ระบบเข้างาน/เลิกงาน (Online/Offline):** ดึงพิกัด GPS อัตโนมัติ (Geolocator) พร้อมระบบ Heartbeat บันทึกเวลาล่าสุดทุก 30 วินาทีลง Firestore เพื่อป้องกันรถหายจากจอตอนจอดนิ่ง
- [x] **ระบบรับแจ้งเตือนจากนักศึกษา:** มี Popup แจ้งเตือนเมื่อนักศึกษากดเรียกรถ และมีปุ่ม "รับทราบ" 
- [x] **หน้าสถานะรถ (Update Status):** อัปเดตสถานะที่นั่ง (ว่าง, เต็ม, พัก, เลิกงาน) แบบ Real-time ไปที่คอลเล็กชัน `shuttles` พร้อมอัปเดตสี/แสงหมุดตำแหน่งรถตามสถานะแบบ Real-time
- [x] **หน้าโปรไฟล์ (Profile):** แสดงข้อมูลคนขับรถ, หมายเลขรถที่รับผิดชอบ, สถิติการวิ่งรถ และปุ่มออกจากระบบ
- [x] **ระบบแชทกับนักศึกษา (Driver Chat):** เพิ่มแท็บแชท (`DriverChatScreen`) เพื่ออ่านและตอบกลับนักศึกษาแบบ Real-time ตามห้องแชทรถตัวเอง
- [x] **ระบบล็อกหมุดไม่ให้ออกนอกเส้นทาง (Snap to Route):** อัลกอริทึมคำนวณระยะห่างระหว่างพิกัด GPS จริงกับเส้นถนนในมหาลัย (`shuttleRoutes`) เพื่อดึงพิกัดหมุดให้อยู่บนเส้นทางเสมอ ป้องกันหมุดกระโดดออกนอกถนนหรือพิกัดเพี้ยน
- [x] **ระบบประหยัดแบตเตอรี่และโควตา (Throttling & Distance Filter):** กรองการอัปเดต GPS เมื่อรถขยับเกิน 3 เมตร และจำกัดการส่งข้อมูลขึ้น Firestore ทุกๆ 3 วินาที
- [x] **ระบบแจ้งเตือนด้วยเสียงจุดจอด Custom (Audio Alerts by Stop ID):** ปิดการทำงานของเสียงพูด AI (`flutter_tts`) และเปลี่ยนมาใช้แพ็กเกจ `audioplayers` เพื่อเปิดไฟล์เสียงจริงจาก Assets โฟลเดอร์ `lib/screens/voice/voice_stop_XX.mp3` ครบทั้ง 21 จุดจอด โดยระบบจะจับคู่ชื่อป้ายกับรหัส `stop_id` แล้วเล่นไฟล์เสียงพร้อมระบบสั่นเตือนและ Ringtone ทันทีเมื่อมีนักศึกษาเรียกรถ

### 🗄️ ฐานข้อมูลและโครงสร้าง (Database & Architecture)
- [x] ออกแบบ Schema ฐานข้อมูลใน Firestore (`DATABASE.md`)
- [x] จัดการเชื่อมระบบพิกัดรถและสถานะรถจาก `buses` เดิม ย้ายไปรวมที่คอลเล็กชัน `shuttles` เพื่อให้ตรงกับข้อมูลที่ลงทะเบียนไว้
- [x] โครงสร้างไฟล์แยกส่วนชัดเจน (screens, role-based folders, utils)

---

## 🧠 อธิบาย Logic สำคัญของระบบ (Core Technical Logic & Algorithms)

### 1. ⏱️ ระบบคำนวณเวลาถึงโดยประมาณ (ETA - Estimated Time of Arrival & Graph Pathfinding)
* **ไฟล์หลัก:** [student_home.dart](file:///c:/psru-shutte-app/lib/screens/student/student_home.dart) (ฟังก์ชัน `_updateRouteAndETA`, `_calculateHighlightedPath`, `_buildRouteEtaBadge` และ `_getPathMidpoint`)
* **โครงสร้างและขั้นตอนการทำงานเชิงลึก (Deep Technical Architecture):**
  1. **การคัดเลือกรถรับส่งคันที่ใกล้ที่สุด (Nearest Active Shuttle Selection):**
     เมื่อนักศึกษาแตะเลือกจุดจอดรถเป้าหมาย (`endLoc`) ระบบจะวนลูปตรวจสอบรถรับส่งทุกคันใน `activeShuttles` ที่มีสถานะ `status == 'online'` โดยใช้คลาส `Distance()` ในการคำนวณระยะทางตรงทางภูมิศาสตร์ (Geodesic Distance / Great-Circle Distance) ระหว่างพิกัดรถ (`startLoc`) กับพิกัดป้าย เพื่อหา **รถคันที่อยู่ใกล้ที่สุด (`nearestShuttle`)** มาใช้เป็นจุดเริ่มต้นในการคำนวณเวลาถึงป้าย
  2. **การแปลงพิกัดเข้าสู่กราฟเครือข่ายถนน (Map Matching to Graph Nodes):**
     เนื่องจากพิกัด GPS ของรถและจุดจอดอาจไม่อยู่บนจุดยอดของกราฟพอดี ฟังก์ชัน `_getClosestNode(LatLng target)` จะทำหน้าที่ค้นหาจุดโหนด (`Node`) บนเครือข่ายถนน (`_routeGraph`) ที่มีระยะห่างน้อยที่สุด เพื่อให้ได้จุดเริ่มต้นของกราฟ (`startNode`) และจุดปลายทางของกราฟ (`endNode`)
  3. **การค้นหาเส้นทางที่สั้นที่สุดด้วย Dijkstra's Algorithm (`Graph Pathfinding Algorithm`):**
     ระบบเครือข่ายถนนในมหาวิทยาลัยถูกสร้างเป็น **Adjacency List (`_routeGraph`)** จากพิกัดใน [route_data.dart](file:///c:/psru-shutte-app/lib/route_data.dart) โดยเชื่อมต่อจุดตัดที่มีระยะห่างไม่เกิน 20 เมตร ฟังก์ชัน `_calculateHighlightedPath` จะทำงานโดย:
     - กำหนดเซต `unvisited` เก็บโหนดทั้งหมด และตั้งค่า `distances[startNode] = 0` (โหนดอื่นเป็น $\infty$)
     - วนลูปเลือกโหนด `current` จาก `unvisited` ที่มีค่า `distances[node]` น้อยที่สุดจนกระทั่งถึง `endNode`
     - คำนวณระยะทางสะสมของเพื่อนบ้าน (`neighbor`): $\text{alt} = \text{distances}[\text{current}] + \text{Distance}(\text{current}, \text{neighbor})$ หาก $\text{alt} < \text{distances}[\text{neighbor}]$ ระบบจะอัปเดตระยะทางสั้นที่สุด พร้อมบันทึกเส้นทางย้อนกลับ (`previous[neighbor] = current`) เพื่อย้อนรอยนำมาสร้างเส้นสีเขียวเข้มไฮไลท์บนแผนที่จริง
  4. **สูตรคำนวณระยะทางจริงตามแนวถนน (Precise Road Distance Computation):**
     ระยะทางรวม (`totalMeters`) ไม่ใช่การวัดเส้นตรง แต่เป็นการรวมระยะทางจริงตามแนวโค้งถนน 3 ส่วนเข้าด้วยกัน:
     $$\text{Total Meters} = \text{Dist}(\text{startLoc}, \text{startNode}) + \text{distances}[\text{endNode}] + \text{Dist}(\text{endNode}, \text{endLoc})$$
  5. **สูตรทางคณิตศาสตร์ในการคำนวณเวลา (ETA Mathematical Formula):**
     ความเร็วเฉลี่ยของรถรับส่งในมหาวิทยาลัยราชภัฏพิบูลสงคราม (`speed`) ถูกกำหนดไว้ที่ **`7.0` เมตร/วินาที (ประมาณ 25.2 กม./ชม.)** ซึ่งเป็นความเร็วที่สะท้อนการวิ่งจริงเมื่อรวมการชะลอตามทางแยกและป้ายต่างๆ และระบบได้บวก **เวลาบัฟเฟอร์เผื่อหยุดรับส่งและชะลอทางแยกอีก `15.0` วินาที** ป้องกันการแสดงเวลาเร็วเกินจริง:
     $$\text{Estimated Seconds} = \left( \frac{\text{totalMeters}}{7.0} \right) + 15.0$$
  6. **การแสดงผลอัจฉริยะแบบ 3 ระดับ (Adaptive UI Presentation Level):**
     - **ระดับที่ 1 ($\text{totalMeters} \le 30 \text{ เมตร}$):** แสดงข้อความ **"รถกำลังจะถึงป้าย"** (Arriving Now) เพื่อให้นักศึกษาสตาร์ทเตรียมตัวขึ้นรถ
     - **ระดับที่ 2 ($\text{Seconds} \le 60 \text{ วินาที}$):** แสดงข้อความ **"ประมาณ 1 นาที (`X` ม.)"** พร้อมระบุระยะทางเมตรจริง
     - **ระดับที่ 3 ($\text{Seconds} > 60 \text{ วินาที}$):** ปัดเศษวินาทีเป็นนาทีด้วยฟังก์ชัน `ceil()` (`(sec / 60).ceil()`) แสดงข้อความ **"ประมาณ `M` นาที (`X` ม.)"**
     - **การแสดงป้ายข้อความบนแผนที่ (`Midpoint Floating Badge`):** ฟังก์ชัน `_getPathMidpoint()` จะคำนวณหาจุดกึ่งกลางของเส้นทางไฮไลท์ (`highlightedPath`) เพื่อวางวิดเจ็ต `_buildRouteEtaBadge` (ป้ายสีเขียวเข้มพร้อมไอคอนนาฬิกาจับเวลา) ลอยอยู่เหนือกลางถนนบนแผนที่อย่างแม่นยำและสวยงาม

### 2. 💬 ระบบแชทสื่อสารแบบ Real-time (Role-based Real-time Chat)
* **ไฟล์หลัก:** [student_chat_screen.dart](file:///c:/psru-shutte-app/lib/screens/student/student_chat_screen.dart) และ [driver_chat_screen.dart](file:///c:/psru-shutte-app/lib/screens/driver/driver_chat_screen.dart)
* **การทำงาน:**
  1. **แยกห้องสนทนาตามรถแต่ละคัน (Channel Isolation):** ระบบเก็บข้อมูลใน Firestore ภายใต้ Path `chats/{shuttle_id}/messages` โดย `shuttle_id` คือ ID ของรถคันนั้นๆ (เช่น `shuttle_line_a`) ทำให้นักศึกษากับคนขับรถสายเดียวกันสื่อสารกันได้ถูกคัน
  2. **การอัปเดตข้อความแบบ Real-time:** ทั้งสองฝั่งใช้ `StreamBuilder` ในการดึงข้อมูลและฟังเหตุการณ์เปลี่ยนแปลงจาก Collection `messages` เรียงลำดับตามเวลาล่าสุด (`descending: true`) ข้อความใหม่จะปรากฏบนจอทั้งสองฝั่งทันทีโดยไม่ต้องกดรีเฟรช
  3. **การระบุตัวตน (Role Identification):** ตอนส่งข้อความจะมีการบันทึกฟิลด์ `senderRole` (`student` หรือ `driver`) เพื่อจัดรูปแบบบับเบิลข้อความบน UI (ข้อความของตัวเองแสดงฝั่งขวาพื้นสีเขียวเข้ม #176a21 ส่วนคู่สนทนาแสดงฝั่งซ้ายพื้นสีขาว)

### 3. 📍 ระบบล็อกหมุดไม่ให้ออกนอกเส้นทาง (Snap to Route Algorithm & Mathematical Map Matching)
* **ไฟล์หลัก:** [driver_home.dart](file:///c:/psru-shutte-app/lib/screens/driver/driver_home.dart) (ฟังก์ชัน `_snapToRoute` และ `_markerAnimationController`)
* **โครงสร้างทางคณิตศาสตร์และขั้นตอนการทำงานเชิงลึก (Mathematical & Algorithmic Architecture):**
  1. **ปัญหาพิกัดเพี้ยนและการลอยของหมุด (GPS Drift & Multipath Error Mitigation):**
     สัญญาณ GPS จากมือถือของคนขับมักเกิดการสะท้อนกับอาคารเรียน ต้นไม้ใหญ่ หรือสูญเสียความแม่นยำในบางช่วง (Drift) ส่งผลให้หมุดรถรับส่งบนแผนที่เกิดอาการกระโดดเข้าไปในตัวอาคาร ลอยอยู่กลางสนามหญ้า หรือออกนอกเส้นทางถนน เพื่อแก้ปัญหานี้ ฟังก์ชัน `_snapToRoute(LatLng rawPoint)` จึงถูกสร้างขึ้นเพื่อทำหน้าที่ **Map Matching** บังคับให้หมุดรถเกาะอยู่บนกึ่งกลางถนนจริงเสมอ
  2. **การแปลงข้อมูลเส้นทางเป็นส่วนของเส้นตรง (Polyline Vector Segments):**
     ระบบนำเข้าพิกัดเส้นทางเดินรถทั้งหมด (`shuttleRoutes`) จาก [route_data.dart](file:///c:/psru-shutte-app/lib/route_data.dart) ซึ่งประกอบด้วยเส้นทางย่อย (Segments) เชื่อมต่อระหว่างจุดยอด $A = (a_x, a_y)$ (`routeSegment[i]`) และจุดยอด $B = (b_x, b_y)$ (`routeSegment[i+1]`)
  3. **คณิตศาสตร์การฉายจุดตั้งฉากลงบนเวกเตอร์ (Vector Orthogonal Projection via Dot Product):**
     เมื่อได้รับพิกัด GPS ดิบ $P = (p_x, p_y)$ ระบบจะคำนวณหาจุดตั้งฉาก $C = (c_x, c_y)$ บนส่วนของเส้นตรง $AB$ โดยเริ่มจากการหาเวกเตอร์ $\vec{AB} = (b_x - a_x, b_y - a_y)$ และเวกเตอร์ $\vec{AP} = (p_x - a_x, p_y - a_y)$ แล้วคำนวณค่าพารามิเตอร์เชิงสเกลาร์ $t$ (Normalized Projection Parameter) ผ่านผลคูณจุด (Dot Product):
     $$t = \frac{\vec{AP} \cdot \vec{AB}}{|\vec{AB}|^2} = \frac{(p_x - a_x)(b_x - a_x) + (p_y - a_y)(b_y - a_y)}{(b_x - a_x)^2 + (b_y - a_y)^2}$$
  4. **การตรวจสอบขอบเขตและยึดจุดปลายทาง (Segment Bounds Clamping):**
     - หาก $t < 0$ แสดงว่าจุดฉายตั้งฉากหลุดออกไปทางฝั่งจุดเริ่มต้น ระบบจะบีบจุดให้อยู่ที่ $C = A$ ($t = 0$)
     - หาก $t > 1$ แสดงว่าจุดฉายตั้งฉากหลุดออกไปทางฝั่งจุดปลาย ระบบจะบีบจุดให้อยู่ที่ $C = B$ ($t = 1$)
     - หาก $0 \le t \le 1$ แสดงว่าจุดฉายตกอยู่บนเส้นตรงระหว่าง $A$ และ $B$ พอดี ระบบจะคำนวณพิกัดตั้งฉากบนถนนจริง:
       $$C = \left( a_x + t(b_x - a_x), \; a_y + t(b_y - a_y) \right)$$
  5. **การหาระยะห่างที่สั้นที่สุดและการขยับหมุดอย่างนุ่มนวล (Minimum Euclidean Distance & Smooth Interpolation):**
     ระบบคำนวณระยะห่างกำลังสอง (Squared Euclidean Distance: $D^2 = (p_x - c_x)^2 + (p_y - c_y)^2$) เปรียบเทียบกับทุกๆ Segment บนแผนที่ เพื่อเลือกจุด $C_{\text{min}}$ ที่ใกล้กับพิกัด GPS ดิบมากที่สุดมาเป็น `snappedPoint`
     หลังจากได้พิกัดบนเส้นถนนแล้ว แทนที่ระบบจะกระโดดเปลี่ยนตำแหน่งหมุดทันที ซึ่งจะทำให้หน้าจอกระตุก ระบบได้ใช้ **`AnimationController` (`Duration(milliseconds: 400)`) ร่วมกับ `Tween<LatLng>` และ `Curves.easeInOut`** เพื่อค่อยๆ เคลื่อนหมุดจากตำแหน่งเดิม (`_oldLocation`) ไปยังพิกัดใหม่บนเส้นถนนอย่างนุ่มนวลเป็นธรรมชาติ ทำให้ผู้โดยสารเห็นหมุดรถวิ่งเกาะตามโค้งถนนอย่างสมบูรณ์แบบและลื่นไหลไม่มีสะดุด

### 4. 🔊 ระบบเล่นไฟล์เสียงแจ้งเตือนจุดจอด (Custom Stop Audio Alert System)
* **ไฟล์หลัก:** [driver_home.dart](file:///c:/psru-shutte-app/lib/screens/driver/driver_home.dart) (ฟังก์ชัน `_triggerVoiceAlert` และ `_fetchStopsFromFirebase`) และโฟลเดอร์ไฟล์เสียง [lib/screens/voice](file:///c:/psru-shutte-app/lib/screens/voice)
* **การทำงาน:**
  1. **การโหลดและแมประหัสจุดจอด (`Stop ID Mapping`):** เมื่อคนขับเปิดแอป ระบบดึงข้อมูลจุดจอดจากคอลเล็กชัน `stops` ใน Firestore โดยจัดเก็บรหัส `id` (`stop_01` ถึง `stop_21`) ควบคู่กับชื่อป้ายรถไว้ใน List `busStops`
  2. **การตรวจจับคำขอเรียกรถ Real-time (`Request Stream Listener`):** ระบบฟังสถานะการเรียกรถที่มีค่า `status == 'waiting'` เมื่อพบเอกสารคำขอใหม่ (`currentRequestId != activeDoc.id`) ฟังก์ชัน `_triggerVoiceAlert(stopName)` จะถูกเรียกทำงานทันที
  3. **การแจ้งเตือนแบบ 3 ชั้น (`Multi-Layer Notification`):** ระบบจะทำงาน 3 ส่วนพร้อมกันเพื่อแจ้งเตือนคนขับอย่างชัดเจน:
     - **ระบบสั่น (`HapticFeedback.heavyImpact`):** สั่นเตือนแรงสุดสำหรับอุปกรณ์มือถือที่รองรับ
     - **เสียงแจ้งเตือนระบบ (`FlutterRingtonePlayer.playNotification`):** เล่นเสียง Ringtone หลักของมือถือ (ยกเว้นบน Web)
     - **เสียงจุดจอด Custom (`audioplayers`):** นำชื่อป้ายไปค้นหา `stop_id` แล้วใช้คำสั่ง `AudioPlayer().play(AssetSource('lib/screens/voice/voice_$stopId.mp3'))` เพื่อเปิดเสียงพูดชื่อจุดจอดจริงที่เตรียมไว้ครบทั้ง 21 จุดจอด

---

## ⏳ สิ่งที่ต้องทำต่อไป (To-Do / Upcoming)
- [ ] พัฒนาและเปิดใช้การแจ้งเตือนแบบ Push Notifications ผ่าน Firebase Cloud Messaging (FCM)
- [ ] เพิ่มระบบสถิติและประวัติการเดินทางของผู้โดยสาร (Ride History)
- [ ] ปรับปรุงหน้าแสดงตารางรอบการวิ่งรถประจำวันและช่วงเวลาให้บริการ (Shuttle Timetable)
