const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

// 1. แจ้งเตือนเมื่อคนขับกดรับ (acknowledged)
exports.onRideRequestStatusChanged = functions.region("asia-southeast1").firestore
  .document("ride_requests/{requestId}")
  .onUpdate(async (change, context) => {
    const newData = change.after.data();
    const oldData = change.before.data();

    // เช็คว่าสถานะเปลี่ยนจาก waiting -> acknowledged
    if (oldData.status === "waiting" && newData.status === "acknowledged") {
      const studentUid = newData.student_uid;
      if (!studentUid) return null;

      try {
        const userDoc = await admin.firestore().collection("users").doc(studentUid).get();
        if (!userDoc.exists) return null;

        const fcmToken = userDoc.data().fcmToken;
        if (!fcmToken) return null;

        const message = {
          notification: {
            title: "รถรับทราบการเรียกแล้ว! 🚐",
            body: "คนขับกำลังเดินทางไปรับคุณที่ " + (newData.stop_name || "จุดจอด"),
          },
          token: fcmToken,
        };

        return admin.messaging().send(message);
      } catch (error) {
        console.error("Error sending push notification (acknowledged):", error);
      }
    }

    return null;
  });

// 2. แจ้งเตือนเมื่อมีข้อความแชทใหม่จากคนขับ
exports.onChatAdded = functions.region("asia-southeast1").firestore
  .document("chats/{lineId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();

    // ดักจับเฉพาะข้อความที่ส่งจากคนขับ
    if (message.senderRole === "driver") {
      try {
        // ส่งหานักศึกษาทุกคนที่มี FCM Token 
        // (ในสเกลใหญ่ควรระบุเฉพาะนักศึกษาที่รอรถ หรือ subscribe หัวข้อนั้นๆ แต่นี่คือวิธีแบบพื้นฐาน)
        const usersSnap = await admin.firestore().collection("users").where("role", "==", "student").get();
        const tokens = [];
        usersSnap.forEach(doc => {
          if (doc.data().fcmToken) {
            tokens.push(doc.data().fcmToken);
          }
        });

        if (tokens.length > 0) {
          const multicastMessage = {
            notification: {
              title: "ข้อความใหม่จากคนขับ 💬",
              body: message.text || "ตรวจสอบข้อความในแอป",
            },
            tokens: tokens,
          };
          // ส่งเป็น batch
          return admin.messaging().sendEachForMulticast(multicastMessage);
        }
      } catch (error) {
        console.error("Error sending chat push notification:", error);
      }
    }

    return null;
  });

// 3. แจ้งเตือนเมื่อมีการเปลี่ยนสถานะของรถ (ว่าง, เต็ม, พักเบรก, เลิกงาน)
exports.onShuttleStatusChanged = functions.region("asia-southeast1").database
  .ref('/shuttles/{shuttleId}')
  .onUpdate(async (change, context) => {
    const newData = change.after.val();
    const oldData = change.before.val();
    const shuttleId = context.params.shuttleId;

    // เช็คว่า passenger_status มีการเปลี่ยนแปลง
    if (newData.passenger_status && oldData.passenger_status !== newData.passenger_status) {
      let statusText = "";
      if (newData.passenger_status === "full") statusText = "ผู้โดยสารเต็มแล้ว";
      else if (newData.passenger_status === "empty") statusText = "รถว่าง พร้อมให้บริการ";
      else if (newData.passenger_status === "break") statusText = "พักเบรกชั่วคราว";
      else if (newData.passenger_status === "offline") statusText = "ออกเวร/เลิกงาน";
      else return null;

      // จัดฟอร์แมตชื่อรถ เช่น shuttle_line_a -> สาย A
      let shuttleName = shuttleId;
      if (shuttleId === "shuttle_line_a") shuttleName = "สาย A";
      else if (shuttleId === "shuttle_line_b") shuttleName = "สาย B";

      try {
        // ส่งแจ้งเตือนหานักศึกษาทั้งหมด
        const usersSnap = await admin.firestore().collection("users").where("role", "==", "student").get();
        const tokens = [];
        usersSnap.forEach(doc => {
          if (doc.data().fcmToken) {
            tokens.push(doc.data().fcmToken);
          }
        });

        if (tokens.length > 0) {
          const multicastMessage = {
            notification: {
              title: `อัปเดตสถานะรถ ${shuttleName} 🚌`,
              body: `ขณะนี้รถ ${statusText}`,
            },
            tokens: tokens,
          };
          return admin.messaging().sendEachForMulticast(multicastMessage);
        }
      } catch (error) {
        console.error("Error sending shuttle status push notification:", error);
      }
    }
    return null;
  });
