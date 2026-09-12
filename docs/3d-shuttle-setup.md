# คู่มือการติดตั้งและใช้งานระบบโมเดลรถรับส่ง 3D (PSRU 3D Shuttle Guide)

สถานะล่าสุด 2026-09-11: พบปัญหาโมเดลกับป้ายรถแยกตำแหน่งและโมเดลค้างหลังเปลี่ยนสถานะ ยังอยู่ระหว่างวิเคราะห์ อ่าน [บันทึกส่งต่องาน](3d-shuttle-handoff.md) สำหรับ patch ที่ค้าง วิธีทดสอบต่อ และคำสั่งรัน Android ARM64 ที่แก้ปัญหา APK ขาด `libflutter.so`

เอกสารนี้อธิบายรายละเอียดโครงสร้างโมเดล 3D, การติดตั้ง, การคำนวณทิศทาง, การเรนเดอร์ร่วมกับ flutter_map และแนวทางทดสอบบนแต่ละแพลตฟอร์ม

---

## 1. ข้อมูลจำเพาะของโมเดล (Model Specifications)

โมเดลรถรับส่งจำลองจากรูปทรงรถราง/รถกอล์ฟไฟฟ้าของมหาวิทยาลัยราชภัฏพิบูลสงคราม:

| รายการ | รายละเอียด |
| --- | --- |
| ไฟล์โมเดลปลายทาง | `assets/models/psru_shuttle.glb` |
| ไฟล์ต้นฉบับ Blender | `tools/3d-shuttle/psru_shuttle.blend` |
| สคริปต์สร้างอัตโนมัติ | `tools/3d-shuttle/build_model.py` |
| จำนวนรูปทรงสามเหลี่ยม (Triangles) | 7,988 triangles |
| จำนวนชิ้นส่วน (Meshes) | 8 meshes |
| จำนวนวัสดุ (Materials) | 8 materials (Ivory, PSRU Green, Glass, Rubber, Seat, Metal, Lamp, Red) |
| ขนาดไฟล์ GLB | ~414 KB (423,656 bytes) |
| ทิศทางใน GLB | -Z = ด้านหน้า (Forward), +Y = ด้านบน (Up) |
| จุดอ้างอิงตำแหน่ง (Origin) | กึ่งกลางฐานรถระดับพื้นดิน (Ground Centre) |

### สรุปการออกแบบรูปทรง
- ตัวถังสีขาวงาช้าง ขอบมน ทรงยาว
- แถบสีเขียวประจำมหาวิทยาลัย (สีใกล้เคียงต้นแบบ; สีวัสดุไม่ใช่ค่าสี badge แบบตรงตัว) และตัวอักษร "PSRU" บริเวณด้านหน้า ด้านข้าง และด้านหลัง
- ด้านข้างเปิดโล่งตามเอกลักษณ์รถรับส่ง พร้อมเสารองรับหลังคา ราวจับ และบันไดก้าวขึ้น
- เบาะผู้โดยสารสีดำหลายแถวภายในตัวรถ
- กระจกหน้าทรงโค้งขนาดใหญ่ โทนสีเข้ม พร้อมก้านที่ปัดน้ำฝน
- ล้อ 4 ล้อพร้อมยางสีดำและดุมล้อโลหะสีเงิน

---

## 2. วิธีการสร้างหรือปรับแต่งโมเดลใหม่ (Rebuilding the Model)

หากต้องการปรับขนาด สัดส่วน หรือแก้ไขรายละเอียด สามารถรันสคริปต์ Blender 5.x ได้โดยตรง:

```bash
blender --background --factory-startup --python tools/3d-shuttle/build_model.py
```

สคริปต์จะทำการ:
1. สร้างโครงสร้างตัวรถ เบาะ ล้อ หลังคา และตัวหนังสือ
2. ปรับ Bevel และวัสดุ Principled BSDF
3. บันทึกเป็น `tools/3d-shuttle/psru_shuttle.blend`
4. ส่งออก (Export) เป็น `assets/models/psru_shuttle.glb` โดยอัตโนมัติ

---

## 3. สถาปัตยกรรมการเรนเดอร์ (Rendering Architecture)

