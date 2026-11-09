import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'add_device_screen.dart';
import 'diet_tab.dart';
import 'health_tab.dart';
import 'measure_screen.dart';
import 'more_tab.dart';
import 'trend_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _i = 0;

  void _plus() {
    final s = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.monitor_weight), title: const Text('Measure with scale'), subtitle: const Text('Weight and body composition'), onTap: () { Navigator.pop(c); startMeasureFlow(context); }),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Add weight manually'), onTap: () { Navigator.pop(c); addManualWeight(context); }),
          ListTile(leading: const Icon(Icons.restaurant), title: const Text('Log food'), onTap: () { Navigator.pop(c); setState(() => _i = 3); }),
          ListTile(leading: const Icon(Icons.bluetooth_searching), title: const Text('Add device'), subtitle: Text('${s.devices.length} bound'), onTap: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen())); }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const tabs = [HealthTab(), TrendTab(), SizedBox.shrink(), DietTab(), MoreTab()];
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget item(int idx, IconData icon, IconData sel, String label) {
      final on = _i == idx;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _i = idx),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(on ? sel : icon, color: on ? brandBlue : mutedColor, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: on ? brandBlue : mutedColor, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [const _OfflineBanner(), Expanded(child: IndexedStack(index: _i, children: tabs))]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: dark ? const Color(0xFF1D2136) : Colors.white, boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))], borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(children: [
              item(0, Icons.home_outlined, Icons.home, 'Home'),
              item(1, Icons.show_chart, Icons.show_chart, 'Trend'),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _plus,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: brandBlue, boxShadow: [BoxShadow(color: brandBlue.withAlpha(90), blurRadius: 12, offset: const Offset(0, 4))]),
                      child: const Icon(Icons.add, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
              item(3, Icons.restaurant_outlined, Icons.restaurant, 'Diet'),
              item(4, Icons.grid_view_outlined, Icons.grid_view_rounded, 'More'),
            ]),
          ),
        ),
      ),
    );
  }
}


/// Shown while the server is unreachable or changes are waiting to sync.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.offline && s.pending == 0 && !s.syncing) return const SizedBox.shrink();
    final text = s.syncing
        ? 'Syncing your changes…'
        : s.offline
            ? 'Offline · showing saved data${s.pending > 0 ? ' · ${s.pending} change(s) will sync automatically' : ''}'
            : '${s.pending} change(s) waiting to sync';
    final c = s.offline ? const Color(0xFF8A5A00) : brandBlue;
    return Material(
      color: s.offline ? const Color(0xFFFFF1D6) : const Color(0xFFE3EAFF),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(children: [
            Icon(s.syncing ? Icons.sync : s.offline ? Icons.cloud_off : Icons.cloud_upload_outlined, size: 18, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600))),
            TextButton(onPressed: s.syncing ? null : s.checkConnection, child: const Text('Retry')),
          ]),
        ),
      ),
    );
  }
}
