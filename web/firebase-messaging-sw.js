importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.8.0/firebase-messaging-compat.js");

// Initialize the Firebase app in the service worker by passing in
// your app's Firebase config object.
// https://firebase.google.com/docs/web/setup#config-object
firebase.initializeApp({
  apiKey: "AIzaSyCh1GNCNtx08-sSX3FqtrCkr2bD2TgZdYY",
  authDomain: "psru-shuttle-app.firebaseapp.com",
  databaseURL: "https://psru-shuttle-app-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "psru-shuttle-app",
  storageBucket: "psru-shuttle-app.firebasestorage.app",
  messagingSenderId: "249582330017",
  appId: "1:249582330017:web:fe1453861a17eab4f7d0e0",
  measurementId: "G-09XSK0GZ57"
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

// Optional: Custom background message handler
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // Customize notification here if needed, but flutter_local_notifications will also try to handle it.
  // const notificationTitle = payload.notification.title;
  // const notificationOptions = {
  //   body: payload.notification.body,
  //   icon: '/icons/Icon-192.png'
  // };
  // self.registration.showNotification(notificationTitle, notificationOptions);
});
