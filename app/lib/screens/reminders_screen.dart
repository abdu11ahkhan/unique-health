import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:provider/provider.dart';
import '../core/reminders.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late bool _on;
  late TimeOfDay _time;
  late Set<int> _days;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().prefs;
    _on = p.getBool('rem_on') ?? false;
    final mins = p.getInt('rem_time') ?? 8 * 60;
    _time = TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
    _days = (p.getStringList('rem_days') ?? ['1', '2', '3', '4', '5', '6', '7']).map(int.parse).toSet();
  }

  Future<void> _apply() async {
    final s = context.read<AppState>();
    await s.prefs.setBool('rem_on', _on);
    await s.prefs.setInt('rem_time', _time.hour * 60 + _time.minute);
    await s.prefs.setStringList('rem_days', _days.map((e) => '$e').toList());
    if (!Reminders.supported) return;
    if (_on && _days.isNotEmpty) {
      if (!await Reminders.requestPermission()) {
        setState(() => _on = false);
        await s.prefs.setBool('rem_on', false);
        if (mounted) toast(context, 'Notifications are blocked. Allow them in system settings to get reminders.', error: true);
        return;
      }
      await Reminders.schedule(_time, _days);
    } else {
      await Reminders.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return GScaffold(
      appBar: AppBar(title: const Text('Weigh-in reminders')),
      body: ListView(padding: const EdgeInsets.only(top: 8), children: [
        if (!Reminders.supported) const AppCard(child: Row(children: [Icon(Icons.info_outline, color: brandBlue), SizedBox(width: 12), Expanded(child: Text('Reminders are delivered by the phone. Your choices are saved here, but notifications only fire in the Android or iOS app.'))])),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Remind me to weigh in'), value: _on, onChanged: (v) async {
              setState(() => _on = v);
              await _apply();
            }),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              trailing: Text(_time.format(context), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) {
                  setState(() => _time = t);
                  await _apply();
                }
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(spacing: 6, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(names[i]),
                    selected: _days.contains(i + 1),
                    onSelected: (v) async {
                      setState(() => v ? _days.add(i + 1) : _days.remove(i + 1));
                      await _apply();
                    },
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
