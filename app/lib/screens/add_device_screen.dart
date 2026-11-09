import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import 'scan_screen.dart';
import '../widgets/common.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});
  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  List<ScaleDevice> _found = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final s = context.read<AppState>();
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final r = await s.scale.scan();
      if (mounted) setState(() => _found = r);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the scale hub at ${s.api.wsUrl}.\nMake sure the backend is running.');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _bind(String mac, String name, String kind) async {
    final s = context.read<AppState>();
    final ok = await guarded(context, () async {
      await s.api.post('/app/user/addUserDevice', {'mac': mac, 'name': name, 'kind': kind});
      await s.loadDevices();
    }, success: '$name added');
    if (ok && mounted) Navigator.pop(context);
  }

  /// QR payload: "uhdev:<name>|<mac>|<kind>" (the virtual scale page shows one), or just a MAC address.
  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scan device QR code', hint: 'Scan the QR code on the scale or on the virtual scale page. You can also type the code, for example uhdev:CF568_G|AA:BB:CC:00:00:01|body.', manualLabel: 'Enter the device code')));
    if (code == null || !mounted) return;
    final m = RegExp(r'^uhdev:([^|]+)\|([0-9A-Fa-f:]{11,17})\|(body|food|coffee)$').firstMatch(code);
    if (m != null) return _bind(m.group(2)!, m.group(1)!, m.group(3)!);
    if (RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(code)) return _bind(code, 'Scale', 'body');
    toast(context, 'That code is not a scale QR code', error: true);
  }

  Future<void> _manual() async {
    final kind = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Device type'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'body'), child: const ListTile(leading: Icon(Icons.monitor_weight), title: Text('Body scale'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'food'), child: const ListTile(leading: Icon(Icons.restaurant), title: Text('Food / kitchen scale'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'coffee'), child: const ListTile(leading: Icon(Icons.coffee), title: Text('Coffee scale'))),
      ]),
    );
    if (kind == null || !mounted) return;
    final food = kind != 'body';
    final name = await askText(context, 'Device name', initial: kind == 'coffee' ? 'CK863' : food ? 'CK850' : 'CF568_G');
    if (name == null || name.isEmpty || !mounted) return;
    final defMac = kind == 'coffee' ? 'AA:BB:CC:00:00:03' : food ? 'AA:BB:CC:00:00:02' : 'AA:BB:CC:00:00:01';
    final mac = await askText(context, 'MAC address (virtual scale: $defMac)', initial: defMac);
    if (mac == null || mac.isEmpty || !mounted) return;
    await _bind(mac, name, kind);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final bound = s.devices.map((d) => d.mac).toSet();
    return GScaffold(
      appBar: AppBar(title: const Text('Add device'), actions: [IconButton(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_scanning) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Scanning for scales…')])),
        if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
        if (!_scanning && _error == null && _found.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('No scale found', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Open ${s.api.baseUrl}/simulator in a browser on your PC to start the virtual scale, then tap refresh.'),
              ]),
            ),
          ),
        for (final d in _found)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(deviceKindIcon(d.kind))),
              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${d.mac} · ${d.rssi} dBm'),
              trailing: bound.contains(d.mac) ? const Chip(label: Text('Added')) : FilledButton(onPressed: () => _bind(d.mac, d.name, d.kind), child: const Text('Add')),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan device QR code')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _manual, icon: const Icon(Icons.edit), label: const Text('Add manually')),
      ]),
    );
  }
}
