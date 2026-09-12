# รายงานผลการแก้ตำแหน่งโมเดล 3D กับป้ายรถไม่ตรงกัน

อัปเดต 2026-09-11 — สถานะ: แก้ไขโค้ดและผ่านการทดสอบ Regression Test ครบทุกข้อแล้ว (37/37 ผ่าน)

เอกสารนี้เป็นบันทึกสรุปผลการวิเคราะห์สาเหตุรากเหง้า การสร้างกรณีทดสอบจำลอง (Regression Tests) และการแก้ไขปัญหาใน `lib/widgets/shuttle_3d_layer.dart` อ้างอิงข้อกำหนดใน `AGENTS.md`, `docs/3d-shuttle-plan.md` และ `docs/3d-shuttle-setup.md`

## สรุปอาการและผลการวินิจฉัยสาเหตุ (Root Cause Analysis)

### อาการที่ 1: เลื่อนแผนที่แล้วโมเดลแกว่ง/คลาดเคลื่อน ไม่เกาะตำแหน่งตามป้าย Marker
- **สาเหตุรากเหง้า:** การคำนวณพิกัดหน้าจอของ MarkerLayer ทำงานแบบ Synchronous ภายในเฟรมเดียวกับที่ Flutter build/layout ขณะที่เดิม `_ShuttleSceneState.didUpdateWidget` เรียกเพียง `_syncVehicles()` เพื่อเพิ่ม/ลบโหนด แต่ **ไม่ได้คำนวณตำแหน่งพิกัดฉายภาพ** โค้ดเดิมรอให้ ThreeJS `Ticker(animate)` ทำงานในรอบ asynchronous ถัดไป ทำให้ตำแหน่งของโมเดล 3D ช้ากว่า Marker อยู่ 1-2 เฟรมเสมอ (Latency Lag)
- **ผลทดสอบจำลองก่อนแก้:** เมื่อรถหรือกล้องขยับในเฟรม rebuild โมเดล 3D คลาดเคลื่อนจาก Marker ถึง 134-202 พิกเซลในเฟรมเดียวกัน

### อาการที่ 2: คนขับเปลี่ยนสถานะคนนั่ง แล้วโมเดล 3D ค้างที่ตำแหน่งเดิม
- **สาเหตุรากเหง้า:**
  1. ใน `_ShuttleSceneState.build()` โค้ดเดิมเรียก `_engine.build()` ใหม่ทุกรอบ rebuild บน Flutter Web การเรียก `build()` ซ้ำทำให้คืนค่า `Builder` -> `HtmlElementView` ตัวใหม่ ซึ่งส่งผลกระทบต่อ identity ของ PlatformView/Canvas ทำให้ภาพค้างหรือตัดการเชื่อมต่อกับบริบท WebGL
  2. เมื่อคนขับอัปเดตสถานะรถ (เช่น available -> full) ข้อมูล `shuttles` ใน widget เปลี่ยน แต่ไม่ได้สั่งคำนวณพิกัดหน้าจอใหม่ในทันที

## รายละเอียดการแก้ไขโค้ด (Implementation)

