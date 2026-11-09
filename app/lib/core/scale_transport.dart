import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart' show ApiException;

class ScaleDevice {
  final String mac, name, kind;
  final int rssi;
  final List<String> caps; // optional features the scale reports: wifi, fingerprint
  ScaleDevice(this.mac, this.name, this.kind, this.rssi, {this.caps = const []});
  factory ScaleDevice.fromJson(Map<String, dynamic> j) => ScaleDevice(j['mac'], j['name'] ?? 'Scale', j['kind'] ?? 'body', (j['rssi'] as num?)?.toInt() ?? -60,
      caps: [for (final c in (j['caps'] as List? ?? const [])) '$c']);
  bool has(String cap) => caps.contains(cap);
}

/// One frame from the scale. `stage`: weighing | measuring | done | error | idle.
class ScaleReading {
  final double value; // kg for body scales, grams for food scales
  final String unit;
  final bool stable;
  final String stage;
  final double impedance;
  ScaleReading(this.value, this.unit, this.stable, this.stage, this.impedance);
  factory ScaleReading.fromJson(Map<String, dynamic> j) => ScaleReading(
        (j['value'] as num).toDouble(), j['unit'] ?? 'kg', j['stable'] == true, j['stage'] ?? 'weighing',
        (j['impedance'] as num?)?.toDouble() ?? 0);
}

enum LinkState { disconnected, connecting, connected }

/// Transport abstraction. The app only talks to this interface, so a real
/// BLE implementation (GATT Weight Scale 0x181D / Body Composition 0x181B or a
/// vendor protocol) can be dropped in next to [SimulatorTransport].
abstract class ScaleTransport extends ChangeNotifier {
  LinkState get state;
  ScaleDevice? get device;
  Stream<ScaleReading> get readings;

  /// Device events (Wi-Fi scan results, fingerprint users, firmware progress...): {event, data}.
  Stream<Map<String, dynamic>> get events;
  Future<List<ScaleDevice>> scan({Duration timeout});
  Future<void> connect(String mac);
  Future<void> disconnect();
  void command(Map<String, dynamic> cmd);
}

/// Talks to the virtual scale through the backend's WebSocket hub.
class SimulatorTransport extends ScaleTransport {
  String Function() urlProvider;
  SimulatorTransport(this.urlProvider);

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  final _readings = StreamController<ScaleReading>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _deviceEvents = StreamController<Map<String, dynamic>>.broadcast();
  LinkState _state = LinkState.disconnected;
  ScaleDevice? _device;

  @override
  LinkState get state => _state;
  @override
  ScaleDevice? get device => _device;
  @override
  Stream<ScaleReading> get readings => _readings.stream;
  @override
  Stream<Map<String, dynamic>> get events => _deviceEvents.stream;

  void _set(LinkState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> _open() async {
    if (_ch != null) return;
    final ch = WebSocketChannel.connect(Uri.parse(urlProvider()));
    await ch.ready.timeout(const Duration(seconds: 5));
    _ch = ch;
    _sub = ch.stream.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (m['type']) {
        case 'reading':
          _readings.add(ScaleReading.fromJson(m));
          break;
        case 'event':
          _deviceEvents.add({'event': m['event'], 'data': Map<String, dynamic>.from(m['data'] ?? {})});
          break;
        case 'disconnected':
          _device = null;
          _set(LinkState.disconnected);
          break;
        default:
          _events.add(m);
      }
    }, onDone: _closed, onError: (_) => _closed());
    ch.sink.add(jsonEncode({'type': 'hello', 'role': 'app'}));
  }

  void _closed() {
    _sub?.cancel();
    _ch = null;
    _device = null;
    _set(LinkState.disconnected);
  }

  Future<Map<String, dynamic>> _await(String type, {Duration timeout = const Duration(seconds: 4)}) =>
      _events.stream.firstWhere((m) => m['type'] == type || m['type'] == 'error').timeout(timeout);

  @override
  Future<List<ScaleDevice>> scan({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      await _open();
      final f = _await('devices', timeout: timeout);
      _ch!.sink.add(jsonEncode({'type': 'list'}));
      final r = await f;
      if (r['type'] == 'error') return [];
      return (r['devices'] as List).map((d) => ScaleDevice.fromJson(d as Map<String, dynamic>)).toList();
    } catch (_) {
      _closed();
      rethrow;
    }
  }

  @override
  Future<void> connect(String mac) async {
    if (_state == LinkState.connected && _device?.mac == mac) return;
    _set(LinkState.connecting);
    try {
      await _open();
      final f = _await('connected');
      _ch!.sink.add(jsonEncode({'type': 'connect', 'mac': mac}));
      final r = await f;
      if (r['type'] == 'error') throw ApiException('Scale not found. Open the virtual scale page (it must say "hub online") and try again.');
      _device = ScaleDevice.fromJson(r['device'] as Map<String, dynamic>);
      _set(LinkState.connected);
    } on ApiException {
      _set(LinkState.disconnected);
      rethrow;
    } catch (_) {
      _set(LinkState.disconnected);
      throw ApiException('Cannot reach the scale hub. Is the backend running?');
    }
  }

  @override
  Future<void> disconnect() async {
    _ch?.sink.add(jsonEncode({'type': 'disconnect'}));
    _device = null;
    _set(LinkState.disconnected);
  }

  @override
  void command(Map<String, dynamic> cmd) => _ch?.sink.add(jsonEncode({'type': 'cmd', ...cmd}));

  @override
  void dispose() {
    _sub?.cancel();
    _ch?.sink.close();
    _readings.close();
    _events.close();
    _deviceEvents.close();
    super.dispose();
  }
}
