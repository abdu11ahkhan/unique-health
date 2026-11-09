import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return GScaffold(
      appBar: AppBar(title: const Text('Family & profiles')),
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberEditScreen())), icon: const Icon(Icons.person_add), label: const Text('Add profile')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        for (final m in s.members)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(m.avatar, style: const TextStyle(fontSize: 20))),
              title: Text('${m.name}${m.isSelf ? ' (me)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${m.gender == 1 ? 'Male' : 'Female'} · ${m.age} yrs · ${m.height.round()} cm${m.athlete ? ' · athlete' : ''}'),
              trailing: s.memberId == m.id ? const Chip(label: Text('Selected')) : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemberEditScreen(member: m))),
              onLongPress: () => s.selectMember(m.id),
            ),
          ),
        const Padding(padding: EdgeInsets.all(8), child: Text('Tip: long-press a profile to make it the active one on the Health tab.')),
      ]),
    );
  }
}

class MemberEditScreen extends StatefulWidget {
  final Member? member;
  const MemberEditScreen({super.key, this.member});
  @override
  State<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends State<MemberEditScreen> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _height = TextEditingController(text: (widget.member?.height ?? 170).round().toString());
  late String _birthday = widget.member?.birthday ?? '1995-01-01';
  late int _gender = widget.member?.gender ?? 1;
  late String _avatar = widget.member?.avatar ?? '🙂';
  late bool _athlete = widget.member?.athlete ?? false;

  Future<void> _save() async {
    final s = context.read<AppState>();
    final h = double.tryParse(_height.text);
    if (_name.text.trim().isEmpty) return toast(context, 'Enter a name', error: true);
    if (h == null || h < 50 || h > 250) return toast(context, 'Height must be 50–250 cm', error: true);
    final body = {'name': _name.text.trim(), 'height': h, 'birthday': _birthday, 'gender': _gender, 'avatar': _avatar, 'athlete': _athlete};
    final ok = await guarded(context, () async {
      if (widget.member == null) {
        await s.api.post('/app/memberDevice/add', body);
      } else {
        await s.api.post('/app/memberDevice/update', {'id': widget.member!.id, ...body});
      }
      await s.loadMembers();
      await s.loadRecords();
    });
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return GScaffold(
      appBar: AppBar(title: Text(widget.member == null ? 'New profile' : 'Edit profile'), actions: [TextButton(onPressed: _save, child: const Text('Save'))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [for (final a in ['🙂', '👩', '👨', '👧', '👦', '👶', '🧓', '🏃']) ChoiceChip(label: Text(a, style: const TextStyle(fontSize: 22)), selected: _avatar == a, onSelected: (_) => setState(() => _avatar = a))]),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('Male')), ButtonSegment(value: 0, label: Text('Female'))], selected: {_gender}, onSelectionChanged: (v) => setState(() => _gender = v.first)),
        const SizedBox(height: 16),
        TextField(controller: _height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height (cm)')),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Birthday'),
          subtitle: Text(_birthday),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_birthday) ?? DateTime(1995), firstDate: DateTime(1920), lastDate: DateTime.now());
            if (d != null) setState(() => _birthday = d.toIso8601String().substring(0, 10));
          },
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Athlete mode'), subtitle: const Text('Adjusts body-fat estimate for very active people'), value: _athlete, onChanged: (v) => setState(() => _athlete = v)),
        if (widget.member != null && !widget.member!.isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete profile and its data'),
              onPressed: () async {
                if (!await confirm(context, 'Delete ${widget.member!.name}?', 'All measurements for this profile will be deleted.', ok: 'Delete')) return;
                if (!context.mounted) return;
                final ok = await guarded(context, () async {
                  await s.api.post('/app/memberDevice/deleteByUid', {'id': widget.member!.id});
                  await s.loadMembers();
                  await s.loadRecords();
                });
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
          ),
      ]),
    );
  }
}
