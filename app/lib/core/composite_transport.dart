import 'dart:async';
import 'ble_transport.dart';
import 'scale_transport.dart';

/// Presents the virtual-scale hub and real Bluetooth as one transport.
/// Which sources are used is controlled by [useSim] / [useBle] (Settings).
class CompositeTransport extends ScaleTransport {
  final SimulatorTransport sim;
  final BleTransport ble;
  bool Function() useSim, useBle;
  CompositeTransport(this.sim, this.ble, {required this.useSim, required this.useBle}) {
    for (final t in [sim, ble]) {
      t.addListener(notifyListeners);
      t.readings.listen(_readings.add);
      t.events.listen(_events.add);
    }
  }

  final _readings = StreamController<ScaleReading>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, ScaleTransport> _owner = {};
  ScaleTransport? _active;
  int _bgScans = 0;

  ScaleTransport get _cur => _active ?? sim;
  @override
  LinkState get state => _cur.state;
  @override
  ScaleDevice? get device => _cur.device;
  @override
  Stream<ScaleReading> get readings => _readings.stream;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// [background] scans (the auto-connect loop) only touch Bluetooth every 6th time to save battery.
  @override
  Future<List<ScaleDevice>> scan({Duration timeout = const Duration(seconds: 4), bool background = false}) async {
    final out = <ScaleDevice>[];
    Object? simError;
    if (useSim()) {
      try {
        for (final d in await sim.scan(timeout: timeout)) {
          _owner[d.mac] = sim;
          out.add(d);
        }
      } catch (e) {
        simError = e;
      }
    }
    final bleDue = !background || (_bgScans++ % 6 == 0);
    if (useBle() && BleTransport.supported && bleDue && ble.state != LinkState.connected) {
      try {
        for (final d in await ble.scan(timeout: background ? const Duration(seconds: 3) : const Duration(seconds: 5))) {
          _owner[d.mac] = ble;
          out.add(d);
        }
      } catch (e) {
        if (!background) rethrow; // surface permission / Bluetooth-off problems when the user scans explicitly
      }
    }
    if (out.isEmpty && simError != null && !(useBle() && BleTransport.supported)) throw simError;
    return out;
  }

  @override
  Future<void> connect(String mac) async {
    final t = _owner[mac] ?? sim;
    if (_active != null && _active != t) await _active!.disconnect();
    _active = t;
    notifyListeners();
    await t.connect(mac);
  }

  @override
  Future<void> disconnect() async {
    await _active?.disconnect();
    notifyListeners();
  }

  @override
  void command(Map<String, dynamic> cmd) => _cur.command(cmd);

  @override
  void dispose() {
    sim.dispose();
    ble.dispose();
    _readings.close();
    _events.close();
    super.dispose();
  }
}