แก้ไขใน [lib/widgets/shuttle_3d_layer.dart](file:///c:/psru-shutte-app/lib/widgets/shuttle_3d_layer.dart):

1. **การซิงก์ตำแหน่งในเฟรมเดียวกัน (Synchronous Projection Update):**
   - ใน `didUpdateWidget(oldWidget)` เรียก `_syncVehicles()` ตามด้วย `_update(0)` ทันที
   - อัปเดต `root.position` ของรถทุกคันและ projection matrix ของ OrthographicCamera ให้ตรงกับ snapshot พิกัดและมุมกล้องของ Flutter ปัจจุบันในเฟรมนั้นทันที โดยไม่ต้องรอรอบ Ticker ถัดไป
   - ตั้งชื่อโหนด `root.name = shuttle.id` เพื่อให้สามารถระบุและตรวจสอบตำแหน่งใน scene graph ได้อย่างแม่นยำ

2. **การรวมคิวเรนเดอร์ (Coalesced Frame Rendering):**
   - เพิ่มฟังก์ชัน `_renderFrame([double dt = 0])` พร้อม concurrency flags (`_rendering` และ `_renderRequested`)
   - ป้องกันการเรียก `_engine.render()` ซ้อนกันขณะเฟรมก่อนหน้ายังวาดไม่เสร็จ
   - หากมีการขอเรนเดอร์ใหม่ระหว่างที่กำลังเรนเดอร์อยู่ ระบบจะบันทึก `_renderRequested = true` และสั่งเรนเดอร์ต่อทันทีที่เฟรมปัจจุบันเสร็จสิ้น

3. **การรักษา PlatformView Identity (View Caching):**
   - เพิ่ม `Widget? _cachedEngineWidget` ใน `_ShuttleSceneState`
   - เมื่อกราฟิกพร้อม (`_ready == true` หลังการเรนเดอร์เฟรมแรกสำเร็จ) ระบบจะบันทึก widget ของ engine ไว้ใน `_cachedEngineWidget`
   - ในรอบ rebuild ถัดไป (เช่น คนขับเปลี่ยนสถานะ หรือกล้องขยับ) เมธอด `build()` จะส่งคืน `_cachedEngineWidget` เดิม ทำให้ Flutter ไม่ต้องทำลายหรือสร้าง DOM Canvas/PlatformView ใหม่ และไม่กระทบต่อ WebGL Context
   - หากเกิดข้อผิดพลาด (`_fail`) หรือล้างวิดเจ็ต (`dispose`) ระบบจะคืนค่า `_cachedEngineWidget = null`

4. **ความปลอดภัยในการ Dispose (Lifecycle Safety):**
   - ครอบ `try-catch` รอบการเรียก `_engine.dispose()` ใน `dispose()` ของ State เพื่อป้องกัน unhandled exception จาก native angle หรือ platform bindings ระหว่าง unmount
   - เพิ่มการตรวจสอบสถานะ `_GuardedThreeJS.isClosed` ก่อนโหลดหรือเพิ่ม asset เข้า scene

## หลักฐานการทดสอบ (Verification Evidence)

### 1. Regression Tests ใน `test/shuttle_3d_test.dart`
เพิ่มชุดทดสอบ 3 ข้อโดยใช้ `_FakeThreeJS` harness ที่จำลองการเรนเดอร์และพิกัดแผนที่จริง:
1. `Shuttle3DLayer: ตรวจสอบการซิงก์ตำแหน่งในเฟรมเดียวกันระหว่างโมเดล 3D และ Marker เมื่อรถขยับ`:
   - ผล: ผ่าน (ระยะห่างระหว่างจุดยึดโมเดล 3D กับ Marker < 3.0 พิกเซลในเฟรม rebuild เดียวกัน)
2. `Shuttle3DLayer: ตรวจสอบการซิงก์ตำแหน่งเมื่อเลื่อนกล้องแผนที่ (Camera Pan)`:
   - ผล: ผ่าน (โมเดลเกาะกับ Marker ทันทีเมื่อกล้องเลื่อน)
3. `Shuttle3DLayer: ไม่สร้าง widget engine build ซ้ำเมื่อ rebuild ด้วยสถานะเดิม`:
   - ผล: ผ่าน (`fakeEngine.buildCallCount` คงเดิม ไม่มีการสร้างต้นไม้วิดเจ็ตของ engine ซ้ำ)

### 2. ผลการรันชุดทดสอบทั้งหมด
- คำสั่ง: `flutter test --no-pub`
- ผลลัพธ์: **37/37 ผ่านทั้งหมด (100%)**
  - `test/review_fixes_test.dart` (REV-01 ถึง REV-06): ผ่านทั้งหมด
  - `test/shuttle_3d_test.dart` (Heading, Interpolation, Regression): ผ่านทั้งหมด 9 ข้อ
  - `test/stop_five_bypass_test.dart`: ผ่านทั้งหมด 10 ข้อ

### 3. Static Analysis
- คำสั่ง: `flutter analyze lib/widgets/shuttle_3d_layer.dart test/shuttle_3d_test.dart`
- ผลลัพธ์: **No issues found!** (0 errors, 0 warnings, 0 lints)

## สถานะปัจจุบันและการทดสอบเพิ่มเติมที่แนะนำ
- **สถานะ:** แก้ไขโค้ดและผ่านการทดสอบระดับ Unit/Widget Test ยืนยันพฤติกรรมแล้ว
- **ขั้นตอนถัดไปสำหรับการทดสอบบนเบราว์เซอร์และอุปกรณ์จริง:**
  - บน Chrome (`localhost:58071/#/studentHome`): ทดสอบเปิดโหมด 3D, ให้คนขับเปลี่ยนสถานะคนนั่ง (ว่าง/เต็ม/พัก) สังเกตว่าโมเดล 3D วิ่งตามป้าย Marker ต่อเนื่องโดยไม่ค้าง
  - บน Android Emulator: ทดสอบสลับแอปไป background และ resume กลับมาเพื่อยืนยันว่ากราฟิกยังฟื้นตัวได้ตาม REV-05/06