### 3.1 การแชร์ Geometry และ Material (Shared Geometry Instance)
เพื่อป้องกันปัญหาการใช้หน่วยความจำเกินขนาดเมื่อมีรถวิ่งพร้อมกันหลายคันบนแผนที่:
- โมเดล GLB จะถูกโหลดเข้าหน่วยความจำเพียงครั้งเดียวเป็นแม่แบบ (`_template`)
- ฟังก์ชัน `_instance()` ใน `lib/widgets/shuttle_3d_layer.dart` จะสร้าง `Mesh` โหนดใหม่ที่มี `position`, `quaternion`, และ `scale` แยกของตนเอง แต่ **แชร์ `geometry` และ `material` เดิมจากแม่แบบ** ช่วยประหยัดหน่วยความจำของ buffer; โหนดและ state ยังเพิ่มต่อคัน และ draw call ยังเพิ่มตามจำนวนรถ/mesh ที่มองเห็น (ไม่ได้ใช้ GPU InstancedMesh)

### 3.2 การแปลงพิกัดและมุมมอง (Projection & Tilt)

อัปเดต 2026-09-12: ปรับขนาดโมเดลตาม zoom แบบมีขอบเขต ที่ zoom ≤15.8 ใช้ 50% ของขนาดเดิม เพิ่มต่อเนื่องจนถึง 100% ที่ zoom ≥18 และไม่โตเกินขนาดเดิม โดยย่อเฉพาะโมเดลไม่ย่อป้ายข้อความ ลด AmbientLight จาก 1.6 เป็น 0.65 และ DirectionalLight จาก 2.2 เป็น 1.1 เพื่อลดตัวถังขาวจ้าและเพิ่มความต่างของด้านรับแสงกับด้านเงา ยังรอตรวจภาพหลังปรับบน Web/Android ของผู้ใช้ ต้องปิด–เปิดโหมด 3D หลัง Hot Reload เพื่อสร้างแสงใน scene ใหม่
- ใช้กล้องแบบ `OrthographicCamera` ที่มีสเกล 1:1 พิกเซลตามขนาดหน้าจอของแผนที่
- แปลงพิกัดทางภูมิศาสตร์ `LatLng` เป็นพิกัดหน้าจอด้วย `camera.latLngToScreenOffset()`
- ตัวรถถูกเอียงมุมมอง Top-down Isometric (เอียงแกน X ประมาณ 36 องศา หรือ `math.pi / 5`) เพื่อให้มองเห็นมิติความลึก ด้านข้าง และเบาะผู้โดยสาร
- การหมุนทิศทางของรถถูกชดเชยการบิดมุมมองของกล้องด้วยสูตรตรีโกณมิติ เพื่อให้หัวรถสัมพันธ์กับทิศ GPS บนแผนที่; ต้องตรวจภาพจริงหลายมุมและเมื่อหมุนแผนที่ก่อนยืนยันผล

### 3.3 การจัดการ Lifecycle และการประหยัดพลังงาน
- **TickerMode:** เมื่อผู้ใช้สลับแท็บจากหน้าแผนที่ไปยังหน้าอื่น (เช่น Live Status, ข้อมูลส่วนตัว) โค้ดตั้ง `visible=false` เพื่อข้ามการ render; ยังต้องวัด lifecycle และการใช้พลังงานบนอุปกรณ์จริง
- **AppLifecycleState:** เมื่อแอปพลิเคชันพับลงเบื้องหลัง (Background) ตัวเรนเดอร์ 3D จะหยุดการทำงานอัตโนมัติผ่าน `WidgetsBindingObserver`

---

## 4. ระบบคำนวณและกรองทิศทาง (Heading Tracker)

ไฟล์ `lib/services/shuttle_heading.dart` มีการทำงานหลักดังนี้:

