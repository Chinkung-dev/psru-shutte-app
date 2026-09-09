import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, set, update, remove, get, onDisconnect, goOffline, runTransaction } from 'firebase/database';
import assert from 'node:assert/strict';

let env;
const shuttle = (uid = 'driver-a') => ({
  driver_uid: uid, name: 'สาย 1', number: 'SH#01',
  lat: 16.83, lng: 100.21, status: 'online', passenger_status: 'available',
});
const db = (uid) => uid ? env.authenticatedContext(uid).database() : env.unauthenticatedContext().database();
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shuttle-security',
    database: { rules: await readFile(new URL('../../database.rules.json', import.meta.url), 'utf8') },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database()), {
      access: { admins: { admin: true } },
      shuttle_drivers: { shuttle_01: 'driver-a', shuttle_02: 'driver-b' },
      shuttles: { shuttle_01: shuttle(), shuttle_02: shuttle('driver-b') },
    });
  });
});

test('นักศึกษาอ่านรถได้ แต่แก้ GPS สถานะ และลบรถไม่ได้', async () => {
  const student = db('student');
  await assertSucceeds(get(ref(student, 'shuttles')));
  await assertFails(update(ref(student, 'shuttles/shuttle_01'), { lat: 0, status: 'offline' }));
  await assertFails(remove(ref(student, 'shuttles/shuttle_01')));
  await assertFails(remove(ref(student, 'shuttles')));
});
test('นักศึกษาสร้างรถหรือปลอม driver_uid เพื่อยึดรถไม่ได้', async () => {
  const student = db('student');
  await assertFails(set(ref(student, 'shuttles/new'), shuttle('student')));
  await assertFails(set(ref(student, 'shuttles/shuttle_01'), shuttle('student')));
  await env.withSecurityRulesDisabled(c => set(ref(c.database(), 'shuttles/shuttle_01/driver_uid'), 'student'));
  await assertFails(update(ref(student, 'shuttles/shuttle_01'), { lat: 1 }));
});
test('ผู้ไม่ล็อกอินอ่านหรือเขียนรถไม่ได้', async () => {
  await assertFails(get(ref(db(), 'shuttles')));
  await assertFails(set(ref(db(), 'shuttles/shuttle_01'), shuttle()));
});
test('คนขับอัปเดตได้เฉพาะคันที่แอดมินมอบหมาย', async () => {
  const driver = db('driver-a');
  await assertSucceeds(update(ref(driver, 'shuttles/shuttle_01'), { lat: 16.84, status: 'offline', last_updated: 1 }));
  await assertSucceeds(set(ref(driver, 'shuttles/shuttle_01/passenger_status'), 'full'));
  await assertFails(update(ref(driver, 'shuttles/shuttle_02'), { lat: 0 }));
  await assertFails(remove(ref(driver, 'shuttles/shuttle_01')));
  await assertFails(remove(ref(driver, 'shuttles/shuttle_01/driver_uid')));
  await assertFails(set(ref(driver, 'shuttles/shuttle_01/driver_uid'), 'student'));
});
test('คนขับสร้างข้อมูลรถที่ได้รับมอบหมายครั้งแรกได้', async () => {
  await env.withSecurityRulesDisabled(c => remove(ref(c.database(), 'shuttles/shuttle_01')));
  await assertSucceeds(set(ref(db('driver-a'), 'shuttles/shuttle_01'), shuttle()));
});
test('นักศึกษาและคนขับเพิ่มสิทธิ์ตนเองไม่ได้ แม้ส่งหลาย path พร้อมกัน', async () => {
  for (const uid of ['student', 'driver-a']) {
    const client = db(uid);
    await assertFails(set(ref(client, `access/admins/${uid}`), true));
    await assertFails(set(ref(client, 'shuttle_drivers/shuttle_02'), uid));
    await assertFails(update(ref(client), { 'shuttle_drivers/shuttle_02': uid, 'shuttles/shuttle_02': shuttle(uid) }));
  }
});
test('แอดมินมอบหมายและถอนสิทธิ์ได้ แต่สร้างแอดมินผ่าน client ไม่ได้', async () => {
  const admin = db('admin');
  await assertSucceeds(set(ref(admin, 'shuttle_drivers/shuttle_01'), 'driver-b'));
  await assertFails(update(ref(db('driver-a'), 'shuttles/shuttle_01'), { status: 'online' }));
  await assertSucceeds(set(ref(db('driver-b'), 'shuttles/shuttle_01'), shuttle('driver-b')));
  await assertSucceeds(remove(ref(admin, 'shuttle_drivers/shuttle_01')));
  await assertFails(update(ref(db('driver-b'), 'shuttles/shuttle_01'), { lat: 0 }));
  await assertSucceeds(remove(ref(admin, 'shuttles/shuttle_01')));
  await assertFails(set(ref(admin, 'access/admins/student'), true));
});
test('onDisconnect ของคนขับยังตั้ง offline ได้', async () => {
  const driver = db('driver-a');
  await assertSucceeds(onDisconnect(ref(driver, 'shuttles/shuttle_01/status')).set('offline'));
  goOffline(driver);
  await env.withSecurityRulesDisabled(async c => {
    for (let attempt = 0; attempt < 30; attempt++) {
      if ((await get(ref(c.database(), 'shuttles/shuttle_01/status'))).val() === 'offline') return;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('สถานะไม่เปลี่ยนเป็น offline');
  });
});
test('ธุรกรรมมอบหมายรถไม่ทับเจ้าของอื่น และถอนเฉพาะสิทธิ์คนขับที่เลือก', async () => {
  const admin = db('admin');
  const assign = uid => runTransaction(ref(admin, 'shuttle_drivers/shuttle_01'), owner => {
    if (owner !== null && owner !== uid) return;
    return uid;
  });
  assert.equal((await assign('driver-b')).committed, false);
  const result = await runTransaction(ref(admin, 'shuttle_drivers'), value => {
    if (value === null) return null;
    return Object.fromEntries(Object.entries(value).filter(([, uid]) => uid !== 'driver-a'));
  });
  assert.equal(result.committed, true);
  assert.equal((await get(ref(admin, 'shuttle_drivers/shuttle_02'))).val(), 'driver-b');
  assert.equal((await assign('driver-b')).committed, true);
  assert.equal((await assign('driver-b')).committed, true);
});
test('เขียน GPS และ heartbeat หลาย path ของรถตนเองได้ แต่แนบรถอื่นไม่ได้', async () => {
  const driver = db('driver-a');
  await assertSucceeds(update(ref(driver), {
    'shuttles/shuttle_01/lat': 16.84,
    'shuttles/shuttle_01/last_updated': 123,
  }));
  await assertFails(update(ref(driver), {
    'shuttles/shuttle_01/lat': 16.85,
    'shuttles/shuttle_02/lat': 16.85,
  }));
});
test('ปฏิเสธพิกัดและสถานะที่ไม่ถูกต้อง', async () => {
  const driver = db('driver-a');
  await assertFails(set(ref(driver, 'shuttles/shuttle_01/lat'), 91));
  await assertFails(set(ref(driver, 'shuttles/shuttle_01/lng'), '100.21'));
  await assertFails(set(ref(driver, 'shuttles/shuttle_01/status'), 'admin'));
});
test('role หรืออีเมลแอดมินใน token ไม่ใช่สิทธิ์มอบหมายรถ', async () => {
  const client = env.authenticatedContext('student', {
    role: 'admin', email: 'admin-shuttle@gmail.com', email_verified: true,
  }).database();
  await assertFails(set(ref(client, 'shuttle_drivers/shuttle_01'), 'student'));
  await assertFails(set(ref(client, 'shuttles/shuttle_01'), shuttle('student')));
});
