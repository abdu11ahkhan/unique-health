import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart' show ApiException;
import 'ble_parse.dart';
import 'scale_transport.dart';

/// Real Bluetooth LE scales that implement the standard Bluetooth SIG
/// Weight Scale (0x181D) and/or Body Composition (0x181B) profiles.
/// Scales with a vendor-specific protocol (including Lefu's) are not supported here.
class BleTransport extends ScaleTransport {
  static final weightService = Uuid.parse('181D'), weightChar = Uuid.parse('2A9D');
  static final bodyService = Uuid.parse('181B'), bodyChar = Uuid.parse('2A9C');

  /// BLE is only available on phones/tablets (the plugin has no desktop support).
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  FlutterReactiveBle? _bleInstance;
  FlutterReactiveBle get _ble => _bleInstance ??= FlutterReactiveBle();

  final _readings = StreamController<ScaleReading>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _wSub, _bSub;
  Timer? _weightOnlyTimer;
  double? _lastKg;
  bool _hasBodyComp = false;
  LinkState _state = LinkState.disconnected;
  ScaleDevice? _device;

  @override
  LinkState get state => _state;
  @override
  ScaleDevice? get device => _device;
  @override
  Stream<ScaleReading> get readings => _readings.stream;
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();

  void _set(LinkState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> _permissions() async {
    if (!supported) throw ApiException('Bluetooth is only available on a phone or tablet build.');
    if (Platform.isAndroid) {
      final r = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
      if (r.values.any((p) => p.isPermanentlyDenied)) {
        throw ApiException('Bluetooth permission was denied. Enable Nearby devices and Location for this app in system settings.');
      }
      if (r[Permission.bluetoothScan]?.isGranted != true || r[Permission.bluetoothConnect]?.isGranted != true) {
        throw ApiException('Bluetooth permission is required to find your scale.');
      }
    }
  }

  @override
  Future<List<ScaleDevice>> scan({Duration timeout = const Duration(seconds: 5)}) async {
    await _permissions();
    if (await _ble.statusStream.first != BleStatus.ready) throw ApiException('Turn on Bluetooth (and Location on Android) and try again.');
    final found = <String, DiscoveredDevice>{};
    final sub = _ble.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency).listen((d) => found[d.id] = d, onError: (_) {});
    await Future.delayed(timeout);
    await sub.cancel();
    bool standard(DiscoveredDevice d) => d.serviceUuids.contains(weightService) || d.serviceUuids.contains(bodyService);
    int rank(DiscoveredDevice d) => standard(d) ? 0 : 1;
    final list = found.values.where((d) => d.name.isNotEmpty || standard(d)).toList()
      ..sort((a, b) {
        final c = rank(a) - rank(b);
        return c != 0 ? c : b.rssi.compareTo(a.rssi);
      });
    return [for (final d in list) ScaleDevice(d.id, d.name.isEmpty ? 'Bluetooth scale' : d.name, 'body', d.rssi)];
  }

  @override
  Future<void> connect(String mac) async {
    if (_state == LinkState.connected && _device?.mac == mac) return;
    await _teardown();
    await _permissions();
    _set(LinkState.connecting);
    final ready = Completer<void>();
    _conn = _ble.connectToDevice(id: mac, connectionTimeout: const Duration(seconds: 15)).listen((u) async {
      if (u.connectionState == DeviceConnectionState.connected && !ready.isCompleted) {
        try {
          await _subscribe(mac);
          ready.complete();
        } catch (e) {
          if (!ready.isCompleted) ready.completeError(e);
        }
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        if (!ready.isCompleted) ready.completeError(ApiException('Could not connect to the scale.'));
        _device = null;
        _set(LinkState.disconnected);
      }
    }, onError: (e) {
      if (!ready.isCompleted) ready.completeError(ApiException('Could not connect to the scale.'));
    });
    try {
      await ready.future.timeout(const Duration(seconds: 25));
      _device = ScaleDevice(mac, 'Bluetooth scale', 'body', -60);
      _set(LinkState.connected);
    } catch (e) {
      await _teardown();
      _set(LinkState.disconnected);
      throw e is ApiException ? e : ApiException('Could not connect to the scale.');
    }
  }

  Future<void> _subscribe(String id) async {
    final services = await _ble.discoverServices(id);
    bool has(Uuid s, Uuid c) => services.any((x) => x.serviceId == s && x.characteristicIds.contains(c));
    final hasW = has(weightService, weightChar);
    _hasBodyComp = has(bodyService, bodyChar);
    if (!hasW && !_hasBodyComp) throw ApiException('This device does not provide the standard Weight Scale or Body Composition service, so it cannot be used.');
    if (hasW) {
      _wSub = _ble.subscribeToCharacteristic(QualifiedCharacteristic(serviceId: weightService, characteristicId: weightChar, deviceId: id)).listen(_onWeight, onError: (_) {});
    }
    if (_hasBodyComp) {
      _bSub = _ble.subscribeToCharacteristic(QualifiedCharacteristic(serviceId: bodyService, characteristicId: bodyChar, deviceId: id)).listen(_onBody, onError: (_) {});
    }
  }

  void _emit(double kg, double impedance, {bool error = false}) {
    _readings.add(ScaleReading(kg, 'kg', true, error ? 'error' : 'done', impedance));
  }

  void _onWeight(List<int> data) {
    final m = parseWeightMeasurement(data);
    if (m?.kg == null) return;
    _lastKg = m!.kg;
    if (!_hasBodyComp) return _emit(m.kg!, 0);
    // Scales with both profiles send the body composition right after the weight; wait briefly so we save one record.
    _weightOnlyTimer?.cancel();
    _weightOnlyTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_lastKg != null) _emit(_lastKg!, 0);
      _lastKg = null;
    });
  }

  void _onBody(List<int> data) {
    final m = parseBodyComposition(data);
    if (m == null) return;
    _weightOnlyTimer?.cancel();
    final kg = m.weightKg ?? _lastKg;
    _lastKg = null;
    if (kg == null) return; // body composition without any weight: nothing to save
    final imp = m.impedanceOhm ?? 0;
    // Unsuccessful body-fat (null) or no impedance: report weight with an impedance error so the app can offer weight-only.
    _emit(kg, imp, error: m.bodyFatPct == null && imp == 0);
  }

  Future<void> _teardown() async {
    _weightOnlyTimer?.cancel();
    await _wSub?.cancel();
    await _bSub?.cancel();
    await _conn?.cancel();
    _wSub = _bSub = null;
    _conn = null;
    _lastKg = null;
  }

  @override
  Future<void> disconnect() async {
    await _teardown();
    _device = null;
    _set(LinkState.disconnected);
  }

  @override
  void command(Map<String, dynamic> cmd) {} // standard profiles have no commands

  @override
  void dispose() {
    _teardown();
    _readings.close();
    super.dispose();
  }
}