1. **`shuttleBearing(from, to)`:** คำนวณมุมแบริ่งระหว่างพิกัด GPS สองจุด
2. **`shortestHeadingDelta(from, to)`:** คำนวณมุมหมุนที่สั้นที่สุด เพื่อให้รถหมุนนุ่มนวล ไม่หมุนวนรอบตัวเองเมื่อข้ามทิศเหนือ (เช่น 359° ไป 1° หมุน +2°)
3. **`ShuttleHeadingTracker`:**
   - สะสมระยะทางอย่างน้อย 4 เมตรก่อนเปลี่ยนทิศทาง เพื่อป้องกัน GPS noise รบกวน
   - เมื่อพิกัดเดิมหรือ noise อยู่ในเกณฑ์ 4 เมตร จะรักษามุมล่าสุด; GPS noise ที่มากกว่านี้ยังทำให้ทิศเปลี่ยนได้
   - ปฏิเสธพิกัดกระโดดผิดปกติ (เช่น กระโดดไกลเกินความเร็วรถที่เป็นไปได้)
   - รีเซ็ตจุดอ้างอิงใหม่หากการเชื่อมต่อขาดหายไปนานกว่า 30 วินาที

---

## 5. ป้ายกำกับ 2D และระบบสำรอง (Badge & Fallback)

ไฟล์ `lib/widgets/shuttle_map_badge.dart`:
- แสดงหมายเลขรถและสถานะ ("ว่าง", "เต็ม", "พัก", "ออฟไลน์") ในลักษณะ Flutter Widget 2D
- ป้ายจะตั้งตรงอ่านได้เสมอ (Upright Label) ไม่หมุนเอียงตามตัวรถ 3D
- **Fallback Marker:** หากเกิดข้อผิดพลาดในการโหลดโมเดล 3D หรืออุปกรณ์ไม่รองรับ WebGL/ANGLE แสดงไอคอนรถ 2D สำรองพร้อมป้ายสถานะ ระหว่างโหลดจน render เฟรมแรกสำเร็จ หรือเมื่อพบ error/เกินเวลาเริ่ม 20 วินาที; การตรวจ GPU context loss และการเรียกรถระหว่าง fallback ยังต้องทดสอบจริง

---

## 6. แนวทางการเปิดใช้งานและทดสอบ

### ในหน้าจอหลักนักศึกษา (Student Home)
- มีปุ่มแคปซูล `2D / 3D` ในแถบหัวหน้าจอ ใช้กรอบขาวขอบเขียวให้เข้ากับหน้าล็อกอิน โหมดที่เลือกเป็นพื้นเขียวเข้ม พื้นที่กดสูงอย่างน้อย 48 พิกเซล มี tooltip และสถานะ selected สำหรับตัวอ่านหน้าจอ กดโหมดเดิมไม่สร้าง renderer ใหม่
- ค่าเริ่มต้นปิด (`SHUTTLE_3D=false`) เพื่อให้ทดลองก่อนใช้เป็นค่าเริ่มต้น; ปุ่มยังไม่บันทึกการตั้งค่าข้ามการเปิดแอป
- หากต้องการเปิดตั้งแต่เริ่ม build ให้เพิ่ม `--dart-define=SHUTTLE_3D=true`
- สามารถกดสลับเปิด/ปิด เพื่อดูความแตกต่างระหว่างหมุด 2D ปกติและโมเดล 3D ได้ทันที

### ในหน้าจอทดสอบ (Phase 1/2 PoC Screen)
- เข้าผ่านปุ่ม `"ทดสอบ 3D"` ที่มุมบนขวาของหน้าล็อกอิน หรือเข้าผ่าน route `'/shuttle3DPoc'`
- มีปุ่มจำลองการวิ่งของรถตามถนนจริง ปุ่มปรับทิศทาง ปุ่มสลับสถานะ และปุ่มโหมด Wireframe

## 7. คำสั่งสำหรับเครื่อง Windows นี้

### อัปเดต 2026-09-12: ค้างโลโก้เมื่อเริ่มผ่าน IDE debugger

