import 'dart:async';
import 'dart:math' as math;
import '../../widgets/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // สำหรับเช็ค kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../route_data.dart';
import 'student_profile.dart';
import 'student_chat_list_screen.dart'; // Import หน้ารวมห้องแชท
import 'student_live_status_screen.dart'; // Import หน้า Live Status
import 'package:geolocator/geolocator.dart'; // เพิ่มเพื่อดึงตำแหน่งผู้ใช้

import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'student_chat_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  final Map<String, LatLng> _oldShuttleLocations = {};
  final Map<String, LatLng> _targetShuttleLocations = {};
  final Map<String, LatLng> _currentShuttleLocations = {};

  bool isWaiting = false;
  bool isAcknowledged = false; // เพิ่มสถานะเมื่อคนขับกดรับทราบแล้ว
  bool isOnBoard = false; // เพิ่มสถานะเมื่อนักศึกษาขึ้นรถแล้ว
  bool isCardMinimized = false; // ย่อการ์ดเหลือแค่ปุ่มเมื่อกดที่แผนที่
  bool _isAutoArriving = false; // เช็คว่ากำลังนับถอยหลังปิดงานออโต้หรือไม่
  bool _isTutorialCardHidden =
      false; // ซ่อนการ์ดระหว่าง Tutorial ขั้นตอนที่ 4 เพื่อให้เห็นจุดจอดบนแผนที่ชัดเจน
  String? selectedStopName;
  String? selectedDropOffName; // จุดลงรถ
  LatLng? selectedStopLatLng; // เก็บพิกัดป้ายที่เลือก
  String? estimatedArrivalText; // ข้อความแสดงเวลา ETA
  int? remainingStops; // เก็บจำนวนป้ายที่เหลือก่อนถึงจุดหมาย
  String?
  targetedShuttleId; // เก็บ ID ของรถคันที่ใกล้ที่สุดเพื่อส่งคำขอเจาะจง
  LatLng? _myLocation; // ตำแหน่งปัจจุบันของนักศึกษา
  StreamSubscription<Position>?
  _positionSubscription; // ฟังตำแหน่งแบบเรียลไทม์

  final MapController _mapController = MapController();

  final LatLng _psruCenter = const LatLng(16.83017, 100.21046);
  final LatLngBounds _psruBounds = LatLngBounds(
    const LatLng(16.81500, 100.19000),
    const LatLng(16.84500, 100.23000),
  );

  List<Map<String, dynamic>> activeShuttles =
      []; // เก็บรายการรถที่กำลังออนไลน์

  List<Map<String, dynamic>> busStops = [];
  bool _isLoadingStops = true;

  // จัดกลุ่มจุดจอดที่อยู่ใกล้กันให้แสดงเป็นหมุดเดียว
  final Map<String, List<String>> _groupedStops = {
    '7-Eleven PSRU และตึก IT': ['7-Eleven PSRU', 'ตึก IT '],
    'คณะสังคมศาสตร์ และคณะพยาบาลศาสตร์': ['คณะสังคมศาสตร์', 'คณะพยาบาลศาสตร์'],
  };

  // ข้อมูลจุดจอดสำหรับแสดงบนแผนที่ (ยุบรวมจุดที่จัดกลุ่มแล้ว)
  List<Map<String, dynamic>> get _visualStops {
    List<Map<String, dynamic>> result = [];
    Set<String> groupedNames = {};

    _groupedStops.forEach((groupName, memberNames) {
      var members = busStops
          .where((s) => memberNames.contains(s['name']))
          .toList();
      if (members.isNotEmpty) {
        double avgLat =
            members
                .map((e) => (e['lat'] is num ? (e['lat'] as num).toDouble() : (double.tryParse(e['lat'].toString()) ?? 0.0)))
                .reduce((a, b) => a + b) /
            members.length;
        double avgLng =
            members
                .map((e) => (e['lng'] is num ? (e['lng'] as num).toDouble() : (double.tryParse(e['lng'].toString()) ?? 0.0)))
                .reduce((a, b) => a + b) /
            members.length;
        result.add({
          'isGroup': true,
          'name': groupName,
          'lat': avgLat,
          'lng': avgLng,
          'members': members,
        });
        groupedNames.addAll(memberNames);
      }
    });

    for (var stop in busStops) {
      if (!groupedNames.contains(stop['name'])) {
        result.add(stop);
      }
    }
    return result;
  }

  String? activeRequestId;
  StreamSubscription<DocumentSnapshot>? requestSubscription;
  StreamSubscription<DocumentSnapshot>? userSubscription;
  StreamSubscription? shuttleSubscription; // เพิ่ม Subscription สำหรับฟังตำแหน่งรถ
  final List<StreamSubscription> _chatSubscriptions = []; // รายการ Subscription สำหรับฟังแชทรถทุกคัน
  Map<String, dynamic>? _incomingChatNotification;
  Timer? _chatNotificationTimer;
  final AudioPlayer _alertPlayer = AudioPlayer();

  // Tutorial GlobalKeys
  final GlobalKey keyStopMarker = GlobalKey();
  final GlobalKey keyCardTopSection = GlobalKey();
  final GlobalKey keyCardBottomSection = GlobalKey();
  final GlobalKey keySelectedStopMarker = GlobalKey();
  final GlobalKey keyMyLocationButton = GlobalKey();
  final GlobalKey keyMyLocationDot = GlobalKey();
  final GlobalKey keyBottomNav = GlobalKey();

  late TutorialCoachMark tutorialCoachMark;

  List<LatLng> highlightedPath = [];
  final Map<LatLng, List<LatLng>> _routeGraph = {};

  List<String> favoriteStops = [];
  bool _isAutoFollow = true; // ตัวแปรเช็คว่ากล้องติดตามเป้าหมายอยู่หรือไม่
  bool _isTutorialShowing =
      false; // ตัวแปรเช็คว่าอยู่ในขั้นตอนสอน Tutorial อยู่หรือไม่

  @override
  void initState() {
    super.initState();
    _fetchStopsFromFirebase();
    _listenToFavoriteStops();
    _buildRouteGraph();
    _listenToShuttles(); // เริ่มฟังตำแหน่งรถ
    _listenToAllChatMessages(); // เริ่มดักฟังข้อความแชทใหม่จากคนขับรถทุกคันแบบ Real-time
    _zoomToUserLocation(); // ดึงตำแหน่งผู้ใช้และซูมแผนที่

    // Setup animation controller for smooth marker movement (ตั้งเป็น 3200ms เพื่อให้สอดคล้องกับฝั่งคนขับที่ส่งข้อมูลทุก 3 วินาที ทำให้รถไหลลื่นตลอดเวลา)
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _markerAnimation =
        CurvedAnimation(
          parent: _markerAnimationController,
          curve: Curves
              .linear, // ใช้ linear เพื่อให้วิ่งต่อเนื่องแบบไม่กระตุกเมื่อรีเซ็ตบ่อยๆ
        )..addListener(() {
          if (mounted) {
            setState(() {
              for (var id in _targetShuttleLocations.keys) {
                final oldLoc = _oldShuttleLocations[id];
                final targetLoc = _targetShuttleLocations[id];
                if (oldLoc != null && targetLoc != null) {
                  final lat =
                      oldLoc.latitude +
                      (targetLoc.latitude - oldLoc.latitude) *
                          _markerAnimation.value;
                  final lng =
                      oldLoc.longitude +
                      (targetLoc.longitude - oldLoc.longitude) *
                          _markerAnimation.value;
                  _currentShuttleLocations[id] = LatLng(lat, lng);
                } else if (targetLoc != null) {
                  _currentShuttleLocations[id] = targetLoc;
                }
              }

              // ล็อกกล้องให้ตามรถที่เรานั่งอยู่ตลอดเวลา (Auto Follow)
              if (_isAutoFollow && isOnBoard && targetedShuttleId != null) {
                final loc = _currentShuttleLocations[targetedShuttleId];
                if (loc != null) {
                  _mapController.move(
                    loc,
                    _mapController.camera.zoom,
                  ); // ล็อกพิกัดแต่คงระดับการซูมไว้
                }
              }
            });
          }
        });
  }

  // ดึงตำแหน่งปัจจุบันของนักศึกษาแล้วซูมแผนที่ไป พร้อมติดตามแบบ Real-time
  Future<void> _zoomToUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      // 1. ดึงตำแหน่งล่าสุด (Last Known) เพื่อให้แอปโหลดตำแหน่งได้เร็วที่สุด (Instant Loading)
      Position? lastPosition;
      try {
        lastPosition = await Geolocator.getLastKnownPosition();
      } catch (e) {
        // Fallback for Web platform where getLastKnownPosition is unsupported
      }

      if (lastPosition != null && mounted) {
        final loc = LatLng(lastPosition.latitude, lastPosition.longitude);
        setState(() {
          _myLocation = loc;
        });
        _mapController.move(loc, 17.0);

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _checkAndShowTutorial();
        });
      }

      // 2. ฟังการอัปเดตตำแหน่งแบบเรียลไทม์
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5, // อัปเดตเมื่อขยับ 5 เมตรขึ้นไป
            ),
          ).listen((Position position) {
            if (mounted) {
              final loc = LatLng(position.latitude, position.longitude);
              setState(() {
                _myLocation = loc;
              });

              // หากไม่มี Last Known Position ค่อยซูมครั้งแรกที่นี่
              if (lastPosition == null) {
                _mapController.move(loc, 17.0);
                lastPosition = position;
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted) _checkAndShowTutorial();
                });
              }
            }
          });
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  // ฟังข้อความแชทใหม่จากคนขับรถทุกคันแบบ Real-time เพื่อส่งเสียงและแสดงป๊อปอัปแจ้งเตือน
  void _listenToAllChatMessages() {
    for (var sub in _chatSubscriptions) {
      sub.cancel();
    }
    _chatSubscriptions.clear();

    final String todayDate = DateFormat('yyyy_MM_dd').format(DateTime.now());
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // รวบรวมห้องแชทของรถทั้งหมดในระบบ
    final Set<String> roomIds = {
      'shuttle_01_$todayDate',
      'shuttle_02_$todayDate',
      'shuttle_03_$todayDate',
      'shuttle_04_$todayDate',
      'shuttle_05_$todayDate',
    };

    for (var shuttle in activeShuttles) {
      final sId = (shuttle['id'] ?? '').toString();
      final sName = (shuttle['name'] ?? '').toString();
      String cleanNum = sName.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.isEmpty && sId.isNotEmpty && !sId.startsWith('-')) {
        cleanNum = sId.replaceAll(RegExp(r'[^0-9]'), '');
      }
      if (cleanNum.isNotEmpty) {
        int numVal = int.tryParse(cleanNum) ?? 1;
        roomIds.add('shuttle_${numVal.toString().padLeft(2, '0')}_$todayDate');
      } else if (sId.isNotEmpty && !sId.startsWith('-')) {
        roomIds.add('${sId}_$todayDate');
      }
    }

    for (var roomId in roomIds) {
      bool isInitial = true;
      final sub = FirebaseFirestore.instance
          .collection('chats')
          .doc(roomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots()
          .listen((snapshot) {
        if (isInitial) {
          isInitial = false;
          return; // ข้ามข้อความเก่าที่โหลดมาตอนแรก
        }

        // หากกำลังเปิดอยู่ในหน้าแชท (แท็บ 2) ไม่ต้องแสดงป๊อปอัปบังหน้าจอ
        if (_selectedIndex == 2) return;

        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data == null) continue;

            final String senderRole =
                (data['sender_role'] ?? data['senderRole'] ?? '').toString();
            final String senderId =
                (data['sender_id'] ?? data['senderId'] ?? '').toString();

            // เช็คว่าเป็นข้อความจากคนขับ หรือไม่ใช่ตัวเอง
            if (senderId != currentUserId &&
                (senderRole == 'driver' || senderRole.isEmpty)) {
              final String senderName = (data['sender_name'] ??
                      data['senderName'] ??
                      'คนขับรถ')
                  .toString();
              final String messageText = (data['text'] ??
                      (data['imageUrl'] != null || data['image_url'] != null
                          ? ' ได้ส่งรูปภาพ'
                          : 'ข้อความใหม่'))
                  .toString();

              _triggerVoiceAlertForChat();

              if (mounted) {
                _chatNotificationTimer?.cancel();
                setState(() {
                  _incomingChatNotification = {
                    'sender': senderName,
                    'text': messageText,
                    'roomId': roomId,
                  };
                });

                _chatNotificationTimer = Timer(
                  const Duration(seconds: 7),
                  () {
                    if (mounted) {
                      setState(() {
                        _incomingChatNotification = null;
                      });
                    }
                  },
                );
              }
            }
          }
        }
      }, onError: (e) {
        debugPrint("Error listening to chat room $roomId: $e");
      });
      _chatSubscriptions.add(sub);
    }
  }

  Future<void> _triggerVoiceAlertForChat() async {
    try {
      if (_alertPlayer.state == PlayerState.playing) {
        await _alertPlayer.stop();
      }
      await _alertPlayer.setVolume(1.0);
      await _alertPlayer.play(AssetSource('voice/chat_sound.mp3'));
    } catch (e) {
      debugPrint("Error playing chat alert sound: $e");
    }
  }

  Widget _buildIncomingChatPopup() {
    if (_incomingChatNotification == null) return const SizedBox.shrink();

    final String sender = _incomingChatNotification!['sender'] ?? 'คนขับรถ';
    final String text = _incomingChatNotification!['text'] ?? '';
    final double topPadding = MediaQuery.of(context).padding.top > 0
        ? MediaQuery.of(context).padding.top + 8
        : 14;

    return Positioned(
      top: topPadding,
      left: 14,
      right: 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Dismissible(
            key: const Key('student_incoming_chat_popup'),
            direction: DismissDirection.up,
            onDismissed: (_) {
              _chatNotificationTimer?.cancel();
              setState(() {
                _incomingChatNotification = null;
              });
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _chatNotificationTimer?.cancel();
                  setState(() {
                    _incomingChatNotification = null;
                    _selectedIndex = 2; // สลับไปหน้าแชตทันที
                  });
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFF9FAF9),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFF81C784).withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF176a21).withValues(alpha: 0.14),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // ไอคอนวงกลมพร้อมจุดแสดงสถานะข้อความใหม่
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF176a21).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // ข้อมูลผู้ส่งและข้อความ
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    sender,
                                    style: const TextStyle(
                                      color: Color(0xFF2C2F30),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF81C784).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'คนขับรถ',
                                    style: TextStyle(
                                      color: Color(0xFF176a21),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              text,
                              style: const TextStyle(
                                color: Color(0xFF5A605B),
                                fontSize: 13,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // ปุ่มกดตอบกลับ & ปุ่มปิด
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              _chatNotificationTimer?.cancel();
                              setState(() {
                                _incomingChatNotification = null;
                                _selectedIndex = 2; // สลับไปหน้าแชตทันที
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF176a21).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ตอบกลับ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  SizedBox(width: 3),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              _chatNotificationTimer?.cancel();
                              setState(() {
                                _incomingChatNotification = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF757778),
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _listenToShuttles() {
    final ref = FirebaseDatabase.instance.ref('shuttles');
    
    // บังคับดึงข้อมูล 1 ครั้งตอนเริ่มต้น เพื่อกระตุ้นการเชื่อมต่อ WebSocket
    // (แก้ปัญหาบน Web ที่ onValue อาจไม่ทำงานจนกว่าจะมีการอัปเดตจากฝั่ง Server)
    ref.get();

    shuttleSubscription = ref.onValue.listen((
      event,
    ) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        if (activeShuttles.isNotEmpty) {
          setState(() {
            activeShuttles = [];
          });
        }
        return;
      }
      if (mounted && event.snapshot.exists) {
        bool shouldAnimate = false;
        final now = DateTime.now();
        final data = event.snapshot.value as Map<dynamic, dynamic>;

        final List<Map<String, dynamic>> newShuttles = [];

        data.forEach((key, value) {
          if (value != null && value is Map) {
            final status = value['status'];
            if (status == 'online') {
              final lastUpdatedMillis = value['last_updated'];
              bool isRecentlyUpdated = false;
              if (lastUpdatedMillis != null) {
                final lastUpdated = DateTime.fromMillisecondsSinceEpoch(
                  (lastUpdatedMillis as num).toInt(),
                );
                isRecentlyUpdated =
                    now.difference(lastUpdated).inMinutes.abs() <= 5;
              }

              if (isRecentlyUpdated) {
                newShuttles.add({
                  'id': key.toString(),
                  'lat': (value['lat'] is num ? (value['lat'] as num).toDouble() : (double.tryParse(value['lat'].toString()) ?? 0.0)),
                  'lng': (value['lng'] is num ? (value['lng'] as num).toDouble() : (double.tryParse(value['lng'].toString()) ?? 0.0)),
                  'passenger_status': value.containsKey('passenger_status')
                      ? value['passenger_status']
                      : 'available',
                  'number': value.containsKey('number') ? value['number'] : '',
                  'last_passed_stop': value.containsKey('last_passed_stop')
                      ? value['last_passed_stop']
                      : null,
                });
              }
            }
          }
        });

        bool hasMeaningfulChange =
            false; // ตรวจสอบว่ามีรถคันไหนขยับจริงหรือเปลี่ยนสถานะที่นั่งหรือไม่

        for (var shuttle in newShuttles) {
          final String id = shuttle['id'];
          final LatLng newLoc = LatLng(shuttle['lat'], shuttle['lng']);
          final String newPassengerStatus = shuttle['passenger_status'];
          final currentLoc = _currentShuttleLocations[id];

          // เช็คว่าสถานะผู้โดยสารเปลี่ยนหรือไม่
          bool statusChanged = true;
          String? oldPassengerStatus;
          for (var oldS in activeShuttles) {
            if (oldS['id'] == id) {
              oldPassengerStatus = oldS['passenger_status'];
              if (oldS['passenger_status'] == newPassengerStatus) {
                statusChanged = false;
              }
              break;
            }
          }
          if (statusChanged) {
            hasMeaningfulChange = true;

            // แจ้งเตือนถ้ารถเป้าหมายเปลี่ยนสถานะเป็นเต็มหรือพัก (นำระบบ TopToast กลับมา)
            if (id == targetedShuttleId) {
              String sName = 'รถคันเป้าหมาย';
              try {
                final targetShuttle = newShuttles.firstWhere((s) => s['id'] == targetedShuttleId);
                final String numStr = (targetShuttle['number'] ?? '').toString();
                if (numStr.isNotEmpty) sName = 'รถเบอร์ $numStr';
              } catch (_) {}

              if (newPassengerStatus == 'full') {
                _alertPlayer.play(AssetSource('voice/glass_1.mp3'));
                TopToast.show(context, 'แจ้งเตือน: $sName ที่กำลังมารับ "เต็มแล้ว" ', isError: true);
              } else if (newPassengerStatus == 'break') {
                _alertPlayer.play(AssetSource('voice/glass_1.mp3'));
                TopToast.show(context, 'แจ้งเตือน: $sName "ขอพักเบรค" ชั่วคราว ', isError: true);
              } else if (newPassengerStatus == 'available' && (oldPassengerStatus == 'full' || oldPassengerStatus == 'break')) {
                _alertPlayer.play(AssetSource('voice/glass_1.mp3'));
                TopToast.show(context, 'อัปเดต: $sName "ว่างแล้ว" ', isError: false);
              }
            }
          }

          final targetLoc = _targetShuttleLocations[id];

          if (currentLoc == null) {
            _currentShuttleLocations[id] = newLoc;
            _targetShuttleLocations[id] = newLoc;
            _oldShuttleLocations[id] = newLoc; // ป้องกันบั๊กเริ่มต้น
            hasMeaningfulChange = true;

            // แจ้งเตือนเมื่อมีรถคันใหม่เพิ่งออนไลน์
            bool isNew = !activeShuttles.any((s) => s['id'] == id);
            if (isNew) {
              String numStr = (shuttle['number'] ?? '').toString();
              String sName = numStr.isNotEmpty ? 'รถเบอร์ $numStr' : 'รถรับส่ง';
              TopToast.show(context, 'อัปเดต: $sName ออนไลน์เข้าสู่ระบบแล้ว ', isError: false);
            }

          } else if (targetLoc == null ||
              targetLoc.latitude != newLoc.latitude ||
              targetLoc.longitude != newLoc.longitude) {
            _targetShuttleLocations[id] = newLoc;
            shouldAnimate = true;
            hasMeaningfulChange = true;
          }
        }

        final activeIds = newShuttles.map((s) => s['id'] as String).toSet();
        if (activeIds.length != activeShuttles.length) {
          hasMeaningfulChange = true;
        }

        // แจ้งเตือนถ้ารถเป้าหมายออฟไลน์/เลิกงาน
        if (targetedShuttleId != null &&
            (isWaiting || isAcknowledged || selectedStopLatLng != null)) {
          bool wasActive = activeShuttles.any(
            (s) => s['id'] == targetedShuttleId,
          );
          bool isStillActive = activeIds.contains(targetedShuttleId);
          if (wasActive && !isStillActive) {
            String sName = 'รถรับส่งคันเป้าหมาย';
            try {
              final targetShuttle = activeShuttles.firstWhere((s) => s['id'] == targetedShuttleId);
              final String numStr = (targetShuttle['number'] ?? '').toString();
              if (numStr.isNotEmpty) sName = 'รถเบอร์ $numStr';
            } catch (_) {}

            TopToast.show(
              context,
              'แจ้งเตือน: $sName "เลิกงาน/ออฟไลน์" แล้วครับ ระบบจะหาคันใหม่ให้',
              isError: true,
            );
          }
        }

        _currentShuttleLocations.removeWhere(
          (id, loc) => !activeIds.contains(id),
        );
        _oldShuttleLocations.removeWhere((id, loc) => !activeIds.contains(id));
        _targetShuttleLocations.removeWhere(
          (id, loc) => !activeIds.contains(id),
        );

        // State Guard: อัปเดต UI และคำนวณกราฟเส้นทางใหม่เฉพาะเมื่อรถขยับจริง หรือสถานะเปลี่ยนเท่านั้น (เพื่อประหยัดแบตเตอรี่และไม่รีบิ้วฟรีเมื่อได้รับ Heartbeat)
        if (hasMeaningfulChange) {
          setState(() {
            activeShuttles = newShuttles;
          });
          if (shouldAnimate) {
            // อัปเดตพิกัดเริ่มต้นใหม่ให้กับรถทุกคัน ป้องกันบั๊กหมุดเด้งถอยหลังเวลาอนิเมชันเริ่มใหม่กลางคัน
            for (var keyId in _targetShuttleLocations.keys) {
              if (_currentShuttleLocations.containsKey(keyId)) {
                _oldShuttleLocations[keyId] = _currentShuttleLocations[keyId]!;
              }
            }
            _markerAnimationController.forward(from: 0.0);
          }

          // ถ้านักศึกษาเลือกป้ายไว้ ให้ทำการอัปเดตเส้นทางและเวลา ETA (ไม่ว่ารถจะออนไลน์หรือเพิ่งออฟไลน์ไป)
          if (selectedStopLatLng != null) {
            _updateRouteAndETA();
          }
        }
      }
    });
  }

  // ฟังข้อความแชทใหม่จากคนขับรถแบบ Real-time เพื่อส่งเสียงและแสดงป๊อปอัปแจ้งเตือน

  void _listenToFavoriteStops() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .handleError((e) => print("Firestore Error (users): $e"))
          .listen((doc) {
            if (doc.exists && doc.data()!.containsKey('favorite_stops')) {
              if (mounted) {
                setState(() {
                  favoriteStops = List<String>.from(
                    doc.data()!['favorite_stops'],
                  );
                });
              }
            }
          });
    }
  }

  Future<void> _toggleFavorite(String stopName) async {
    setState(() {
      if (favoriteStops.contains(stopName)) {
        favoriteStops.remove(stopName);
      } else {
        favoriteStops.add(stopName);
      }
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'favorite_stops': favoriteStops},
      );
    }
  }

  // ---------------------------------------------------------
  // ระบบคำนวณเส้นทาง (Graph & Pathfinding)
  // ---------------------------------------------------------
  void _buildRouteGraph() {
    const distanceCalc = Distance();

    Set<LatLng> endpoints = {};
    for (var segment in shuttleRoutes) {
      if (segment.isNotEmpty) {
        endpoints.add(segment.first);
        endpoints.add(segment.last);
      }
    }

    // กำหนด Segment ที่เป็น One-way (อ้างอิงจากจุดเริ่มต้นของ Segment)
    // เพื่อป้องกันระบบคำนวณเส้นทางย้อนศร (เช่น ย้อนกลับไปใช้ทางลัด)
    List<LatLng> oneWaySegments = [
      const LatLng(
        16.8278942,
        100.2065133,
      ), // Segment 13 (ขาเข้า อาคารทีปวิชญ์)
      const LatLng(
        16.8286828,
        100.2050371,
      ), // Segment 14 (ขาออก อาคารทีปวิชญ์ -> วงเวียน)
      const LatLng(16.8284757, 100.2060200), // Segment 15 (วงเวียนลงใต้)
      const LatLng(16.82925150, 100.20720840), // Segment 23 (ทางลัดลงใต้)
    ];

    for (var segment in shuttleRoutes) {
      bool isOneWay = false;
      if (segment.isNotEmpty) {
        if (oneWaySegments.contains(segment.first)) {
          isOneWay = true;
        }
      }
      for (var point in segment) {
        _routeGraph.putIfAbsent(point, () => []);
      }
      for (int i = 0; i < segment.length - 1; i++) {
        final p1 = segment[i];
        final p2 = segment[i + 1];
        _routeGraph[p1]!.add(p2);

        // ถ้าไม่ใช่ One-way ให้เติมเส้นทางย้อนกลับเพื่อให้เป็น Undirected Graph
        if (!isOneWay) {
          _routeGraph[p2]!.add(p1);
        }
      }
    }

    List<LatLng> allNodes = _routeGraph.keys.toList();
    for (int i = 0; i < allNodes.length; i++) {
      for (int j = i + 1; j < allNodes.length; j++) {
        if (endpoints.contains(allNodes[i]) ||
            endpoints.contains(allNodes[j])) {
          if (distanceCalc.distance(allNodes[i], allNodes[j]) <= 20.0) {
            if (!_routeGraph[allNodes[i]]!.contains(allNodes[j])) {
              _routeGraph[allNodes[i]]!.add(allNodes[j]);
              _routeGraph[allNodes[j]]!.add(allNodes[i]);
            }
          }
        }
      }
    }
  }

  LatLng? _getClosestNode(LatLng target) {
    if (_routeGraph.isEmpty) return null;
    LatLng? closest;
    double minDistance = double.infinity;
    const distanceCalc = Distance();

    for (var node in _routeGraph.keys) {
      double dist = distanceCalc.distance(target, node);
      if (dist < minDistance) {
        minDistance = dist;
        closest = node;
      }
    }
    return closest;
  }

  void _calculateHighlightedPath(List<LatLng> waypoints) {
    if (waypoints.length < 2) {
      setState(() => highlightedPath.clear());
      return;
    }

    List<LatLng> fullPath = [];
    double totalMeters = 0;
    const distanceCalc = Distance();

    for (int i = 0; i < waypoints.length - 1; i++) {
      LatLng startLoc = waypoints[i];
      LatLng endLoc = waypoints[i + 1];

      LatLng? startNode = _getClosestNode(startLoc);
      LatLng? endNode = _getClosestNode(endLoc);

      if (startNode == null || endNode == null) continue;

      Set<LatLng> unvisited = Set.from(_routeGraph.keys);
      Map<LatLng, double> distances = {};
      Map<LatLng, LatLng> previous = {};

      for (var node in _routeGraph.keys) {
        distances[node] = double.infinity;
      }
      distances[startNode] = 0;

      while (unvisited.isNotEmpty) {
        LatLng? current;
        double minDist = double.infinity;
        for (var node in unvisited) {
          if (distances[node]! < minDist) {
            minDist = distances[node]!;
            current = node;
          }
        }

        if (current == null || current == endNode) break;
        unvisited.remove(current);

        for (var neighbor in _routeGraph[current] ?? []) {
          if (!unvisited.contains(neighbor)) continue;
          double alt =
              distances[current]! + distanceCalc.distance(current, neighbor);
          if (alt < distances[neighbor]!) {
            distances[neighbor] = alt;
            previous[neighbor] = current;
          }
        }
      }

      List<LatLng> path = [];
      LatLng? curr = endNode;
      if (previous.containsKey(curr) || curr == startNode) {
        while (curr != null) {
          path.insert(0, curr);
          curr = previous[curr];
        }
      }
      
      print(" DEBUG: Path calculated length = ${path.length}");
      if (path.isEmpty) {
        print(" DEBUG: Path is EMPTY between ${startNode.latitude},${startNode.longitude} and ${endNode.latitude},${endNode.longitude}");
      }

      if (path.isNotEmpty) {
        if (i == 0) {
          // ถ้าเส้นทางมีจุดต่อไป ให้เช็คว่ารถวิ่งเลย startNode มาหรือยัง
          // ถ้าระยะจากรถไป node ถัดไป สั้นกว่าจาก startNode ไป node ถัดไป = รถวิ่งเลยมาแล้ว
          if (path.length > 1) {
            double distBusToNext = distanceCalc.distance(startLoc, path[1]);
            double distStartNodeToNext = distanceCalc.distance(
              path[0],
              path[1],
            );
            if (distBusToNext <= distStartNodeToNext) {
              path.removeAt(0); // ลบ startNode ที่อยู่ข้างหลังทิ้ง
            }
          }
          path.insert(0, startLoc);
        } else {
          if (fullPath.isNotEmpty && fullPath.last == path.first) {
            path.removeAt(0);
          }
        }
        if (i == waypoints.length - 2) {
          path.add(endLoc);
        }
        fullPath.addAll(path);
      } else {
        // ถ้าหาเส้นทางตามถนนไม่เจอ (เช่น ต้องย้อนศร)
        // ถ้านี่คือช่วงแรก (จากรถไปป้ายถัดไป) ให้ข้ามการวาดเส้นตรงทะลุตึก
        // เพื่อป้องกันเส้นไฮไลท์ลากย้อนกลับแบบพังๆ
        if (i == 0 && waypoints.length > 2) {
          fullPath.add(endLoc); // ใส่แค่จุดปลาย เพื่อให้วาดเส้นต่อไปได้
        } else {
          if (i == 0) fullPath.add(startLoc);
          fullPath.add(endLoc);
        }
      }

      if (distances[endNode] != null && distances[endNode] != double.infinity) {
        totalMeters +=
            distanceCalc.distance(startLoc, startNode) +
            distances[endNode]! +
            distanceCalc.distance(endNode, endLoc);
      } else {
        totalMeters += distanceCalc.distance(startLoc, endLoc);
      }
    }

    String eta;
    double speed =
        7.0; // ~25.2 กม./ชม. (ความเร็วเฉลี่ย 20-30 กม./ชม. รวมชะลอทางแยก/รับส่ง)
    double sec =
        (totalMeters / speed) + 15.0; // เผื่อเวลาชะลอทางแยก/รับส่ง 15 วินาที

    if (totalMeters <= 30) {
      eta = "รถกำลังจะถึงป้าย";
    } else if (sec <= 60) {
      eta = "ประมาณ 1 นาที (${totalMeters.round()} ม.)";
    } else {
      int mins = (sec / 60).ceil();
      eta = "ประมาณ $mins นาที (${totalMeters.round()} ม.)";
    }

    setState(() {
      highlightedPath = fullPath;
      estimatedArrivalText = eta;
    });
  }

  // หาพิกัดกึ่งกลางของเส้นทางไฮไลท์สำหรับแสดงป้ายข้อความเวลา ETA บนแผนที่
  LatLng? _getPathMidpoint() {
    if (highlightedPath.isEmpty) return null;
    if (highlightedPath.length == 1) return highlightedPath.first;
    int midIndex = highlightedPath.length ~/ 2;
    if (highlightedPath.length == 2) {
      return LatLng(
        (highlightedPath[0].latitude + highlightedPath[1].latitude) / 2,
        (highlightedPath[0].longitude + highlightedPath[1].longitude) / 2,
      );
    }
    return highlightedPath[midIndex];
  }

  // วิดเจ็ตข้อความแสดงเวลาประมาณการ (ETA) ข้างเส้นทางไฮไลท์บนแผนที่ (เหลือแค่ไอคอนและตัวหนังสือ)
  Widget _buildRouteEtaBadge(String etaText) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer, color: Color(0xFF176a21), size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            etaText,
            style: const TextStyle(
              color: Color(0xFF176a21),
              fontSize: 13.0,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, 0),
                ),
                Shadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _fetchStopsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stops')
          .get();

      List<Map<String, dynamic>> loadedStops = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        loadedStops.add({
          'id': doc.id, // ใช้สำหรับ Key ของ Marker
          'name': data['name'],
          'lat': (data['lat'] is num ? (data['lat'] as num).toDouble() : (double.tryParse(data['lat'].toString()) ?? 0.0)),
          'lng': (data['lng'] is num ? (data['lng'] as num).toDouble() : (double.tryParse(data['lng'].toString()) ?? 0.0)),
          'order': data['order'], // สำคัญสำหรับคำนวณเส้นทาง
        });
      }

      if (mounted) {
        setState(() {
          busStops = loadedStops;
          _isLoadingStops = false;
        });
      }
    } catch (e) {
      print("Error loading stops: $e");
      if (mounted) setState(() => _isLoadingStops = false);
    }
  }

  @override
  void dispose() {
    _markerAnimationController.dispose();
    requestSubscription?.cancel();
    userSubscription?.cancel();
    shuttleSubscription?.cancel(); // ยกเลิกฟังตำแหน่งรถ
    _positionSubscription?.cancel(); // ยกเลิกฟังตำแหน่งนักศึกษา
    for (var sub in _chatSubscriptions) {
      sub.cancel();
    }
    _chatNotificationTimer?.cancel();
    _alertPlayer.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    // 1. พาผู้ใช้กลับไปหน้า Login ทันที (เพื่อให้ Navigator ทำลาย Widget ปัจจุบันและปิด Stream ย่อยทั้งหมดในแอปอัตโนมัติ)
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }

    // 2. หน่วงเวลา 500ms เพื่อให้กระบวนการเปลี่ยนหน้าและ Dispose ทำงานเสร็จสิ้น ป้องกัน Firebase Error / แอปค้าง
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. ออกจากระบบ (กำหนดเวลา Timeout กันแอปค้างถ้าเน็ตหลุด)
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
  }

  void _moveToStop(Map<String, dynamic> stop) {
    if (isAcknowledged || isOnBoard) {
      if (isCardMinimized) {
        setState(() => isCardMinimized = false);
      }
      return;
    }
    if (isWaiting) return;

    setState(() {
      selectedStopName = stop['name'];
      selectedStopLatLng = LatLng(stop['lat'], stop['lng']);
    });

    _mapController.move(selectedStopLatLng!, 17.5);
    _updateRouteAndETA();

    FocusManager.instance.primaryFocus?.unfocus();
  }

  // คำนวณเส้นทางและเวลา ETA จากรถคันที่ใกล้ป้ายที่สุดด้วย Modulo Route Index
  void _updateRouteAndETA() {
    if (_isTutorialShowing) {
      if (highlightedPath.isNotEmpty) {
        setState(() {
          highlightedPath.clear();
        });
      }
      return;
    }

    String? targetName = isOnBoard ? selectedDropOffName : selectedStopName;
    if (targetName == null) return;

    LatLng target;
    if (isOnBoard) {
      final targetStopMap = busStops.firstWhere(
        (s) => s['name'] == targetName,
        orElse: () => {},
      );
      if (targetStopMap.isEmpty) return;
      target = LatLng(targetStopMap['lat'], targetStopMap['lng']);
    } else {
      if (selectedStopLatLng == null) return;
      target = selectedStopLatLng!;
    }

    if (activeShuttles.isEmpty) {
      setState(() {
        highlightedPath.clear();
        estimatedArrivalText =
            " ขณะนี้ยังไม่มีคนขับเปิดแอปออนไลน์อยู่ \n(ไม่สามารถแสดงเส้นทางและเวลา ETA ได้)";
      });
      return;
    }

    // หาระบบ order ของป้ายที่เป็นเป้าหมาย
    final targetStopMap = busStops.firstWhere(
      (s) => s['name'] == targetName,
      orElse: () => {},
    );
    int targetOrder = (targetStopMap['order'] as num?)?.toInt() ?? 1;

    String? closestBusId;
    LatLng? closestBusLoc;
    int? closestBusLastPassed;
    int minIndexDistance = 999;
    double minDirectDistFallback = double.infinity;

    // ถ้านักศึกษาเรียกไปแล้ว หรือขึ้นรถแล้ว ให้ track รถคันที่รับงาน
    if ((isAcknowledged || isOnBoard) && targetedShuttleId != null) {
      try {
        final trackedBus = activeShuttles.firstWhere(
          (bus) => bus['id'] == targetedShuttleId,
        );
        closestBusId = trackedBus['id'];
        closestBusLoc = LatLng(trackedBus['lat'], trackedBus['lng']);

        int? lastPassed = (trackedBus['last_passed_stop'] as num?)?.toInt();
        if (lastPassed != null) {
          closestBusLastPassed = lastPassed;
          int maxOrder = 23;
          if (busStops.isNotEmpty) {
            maxOrder = busStops
                .map((s) => ((s['order'] ?? 0) as num).toInt())
                .reduce((a, b) => a > b ? a : b);
            if (maxOrder == 0) maxOrder = 23;
          }
          int distIndex = targetOrder - lastPassed;
          if (distIndex < 0) {
            distIndex += maxOrder;
          }
          minIndexDistance = distIndex;
        }
      } catch (e) {
        // รถอาจจะออฟไลน์ไปแล้ว Fallback ไปหาคันใกล้สุดใหม่
      }
    }

    if (closestBusId == null) {
      for (var bus in activeShuttles) {
        LatLng busLoc = LatLng(bus['lat'], bus['lng']);
        int? lastPassed = (bus['last_passed_stop'] as num?)?.toInt();

        if (lastPassed != null) {
          int maxOrder = 23;
          if (busStops.isNotEmpty) {
            maxOrder = busStops
                .map((s) => ((s['order'] ?? 0) as num).toInt())
                .reduce((a, b) => a > b ? a : b);
            if (maxOrder == 0) maxOrder = 23;
          }

          int distIndex = targetOrder - lastPassed;
          if (distIndex < 0) {
            distIndex += maxOrder;
          }

          if (distIndex < minIndexDistance) {
            minIndexDistance = distIndex;
            closestBusId = bus['id'];
            closestBusLoc = busLoc;
            closestBusLastPassed = lastPassed;
          }
        } else {
          double d = const Distance().distance(busLoc, target);
          if (d < minDirectDistFallback && minIndexDistance == 999) {
            minDirectDistFallback = d;
            closestBusId = bus['id'];
            closestBusLoc = busLoc;
          }
        }
      }
    }

    if (closestBusId == null) {
      closestBusId = activeShuttles.first['id'];
      closestBusLoc = LatLng(
        activeShuttles.first['lat'],
        activeShuttles.first['lng'],
      );
    }

    targetedShuttleId = closestBusId;
    remainingStops = (minIndexDistance != 999) ? minIndexDistance : null;

    List<LatLng> waypoints = [closestBusLoc!];
    const distanceCalc = Distance();
    double directDistToTarget = distanceCalc.distance(closestBusLoc, target);

    // ระบบ Smart Check แบบเก่าที่ใช้ระยะ 80m ถูกเอาออกไปเพื่อป้องกันไม่ให้รถตัดจบลัดคิว
    if (busStops.isNotEmpty) {
      int maxOrder = busStops
          .map((s) => ((s['order'] ?? 0) as num).toInt())
          .reduce((a, b) => a > b ? a : b);
      if (maxOrder == 0) maxOrder = 23;

      // Fix: ค้นหาป้ายที่อยู่ใกล้รถมากที่สุดในปัจจุบัน เพื่อใช้เป็นจุดเริ่มต้นของการลากเส้น
      // ป้องกันปัญหารถวิ่งไปไกลแล้วแต่ last_passed_stop ในฐานข้อมูลยังไม่อัปเดต ซึ่งจะทำให้เส้นไฮไลท์ลากย้อนกลับไปมา (Zig-zag)
      int currentOrder = closestBusLastPassed ?? 1;
      if (busStops.isNotEmpty) {
        double minStopDist = double.infinity;
        int tempCurrentOrder = currentOrder;
        for (var stop in busStops) {
          LatLng sLoc = LatLng(stop['lat'], stop['lng']);
          double d = distanceCalc.distance(closestBusLoc, sLoc);
          if (d < minStopDist) {
            minStopDist = d;
            tempCurrentOrder = ((stop['order'] ?? 1) as num).toInt();
          }
        }

        // ป้องกันปัญหาระยะกระจัดหลอก (เช่น รถอยู่ตรงทางแยก ป้าย 13 อยู่ใกล้กว่าป้าย 12 ในแนวเส้นตรง)
        // ทำให้ระบบคิดว่ารถข้ามป้าย 12 ไปแล้ว ทั้งๆ ที่ยังไม่ถึง
        if (closestBusLastPassed != null) {
          int expectedNext = closestBusLastPassed + 1;
          if (expectedNext > maxOrder) expectedNext -= maxOrder;

          int stepsFromExpected = tempCurrentOrder - expectedNext;
          if (stepsFromExpected < 0) stepsFromExpected += maxOrder;

          // ถ้าระบบไปจับป้ายที่ "ผ่านไปแล้ว" หรืออยู่ข้างหลัง (stepsFromExpected > 11)
          // ให้บังคับมุ่งหน้าไปที่ expectedNext เสมอ ห้ามวาดเส้นถอยหลังกลับไปหาป้ายเดิม
          if (stepsFromExpected > 11) {
            tempCurrentOrder = expectedNext;
          } else {
            int stepsAhead = tempCurrentOrder - closestBusLastPassed;
            if (stepsAhead < 0) stepsAhead += maxOrder;

            // ถ้าระบบคิดว่ารถกระโดดข้ามป้ายไปไกลกว่า 2 ป้าย (ให้สอดคล้องกับฝั่งคนขับ)
            if (stepsAhead > 2) {
              // จะยอมให้ข้ามก็ต่อเมื่อรถอยู่ใกล้ป้ายนั้นจริงๆ (< 40 เมตร)
              // ถ้าไม่ใช่ แสดงว่าเป็นระยะกระจัดหลอกตรงทางแยก ให้พิจารณากลับมาที่ป้ายถัดไปที่ควรจะไป (expectedNext)
              if (minStopDist >= 40.0) {
                // แต่จะกลับไปหา expectedNext ก็ต่อเมื่อมันไม่ได้อยู่ไกลเกินไป (< 200m)
                // เพื่อป้องกันเคสที่ last_passed_stop ค้างเป็นค่าเก่ามากๆ
                try {
                  final expectedStop = busStops.firstWhere(
                    (s) => s['order'] == expectedNext,
                  );
                  LatLng expectedLoc = LatLng(
                    expectedStop['lat'],
                    expectedStop['lng'],
                  );
                  if (distanceCalc.distance(closestBusLoc, expectedLoc) < 200.0) {
                    tempCurrentOrder = expectedNext;
                  }
                } catch (_) {}
              }
            }
          }
        }

        // ป้องกันปัญหา currentOrder กระโดดข้ามป้ายเป้าหมาย
        int stepWithTemp = targetOrder - tempCurrentOrder;
        if (stepWithTemp < 0) stepWithTemp += maxOrder;

        int stepWithLastPassed = targetOrder - (closestBusLastPassed ?? 1);
        if (stepWithLastPassed < 0) stepWithLastPassed += maxOrder;

        // เช็คว่า stepWithTemp > 11 ด้วย เพื่อแยกระหว่าง "รถวิ่งเลยป้ายเป้าหมาย (step จะเป็น 20+)"
        // กับ "ข้อมูล last_passed เก่าตกค้าง (step เป็น 1-3)"
        if (stepWithTemp > stepWithLastPassed &&
            stepWithTemp > 11 &&
            closestBusLastPassed != null) {
          currentOrder = closestBusLastPassed;
        } else {
          currentOrder = tempCurrentOrder;
        }
      }

      int stepCount = targetOrder - currentOrder;
      if (stepCount < 0) stepCount += maxOrder;

      // ถ้าคำนวณได้ 0 (คือป้ายเป้าหมายคือป้ายถัดไป) ให้ไปที่ target ทันที
      if (stepCount == 0) {
        waypoints.add(target);
        remainingStops = 0;
        
        // Auto-Arrive System ย้ายมาไว้ตรงนี้
        // จะปิดงานอัตโนมัติก็ต่อเมื่อ "ไม่มีป้ายให้ต้องไปก่อนหน้าแล้ว" (stepCount == 0) 
        // และรถแจ้งว่าได้วิ่งผ่านป้ายเป้าหมายแล้ว (อ้างอิงจากระบบคนขับ)
        if (isOnBoard && closestBusLastPassed == targetOrder) {
          _handleAutoArrive();
          return;
        }
      } else {
        remainingStops =
            stepCount; // อัปเดตจำนวนป้ายที่เหลือให้ตรงกับเส้นทางจริง
        // บังคับให้เส้นทางต้องผ่านทุกป้าย (เริ่มที่ i = 0 เสมอ)
        for (int i = 0; i < stepCount; i++) {
          int nextOrder = currentOrder + i;
          if (nextOrder > maxOrder) nextOrder -= maxOrder;

          // FIX: ป้องกันการวาดเส้นทางย้อนกลับไปหาป้ายที่เพิ่งวิ่งผ่านมาแล้ว
          if (closestBusLastPassed != null && nextOrder == closestBusLastPassed) {
            continue;
          }

          try {
            final stop = busStops.firstWhere((s) => s['order'] == nextOrder);
            LatLng stopLoc = LatLng(stop['lat'], stop['lng']);

            waypoints.add(stopLoc);
          } catch (e) {
            // ข้ามถ้าไม่เจอป้าย
          }
        }
        waypoints.add(target);
      }
    } else {
      waypoints.add(target);
    }

    _calculateHighlightedPath(waypoints);
    _listenToAllChatMessages();
  }

  // ฟังก์ชันเมื่อนักศึกษากด "ขึ้นรถเรียบร้อยแล้ว"
  Future<void> _boardShuttle() async {
    if (activeRequestId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(activeRequestId)
            .update({'status': 'on_board'});
      } catch (e) {
        print("Error updating request status to on_board: $e");
      }
    }
    if (mounted) {
      setState(() {
        isOnBoard = true;
      });
      _updateRouteAndETA(); // อัปเดตเส้นทางไปยังจุดลงรถและคำนวณ ETA
    }
  }

  Future<void> _resetRideState() async {
    if (activeRequestId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(activeRequestId)
            .delete();
      } catch (e) {
        print("Error deleting request: $e");
      }
      requestSubscription?.cancel();
    }
    if (mounted) {
      setState(() {
        isWaiting = false;
        isAcknowledged = false;
        isOnBoard = false;
        isCardMinimized = false;
        activeRequestId = null;
        selectedStopName = null;
        selectedDropOffName = null;
        selectedStopLatLng = null;
        estimatedArrivalText = null;
        highlightedPath.clear();
      });

      // เลื่อนกล้องกลับมาที่ตำแหน่งของนักศึกษาเมื่อลงรถเสร็จสิ้น
      if (_myLocation != null) {
        _mapController.move(_myLocation!, 17.0);
      } else {
        _mapController.move(_psruCenter, 15.5);
      }
    }
  }

  void _showRatingDialog() {
    int _rating = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'ให้คะแนนคนขับรถ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF176a21),
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'คุณมีความพึงพอใจต่อการเดินทางครั้งนี้อย่างไรบ้าง?',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 40,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            _rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.spaceEvenly,
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetRideState();
                  },
                  child: const Text(
                    'ข้าม',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF176a21),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _rating > 0
                      ? () async {
                          Navigator.pop(context);
                          await _submitRating(_rating);
                          _resetRideState();
                        }
                      : null,
                  child: const Text(
                    'ส่งคะแนน',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitRating(int score) async {
    if (targetedShuttleId == null) return;
    try {
      final shuttleDoc = await FirebaseDatabase.instance
          .ref('shuttles')
          .child(targetedShuttleId!)
          .get();
      if (!shuttleDoc.exists || shuttleDoc.value == null) return;
      final data = shuttleDoc.value as Map<dynamic, dynamic>;
      if (data.containsKey('driver_uid') && data['driver_uid'] != null) {
        final String driverUid = data['driver_uid'];

        final userDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(driverUid);
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(userDocRef);
          if (!snapshot.exists) return;

          double currentTotal = (snapshot.data()?['total_rating_score'] ?? 0.0)
              .toDouble();
          int currentCount = (snapshot.data()?['rating_count'] ?? 0).toInt();

          transaction.update(userDocRef, {
            'total_rating_score': currentTotal + score,
            'rating_count': currentCount + 1,
          });
        });

        if (mounted) {
          TopToast.show(context, 'ขอบคุณสำหรับคะแนนครับ! ', isError: false);
        }
      }
    } catch (e) {
      print("Error submitting rating: $e");
    }
  }

  Future<void> _handleAutoArrive({bool isManual = false}) async {
    if (!isManual) {
      if (_isAutoArriving) return;
      _isAutoArriving = true;
      
      // หน่วงเวลา 5 วินาทีเมื่อถึงจุดหมาย
      await Future.delayed(const Duration(seconds: 5));
      
      if (!mounted) return;
      if (!isOnBoard) { // ถ้าผู้ใช้กดปิดเองไปแล้วระหว่างรอ 5 วิ
        _isAutoArriving = false;
        return; 
      }
      _isAutoArriving = false;
    }

    // ถ้าเพิ่งลงจากรถ ให้จำลองว่าตัวเราไปอยู่ที่จุดหมายแล้ว (สำหรับการเทสบนเว็บ)
    if (selectedDropOffName != null) {
      try {
        final stop = busStops.firstWhere(
          (s) => s['name'] == selectedDropOffName,
        );
        if (mounted) {
          setState(() {
            _myLocation = LatLng(stop['lat'], stop['lng']);
          });
        }
      } catch (e) {
        // ข้ามถ้าหาป้ายไม่เจอ
      }
    }

    // 1. ลบคำขอเรียกรถออกจาก Firestore ทันที เพื่อคืนคิวให้ระบบ
    if (activeRequestId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(activeRequestId)
            .delete();
        activeRequestId = null;
      } catch (e) {
        print("Error deleting request during auto-arrive: $e");
      }
    }

    // 2. ปิดสถานะการเดินทาง
    if (mounted) {
      setState(() {
        isOnBoard = false;
      });
      // 3. เด้ง Popup ให้คะแนน
      _showRatingDialog();
    }
  }

  Future<void> _toggleWaitState() async {
    if (isOnBoard) {
      // ถ้านักศึกษาอยู่บนรถ และกดเสร็จสิ้น ให้เรียกใช้งาน Auto-Arrive แบบเดียวกัน
      await _handleAutoArrive(isManual: true);
      return;
    }

    if (isWaiting || isAcknowledged) {
      await _resetRideState();
    } else {
      if (selectedDropOffName == null) {
        TopToast.show(
          context,
          'กรุณาเลือกจุดลงรถก่อนกดเรียกรถครับ',
          isError: true,
        );
        return;
      }

      // ตรวจสอบระยะห่างระหว่างนักศึกษากับป้ายที่เลือก
      if (_myLocation == null) {
        TopToast.show(
          context,
          'ไม่สามารถระบุตำแหน่งของคุณได้ กรุณาเปิด GPS ครับ',
          isError: true,
        );
        return;
      }

      if (selectedStopLatLng != null) {
        final double distanceToStop = const Distance().as(
          LengthUnit.Meter,
          _myLocation!,
          selectedStopLatLng!,
        );

        if (distanceToStop > 50) { // ตั้งค่ารัศมี 50 เมตร
          TopToast.show(
            context,
            'คุณต้องอยู่ใกล้ป้าย (รัศมี 50 เมตร) จึงจะเรียกรถได้ครับ\nระยะห่างปัจจุบัน: ${distanceToStop.toStringAsFixed(0)} เมตร',
            isError: true,
          );
          return;
        }
      }

      setState(() {
        isWaiting = true;
        isAcknowledged = false;
      });
      final user = FirebaseAuth.instance.currentUser;

      try {
        final docRef = await FirebaseFirestore.instance
            .collection('ride_requests')
            .add({
              'student_uid': user?.uid,
              'stop_name': selectedStopName,
              'status': 'waiting',
              'timestamp': FieldValue.serverTimestamp(),
              if (_myLocation != null) 'student_lat': _myLocation!.latitude,
              if (_myLocation != null) 'student_lng': _myLocation!.longitude,
              if (targetedShuttleId != null)
                'target_shuttle_id': targetedShuttleId,
              if (selectedDropOffName != null)
                'dropoff_stop': selectedDropOffName,
            });

        // บันทึกสถิติลง Analytics สำหรับสร้างกราฟในหน้า Admin
        try {
          final now = DateTime.now();
          final dateStr =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final hourStr = now.hour.toString().padLeft(2, '0');

          await FirebaseFirestore.instance
              .collection('analytics')
              .doc('daily_stats_$dateStr')
              .set({
                'hourly_counts': {hourStr: FieldValue.increment(1)},
              }, SetOptions(merge: true));
        } catch (e) {
          print("Error updating analytics: $e");
        }

        activeRequestId = docRef.id;

        requestSubscription?.cancel();
        requestSubscription = docRef
            .snapshots()
            .handleError((e) => print("Firestore Error (ride_requests): $e"))
            .listen((snapshot) {
              if (snapshot.exists) {
                final data = snapshot.data();
                if (data != null && data['status'] == 'acknowledged') {
                  if (mounted) {
                    TopToast.show(
                      context,
                      'คนขับรับทราบแล้ว! กำลังเดินทางไปรับที่ป้ายครับ ',
                      isError: false,
                    );
                    setState(() {
                      isWaiting = false;
                      isAcknowledged =
                          true; // เปลี่ยนสถานะเป็นคนขับรับทราบแล้ว และคงเส้นทางกับป้ายจอดไว้
                      isCardMinimized = false;
                    });
                    _updateRouteAndETA();
                  }
                } else if (data != null && data['status'] == 'on_board') {
                  // ถ้าสถานะถูกเปลี่ยนจากที่อื่น
                  if (mounted) {
                    if (!isOnBoard) {
                      setState(() {
                        isOnBoard = true;
                      });
                      _updateRouteAndETA(); // อัปเดตเส้นทาง
                    }
                  }
                }
              }
            });
      } catch (e) {
        print("Error requesting ride: $e");
        if (mounted) {
          setState(() => isWaiting = false);
        }
      }
    }
  }

  void _showDropOffSelectionSheet(BuildContext context) {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableStops = busStops
                .where((stop) => stop['name'] != selectedStopName)
                .toList();

            var filteredStops = availableStops;
            if (searchQuery.isNotEmpty) {
              filteredStops = availableStops
                  .where(
                    (stop) => stop['name'].toString().toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ),
                  )
                  .toList();
            }

            filteredStops.sort((a, b) {
              bool aIsFav = favoriteStops.contains(a['name']);
              bool bIsFav = favoriteStops.contains(b['name']);
              if (aIsFav && !bIsFav) return -1;
              if (!aIsFav && bIsFav) return 1;
              return 0;
            });

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.5,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'เลือกลงที่ป้าย',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C2F30),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setModalState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: const InputDecoration(
                            hintText: 'ค้นหาจุดลงรถ...',
                            hintStyle: TextStyle(
                              color: Color(0xFF757778),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Color(0xFF757778),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: Colors.grey.shade200),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredStops.length,
                        itemBuilder: (context, index) {
                          final option = filteredStops[index];
                          final bool isFav = favoriteStops.contains(
                            option['name'],
                          );

                          return Material(
                            color: index % 2 == 0
                                ? Colors.grey.shade50
                                : Colors.white,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  selectedDropOffName = option['name'];
                                });
                                Navigator.pop(context);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      color: Color(0xFF176a21),
                                      size: 22,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        option['name'],
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF2C2F30),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        await _toggleFavorite(option['name']);
                                        setModalState(() {});
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          isFav
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: isFav
                                              ? Colors.amber
                                              : Colors.grey.shade400,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F2),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildMapScreen(),
              StudentLiveStatusScreen(
                busStops: busStops,
                onSelectTab: (index) {
                  setState(() => _selectedIndex = index);
                },
              ), // หน้า Live Status ตามดีไซน์
              // เปลี่ยนเป็นหน้า StudentChatListScreen ที่รวมรายการแชททุกคัน
              StudentChatListScreen(
                onSelectTab: (index) {
                  setState(() => _selectedIndex = index);
                },
              ),

              const StudentProfileScreen(),
            ],
          ),

          // ป๊อปอัปแจ้งเตือนข้อความแชตใหม่จากคนขับรถ
          _buildIncomingChatPopup(),

          // Bottom Navigation Bar สไตล์ Floating Dock โมเดิร์น (ลอยขึ้นมาจากขอบล่าง และเว้นระยะซ้าย-ขวา)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom > 0
                ? MediaQuery.of(context).padding.bottom + 8
                : 16,
            left: 16,
            right: 16,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildCurvedBottomNav(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapScreen() {
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _psruCenter,
              initialZoom: 15.5,
              minZoom: 14.5,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(bounds: _psruBounds),
              interactionOptions: InteractionOptions(
                flags:
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
                cursorKeyboardRotationOptions:
                    CursorKeyboardRotationOptions.disabled(), // ปิดการหมุนด้วยคีย์บอร์ด/เมาส์บน Web
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isAutoFollow) {
                  setState(() {
                    _isAutoFollow = false;
                  });
                }
              },
              onTap: (tapPosition, point) {
                if (isAcknowledged || isOnBoard) {
                  setState(() {
                    isCardMinimized =
                        true; // ย่อกรอบรายละเอียดออก ให้เหลือแค่ปุ่ม "ขึ้นรถเรียบร้อย"
                  });
                } else if (!isWaiting) {
                  setState(() {
                    selectedStopName = null;
                    selectedStopLatLng = null;
                    estimatedArrivalText = null;
                    highlightedPath.clear();
                  });
                }
                FocusManager.instance.primaryFocus?.unfocus();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.psru_shuttle_app',
              ),
              PolylineLayer(
                polylines: [
                  ...shuttleRoutes.map((segment) {
                    return Polyline(
                      points: segment,
                      strokeWidth: 5.0,
                      color: const Color(0xFF176a21).withValues(
                        alpha: 0.5,
                      ), // ปรับให้เข้มขึ้นเพื่อให้มองเห็นชัด
                    );
                  }),
                  if (highlightedPath.isNotEmpty)
                    Polyline(
                      points: highlightedPath,
                      strokeWidth: 6.0,
                      color: const Color(0xFF176a21),
                    ),
                ],
              ),
              MarkerLayer(
                markers: (() {
                  List<Marker> allMarkers = [];
                  Marker? selectedMarker;

                  // 1. หมุดจุดจอดรถ (ที่ไม่ได้เลือก)
                  for (var vStop in _visualStops) {
                    bool isSelected = false;
                    if (vStop['isGroup'] == true) {
                      isSelected = isOnBoard
                          ? (vStop['members'] as List).any(
                              (m) => m['name'] == selectedDropOffName,
                            )
                          : (vStop['members'] as List).any(
                              (m) => m['name'] == selectedStopName,
                            );
                    } else {
                      isSelected = isOnBoard
                          ? selectedDropOffName == vStop['name']
                          : selectedStopName == vStop['name'];
                    }

                    final marker = Marker(
                      key: ValueKey('stop_${vStop['id'] ?? vStop['name']}'),
                      point: LatLng(vStop['lat'], vStop['lng']),
                      width: isSelected ? 150 : 130,
                      height: isSelected ? 75 : 65,
                      child: RepaintBoundary(
                        child: GestureDetector(
                          key: isSelected
                              ? keySelectedStopMarker
                              : (_visualStops.isNotEmpty &&
                                        vStop == _visualStops.first
                                    ? keyStopMarker
                                    : null),
                          onTap: () {
                            if (vStop['isGroup'] == true) {
                              if (!isSelected) {
                                _moveToStop(vStop['members'][0]);
                              } else {
                                _moveToStop(
                                  busStops.firstWhere(
                                    (s) => s['name'] == selectedStopName,
                                    orElse: () => vStop['members'][0],
                                  ),
                                );
                              }
                            } else {
                              _moveToStop(vStop);
                            }
                          },
                          child: _buildStopMarker(
                            isSelected: isSelected,
                            name: vStop['name'] ?? '',
                          ),
                        ),
                      ),
                    );

                    if (isSelected) {
                      selectedMarker = marker;
                    } else {
                      allMarkers.add(marker);
                    }
                  }

                  // 2. แสดงตำแหน่งนักศึกษา (ซ่อนเมื่ออยู่บนรถแล้ว เพื่อใช้หมุดรถแทน)
                  if (_myLocation != null && !isOnBoard) {
                    allMarkers.add(
                      Marker(
                        point: _myLocation!,
                        width: 80,
                        height: 80,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Container(
                              key: keyMyLocationDot,
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 16, // ใส่ไอคอนรูปคนตรงกลางสีฟ้า
                              ),
                            ),
                            Positioned(
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.0,
                                  ),
                                ),
                                child: const Text(
                                  'ฉัน', // ข้อความบอกว่าเป็นตัวนักศึกษาเอง
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 3. แสดงหมุดรถรับส่งทุกคันที่ออนไลน์ (ขยับแบบอนิเมชันเหมือนฝั่งคนขับ)
                  allMarkers.addAll(
                    activeShuttles.map((shuttle) {
                      final String id = shuttle['id'];
                      final LatLng displayLoc =
                          _currentShuttleLocations[id] ??
                          LatLng(
                            (shuttle['lat'] is num ? (shuttle['lat'] as num).toDouble() : (double.tryParse(shuttle['lat'].toString()) ?? 0.0)),
                            (shuttle['lng'] is num ? (shuttle['lng'] as num).toDouble() : (double.tryParse(shuttle['lng'].toString()) ?? 0.0)),
                          );
                      return Marker(
                        key: ValueKey('shuttle_$id'),
                        point: displayLoc,
                        width: 80,
                        height: 80,
                        child: RepaintBoundary(
                          child: _buildBusMarker(
                            shuttle['passenger_status'],
                            shuttle['number']?.toString(),
                          ),
                        ),
                      );
                    }),
                  );

                  // 4. แสดงหมุดจุดจอดที่ถูกเลือกเป็น Layer บนสุด!
                  if (selectedMarker != null) {
                    allMarkers.add(selectedMarker);
                  }

                  // 5. แสดงป้ายเวลาประมาณการ (ETA Badge) ข้างเส้นทางไฮไลท์บนแผนที่
                  if (highlightedPath.isNotEmpty &&
                      estimatedArrivalText != null &&
                      _getPathMidpoint() != null) {
                    allMarkers.add(
                      Marker(
                        key: const ValueKey('eta_badge'),
                        point: _getPathMidpoint()!,
                        width: 170,
                        height: 40,
                        child: RepaintBoundary(
                          child: _buildRouteEtaBadge(estimatedArrivalText!),
                        ),
                      ),
                    );
                  }

                  return allMarkers;
                })(),
              ),
            ],
          ),
        ),

        if (_isLoadingStops)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text("กำลังโหลดป้ายรถ..."),
                  ],
                ),
              ),
            ),
          ),

        // Curved Bottom Header สไตล์ที่ 2 (ชิดบน ขอบล่างโค้งมนรับสายตา)
        // Curved Bottom Header สไตล์ที่ 2 (ชิดบน ขอบล่างโค้งมน สะอาดตา)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFF8FAF8),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(26),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF176a21).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.03),
                width: 1.0,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ฝั่งซ้าย: โลโก้
                        Image.asset(
                          'lib/screens/driver/logo.png',
                          height: 38,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Row(
                              children: [
                                Icon(
                                  Icons.directions_bus,
                                  color: Color(0xFF176a21),
                                  size: 26,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'PSRU Shuttle',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF176a21),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        // ฝั่งขวา: ปุ่มออกจากระบบ (Logout Capsule Chip)
                        GestureDetector(
                          onTap: _logout,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.04),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFF5A605B),
                                  size: 16,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'ออก',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5A605B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ป้ายสถานะรถรับส่งแบบลอยชิดซ้ายบนแผนที่ (Floating Status Pill on Map - Left Aligned)
        Positioned(
          top: 84,
          left: 16,
          child: SafeArea(
            top: true,
            bottom: false,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (activeShuttles.isNotEmpty
                            ? const Color(0xFF176a21)
                            : const Color(0xFFD84315))
                        .withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: activeShuttles.isNotEmpty
                      ? const Color(0xFF81C784).withValues(alpha: 0.6)
                      : Colors.orange.shade200,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeShuttles.isNotEmpty
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF57C00),
                      boxShadow: activeShuttles.isNotEmpty
                          ? [
                              BoxShadow(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    activeShuttles.isNotEmpty
                        ? 'รถรับส่งวิ่งให้บริการ ${activeShuttles.length} คัน '
                        : ' ขณะนี้ยังไม่มีคนขับออนไลน์ในระบบ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: activeShuttles.isNotEmpty
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFFD84315),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ปุ่มขยายการ์ดข้อมูล (แสดงเฉพาะตอนการ์ดย่อ)
        if (selectedStopName != null && isCardMinimized && !_isTutorialCardHidden)
          Positioned(
            bottom: 210, // อยู่เหนือปุ่มเป้าเล็ง (150 + 60)
            right: 20,
            child: FloatingActionButton(
              heroTag: 'expandCardBtn',
              key: const ValueKey('expandCardButton'),
              mini: true,
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () {
                setState(() {
                  isCardMinimized = false;
                });
              },
              child: const Icon(
                Icons.open_in_full,
                color: Color(0xFF176a21),
              ),
            ),
          ),

        // ปุ่มเป้าเล็ง (แบบเดียวกับของคนขับ)
        Positioned(
          bottom: (selectedStopName != null && !_isTutorialCardHidden)
              ? (isCardMinimized ? 165 : 395) // เลื่อนหลบการ์ดแบบเต็มหรือย่อ
              : 115, // กลับสู่ปกติเวลาปิดการ์ด
          right: 20,
          child: FloatingActionButton(
            heroTag: 'myLocationBtn',
            key: keyMyLocationButton,
            mini: true,
            backgroundColor: _isAutoFollow
                ? const Color(0xFF176a21)
                : Colors.white,
            elevation: 4,
            onPressed: () {
              setState(() {
                _isAutoFollow = true;
              });
              if (isOnBoard &&
                  targetedShuttleId != null &&
                  _currentShuttleLocations.containsKey(targetedShuttleId)) {
                _mapController.move(
                  _currentShuttleLocations[targetedShuttleId]!,
                  17.5,
                );
              } else if (selectedStopLatLng != null) {
                _mapController.move(selectedStopLatLng!, 17.5);
              } else if (_myLocation != null) {
                _mapController.move(_myLocation!, 17.0);
              } else {
                _mapController.move(_psruCenter, 15.5);
              }
            },
            child: Icon(
              _isAutoFollow ? Icons.my_location : Icons.location_searching,
              color: _isAutoFollow ? Colors.white : const Color(0xFF176a21),
            ),
          ),
        ),

        if (selectedStopName != null && !_isTutorialCardHidden)
          Positioned(
            bottom: 105,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: (selectedStopName != null && !_isTutorialCardHidden)
                  ? 1.0
                  : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildStopDetailsCard(),
            ),
          ),
      ],
    );
  }

  // ตรวจสอบและแสดง Tutorial
  Future<void> _checkAndShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();

    // ลบคอมเมนต์บรรทัดล่างนี้ออกเพื่อ "บังคับรีเซ็ต" ให้ Tutorial กลับมาแสดงอีกครั้ง (สำหรับการทดสอบ)
    //await prefs.setBool('hasSeenTutorial', false);

    final bool hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;

    if (!hasSeenTutorial) {
      if (_visualStops.isEmpty) {
        // ถ้ารอโหลดป้ายรถยังไม่เสร็จ ให้รออีกครึ่งวินาทีแล้วเช็คใหม่
        Future.delayed(
          const Duration(milliseconds: 500),
          _checkAndShowTutorial,
        );
        return;
      }

      bool openedForTutorial = false;

      // รอให้ Layout และ Marker สร้างเสร็จก่อนโชว์ Tutorial (ประมาณ 350ms)
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _showTutorial(openedForTutorial, phase: 1);
        }
      });
    }
  }

  void _showTutorial(bool closeCardOnFinish, {int phase = 1}) {
    if (mounted) {
      setState(() {
        _isTutorialShowing = true;
        highlightedPath.clear();
      });
    }

    final targets = _createTutorialTargets(phase: phase);
    if (targets.isEmpty) {
      if (mounted) {
        setState(() {
          _isTutorialShowing = false;
        });
      }
      return;
    }

    tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: const Color(0xFF176a21),
      textSkip: "ข้าม",
      paddingFocus: 10,
      opacityShadow: 0.85,
      onFinish: () {
        if (phase == 1) {
          // จบ Phase 1 -> ให้จำลองการกดเลือกจุดจอดที่อยู่ใกล้นักศึกษามากที่สุด
          Map<String, dynamic>? targetStop;
          if (_myLocation != null && _visualStops.isNotEmpty) {
            const distanceCalc = Distance();
            double minDistance = double.infinity;
            for (var vStop in _visualStops) {
              double lat = (vStop['lat'] is num ? (vStop['lat'] as num).toDouble() : (double.tryParse(vStop['lat'].toString()) ?? 0.0));
              double lng = (vStop['lng'] is num ? (vStop['lng'] as num).toDouble() : (double.tryParse(vStop['lng'].toString()) ?? 0.0));
              double d = distanceCalc.distance(_myLocation!, LatLng(lat, lng));
              if (d < minDistance) {
                minDistance = d;
                targetStop = vStop;
              }
            }
          }
          targetStop ??= _visualStops.first;

          if (targetStop['isGroup'] == true &&
              targetStop['members'] != null &&
              (targetStop['members'] as List).isNotEmpty) {
            _moveToStop(targetStop['members'][0]);
          } else {
            _moveToStop(targetStop);
          }
          if (mounted) {
            setState(() {
              _isTutorialCardHidden = true; // ซ่อนการ์ดก่อนเข้า Phase 2
              highlightedPath.clear();
            });
          }
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) _showTutorial(closeCardOnFinish, phase: 2);
          });
        } else if (phase == 2) {
          // จบ Phase 2 (ขั้นตอนที่ 4) -> แสดงการ์ดขึ้นมาแล้วเข้าสู่ Phase 3 (ขั้นตอนที่ 5 และ 6)
          if (mounted) {
            setState(() {
              _isTutorialCardHidden = false; // เปิดแสดงการ์ดสำหรับ Phase 3
              highlightedPath.clear();
            });
          }
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) _showTutorial(closeCardOnFinish, phase: 3);
          });
        } else {
          // จบ Tutorial ทั้งหมดจริงๆ -> สรุปบทเรียนและล็อกกล้องกลับไปที่ตำแหน่งของนักศึกษา
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('hasSeenTutorial', true);
          });
          if (mounted) {
            setState(() {
              _isTutorialShowing = false;
              _isTutorialCardHidden = false;
              selectedStopName = null;
              selectedStopLatLng = null;
              estimatedArrivalText = null;
              highlightedPath.clear();
              _isAutoFollow = true;
            });
            if (_myLocation != null) {
              _mapController.move(_myLocation!, 17.0);
            }
          }
        }
      },
      onSkip: () {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('hasSeenTutorial', true);
        });
        if (mounted) {
          setState(() {
            _isTutorialShowing = false;
            _isTutorialCardHidden = false;
            selectedStopName = null;
            selectedStopLatLng = null;
            estimatedArrivalText = null;
            highlightedPath.clear();
            _isAutoFollow = true;
          });
          if (_myLocation != null) {
            _mapController.move(_myLocation!, 17.0);
          }
        }
        return true;
      },
    );

    tutorialCoachMark.show(context: context);
  }

  Widget _buildTutorialContent(
    String title,
    String description,
    int currentStep,
    int totalSteps,
    TutorialCoachMarkController controller, {
    bool canGoBack = false,
  }) {
    bool isLast = currentStep == totalSteps;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "$currentStep / $totalSteps",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: canGoBack
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          children: [
            if (canGoBack)
              TextButton(
                onPressed: () {
                  controller.previous();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.8),
                      width: 1.2,
                    ),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 18),
                    SizedBox(width: 6),
                    Text(
                      "ย้อนกลับ",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox.shrink(),

            ElevatedButton(
              onPressed: () {
                if (isLast) {
                  controller.skip(); // On last step, skip to finish properly
                } else {
                  controller.next();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF176a21),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLast ? "เริ่มใช้งานเลย!" : "ถัดไป",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (!isLast) const SizedBox(width: 8),
                  if (!isLast)
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<TargetFocus> _createTutorialTargets({int phase = 1}) {
    List<TargetFocus> targets = [];

    const int totalSteps = 6;
    bool hasStopMarker = keyStopMarker.currentContext != null;
    bool hasCardTop = keyCardTopSection.currentContext != null;
    bool hasCardBottom = keyCardBottomSection.currentContext != null;
    bool hasSelectedStopMarker = keySelectedStopMarker.currentContext != null;
    bool hasMyLocationButton = keyMyLocationButton.currentContext != null;
    bool hasBottomNav = keyBottomNav.currentContext != null;

    int startingStep = phase == 1 ? 1 : (phase == 2 ? 3 : 4);
    int currentStepCounter = startingStep;

    // ----------------- PHASE 1 -----------------
    if (phase == 1) {
      // 1. ปุ่มเป้าเล็ง (My Location Button)
      if (hasMyLocationButton) {
        final step = currentStepCounter++;
        targets.add(
          TargetFocus(
            identify: "MyLocationButton",
            keyTarget: keyMyLocationButton,
            alignSkip: Alignment.topRight,
            contents: [
              TargetContent(
                align: ContentAlign.top,
                builder: (context, controller) => _buildTutorialContent(
                  "ค้นหาตัวคุณ",
                  "หากเลื่อนแผนที่ไปที่อื่น คุณสามารถกดปุ่ม 'เป้าเล็ง' ตรงนี้เพื่อซูมกลับมาหาตำแหน่งปัจจุบันของคุณได้เสมอ",
                  step,
                  totalSteps,
                  controller,
                  canGoBack: false,
                ),
              ),
            ],
          ),
        );
      }

      // 2. หมุดจุดจอดรถ (Stop Marker)
      if (hasStopMarker) {
        final step = currentStepCounter++;
        targets.add(
          TargetFocus(
            identify: "StopMarker",
            keyTarget: keyStopMarker,
            alignSkip: Alignment.topRight,
            contents: [
              TargetContent(
                align: ContentAlign.bottom,
                builder: (context, controller) => _buildTutorialContent(
                  "นี่คือป้ายจุดจอดรถ",
                  "เมื่อเห็นหมุดแบบนี้บนแผนที่ แสดงว่าเป็นจุดจอดรถครับ ลองกดที่ป้ายเพื่อดูรายละเอียดและเลือกเป็น 'จุดขึ้นรถ' (ต้นทาง) ได้เลย!",
                  step,
                  totalSteps,
                  controller,
                  canGoBack: true,
                ),
              ),
            ],
          ),
        );
      }
    }

    // ----------------- PHASE 2 -----------------
    if (phase == 2) {
      // 3. หมุดจุดจอดรถที่ถูกเลือก (Selected Stop Marker - ซ่อนการ์ด)
      final step = currentStepCounter++;
      targets.add(
        TargetFocus(
          identify: "SelectedStopMarker",
          keyTarget: hasSelectedStopMarker
              ? keySelectedStopMarker
              : keyStopMarker,
          alignSkip: Alignment.topRight,
          shape: ShapeLightFocus.RRect,
          radius: 16,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => _buildTutorialContent(
                "จุดจอดที่คุณเลือก",
                "นี่คือจุดจอดที่คุณกำลังดูข้อมูลอยู่ ระบบจะแสดงชื่อป้ายให้เห็นชัดเจนบนแผนที่",
                step,
                totalSteps,
                controller,
                canGoBack: false,
              ),
            ),
          ],
        ),
      );
    }

    // ----------------- PHASE 3 -----------------
    if (phase == 3) {
      // 4. ส่วนบนของการ์ด (Card Top Section)
      if (hasCardTop) {
        final step = currentStepCounter++;
        targets.add(
          TargetFocus(
            identify: "CardTopSection",
            keyTarget: keyCardTopSection,
            alignSkip: Alignment.topRight,
            shape: ShapeLightFocus.RRect,
            radius: 16,
            contents: [
              TargetContent(
                align: ContentAlign.top,
                builder: (context, controller) => _buildTutorialContent(
                  "ข้อมูลจุดจอดรถ",
                  "ส่วนนี้จะแสดงชื่อของป้ายรถที่คุณเลือก และเวลาโดยประมาณที่รถจะเดินทางมาถึง",
                  step,
                  totalSteps,
                  controller,
                  canGoBack: false,
                ),
              ),
            ],
          ),
        );
      }

      // 5. ส่วนล่างของการ์ด (Card Bottom Section)
      if (hasCardBottom) {
        final step = currentStepCounter++;
        targets.add(
          TargetFocus(
            identify: "CardBottomSection",
            keyTarget: keyCardBottomSection,
            alignSkip: Alignment.topRight,
            shape: ShapeLightFocus.RRect,
            radius: 16,
            contents: [
              TargetContent(
                align: ContentAlign.top,
                builder: (context, controller) => _buildTutorialContent(
                  "เลือกปลายทางและเรียกรถ",
                  "แตะที่ช่องค้นหาเพื่อเลือก 'ป้ายปลายทาง' ที่คุณต้องการไป จากนั้นกดปุ่มสีเขียวด้านล่างเพื่อแจ้งให้คนขับทราบว่าคุณกำลังรออยู่",
                  step,
                  totalSteps,
                  controller,
                  canGoBack: true,
                ),
              ),
            ],
          ),
        );
      }

      // 6. แถบเมนูด้านล่าง (Bottom Navigation)
      if (hasBottomNav) {
        final step = currentStepCounter++;
        targets.add(
          TargetFocus(
            identify: "BottomNav",
            keyTarget: keyBottomNav,
            alignSkip: Alignment.topRight,
            shape: ShapeLightFocus.RRect,
            radius: 20,
            contents: [
              TargetContent(
                align: ContentAlign.top,
                builder: (context, controller) => _buildTutorialContent(
                  "เมนูหลัก",
                  "ใช้งานฟังก์ชันต่างๆ ได้จากตรงนี้:\n• Map: ดูแผนที่และเรียกรถ\n• Live Status: ดูสถานะรถแบบเรียลไทม์\n• Chat: พูดคุยกับคนขับ\n• Profile: จัดการบัญชีผู้ใช้",
                  step,
                  totalSteps,
                  controller,
                  canGoBack: true,
                ),
              ),
            ],
          ),
        );
      }
    }

    return targets;
  }

  // วิดเจ็ต Bottom Navigation Bar ดีไซน์โค้งเว้า (Curved Notch) พรีเมียม พร้อมชิปไอคอนและ Live Status Indicator
  Widget _buildCurvedBottomNav() {
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map_outlined, 'activeIcon': Icons.map, 'label': 'Map'},
      {
        'icon': Icons.directions_bus_outlined,
        'activeIcon': Icons.directions_bus,
        'label': 'Live Status',
      },
      {
        'icon': Icons.chat_bubble_outline,
        'activeIcon': Icons.chat_bubble,
        'label': 'Chat',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'Profile',
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double itemWidth = width / navItems.length;
        final double targetX = itemWidth * _selectedIndex + itemWidth / 2;

        return SizedBox(
          key: keyBottomNav,
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. พื้นหลังบาร์สีขาวไข่มุกพร้อมรอยบากเว้า (Pearl Gradient & Curved Notch)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: targetX, end: targetX),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, animatedX, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(width, 80),
                        painter: _CurvedNavPainter(
                          notchCenter: animatedX,
                        ),
                      ),
                      // 2. ปุ่มวงกลมสีเขียวมรกตลอยอยู่ในรอยบาก (พร้อมขอบสีขาวคมชัด)
                      Positioned(
                        top: 2,
                        left: animatedX - 23,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1F8B2E), Color(0xFF176a21)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 3.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF176a21).withValues(alpha: 0.38),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            navItems[_selectedIndex]['activeIcon'],
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 3. รายการปุ่มกดและข้อความแต่ละแท็บ (พร้อม Capsule Chip รองรับไอคอน)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: List.generate(navItems.length, (index) {
                    final bool isActive = _selectedIndex == index;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _selectedIndex = index);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isActive) ...[
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      navItems[index]['icon'],
                                      color: const Color(0xFF5A605B),
                                      size: 19,
                                    ),
                                  ),
                                  // จุดเขียวกระพริบเตือนเมื่อมีรถออนไลน์ในหน้า Live Status
                                  if (index == 1 && activeShuttles.isNotEmpty)
                                    Positioned(
                                      top: -1,
                                      right: -1,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.6),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5A605B),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 24),
                              Text(
                                navItems[index]['label'],
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF176a21),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStopMarker({required bool isSelected, required String name}) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // หมุดไอคอนจุดจอด (อยู่ตรงกลาง LatLng พอดีเป๊ะ)
        Container(
          width: isSelected ? 34 : 28,
          height: isSelected ? 34 : 28,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF176a21) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : const Color(0xFF757778),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isSelected ? 0.3 : 0.1),
                blurRadius: isSelected ? 6 : 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.hail,
            color: isSelected ? Colors.white : const Color(0xFF757778),
            size: isSelected ? 18 : 15,
          ),
        ),
        // ป้ายชื่อจุดจอดรถ (ลอยอยู่ด้านบน)
        Positioned(
          bottom: isSelected ? 48 : 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF176a21) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.white : const Color(0xFF176a21),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              name,
              style: TextStyle(
                fontSize: isSelected ? 11 : 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF2C2F30),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusMarker(String? status, String? shuttleNumber) {
    Color statusColor = const Color(0xFF176a21); // Default available
    if (status == 'full') {
      statusColor = const Color(0xFF757778); // Grey
    } else if (status == 'break') {
      statusColor = const Color(0xFFF28522); // Orange
    } else if (status == 'offline') {
      statusColor = Colors.red; // Red
    }

    String displayNum = shuttleNumber ?? '';
    displayNum = displayNum
        .replaceAll(RegExp(r'sh#|shuttle#', caseSensitive: false), '')
        .trim();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // วงกลมไอคอนรถบัส (จะอยู่ตรงกลาง LatLng พอดี)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3), // ลดความหนาขอบขาวลง
          child: Container(
            padding: const EdgeInsets.all(7), // ระยะห่างขอบสีถึงไอคอน
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 22,
            ), // ปรับขนาดไอคอนรถบัสตามที่ต้องการ
          ),
        ),
        // ป้ายเบอร์รถ (จะห้อยอยู่ด้านล่างวงกลม)
        if (displayNum.isNotEmpty)
          Positioned(
            bottom: -4, // ขยับลงมาด้านล่างวงกลม
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF176a21).withOpacity(0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white,
                  width: 1.0,
                ), // ลดความหนาขอบขาวของป้ายเบอร์
              ),
              child: Text(
                displayNum,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900, // ปรับให้หนาพิเศษ
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStopTitleArea() {
    String? currentName = isOnBoard ? selectedDropOffName : selectedStopName;
    if (currentName == null) return const SizedBox.shrink();

    String? groupName;
    List<String> groupMembers = [];
    _groupedStops.forEach((gName, members) {
      if (members.contains(currentName)) {
        groupName = gName;
        groupMembers = members;
      }
    });

    if (groupName != null && !isOnBoard) {
      if (!isWaiting && !isAcknowledged) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ฝั่ง :',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF595C5D),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: groupMembers.map((mName) {
                bool isSubSelected = currentName == mName;
                return GestureDetector(
                  onTap: () {
                    final stop = busStops.firstWhere((s) => s['name'] == mName);
                    _moveToStop(stop);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSubSelected
                          ? const Color(0xFF176a21)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF176a21),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      mName.trim(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isSubSelected
                            ? Colors.white
                            : const Color(0xFF176a21),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      } else {
        return Text(
          currentName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2C2F30),
            height: 1.2,
          ),
        );
      }
    }

    return Text(
      currentName,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Color(0xFF2C2F30),
        height: 1.2,
      ),
    );
  }

  Widget _buildStopDetailsCard() {
    // ดึงชื่อ/หมายเลขรถที่กำลังเดินทางมารับ หรือรถที่เราขึ้นไปแล้ว
    String? assignedShuttleName;
    if ((isAcknowledged || isOnBoard) && targetedShuttleId != null) {
      try {
        final trackedBus = activeShuttles.firstWhere(
          (bus) => bus['id'] == targetedShuttleId,
        );
        assignedShuttleName = trackedBus['number']?.toString();
        if (assignedShuttleName == null || assignedShuttleName.trim().isEmpty) {
          assignedShuttleName = trackedBus['name']?.toString();
        }
      } catch (e) {
        assignedShuttleName = null;
      }
    }

    // ถ้าอยู่ในสถานะคนขับรับทราบแล้ว และถูกย่อจากการกดที่แผนที่ ให้แสดงเหลือแค่ปุ่ม "ขึ้นรถเรียบร้อยแล้ว"
    if ((isAcknowledged || isOnBoard) && isCardMinimized) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            child: GestureDetector(
              onTap: isOnBoard ? _toggleWaitState : _boardShuttle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9DF197), Color(0xFF176a21)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF176a21).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isOnBoard
                            ? 'ถึงที่หมายแล้ว (เสร็จสิ้น)'
                            : 'ขึ้นรถเรียบร้อยแล้ว',
                        style: const TextStyle(
                          fontSize: 15.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C2F30).withOpacity(0.1),
                blurRadius: 25,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: keyCardTopSection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF1F2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'จุดจอดรถรับส่ง',
                                style: TextStyle(
                                  color: Color(0xFF595C5D),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            if (assignedShuttleName != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF176a21,
                                  ).withOpacity(0.1),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF176a21,
                                    ).withOpacity(0.5),
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.directions_bus,
                                      size: 12,
                                      color: Color(0xFF176a21),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'รถเบอร์ $assignedShuttleName',
                                      style: const TextStyle(
                                        color: Color(0xFF176a21),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!isWaiting)
                          GestureDetector(
                            onTap: () {
                              if (mounted) {
                                setState(() {
                                  selectedStopName = null;
                                  selectedStopLatLng = null;
                                  estimatedArrivalText = null;
                                  highlightedPath.clear();
                                  targetedShuttleId = null;
                                  isCardMinimized = false;
                                });
                              }
                            },
                            child: const Icon(
                              Icons.close,
                              color: Color(0xFF757778),
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildStopTitleArea(),
                    const SizedBox(height: 6),

                    if (isWaiting)
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'กำลังส่งสัญญาณเรียกคนขับ...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    else if (isAcknowledged || isOnBoard)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: Color(0xFF176a21),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isOnBoard
                                      ? (remainingStops != null
                                            ? 'กำลังเดินทางไปยังจุดหมายของคุณ อีก $remainingStops จุดจอดจะถึงจุดหมายคุณ '
                                            : 'กำลังเดินทางไปยังจุดหมายของคุณ ')
                                      : 'คนขับรับทราบแล้ว! รถกำลังเดินทางมารับคุณที่ป้าย',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF176a21),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (estimatedArrivalText != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  activeShuttles.isEmpty
                                      ? Icons.info_outline
                                      : Icons.timer_outlined,
                                  size: 16,
                                  color: activeShuttles.isEmpty
                                      ? const Color(0xFFD84315)
                                      : const Color(0xFF595C5D),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    activeShuttles.isEmpty
                                        ? estimatedArrivalText!
                                        : (isOnBoard
                                              ? 'เวลาที่จะถึงจุดหมาย: $estimatedArrivalText'
                                              : 'รถจะมาถึง: $estimatedArrivalText'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: activeShuttles.isEmpty
                                          ? const Color(0xFFD84315)
                                          : const Color(0xFF595C5D),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      )
                    else if (estimatedArrivalText != null)
                      Row(
                        children: [
                          Icon(
                            activeShuttles.isEmpty
                                ? Icons.info_outline
                                : Icons.timer_outlined,
                            size: 16,
                            color: activeShuttles.isEmpty
                                ? const Color(0xFFD84315)
                                : const Color(0xFF176a21),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              estimatedArrivalText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: activeShuttles.isEmpty
                                    ? const Color(0xFFD84315)
                                    : const Color(0xFF176a21),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            activeShuttles.isEmpty
                                ? Icons.info_outline
                                : Icons.directions_bus,
                            size: 16,
                            color: activeShuttles.isEmpty
                                ? const Color(0xFFD84315)
                                : const Color(0xFF176a21),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              activeShuttles.isEmpty
                                  ? ' ขณะนี้ยังไม่มีคนขับเปิดแอปออนไลน์ในระบบ'
                                  : 'รถรับส่ง กำลังวิ่งให้บริการ',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: activeShuttles.isEmpty
                                    ? const Color(0xFFD84315)
                                    : const Color(0xFF176a21),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Dropdown เลือกจุดลงรถ (แสดงเฉพาะตอนยังไม่กดเรียกรถ)
              // ส่วนล่างของการ์ด (เลือกปลายทาง + ปุ่มเรียกรถ)
              Container(
                key: keyCardBottomSection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isWaiting && !isAcknowledged) ...[
                      const Text(
                        'เลือกลงที่ป้าย:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF595C5D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _showDropOffSelectionSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: selectedDropOffName == null
                                    ? Colors.grey.shade500
                                    : const Color(0xFF176a21),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedDropOffName ?? 'ต้องการลงที่ป้ายไหน?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: selectedDropOffName == null
                                        ? Colors.grey.shade600
                                        : const Color(0xFF2C2F30),
                                    fontWeight: selectedDropOffName == null
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.search,
                                color: Color(0xFF176a21),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    GestureDetector(
                      onTap: isOnBoard
                          ? _toggleWaitState
                          : (isAcknowledged
                              ? _boardShuttle
                              : (isWaiting
                                  ? _toggleWaitState
                                  : (activeShuttles.isEmpty
                                      ? () {
                                          TopToast.show(
                                            context,
                                            'ไม่สามารถเรียกรถได้: ขณะนี้ไม่มีคนขับออนไลน์อยู่ในระบบ',
                                            isError: true,
                                          );
                                        }
                                      : _toggleWaitState))),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isWaiting
                                ? [Colors.red.shade400, Colors.red.shade600]
                                : (!isWaiting && !isOnBoard && !isAcknowledged && activeShuttles.isEmpty)
                                    ? [Colors.grey.shade400, Colors.grey.shade500]
                                    : [
                                        const Color(0xFF9DF197),
                                        const Color(0xFF176a21),
                                      ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(23),
                          boxShadow: [
                            BoxShadow(
                              color: (!isWaiting && !isOnBoard && !isAcknowledged && activeShuttles.isEmpty)
                                  ? Colors.transparent
                                  : (isWaiting
                                          ? Colors.red
                                          : const Color(0xFF176a21))
                                      .withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isWaiting
                                    ? Icons.cancel
                                    : (isOnBoard
                                          ? Icons.check_circle_outline
                                          : (isAcknowledged
                                                ? Icons.directions_walk
                                                : Icons.waving_hand)),
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isWaiting
                                    ? 'ยกเลิกการรอรถ'
                                    : (isOnBoard
                                          ? 'ถึงที่หมายแล้ว (เสร็จสิ้น)'
                                          : (isAcknowledged
                                                ? 'ขึ้นรถเรียบร้อยแล้ว'
                                                : 'แจ้งรอรถที่จุดนี้')),
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// CustomPainter สำหรับวาด Bottom Navigation Bar โค้งเว้า (Curved Notch) ขอบมนสวยงามพอดี (Radius = 16px)
class _CurvedNavPainter extends CustomPainter {
  final double notchCenter;

  _CurvedNavPainter({required this.notchCenter});

  @override
  void paint(Canvas canvas, Size size) {
    const double barTop = 16.0;
    const double notchDepth = 25.0;
    const double notchHalfWidth = 34.0;
    const double radius = 16.0; // ปรับลดความโค้งขอบมนซ้าย-ขวาลงมาที่ 16px ตามที่ต้องการ

    // 1. สร้าง Base Path สี่เหลี่ยมขอบมนโค้งมนสวยกระชับ
    final RRect barRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, size.height - barTop),
      const Radius.circular(radius),
    );

    // 2. สร้าง Path รอยบากโค้งเว้า นุ่มนวล
    final Path notchPath = Path();
    notchPath.moveTo(notchCenter - notchHalfWidth, barTop);
    notchPath.cubicTo(
      notchCenter - 20,
      barTop,
      notchCenter - 22,
      barTop + notchDepth,
      notchCenter,
      barTop + notchDepth,
    );
    notchPath.cubicTo(
      notchCenter + 22,
      barTop + notchDepth,
      notchCenter + 20,
      barTop,
      notchCenter + notchHalfWidth,
      barTop,
    );
    notchPath.lineTo(notchCenter + notchHalfWidth, 0);
    notchPath.lineTo(notchCenter - notchHalfWidth, 0);
    notchPath.close();

    // 3. ผสานตัดรอยบากออกจากตัวบาร์อย่างนุ่มนวล
    final Path finalPath = Path.combine(
      PathOperation.difference,
      Path()..addRRect(barRRect),
      notchPath,
    );

    // 4. วาดเงามิติ 2 ชั้น (เงาสีเขียวมรกตบางๆ + เงา Depth นุ่มนวล)
    canvas.drawShadow(
      finalPath,
      const Color(0xFF176a21).withValues(alpha: 0.08),
      16.0,
      true,
    );
    canvas.drawShadow(
      finalPath,
      Colors.black.withValues(alpha: 0.08),
      10.0,
      true,
    );

    // 5. วาดพื้นหลังไล่เฉดสีขาวไข่มุก (Soft Pearl Gradient) สวยพรีเมียม
    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF9FBF9),
        ],
      ).createShader(Rect.fromLTWH(0, barTop, size.width, size.height - barTop));
    canvas.drawPath(finalPath, fillPaint);

    // 6. วาดเส้นขอบบางประณีต (Subtle Hairline Accent Border)
    final Paint borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(finalPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedNavPainter oldDelegate) {
    return oldDelegate.notchCenter != notchCenter;
  }
}


