import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'history_screen.dart';

class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});
  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  List<Map<String, dynamic>> _mine = [], _others = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      final a = await s.api.get('/app/bodyDataShare/list') as List;
      final b = await s.api.get('/app/bodyDataShare/otherList') as List;
      if (mounted) setState(() {
        _mine = a.map((e) => Map<String, dynamic>.from(e)).toList();
        _others = b.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    });
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _share() async {
    final s = context.read<AppState>();
    final email = await askText(context, 'Share with', hint: 'Their account email', type: TextInputType.emailAddress);
    if (email == null || email.isEmpty || !mounted) return;
    final m = await showDialog<Member>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Which profile?'), children: [for (final x in s.members) SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text('${x.avatar}  ${x.name}'))]),
    );
    if (m == null || !mounted) return;
    final ok = await guarded(context, () => s.api.post('/app/bodyDataShare', {'email': email, 'memberId': m.id}), success: 'Shared ${m.name}');
    if (ok) _load();
  }

  Future<void> _open(Map<String, dynamic> o) async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      final l = await s.api.get('/app/bodyDataShare/bodyData/list', query: {'ownerId': o['ownerId'], 'memberId': o['memberId']}) as List;
      final recs = l.map((e) => BodyRecord.fromJson(Map<String, dynamic>.from(e))).toList();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(recordsOverride: recs, title: '${o['memberName']} (${o['ownerNickname']})', readOnly: true)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return GScaffold(
      appBar: AppBar(title: const Text('Data sharing')),
      floatingActionButton: FloatingActionButton.extended(heroTag: null, onPressed: _share, icon: const Icon(Icons.person_add), label: const Text('Share')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Text('Shared with me', style: Theme.of(context).textTheme.titleMedium),
                if (_others.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nobody has shared data with you.')),
                for (final o in _others)
                  Card(child: ListTile(leading: const Icon(Icons.visibility), title: Text('${o['memberName']}'), subtitle: Text('from ${o['ownerNickname']} (${o['ownerEmail']})'), trailing: const Icon(Icons.chevron_right), onTap: () => _open(o))),
                const SizedBox(height: 16),
                Text('I share', style: Theme.of(context).textTheme.titleMedium),
                if (_mine.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('You are not sharing any profile.')),
                for (final m in _mine)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.share),
                      title: Text('${m['memberName']} → ${m['nickname']}'),
                      subtitle: Text('${m['email']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await guarded(context, () => context.read<AppState>().api.post('/app/bodyDataShare/delete', {'id': m['id']}));
                          _load();
                        },
                      ),
                    ),
                  ),
              ]),
            ),
    );
  }
}
