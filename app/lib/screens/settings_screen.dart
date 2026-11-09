import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/ble_transport.dart';
import '../core/i18n.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return GScaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.straighten),
          title: const Text('Weight unit'),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'kg', label: Text('kg')), ButtonSegment(value: 'lb', label: Text('lb'))],
            selected: {s.useLb ? 'lb' : 'kg'},
            onSelectionChanged: (v) => guarded(context, () => s.saveSetting('unit', v.first)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          trailing: Text(I18n.languages[s.lang] ?? 'English', style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            final c = await showDialog<String>(
              context: context,
              builder: (d) => SimpleDialog(title: const Text('Language'), children: [for (final e in I18n.languages.entries) SimpleDialogOption(onPressed: () => Navigator.pop(d, e.key), child: Row(children: [Expanded(child: Text(e.value)), if (e.key == s.lang) const Icon(Icons.check, color: Colors.blue)]))]),
            );
            if (c != null) await s.setLang(c);
          },
        ),
        SwitchListTile(secondary: const Icon(Icons.dark_mode), title: const Text('Dark mode'), value: s.settings['darkMode'] == true, onChanged: (v) => guarded(context, () => s.saveSetting('darkMode', v))),
        ListTile(
          leading: const Icon(Icons.dns),
          title: const Text('Server address'),
          subtitle: Text(s.api.baseUrl),
          onTap: () async {
            final v = await askText(context, 'Server address', initial: s.api.baseUrl, hint: 'http://192.168.1.10:3000');
            if (v != null && v.isNotEmpty && context.mounted) {
              await s.api.setBaseUrl(v);
              await s.scale.disconnect();
              if (context.mounted) await guarded(context, s.loadAll, success: 'Connected to ${s.api.baseUrl}');
            }
          },
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.bluetooth),
          title: const Text('Real Bluetooth scales'),
          subtitle: Text(BleTransport.supported ? 'Standard Weight Scale and Body Composition profiles' : 'Needs the Android or iOS app'),
          value: s.useBle && BleTransport.supported,
          onChanged: BleTransport.supported ? (v) => s.setUseBle(v) : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.science_outlined),
          title: const Text('Virtual scale (testing)'),
          subtitle: const Text('Connect to the simulator on the backend'),
          value: s.useSim,
          onChanged: (v) => s.setUseSim(v),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.lock),
          title: const Text('Change password'),
          onTap: () async {
            final o = await askText(context, 'Current password', obscure: true);
            if (o == null || !context.mounted) return;
            final n = await askText(context, 'New password (min 6)', obscure: true);
            if (n == null || !context.mounted) return;
            await guarded(context, () => s.api.post('/app/user/updatePassword', {'oldPassword': o, 'newPassword': n}), success: 'Password updated');
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('Delete account', style: TextStyle(color: Colors.red)),
          onTap: () async {
            final pw = await askText(context, 'Enter your password to delete the account', obscure: true);
            if (pw == null || pw.isEmpty || !context.mounted) return;
            if (!await confirm(context, 'Delete account?', 'All profiles, devices and measurements will be permanently deleted.', ok: 'Delete')) return;
            if (!context.mounted) return;
            await guarded(context, () => s.deleteAccount(pw));
          },
        ),
      ]),
    );
  }
}
