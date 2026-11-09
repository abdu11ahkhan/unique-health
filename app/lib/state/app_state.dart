import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api.dart';
import '../core/ble_transport.dart';
import '../core/body_calc.dart' as calc;
import '../core/composite_transport.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../screens/result_screen.dart';

String defaultBaseUrl() {
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000'; // Android emulator -> host PC
  return 'http://localhost:3000';
}

final navKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class AppState extends ChangeNotifier {
  late final Api api;
  late final CompositeTransport scale;
  late final SharedPreferences prefs;

  bool ready = false;
  AppUser? user;
  List<Member> members = [];
  int? memberId;
  List<Device> devices = [];
  List<BodyRecord> records = [];
  List<BodyRecord> unclaimed = [];
  Map<String, dynamic>? goal;
  Map<String, dynamic>? weekly;
  int unread = 0;
  List<Map<String, dynamic>> messages = [];
  int _beats = 0;
  Map<String, dynamic> settings = {'unit': 'kg', 'darkMode': false};
  bool loading = false;

  // Offline mode: cached reads + an outbox of queued writes that sync when the server is back
  bool offline = false;
  bool syncing = false;
  List<Map<String, dynamic>> outbox = [];
  final List<String> syncNotes = [];
  Timer? _beat;
  final Map<int, String> _localIds = {};
  int get pending => outbox.length;

  // Scale presence / auto-connect / background save
  int measureActive = 0; // >0 while a measure or food screen handles readings itself
  Set<String> onlineMacs = {};
  Timer? _watch;
  bool _autoHandled = false;

  Member? get member {
    for (final m in members) {
      if (m.id == memberId) return m;
    }
    return members.isEmpty ? null : members.first;
  }

  /// Scale sources. The virtual scale is for testing; Bluetooth needs a phone build.
  bool get useSim => prefs.getBool('useSim') ?? true;
  bool get useBle => prefs.getBool('useBle') ?? BleTransport.supported;
  Future<void> setUseSim(bool v) async {
    await prefs.setBool('useSim', v);
    notifyListeners();
  }

  Future<void> setUseBle(bool v) async {
    await prefs.setBool('useBle', v);
    notifyListeners();
  }

  /// UI language code (see I18n.languages). Defaults to the phone language when we have a translation.
  String get lang {
    final saved = prefs.getString('lang');
    if (saved != null) return saved;
    final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return I18n.languages.containsKey(sys) ? sys : 'en';
  }

  Future<void> setLang(String code) async {
    await prefs.setString('lang', code);
    notifyListeners();
  }

  bool get useLb => settings['unit'] == 'lb';
  ThemeMode get themeMode => settings['darkMode'] == true ? ThemeMode.dark : ThemeMode.light;
  BodyRecord? get latest => records.isEmpty ? null : records.first;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    api = Api(prefs, prefs.getString('baseUrl') ?? defaultBaseUrl());
    api.onSessionExpired = () {
      if (user != null) {
        user = null;
        notifyListeners();
      }
    };
    scale = CompositeTransport(SimulatorTransport(() => api.wsUrl), BleTransport(), useSim: () => useSim, useBle: () => useBle);
    scale.readings.listen(_onGlobalReading);
    if (api.hasSession) {
      try {
        await loadAll();
      } catch (e) {
        final network = e is ApiException && e.code == -1;
        if (user == null && !network) await api.clearTokens();
      }
    }
    ready = true;
    notifyListeners();
    _watch = Timer.periodic(const Duration(seconds: 3), (_) => _watchTick());
    _beat = Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
  }

  /// Looks for bound scales on the hub and connects automatically, like the
  /// original app does when a known scale wakes up.
  Future<void> _watchTick() async {
    if (user == null || devices.isEmpty) return;
    if (scale.state == LinkState.connecting) return;
    if (scale.state == LinkState.connected) {
      onlineMacs = {if (scale.device != null) scale.device!.mac};
      return;
    }
    try {
      final found = await scale.scan(timeout: const Duration(seconds: 2), background: true);
      onlineMacs = found.map((d) => d.mac).toSet();
      if (scale.state != LinkState.disconnected) return;
      for (final d in devices) {
        if (onlineMacs.contains(d.mac)) {
          await scale.connect(d.mac);
          break;
        }
      }
    } catch (_) {
      onlineMacs = {};
    }
    notifyListeners();
  }

  /// Saves a finished body measurement when no measure screen is open.
  Future<void> _onGlobalReading(ScaleReading r) async {
    // A new weighing cycle (or stepping off) re-arms saving.
    if ((r.stage == 'idle' && r.value < 1) || (r.stage == 'weighing' && !r.stable)) {
      _autoHandled = false;
      if (r.stage == 'idle') return;
    }
    if (_autoHandled || measureActive > 0 || user == null || member == null) return;
    if (r.unit != 'kg' || r.stage != 'done' || r.impedance <= 0) return; // body-scale frames only
    _autoHandled = true;
    try {
      Device? dev;
      for (final d in devices) {
        if (d.mac == scale.device?.mac) dev = d;
      }
      final who = member;
      final rec = await saveMeasurement(weight: r.value, impedance: r.impedance, memberId: who!.id, deviceId: dev?.id, source: 'scale');
      _snack(SnackBar(
        content: Text('Saved ${fmtWeight(rec.weight)} for ${who.name}${rec.id < 0 ? ' (will sync when online)' : ''}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'View', onPressed: () => navKey.currentState?.push(MaterialPageRoute(builder: (_) => ResultScreen(record: rec, member: who)))),
      ));
    } catch (e) {
      _snack(SnackBar(content: Text('Could not save measurement: $e'), backgroundColor: Colors.red.shade700));
    }
  }

  // ----- auth -----
  Future<void> _afterAuth(dynamic data) async {
    await api.saveTokens(data['accessToken'], data['refreshToken']);
    await loadAll();
  }

  Future<void> login(String email, String password) async =>
      _afterAuth(await api.post('/app/user/login', {'email': email, 'password': password}, false));

  Future<void> signUp(String email, String password, String nickname) async => _afterAuth(
      await api.post('/app/user/signUp', {'email': email, 'password': password, 'nickname': nickname}, false));

  Future<void> logout() async {
    try {
      await api.post('/app/user/logOut');
    } catch (_) {}
    await scale.disconnect();
    await api.clearTokens();
    user = null;
    members = [];
    devices = [];
    records = [];
    memberId = null;
    notifyListeners();
  }

  Future<void> deleteAccount(String password) async {
    await api.post('/app/user/logOff', {'password': password});
    await api.clearTokens();
    user = null;
    notifyListeners();
  }

  // ----- cache + offline helpers -----
  int get _uid => user?.id ?? prefs.getInt('lastUid') ?? 0;
  String _ck(String name) => 'c:$_uid:$name';

  void _setOffline(bool v) {
    if (offline != v) {
      offline = v;
      notifyListeners();
    }
  }

  /// GET with a local cache: fresh data is cached, and when the server is unreachable the last cached copy is returned.
  Future<dynamic> cachedGet(String name, String path, {Map<String, dynamic>? query}) async {
    try {
      final d = await api.get(path, query: query);
      await prefs.setString(_ck(name), jsonEncode(d));
      if (offline) _setOffline(false);
      return d;
    } on ApiException catch (e) {
      if (e.code == -1) {
        final c = prefs.getString(_ck(name));
        if (c != null) {
          _setOffline(true);
          return jsonDecode(c);
        }
      }
      rethrow;
    }
  }

  Future<void> _saveOutbox() async => prefs.setString('outbox:$_uid', jsonEncode(outbox));

  void _loadOutbox() {
    final raw = prefs.getString('outbox:$_uid');
    outbox = raw == null ? [] : (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
  int _localId(String opId) {
    final id = -((opId.hashCode.abs() % 1000000000) + 1);
    _localIds[id] = opId;
    return id;
  }

  BodyRecord _localRecord(Map<String, dynamic> op) {
    final b = Map<String, dynamic>.from(op['body']);
    final m = {for (final e in Map<String, dynamic>.from(op['metrics'] ?? {}).entries) e.key: (e.value as num).toDouble()};
    return BodyRecord(id: _localId(op['id']), memberId: (b['memberId'] as num?)?.toInt(), weight: (b['weight'] as num).toDouble(), impedance: (b['impedance'] as num?)?.toDouble() ?? 0, metrics: m, source: '${b['source'] ?? 'manual'}', ts: DateTime.fromMillisecondsSinceEpoch((b['ts'] as num).toInt()));
  }

  /// Server list + records still waiting in the outbox, minus records queued for deletion.
  List<BodyRecord> _overlay(List<BodyRecord> server, bool Function(BodyRecord) wanted) {
    final deleted = {for (final op in outbox) if (op['kind'] == 'bodyDelete') (op['body']['id'] as num).toInt()};
    final local = [for (final op in outbox) if (op['kind'] == 'bodyData') _localRecord(op)].where(wanted);
    final all = [...local, ...server.where((r) => !deleted.contains(r.id))];
    all.sort((a, b) => b.ts.compareTo(a.ts));
    return all;
  }

  // ----- loading -----
  Future<void> loadAll() async {
    loading = true;
    notifyListeners();
    try {
      final u = await cachedGet('user', '/app/user');
      user = AppUser.fromJson(Map<String, dynamic>.from(u));
      await prefs.setInt('lastUid', user!.id);
      _loadOutbox();
      settings = {...settings, ...Map<String, dynamic>.from(await cachedGet('settings', '/app/user/getSetting'))};
      await loadMembers();
      await loadDevices();
      await loadRecords();
      await loadMessages();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMembers() async {
    final l = await cachedGet('members', '/app/memberDevice/list') as List;
    members = l.map((e) => Member.fromJson(Map<String, dynamic>.from(e))).toList();
    if (memberId == null || !members.any((m) => m.id == memberId)) memberId = members.isEmpty ? null : members.first.id;
    notifyListeners();
  }

  Future<void> loadDevices() async {
    final l = await cachedGet('devices', '/app/user/getUserDevice') as List;
    devices = l.map((e) => Device.fromJson(Map<String, dynamic>.from(e))).toList();
    notifyListeners();
  }

  Future<void> loadRecords() async {
    var server = <BodyRecord>[];
    if (memberId != null) {
      final l = await cachedGet('records:$memberId', '/app/bodyData/list', query: {'memberId': memberId}) as List;
      server = l.map((e) => BodyRecord.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    records = _overlay(server, (r) => r.memberId == memberId && memberId != null);
    final u = await cachedGet('unclaimed', '/app/bodyData/unclaimed') as List;
    unclaimed = _overlay(u.map((e) => BodyRecord.fromJson(Map<String, dynamic>.from(e))).toList(), (r) => r.memberId == null).where((r) => r.memberId == null).toList();
    await loadInsights();
    notifyListeners();
  }

  /// In-app message center (goal / streak / weekly summary notices from the backend).
  Future<void> loadMessages() async {
    try {
      final r = Map<String, dynamic>.from(await cachedGet('messages', '/app/messages'));
      messages = [for (final m in (r['messages'] as List)) Map<String, dynamic>.from(m)];
      unread = (r['unread'] as num).toInt();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markMessagesRead({int? id}) async {
    await api.post('/app/messages/read', {if (id != null) 'id': id});
    await loadMessages();
  }

  Future<void> deleteMessage(int id) async {
    messages.removeWhere((m) => m['id'] == id);
    notifyListeners();
    try {
      await api.post('/app/messages/delete', {'id': id});
    } catch (_) {}
    await loadMessages();
  }

  /// Goal and weekly summary for the selected profile.
  Future<void> loadInsights() async {
    if (memberId == null) {
      goal = null;
      weekly = null;
      return;
    }
    try {
      final g = await cachedGet('goal:$memberId', '/app/goal', query: {'memberId': memberId});
      goal = g == null ? null : Map<String, dynamic>.from(g);
      final today = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0).millisecondsSinceEpoch;
      weekly = Map<String, dynamic>.from(await cachedGet('weekly:$memberId', '/app/summary/weekly', query: {'memberId': memberId, 'today': today}));
    } catch (_) {
      // insights are optional; never block the main screens
    }
  }

  Future<void> saveGoal(String type, double target, DateTime? date) async {
    await api.post('/app/goal', {'memberId': memberId, 'type': type, 'target': target, if (date != null) 'targetDate': date.millisecondsSinceEpoch});
    await loadInsights();
    notifyListeners();
  }

  Future<void> deleteGoal() async {
    await api.post('/app/goal/delete', {'memberId': memberId});
    goal = null;
    notifyListeners();
  }

  Future<void> selectMember(int id) async {
    memberId = id;
    notifyListeners();
    await loadRecords();
  }

  // ----- settings -----
  Future<void> saveSetting(String key, dynamic value) async {
    settings[key] = value;
    notifyListeners();
    await api.post('/app/user/saveOrUpdateSetting', {key: value});
  }

  Future<void> updateNickname(String name) async {
    await api.post('/app/user/update', {'nickname': name});
    user = AppUser(user!.id, user!.email, name);
    notifyListeners();
  }

  // ----- writes that survive being offline -----
  /// Saves a measurement. Offline, it is queued, shown immediately (metrics computed on the device) and synced later.
  Future<BodyRecord> saveMeasurement({required double weight, double impedance = 0, int? memberId, int? deviceId, String source = 'manual', Map<String, double>? metrics}) async {
    final id = _newId();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final body = <String, dynamic>{
      'weight': weight,
      'impedance': impedance,
      'memberId': memberId,
      'deviceId': deviceId,
      'source': source,
      'clientId': id,
      'ts': ts,
      if (metrics != null) 'metrics': metrics,
    };
    try {
      if (offline) throw ApiException('offline', -1);
      final d = await api.post('/app/bodyData', body);
      final rec = BodyRecord.fromJson(Map<String, dynamic>.from(d));
      await loadRecords();
      return rec;
    } on ApiException catch (e) {
      if (e.code != -1) rethrow;
      _setOffline(true);
      Map<String, double> local = metrics ?? {};
      if (metrics == null && memberId != null) {
        final m = members.where((x) => x.id == memberId).firstOrNull;
        if (m != null) local = calc.computeMetrics(weight: weight, impedance: impedance, height: m.height, age: m.age, gender: m.gender, athlete: m.athlete);
      }
      final op = {'id': id, 'kind': 'bodyData', 'body': body, 'metrics': local, 'at': ts};
      outbox.add(op);
      await _saveOutbox();
      await loadRecords();
      return _localRecord(op);
    }
  }

  Future<void> deleteRecord(BodyRecord r) async {
    if (r.id < 0) {
      outbox.removeWhere((op) => op['id'] == _localIds[r.id]);
      await _saveOutbox();
      await loadRecords();
      return;
    }
    try {
      if (offline) throw ApiException('offline', -1);
      await api.post('/app/bodyData/delete', {'id': r.id});
    } on ApiException catch (e) {
      if (e.code != -1) rethrow;
      _setOffline(true);
      outbox.add({'id': _newId(), 'kind': 'bodyDelete', 'body': {'id': r.id}, 'at': DateTime.now().millisecondsSinceEpoch});
      await _saveOutbox();
    }
    await loadRecords();
  }

  /// Logs food. Returns true if it reached the server, false if it was queued.
  Future<bool> uploadFood(Map<String, dynamic> body) async {
    final b = {...body, 'clientId': _newId(), 'ts': DateTime.now().millisecondsSinceEpoch};
    try {
      if (offline) throw ApiException('offline', -1);
      await api.post('/food/record/upload', b);
      return true;
    } on ApiException catch (e) {
      if (e.code != -1) rethrow;
      _setOffline(true);
      outbox.add({'id': b['clientId'], 'kind': 'foodUpload', 'body': b, 'at': b['ts']});
      await _saveOutbox();
      notifyListeners();
      return false;
    }
  }

  /// Food entries waiting to sync (shown in the diary while offline).
  List<FoodRecord> pendingFoods(DateTime from, DateTime to) {
    final out = <FoodRecord>[];
    for (final op in outbox) {
      if (op['kind'] != 'foodUpload') continue;
      final b = Map<String, dynamic>.from(op['body']);
      final ts = DateTime.fromMillisecondsSinceEpoch((b['ts'] as num).toInt());
      if (ts.isBefore(from) || !ts.isBefore(to)) continue;
      final per = Map<String, dynamic>.from(b['per100'] ?? {});
      final k = (b['grams'] as num).toDouble() / 100;
      double v(String x) => ((per[x] as num?)?.toDouble() ?? 0) * k;
      out.add(FoodRecord(id: -1, name: '${b['name']}', grams: (b['grams'] as num).toDouble(), kcal: v('kcal'), protein: v('protein'), fat: v('fat'), carb: v('carb'), meal: '${b['meal'] ?? 'snack'}', ts: ts));
    }
    return out;
  }

  void _snack(SnackBar bar) {
    try {
      messengerKey.currentState?.showSnackBar(bar);
    } catch (_) {} // no UI (e.g. in tests)
  }

  /// Sends a command to the connected scale and waits for its answer event.
  /// Throws if the scale is not connected, does not answer, or reports an error event ([failEvents]).
  Future<Map<String, dynamic>> deviceRequest(String cmd, String answer, {Map<String, dynamic> data = const {}, Duration timeout = const Duration(seconds: 6), List<String> failEvents = const []}) async {
    if (scale.state != LinkState.connected) throw ApiException('Connect to the scale first.');
    final f = scale.events.firstWhere((e) => e['event'] == answer || failEvents.contains(e['event'])).timeout(timeout, onTimeout: () => throw ApiException('The scale did not answer. Check that it is on and connected.'));
    scale.command({'cmd': cmd, ...data});
    final e = await f;
    if (failEvents.contains(e['event'])) throw ApiException('The scale reported: ${e['data']['reason'] ?? e['event']}');
    return Map<String, dynamic>.from(e['data']);
  }

  Future<void> checkConnection() => _heartbeat();

  Future<void> _heartbeat() async {
    if (user == null || syncing) return;
    try {
      await api.get('/common/whichServer', auth: false);
    } catch (_) {
      _setOffline(true);
      return;
    }
    final was = offline;
    _setOffline(false);
    if (++_beats % 12 == 0) await loadMessages(); // about once a minute
    await syncNow();
    if (was) {
      try {
        await loadAll();
      } catch (_) {}
    }
  }

  /// Sends queued writes in order. Stops at the first network failure; drops writes the server rejects.
  Future<void> syncNow() async {
    if (syncing || outbox.isEmpty) return;
    syncing = true;
    notifyListeners();
    var changed = false;
    try {
      for (final op in List<Map<String, dynamic>>.from(outbox)) {
        final path = op['kind'] == 'bodyData' ? '/app/bodyData' : op['kind'] == 'foodUpload' ? '/food/record/upload' : '/app/bodyData/delete';
        try {
          await api.post(path, Map<String, dynamic>.from(op['body']));
          outbox.removeWhere((o) => o['id'] == op['id']);
          changed = true;
        } on ApiException catch (e) {
          if (e.code == -1) {
            _setOffline(true);
            break;
          }
          outbox.removeWhere((o) => o['id'] == op['id']);
          syncNotes.add('A queued ${op['kind']} was rejected: ${e.message}');
          changed = true;
        }
      }
      await _saveOutbox();
    } finally {
      syncing = false;
      notifyListeners();
    }
    if (changed) {
      try {
        await loadRecords();
      } catch (_) {}
      if (outbox.isEmpty) {
        _snack(SnackBar(content: Text(syncNotes.isEmpty ? 'Back online. Everything is synced.' : syncNotes.removeLast()), behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ----- formatting helpers -----
  String fmtWeight(double kg, {int d = 1}) =>
      useLb ? '${(kg * 2.20462).toStringAsFixed(d)} lb' : '${kg.toStringAsFixed(d)} kg';
  double toDisplayWeight(double kg) => useLb ? kg * 2.20462 : kg;
  double fromDisplayWeight(double v) => useLb ? v / 2.20462 : v;
  String get weightUnit => useLb ? 'lb' : 'kg';

  @override
  void dispose() {
    _watch?.cancel();
    _beat?.cancel();
    scale.dispose();
    super.dispose();
  }
}
