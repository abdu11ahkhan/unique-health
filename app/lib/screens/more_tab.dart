import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'device_mgmt_screen.dart';
import 'diet_tab.dart';
import 'members_screen.dart';
import 'health_sync_screen.dart';
import 'qr_login.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'sharing_screen.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final u = s.user;
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final dark = s.settings['darkMode'] == true;
    return GScaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              const BrandLogo(size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final v = await askText(context, 'Nickname', initial: u?.nickname ?? '');
                    if (v != null && v.isNotEmpty && context.mounted) await guarded(context, () => s.updateNickname(v));
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u?.email ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    Text(u?.nickname ?? '', style: const TextStyle(fontSize: 12, color: mutedColor)),
                  ]),
                ),
              ),
              IconButton(
                tooltip: 'Dark mode',
                icon: Icon(dark ? Icons.light_mode : Icons.dark_mode_outlined),
                onPressed: () => guarded(context, () => s.saveSetting('darkMode', !dark)),
              ),
            ]),
          ),
          const GroupTitle('Archives'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              MenuRow(icon: Icons.groups_outlined, title: 'Member management', subtitle: '${s.members.length} profile(s)', onTap: () => go(const MembersScreen())),
              MenuRow(icon: Icons.devices_other_outlined, title: 'Device management', subtitle: '${s.devices.length} device(s)', onTap: () => go(const DeviceManagementScreen())),
              MenuRow(icon: Icons.share_outlined, title: 'Data sharing', onTap: () => go(const SharingScreen())),
            ]),
          ),
          const GroupTitle('Setting'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              MenuRow(icon: Icons.settings_outlined, title: 'General settings', onTap: () => go(const SettingsScreen())),
              MenuRow(icon: Icons.verified_user_outlined, title: 'Permission management', onTap: () => go(const PermissionsScreen())),
              MenuRow(icon: Icons.notifications_active_outlined, title: 'Weigh-in reminders', onTap: () => go(const RemindersScreen())),
              MenuRow(icon: Icons.health_and_safety_outlined, title: 'Health sync & export', onTap: () => go(const HealthSyncScreen())),
              MenuRow(icon: Icons.restaurant_menu, title: 'Food Database', onTap: () => go(const FoodDatabaseScreen())),
              MenuRow(icon: Icons.qr_code_scanner, title: 'Scan QR to log in', subtitle: 'Sign in to the web page', onTap: () => scanQrLogin(context)),
            ]),
          ),
          const GroupTitle('Feedback'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              MenuRow(
                icon: Icons.chat_bubble_outline,
                title: 'Send feedback',
                onTap: () async {
                  final t = await askText(context, 'Your feedback', hint: 'Tell us what to improve');
                  if (t == null || t.isEmpty || !context.mounted) return;
                  final old = s.prefs.getStringList('feedback') ?? [];
                  await s.prefs.setStringList('feedback', [...old, t]);
                  if (context.mounted) toast(context, 'Thanks! Saved on this device (no server in the test build).');
                },
              ),
              MenuRow(icon: Icons.info_outline, title: 'About', subtitle: 'Version 1.0.0 (test build)', onTap: () => showAboutDialog(context: context, applicationName: 'Unique Health clone', applicationVersion: '1.0.0', children: const [Text('Local test build. Body metrics are estimates from generic formulas and are not medical advice.')])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              onPressed: () async {
                if (await confirm(context, 'Sign out?', 'You can sign back in any time.', ok: 'Sign out')) await s.logout();
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.bluetooth, 'Bluetooth', 'Find and connect to your scale.'),
      (Icons.location_on_outlined, 'Location', 'Required by Android to scan for Bluetooth devices. Not used for tracking.'),
      (Icons.notifications_none, 'Notifications', 'Measurement reminders.'),
      (Icons.camera_alt_outlined, 'Camera', 'Scanning food barcodes and device QR codes.'),
      (Icons.health_and_safety_outlined, 'Health data', 'Syncing weight and body data to Health Connect.'),
    ];
    return GScaffold(
      appBar: AppBar(title: const Text('Permission management')),
      body: ListView(padding: const EdgeInsets.only(top: 8), children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [for (final i in items) MenuRow(icon: i.$1, title: i.$2, subtitle: i.$3)]),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('The test build runs against the virtual scale and does not request these permissions. Manage them in your phone settings once real Bluetooth is added.', style: TextStyle(fontSize: 12, color: mutedColor))),
      ]),
    );
  }
}

class FoodDatabaseScreen extends StatefulWidget {
  const FoodDatabaseScreen({super.key});
  @override
  State<FoodDatabaseScreen> createState() => _FoodDatabaseScreenState();
}

class _FoodDatabaseScreenState extends State<FoodDatabaseScreen> {
  List<FoodItem> _foods = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<AppState>();
      await guarded(context, () async {
        final f = await s.api.get('/food/scale/defaultFood') as List;
        if (mounted) setState(() => _foods = f.map((e) => FoodItem.fromJson(Map<String, dynamic>.from(e))).toList());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = _foods.where((f) => f.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return GScaffold(
      appBar: AppBar(title: const Text('Food Database')),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search foods'))),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            for (final f in list)
              MenuRow(
                icon: Icons.fastfood_outlined,
                title: '${f.icon}  ${f.name}',
                subtitle: '${f.kcal.round()} kcal · P ${f.protein}g · F ${f.fat}g · C ${f.carb}g per 100 g',
                trailing: s.prefs.getBool('fav_${f.id}') == true ? const Icon(Icons.star, color: Color(0xFFE5B83B)) : const Icon(Icons.chevron_right, color: mutedColor),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => FoodDetailScreen(food: f)));
                  if (mounted) setState(() {});
                },
              ),
          ]),
        ),
      ]),
    );
  }
}
