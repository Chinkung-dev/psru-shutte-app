import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:psru_shuttle_app/services/stop_five_bypass.dart';

void main() {
  const four = LatLng(16.83, 100.2085);
  const fork = LatLng(16.83, 100.21);
  const five = LatLng(16.82895, 100.21);
  const six = LatLng(16.83, 100.2117);
  final graph = <LatLng, List<LatLng>>{
    four: [fork],
    fork: [four, five, six],
    five: [fork],
    six: [fork],
  };
  final stops = <Map<String, dynamic>>[
    {'order': 4, 'lat': four.latitude, 'lng': four.longitude},
    {'order': 5, 'lat': five.latitude, 'lng': five.longitude},
    {'order': 6, 'lat': six.latitude, 'lng': six.longitude},
  ];
  late StopFiveBypass tracker;
  setUp(() => tracker = StopFiveBypass());
  int? observe(
    LatLng p, {
    int? last = 4,
    String bus = 'one',
    Map<LatLng, List<LatLng>>? roads,
  }) => tracker.nextStopOrder(
    graph: roads ?? graph,
    stops: stops,
    shuttleId: bus,
    position: p,
    lastPassedStop: last,
  );

  test('ก่อนถึงแยกและ GPS แกว่งตรงแยกยังต้องผ่านป้าย 5', () {
    expect(observe(four), 5);
    expect(observe(const LatLng(16.83, 100.21005)), 5);
    expect(observe(const LatLng(16.83, 100.21015)), 5);
  });
  test('เข้าแขนงป้าย 5 ยังคงป้าย 5', () {
    expect(observe(const LatLng(16.8296, 100.21)), 5);
    expect(observe(const LatLng(16.8294, 100.21)), 5);
  });
  test('เลี้ยวไป 6 ต่อเนื่อง แม้ last_passed_stop ยังค้าง 4 ให้ข้าม 5', () {
    expect(observe(const LatLng(16.83, 100.2103)), 5);
    expect(observe(const LatLng(16.83, 100.2104)), 6);
    expect(observe(fork), 6); // ไม่สลับกลับเพราะ GPS แกว่ง
  });
  test('ตำแหน่งซ้ำและการเคลื่อนย้อนกลับไม่ใช่หลักฐานการข้าม', () {
    expect(observe(const LatLng(16.83, 100.2105)), 5);
    expect(observe(const LatLng(16.83, 100.2105)), 5);
    expect(observe(const LatLng(16.83, 100.2104)), 5);
    expect(observe(const LatLng(16.8297, 100.21)), 5);
  });
  test('ข้อมูลนอกถนนไม่ทำให้ข้าม', () {
    expect(observe(const LatLng(16.8305, 100.2103)), 5);
    expect(observe(const LatLng(16.8305, 100.2105)), 5);
  });
  test('แยกสถานะรถและเริ่มใหม่หลังพ้นช่วงป้าย 4', () {
    observe(const LatLng(16.83, 100.2103));
    expect(observe(const LatLng(16.83, 100.2104)), 6);
    expect(observe(fork, bus: 'two'), 5);
    expect(observe(six, last: 6), isNull);
    expect(observe(fork), 5);
  });
  test('รถหายหรือจบรอบขณะไม่ได้เลือกปลายทางต้องล้างผลเดิม', () {
    observe(const LatLng(16.83, 100.2103));
    observe(const LatLng(16.83, 100.2104));
    tracker.retainApproachingVehicles([]);
    expect(observe(fork), 5);
  });
  test('ป้ายอื่นและข้อมูล last_passed ที่ไม่ทราบใช้ระบบเดิม', () {
    expect(observe(fork, last: 3), isNull);
    expect(observe(fork, last: 5), isNull);
    expect(observe(fork, last: null), isNull);
  });
  test('หาถนนต่อไป 6 ไม่ได้ต้องไม่เดาว่าข้าม', () {
    final disconnected = <LatLng, List<LatLng>>{
      four: [fork],
      fork: [four, five],
      five: [fork],
      six: [],
    };
    expect(observe(const LatLng(16.83, 100.2103), roads: disconnected), isNull);
    expect(observe(const LatLng(16.83, 100.2104), roads: disconnected), isNull);
  });
  test('กรณีถนนบังคับผ่าน 5 จริง ห้ามตัด 5 ออก', () {
    final throughFive = <LatLng, List<LatLng>>{
      four: [fork],
      fork: [four, five],
      five: [fork, six],
      six: [five],
    };
    expect(observe(const LatLng(16.83, 100.2104), roads: throughFive), isNull);
  });
}
