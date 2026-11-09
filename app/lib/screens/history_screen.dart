import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// History of the selected member. Tick two entries to compare them.
/// Pass [recordsOverride] / [readOnly] to show someone else's shared data.
class HistoryScreen extends StatefulWidget {
  final List<BodyRecord>? recordsOverride;
  final String? title;
  final Member? memberOverride;
  final bool readOnly;
  const HistoryScreen({super.key, this.recordsOverride, this.title, this.memberOverride, this.readOnly = false});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<int> _sel = {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final recs = widget.recordsOverride ?? s.records;
    final member = widget.memberOverride ?? s.member;
    final df = DateFormat('MMM d, y · HH:mm');
    return GScaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'History'),
        actions: [
          if (_sel.length == 2)
            TextButton.icon(
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Compare'),
              onPressed: () {
                final l = recs.where((r) => _sel.contains(r.id)).toList()..sort((a, b) => a.ts.compareTo(b.ts));
                Navigator.push(context, MaterialPageRoute(builder: (_) => CompareScreen(a: l[0], b: l[1], member: member)));
              },
            ),
        ],
      ),
      body: recs.isEmpty
          ? const EmptyState(icon: Icons.history, text: 'No records')
          : ListView.separated(
              itemCount: recs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = recs[i];
                final bf = r.m('bodyFat');
                final tile = ListTile(
                  leading: Checkbox(
                    value: _sel.contains(r.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        if (_sel.length < 2) _sel.add(r.id);
                      } else {
                        _sel.remove(r.id);
                      }
                    }),
                  ),
                  title: Text(s.fmtWeight(r.weight), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${df.format(r.ts)}${bf != null ? '  ·  Fat ${bf.toStringAsFixed(1)}%' : ''}'),
                  trailing: r.m('score') == null ? null : Text('${r.m('score')!.round()}', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(record: r, member: member))),
                );
                if (widget.readOnly) return tile;
                return Dismissible(
                  key: ValueKey(r.id),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                  confirmDismiss: (_) => confirm(context, 'Delete record?', 'This cannot be undone.', ok: 'Delete'),
                  onDismissed: (_) async {
                    _sel.remove(r.id);
                    await guarded(context, () async {
                      await s.deleteRecord(r);
                    });
                  },
                  child: tile,
                );
              },
            ),
    );
  }
}

class CompareScreen extends StatelessWidget {
  final BodyRecord a, b; // a older, b newer
  final Member? member;
  const CompareScreen({super.key, required this.a, required this.b, this.member});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final df = DateFormat('MMM d, HH:mm');
    Widget row(String label, String va, String vb, double? diff, {bool lowerIsBetter = true, String unit = ''}) {
      Color? c;
      IconData? ic;
      if (diff != null && diff.abs() >= 0.05) {
        ic = diff > 0 ? Icons.arrow_upward : Icons.arrow_downward;
        c = (diff < 0) == lowerIsBetter ? Colors.green : Colors.orange;
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label)),
          Expanded(flex: 2, child: Text(va, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(vb, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (ic != null) Icon(ic, size: 14, color: c),
            Text(diff == null ? '' : ' ${diff.abs().toStringAsFixed(1)}$unit', style: TextStyle(color: c)),
          ])),
        ]),
      );
    }

    final rows = <Widget>[
      row('Weight', s.fmtWeight(a.weight), s.fmtWeight(b.weight), s.toDisplayWeight(b.weight - a.weight), unit: ' ${s.weightUnit}'),
      for (final d in metricDefs.where((d) => a.m(d.key) != null && b.m(d.key) != null))
        row(d.label, fmtNum(a.m(d.key)!, d.decimals), fmtNum(b.m(d.key)!, d.decimals), b.m(d.key)! - a.m(d.key)!,
            lowerIsBetter: !const {'muscleRate', 'muscleMass', 'water', 'boneMass', 'protein', 'leanMass', 'bmr'}.contains(d.key)),
    ];
    return GScaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
        Section(
          child: Column(children: [
            Row(children: [
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(flex: 2, child: Text(df.format(a.ts), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              Expanded(flex: 2, child: Text(df.format(b.ts), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              const Expanded(flex: 2, child: Text('Change', textAlign: TextAlign.right, style: TextStyle(fontSize: 11))),
            ]),
            const Divider(),
            ...rows,
          ]),
        ),
      ]),
    );
  }
}
