import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'add_device_screen.dart';
import 'device_detail_screen.dart';

/// "Device management": swipe through bound devices, quick toggles, add device.
class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});
  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final _page = PageController(viewportFraction: 0.86);
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final devs = s.devices;
    final d = devs.isEmpty ? null : devs[_i.clamp(0, devs.length - 1)];
    final connected = d != null && s.scale.state == LinkState.connected && s.scale.device?.mac == d.mac;
    final voice = d != null && (s.prefs.getBool('voice_${d.id}') ?? true);
    return GScaffold(
      appBar: AppBar(title: const Text('Device management')),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 8), children: [
            if (devs.isEmpty)
              const AppCard(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(children: [Icon(Icons.scale, size: 72, color: mutedColor), SizedBox(height: 12), Text('No devices yet', style: TextStyle(fontWeight: FontWeight.w700)), Text('Turn on your scale and tap Add device', style: TextStyle(color: mutedColor, fontSize: 12))]),
              )
            else ...[
              SizedBox(
                height: 210,
                child: PageView.builder(
                  controller: _page,
                  itemCount: devs.length,
                  onPageChanged: (v) => setState(() => _i = v),
                  itemBuilder: (_, k) => _DeviceCard(device: devs[k], connected: s.scale.state == LinkState.connected && s.scale.device?.mac == devs[k].mac),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var k = 0; k < devs.length; k++)
                  Container(margin: const EdgeInsets.all(3), width: k == _i ? 16 : 6, height: 6, decoration: BoxDecoration(color: k == _i ? brandBlue : mutedColor.withAlpha(110), borderRadius: BorderRadius.circular(3))),
              ]),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  MenuRow(icon: Icons.label_outline, title: d!.customName, subtitle: d.name, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceDetailScreen(device: d)))),
                  const Divider(height: 1),
                  MenuRow(icon: Icons.business, title: 'Unique Health', trailing: Text(d.mac, style: const TextStyle(fontSize: 11, color: mutedColor))),
                  const Divider(height: 1),
                  MenuRow(
                    icon: Icons.bluetooth,
                    title: 'Connection',
                    trailing: TextButton(
                      onPressed: () => guarded(context, () async {
                        if (connected) {
                          await s.scale.disconnect();
                        } else {
                          await s.scale.connect(d.mac);
                        }
                      }),
                      child: Text(connected ? 'Connected · Disconnect' : 'Offline · Connect'),
                    ),
                  ),
                  const Divider(height: 1),
                  MenuRow(
                    icon: Icons.volume_up_outlined,
                    title: 'Voice broadcast',
                    trailing: Switch(
                      value: voice,
                      onChanged: (v) async {
                        await s.prefs.setBool('voice_${d.id}', v);
                        if (connected) s.scale.command({'cmd': 'voice', 'value': v});
                        setState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  MenuRow(icon: Icons.add_to_home_screen, title: 'Add Shortcut to Home Screen', onTap: () => toast(context, 'Shortcuts are not available in the test build')),
                  const Divider(height: 1),
                  MenuRow(icon: Icons.info_outline, title: 'Device Details', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceDetailScreen(device: d)))),
                ]),
              ),
            ],
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen())), icon: const Icon(Icons.add), label: const Text('Add device')),
            ),
          ),
        ),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final bool connected;
  const _DeviceCard({required this.device, required this.connected});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1D2136) : Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Stack(children: [
            Center(
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(color: const Color(0xFF262B3A), borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 8))]),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF0F1220), borderRadius: BorderRadius.circular(6)), child: Text(device.isFood ? '250 g' : '72.5', style: const TextStyle(color: Color(0xFF7CF5C2), fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 18))),
                  const SizedBox(height: 14),
                  Icon(deviceKindIcon(device.kind), color: Colors.white54, size: 26),
                ]),
              ),
            ),
            Positioned(top: 12, right: 14, child: Row(children: [Icon(Icons.circle, size: 9, color: connected ? Colors.green : mutedColor), const SizedBox(width: 5), Text(connected ? 'Connected' : 'Offline', style: const TextStyle(fontSize: 11, color: mutedColor))])),
            Positioned(left: 16, bottom: 12, child: Text(device.customName, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}