ตรวจ Medium Phone API 37.1 / emulator-5554: APK โหลด `libflutter.so` สำเร็จ แต่การเริ่มจาก IDE ด้วย `--start-paused` ค้างหน้าโลโก้และยังไม่พบ VM Service ใน log ของ process นั้น ทดลอง force-stop เฉพาะแอปแล้วเปิด APK เดิมด้วย `adb shell am start -n com.example.psru_shuttle_app/.MainActivity` โดยไม่ส่งตัวเลือก debugger พบ VM Service, Firebase เริ่มสำเร็จ และตรวจภาพถึงหน้า Login แล้ว (`build/psru-startup-check.png` เป็นหลักฐานชั่วคราว ไม่ได้ commit)

ผลนี้แยกได้ว่า APK และ Emulator ชุดนี้เปิดหน้า Login ได้โดยไม่ต้องเปลี่ยนรุ่นหรือปิด Impeller แต่ยังไม่ยืนยันต้นเหตุภายใน IDE/debugger หรือ breakpoint/Hot Reload ให้ใช้ Run ปกติสำหรับทดสอบ UI และตรวจการ attach debugger แยกต่างหาก ไม่ถือว่าการเห็น process หรือข้อความ Firebase เพียงอย่างเดียวคือผ่านการตรวจภาพ ไม่มีการแก้ source ในการทดลองนี้

### อัปเดต 2026-09-11: แก้ Run/Debug จาก Android Studio แล้วแอปเด้ง

พบ APK ไม่มี `libflutter.so` เพราะแอปกำหนด ABI เป็น ARM64 และตัด x86_64 ออก แต่ Flutter เลือก engine ตาม emulator x86_64 การ build ผ่านจึงยังเปิดไม่ได้ แก้ `android/build.gradle.kts` ให้กำหนด property `target-platform=android-arm64` ของ subproject `app` ก่อน Flutter Gradle plugin เลือก engine ให้ตรงกับ ABI ที่แพ็ก

ทดสอบ `flutter build apk --debug --target-platform android-x64 -t lib/main.dart --no-pub` ผ่าน (จำลอง target ที่ IDE ส่ง) ตรวจ ZIP พบ `lib/arm64-v8a/libflutter.so` ติดตั้งทับโดยเก็บข้อมูลและเปิดบน Pixel_10_Pro / emulator-5554 สำเร็จ พบ process แอป, Dart VM Service และ `Firebase Initialized Successfully` ยังไม่ได้ตรวจ breakpoint/Hot Reload ผ่าน UI ของ Android Studio ในรอบนี้

ให้หยุด Run เดิมแล้ว Run/Debug ใหม่ได้ ต้องใช้ emulator ที่รองรับ ARM translation หรืออุปกรณ์ ARM64 จริง การกำหนดนี้มีผลกับ Android build ทุกโหมดตามข้อจำกัด ARM64 เดิม หากรองรับ ABI อื่นในอนาคต ให้ทบทวน property นี้ร่วมกับ `abiFilters` และรายการ excludes ผลนี้ยืนยันการเริ่มแอป ไม่ใช่ผลทดสอบซิงก์ตำแหน่ง 3D

รันจากรากโปรเจกต์ `C:/psru-shutte-app` ใน PowerShell:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python tools/3d-shuttle/build_model.py
flutter pub get
flutter test --no-pub
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8091
```

หาก wrapper `flutter.bat` ค้าง ให้ใช้ Flutter SDK ที่ติดตั้งโดยตรง พร้อม package configuration ของ Flutter tools (จำเป็นสำหรับ debug web server):

```powershell
& C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe --packages=C:/src/flutter/packages/flutter_tools/.dart_tool/package_config.json C:/src/flutter/bin/cache/flutter_tools.snapshot run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 8091
```

เปิด `http://127.0.0.1:8091` แล้วกด "ทดสอบ 3D" บนหน้า Login การเปิด hash route โดยตรงอาจถูกขั้นตอน Splash/ตรวจ session พากลับหน้า Login ต้องเห็นทั้งข้อความ "โหลดโมเดล GLB แล้ว" และตัวรถจริง ไม่ใช้เพียงข้อความเป็นหลักฐานว่าภาพถูกต้อง

หากต้องการทดสอบเฉพาะโมเดลด้วยข้อมูลจำลองโดยไม่เริ่ม Firebase ใช้ entrypoint แยก:

