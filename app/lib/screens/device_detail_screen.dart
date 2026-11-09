import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'coffee_screen.dart';
import 'device_features.dart';
import 'food_screen.dart';
import 'measure_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Device device;
  const DeviceDetailScreen({super.key, required this.device});
  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  List<AppUser> _shares = [];

  Device _cur(AppState s) => s.devices.firstWhere((d) => d.id == widget.device.id, orElse: () => widget.device);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadShares());
  }

  Future<void> _loadShares() async {
    final s = context.read<AppState>();
    if (widget.device.shared) return;
    try {
      final l = await s.api.get('/app/device/shareUsers', query: {'id': widget.device.id}) as List;
      if (mounted) setState(() => _shares = l.map((e) => AppUser.fromJson(Map<String, dynamic>.from(e))).toList());
    } catch (_) {}
  }

  Future<void> _update(Map<String, dynamic> patch) async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      await s.api.post('/app/device/updateDevice', {'id': widget.device.id, ...patch});
      await s.loadDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = _cur(s);
    final connected = s.scale.state == LinkState.connected && s.scale.device?.mac == d.mac;
    return GScaffold(
      appBar: AppBar(title: Text(d.customName)),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
        Section(
          child: Column(children: [
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.bluetooth), title: Text(d.name), subtitle: Text(d.mac), trailing: Chip(label: Text(connected ? 'Connected' : 'Offline'))),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => d.isFood
                      ? Navigator.push(context, MaterialPageRoute(builder: (_) => FoodScreen(device: d)))
                      : d.isCoffee
                          ? Navigator.push(context, MaterialPageRoute(builder: (_) => CoffeeScreen(device: d)))
                          : startMeasureFlow(context, device: d),
                  icon: Icon(deviceKindIcon(d.kind)),
                  label: Text(d.isFood ? 'Open food diary' : d.isCoffee ? 'Open coffee scale' : 'Measure'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => guarded(context, () async {
                  if (connected) {
                    await s.scale.disconnect();
                  } else {
                    await s.scale.connect(d.mac);
                  }
                }),
                child: Text(connected ? 'Disconnect' : 'Connect'),
              ),
            ]),
          ]),
        ),
        Section(
          title: 'Settings',
          child: Column(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit),
              title: const Text('Device name'),
              subtitle: Text(d.customName),
              onTap: () async {
                final v = await askText(context, 'Rename device', initial: d.customName);
                if (v != null && v.isNotEmpty) _update({'customName': v});
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.straighten),
              title: const Text('Unit shown on the scale'),
              trailing: SegmentedButton<String>(
                segments: [for (final u in (d.isFood ? ['g', 'oz'] : ['kg', 'lb'])) ButtonSegment(value: u, label: Text(u))],
                selected: {d.unit == 'lb' || d.unit == 'oz' ? d.unit : (d.isFood ? 'g' : 'kg')},
                onSelectionChanged: (v) {
                  _update({'unit': v.first});
                  if (connected) s.scale.command({'cmd': 'unit', 'value': v.first});
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update),
              title: const Text('Firmware update'),
              subtitle: const Text('Check for and install a new version'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FirmwareScreen(device: d))),
            ),
            if (d.kind == 'body' && (!connected || s.scale.device!.has('wifi')))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi),
                title: const Text('Wi-Fi setup'),
                subtitle: const Text('Connect the scale to your network'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WifiSetupScreen(device: d))),
              ),
            if (d.kind == 'body' && (!connected || s.scale.device!.has('fingerprint')))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fingerprint),
                title: const Text('Fingerprint users'),
                subtitle: const Text('Recognise who steps on the scale'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FingerprintScreen(device: d))),
              ),
            if (d.isCoffee)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: const Text('Brew history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrewHistoryScreen())),
              ),
          ]),
        ),
        DisplaySettingsCard(device: d),
        if (!d.shared)
          Section(
            title: 'Shared with',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_shares.isEmpty) const Text('Not shared with anyone.'),
              for (final u in _shares)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: Text(u.nickname),
                  subtitle: Text(u.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await guarded(context, () => s.api.post('/app/device/unshareDevice', {'id': d.id, 'userId': u.id}));
                      _loadShares();
                    },
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Share with another account'),
                onPressed: () async {
                  final e = await askText(context, 'Share device', hint: 'Their account email', type: TextInputType.emailAddress);
                  if (e == null || e.isEmpty || !mounted) return;
                  final ok = await guarded(context, () => s.api.post('/app/device/shareDevice', {'id': d.id, 'email': e}), success: 'Shared');
                  if (ok) _loadShares();
                },
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline),
            label: Text(d.shared ? 'Remove shared device' : 'Unbind device'),
            onPressed: () async {
              if (!await confirm(context, 'Remove device?', 'You can add it again later.', ok: 'Remove')) return;
              if (!context.mounted) return;
              final ok = await guarded(context, () async {
                if (connected) await s.scale.disconnect();
                await s.api.post('/app/user/removeUserDevice', {'id': d.id});
                await s.loadDevices();
              });
              if (ok && context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ]),
    );
  }
}
