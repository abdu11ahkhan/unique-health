// Starts its own backend on :3101, then stops and restarts it to exercise offline mode and sync.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unique_clone/state/app_state.dart';

const port = 3101;

Future<Process> startBackend(String db) async {
  final p = await Process.start('node', ['--no-warnings', 'server.js'], workingDirectory: '../backend', environment: {'PORT': '$port', 'DB_FILE': db});
  p.stdout.drain();
  p.stderr.drain();
  for (var i = 0; i < 40; i++) {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
      final r = await (await c.getUrl(Uri.parse('http://127.0.0.1:$port/health'))).close();
      await r.drain();
      return p;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
  throw StateError('backend did not start');
}

Future<void> stopBackend(Process p) async {
  p.kill();
  await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  await Future.delayed(const Duration(milliseconds: 300));
}

void main() {
  test('offline: cached reads, queued writes, local metrics, idempotent sync', () async {
    final db = '${Directory.systemTemp.path}/uc-offline-${DateTime.now().millisecondsSinceEpoch}.db';
    var be = await startBackend(db);
    SharedPreferences.setMockInitialValues({'baseUrl': 'http://127.0.0.1:$port'});
    final s = AppState();
    try {
      await s.init();
      await s.login('demo@unique.test', 'demo1234');
      final before = s.records.length;
      expect(before, 30);
      expect(s.offline, isFalse);

      await stopBackend(be); // ---- server goes away ----

      final rec = await s.saveMeasurement(weight: 77.7, impedance: 500, memberId: s.member!.id, source: 'scale');
      expect(rec.id, lessThan(0), reason: 'queued record gets a temporary negative id');
      expect(s.offline, isTrue);
      expect(s.pending, 1);
      expect(rec.m('bodyFat'), isNotNull, reason: 'metrics are computed on the device');
      expect(s.records.length, before + 1);
      expect(s.records.first.weight, 77.7);

      // reads fall back to the cache
      await s.loadMembers();
      expect(s.members, isNotEmpty);
      expect(s.offline, isTrue);

      // a second record, then delete it before it ever synced
      final tmp = await s.saveMeasurement(weight: 60.0, impedance: 0, memberId: s.member!.id);
      expect(s.pending, 2);
      await s.deleteRecord(tmp);
      expect(s.pending, 1);

      // food is queued and shown in the diary overlay
      final sent = await s.uploadFood({'name': 'Egg', 'grams': 100, 'per100': {'kcal': 155, 'protein': 13, 'fat': 11, 'carb': 1}, 'meal': 'lunch'});
      expect(sent, isFalse);
      expect(s.pending, 2);
      final today = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
      expect(s.pendingFoods(today, today.add(const Duration(days: 1))).single.kcal, 155);

      // the outbox survives an app restart
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('outbox:${s.user!.id}'), contains('Egg'));

      be = await startBackend(db); // ---- server is back ----
      await s.checkConnection();
      expect(s.offline, isFalse);
      expect(s.pending, 0);
      await s.syncNow(); // replaying again must not duplicate anything
      await s.loadRecords();
      expect(s.records.length, before + 1);
      expect(s.records.first.id, greaterThan(0));
      expect(s.records.first.weight, 77.7);
      expect(s.records.where((r) => r.weight == 77.7).length, 1);
      final food = await s.api.get('/food/record/list', query: {'from': today.millisecondsSinceEpoch, 'to': today.millisecondsSinceEpoch + 86400000}) as List;
      expect(food.where((f) => f['name'] == 'Egg').length, 1);
    } finally {
      s.dispose();
      await stopBackend(be);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