```powershell
flutter run -t lib/shuttle_3d_preview.dart -d chrome
flutter build web --no-pub --no-wasm-dry-run -t lib/shuttle_3d_preview.dart --output build/shuttle-preview
```

สคริปต์ Blender จะเขียนทับ GLB, `.blend`, `model_stats.json` และภาพ preview 4 มุม ควรเก็บการแก้ด้วยมือใน `.blend` อีกชื่อก่อนรันสคริปต์ใหม่ ไฟล์ฉากมีพื้น/กล้อง/ไฟสำหรับ preview แต่ GLB ส่งออกเฉพาะตัวรถ

ไฟล์ `web/gles_bindings.js` ถูกบรรจุใน repo แล้ว ต้องใช้คู่กับรุ่น `flutter_angle` ใน lockfile และทดสอบอีกครั้งหากอัปเดตแพ็กเกจ ไม่จำเป็นต้องเพิ่มสิทธิ์ AR/กล้อง/ไมโครโฟนสำหรับฟีเจอร์นี้

## 8. ผลตรวจที่ยืนยันได้และสิ่งที่ยังต้องตรวจ

- Blender 5.2.1 LTS สร้าง GLB 423,656 bytes / 7,988 triangles / 8 meshes / 8 materials และตรวจภาพ 4 มุมแล้ว
- `flutter test --no-pub`: ผ่าน 16 ข้อ (heading/badge 6, stop-five bypass 10)
- `flutter analyze --no-pub` เฉพาะ 4 โมดูล 3D (layer, badge, heading, PoC): No issues found; `student_home.dart` ยังมี lint เดิมของหน้าจอ
- `flutter build web --no-pub --no-wasm-dry-run`: release build ของแอปหลักผ่าน การ build ผ่านไม่เท่ากับผ่านการตรวจภาพบนอุปกรณ์
- พรีวิวแยก `lib/shuttle_3d_preview.dart` คอมไพล์ Web release ผ่านเช่นกัน
- ตรวจภาพ Web release ของแอปหลักใน Codex In-app Browser บน Windows ขนาด 1280×720: โหลด GLB แสดงรถ 2 คันบนพื้นโปร่งใสได้, หมุนรถ 0° → 45° แล้วเห็นมุมโมเดลเปลี่ยน, เปลี่ยนสถานะว่าง → เต็มโดยป้ายตั้งตรง, แตะป้าย 2 ได้ และสลับเป็นไอคอนสำรองได้ ผลนี้ไม่ใช่ Android หรือการวัด FPS
- เว็บ debug ในการตรวจรอบนี้ค้างระหว่างโหลด DDC modules จึงใช้ release build ตรวจภาพ ส่วน console release มีคำเตือนขนาด PlatformView จากแพ็กเกจ (ใช้ 100% โดยปริยาย) ยังต้องตรวจ resize เพิ่ม
- การกรอง GPS ใน `ShuttleHeadingTracker` มีผลต่อทิศเท่านั้น การขยับตำแหน่งยังใช้ระบบเดิม
- ตรวจภาพบน Android Emulator (Pixel_9 / API 37): build APK ผ่าน `flutter build apk --debug --target-platform android-arm64 -t lib/shuttle_3d_preview.dart --no-pub` สำเร็จ, แก้ไข guard ขนาดเริ่มต้น 0x0 แล้ว, โมเดล 3D GLB เรนเดอร์บน OpenStreetMap พร้อมป้าย 2D ชัดเจน, ทดสอบรถวิ่งเลี้ยวตามทาง สลับหมุดสำรอง และโหมด Wireframe ผ่านการตรวจภาพบนหน้าจอเรียบร้อย
- ยังไม่มีผลวัด FPS/memory บนอุปกรณ์จริง Android (ทดสอบบน Emulator แบบ ARM translation) และไม่มีผลทดสอบ iOS ห้ามใช้ผล unit tests เป็นหลักฐานความพร้อมของ GPU renderer
- ต้องตรวจรถ 1/5/10 คัน, pan/zoom/rotation/resize, ป้ายซ้อนกัน, loading failure, context loss, background/resume และเข้าออกหน้าซ้ำก่อนเปิดใช้เป็นค่าเริ่มต้น
