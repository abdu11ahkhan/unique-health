// Needs the backend running: PORT=3100 node server.js  (see README). Skipped otherwise.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unique_clone/core/models.dart';
import 'package:unique_clone/core/scale_transport.dart';
import 'package:unique_clone/state/app_state.dart';

const base = 'http://127.0.0.1:3100';

void main() {
  test('full client stack against live backend + virtual scale', () async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      await (await c.getUrl(Uri.parse('$base/health'))).close();
    } catch (_) {
      markTestSkipped('backend not running on :3100');
      return;
    }
    SharedPreferences.setMockInitialValues({'baseUrl': base});
    final s = AppState();
    await s.init();
    expect(s.user, isNull);
    await s.login('demo@unique.test', 'demo1234');
    expect(s.user!.email, 'demo@unique.test');
    expect(s.members.length, greaterThanOrEqualTo(2));
    expect(s.records.length, 30);
    expect(s.latest!.m('bodyFat'), isNotNull);

    // virtual scale registers on the hub
    final ws = await WebSocket.connect('ws://127.0.0.1:3100/ws');
    ws.add(jsonEncode({'type': 'hello', 'role': 'scale', 'mac': 'E2:E2:E2:00:00:01', 'name': 'CF568_G', 'kind': 'body'}));
    await Future.delayed(const Duration(milliseconds: 300));

    final found = await s.scale.scan();
    expect(found.any((d) => d.mac == 'E2:E2:E2:00:00:01'), isTrue);
    await s.api.post('/app/user/addUserDevice', {'mac': 'E2:E2:E2:00:00:01', 'name': 'CF568_G', 'kind': 'body'});
    await s.loadDevices();
    expect(s.devices.any((d) => d.mac == 'E2:E2:E2:00:00:01'), isTrue);

    await s.scale.connect('E2:E2:E2:00:00:01');
    expect(s.scale.state, LinkState.connected);
    final got = s.scale.readings.firstWhere((r) => r.stage == 'done').timeout(const Duration(seconds: 3));
    ws.add(jsonEncode({'type': 'reading', 'value': 73.4, 'unit': 'kg', 'stable': true, 'stage': 'done', 'impedance': 505}));
    final r = await got;
    expect(r.value, 73.4);

    final before = s.records.length;
    final d = await s.api.post('/app/bodyData', {'weight': r.value, 'impedance': r.impedance, 'memberId': s.member!.id, 'source': 'scale'});
    final rec = BodyRecord.fromJson(Map<String, dynamic>.from(d));
    expect(rec.m('bodyFat'), inInclusiveRange(4, 60));
    await s.loadRecords();
    expect(s.records.length, before + 1);

    // wrong credentials surface a readable error
    final s2 = AppState();
    await s2.init();
    expect(() => s2.login('demo@unique.test', 'wrong'), throwsA(predicate((e) => e.toString().contains('wrong email or password'))));

    await s.scale.disconnect();
    await ws.close();
  });
}
