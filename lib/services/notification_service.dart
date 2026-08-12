import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String webVapidKey =
      "BMR_2qBCeBxxVkw_oKoe-qsvM4Ni9YmQ_S8rP1SDZmqWMnxcpw9cwqSinzxBZjrRpLFxfohAe2Cz8ssVn99T1FI";

  Future<void> initialize() async {
    // 1. ขอสิทธิ์ (Permission) สำหรับ iOS/Web/Android 13+
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
    } else {
      debugPrint('User declined or has not accepted permission');
    }

    // 2. ตั้งค่าการแสดงผลแบบ Heads-up สำหรับ Apple (iOS/macOS)
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. ตั้งค่า Flutter Local Notifications สำหรับโชว์แจ้งเตือนตอนเปิดแอป (Foreground)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false);
    
    const InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS);

    await _localNotificationsPlugin.initialize(settings: initializationSettings);

    // 4. ดักจับเมื่อมีข้อความเข้าขณะเปิดแอป (Foreground Message)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
            'Message also contained a notification: ${message.notification}');
        _showLocalNotification(message);
      }
    });
  }

  // ฟังก์ชันดึง Token (และรีเฟรชถ้าหมดอายุ)
  Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        return await _firebaseMessaging.getToken(vapidKey: webVapidKey);
      } else {
        return await _firebaseMessaging.getToken();
      }
    } catch (e) {
      debugPrint("Error getting FCM Token: $e");
      return null;
    }
  }

  // ฟังก์ชันแสดงแจ้งเตือนผ่าน Local Notifications
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'psru_shuttle_high_importance_channel', // id
      'High Importance Notifications', // title
      channelDescription: 'This channel is used for important notifications.', // description
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _localNotificationsPlugin.show(
      id: message.notification.hashCode,
      title: message.notification?.title ?? '',
      body: message.notification?.body ?? '',
      notificationDetails: platformChannelSpecifics,
    );
  }
}
