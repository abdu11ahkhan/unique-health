import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// "Measurement result" / "Data details": top cards, metric tabs and a
/// detail card with the colored range bar, status and tips.
class ResultScreen extends StatefulWidget {
  final BodyRecord record;
  final Member? member;
  final String initialKey;
  const ResultScreen({super.key, required this.record, this.member, this.initialKey = 'weight'});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late String _key = widget.initialKey;

  double? _value(String key) => key == 'weight' ? widget.record.weight : widget.record.m(key);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = widget.record;
    final m = widget.member;
    final haveMetrics = r.metrics.isNotEmpty;
    final keys = ['weight', ...metricDefs.where((d) => r.m(d.key) != null).map((d) => d.key)];
    if (!keys.contains(_key)) _key = 'weight';
    final def = defOf(_key);
    final label = _key == 'weight' ? 'Weight' : def!.label;
    final unit = _key == 'weight' ? s.weightUnit : def!.unit;
    final v = _value(_key)!;
    final shown = _key == 'weight' ? s.toDisplayWeight(v) : v;
    final decimals = _key == 'weight' ? 1 : def!.decimals;
    final rt = rate(_key, v, m, weight: r.weight);
    final spec = rangeFor(_key, m, weight: r.weight);
    final help = _key == 'weight' ? 'Weight is the mass of the body, usually measured in kilograms or pounds. It is an important indicator of human health, but it needs to be evaluated together with height, body shape and body fat percentage.' : def!.help;
    final advice = adviceFor(_key, rt);
    final score = (r.m('score') ?? 0).round();
    final head = [for (final k in ['weight', 'bmi']) if (_value(k) != null) k];

    return GScaffold(
      appBar: AppBar(title: const Text('Measurement result')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        AppCard(
          child: Row(children: [
            if (haveMetrics) ...[ScoreRing(score: score, size: 84), const SizedBox(width: 16)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('MMM d, y · HH:mm').format(r.ts), style: const TextStyle(color: mutedColor, fontSize: 12)),
                if (m != null) Text('${m.avatar} ${m.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (haveMetrics) Text('Health score: ${scoreLabel(score)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Source: ${r.source}${r.impedance > 0 ? ' · ${r.impedance.round()} Ω' : ''}', style: const TextStyle(color: mutedColor, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const GroupTitle('Body Weight and Basic Indicators'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final k in head) ...[
              Expanded(
                child: AppCard(
                  margin: EdgeInsets.zero,
                  onTap: () => setState(() => _key = k),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k == 'weight' ? 'Weight' : 'BMI (Body Mass Index)', style: const TextStyle(fontSize: 12, color: mutedColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(k == 'weight' ? s.toDisplayWeight(_value(k)!).toStringAsFixed(1) : _value(k)!.toStringAsFixed(1), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _key == k ? brandBlue : null)),
                    const SizedBox(height: 6),
                    StatusChip(rate(k, _value(k)!, m, weight: r.weight)),
                  ]),
                ),
              ),
              if (k != head.last) const SizedBox(width: 12),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final k in keys)
                  GestureDetector(
                    onTap: () => setState(() => _key = k),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(k == 'weight' ? 'Weight' : defOf(k)!.label, style: TextStyle(fontWeight: _key == k ? FontWeight.w800 : FontWeight.w400, color: _key == k ? inkColorOf(context) : mutedColor)),
                        const SizedBox(height: 4),
                        Container(height: 3, width: 22, decoration: BoxDecoration(color: _key == k ? brandBlue : Colors.transparent, borderRadius: BorderRadius.circular(2))),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.circle, size: 9, color: brandBlue),
              const SizedBox(width: 8),
              Expanded(child: Text('$label (${fmtNum(shown, decimals)}${unit.isEmpty ? '' : unit == 'kg' || unit == 'lb' ? unit : ' $unit'})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            Text(help, style: const TextStyle(fontSize: 13, height: 1.45, color: mutedColor)),
            if (spec != null && rt != null) ...[
              const SizedBox(height: 18),
              RangeBar(spec: spec, value: v, fmt: (x) => fmtNum(_key == 'weight' ? s.toDisplayWeight(x) : x, _key == 'bmi' || _key == 'weight' ? 1 : 0)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: rt.color.withAlpha(24), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(Icons.circle, size: 9, color: rt.color), const SizedBox(width: 8), Text(rt.label, style: TextStyle(fontWeight: FontWeight.w800, color: rt.color))]),
                  const SizedBox(height: 6),
                  Text(explainFor(label.toLowerCase(), rt), style: const TextStyle(fontSize: 13, height: 1.4)),
                ]),
              ),
              if (advice.isNotEmpty && rt.watch) ...[
                const SizedBox(height: 14),
                const Row(children: [Icon(Icons.circle, size: 9, color: brandBlue), SizedBox(width: 8), Text('Tips', style: TextStyle(fontWeight: FontWeight.w800))]),
                const SizedBox(height: 6),
                Text(advice, style: const TextStyle(fontSize: 13, height: 1.4, color: mutedColor)),
              ],
            ],
          ]),
        ),
        if (!haveMetrics) const AppCard(child: Text('Only weight was recorded for this entry.')),
        if (haveMetrics && r.m('method') != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              r.m('method') == 1
                  ? 'Body fat, water, lean and muscle mass use published bioimpedance equations (Sun 2003, Janssen 2000). Bone, protein, visceral fat, body age and score are estimates. Not a medical measurement.'
                  : 'No usable impedance reading: body fat is estimated from BMI, age and sex (Deurenberg 1991). Step on barefoot for a bioimpedance result. Not a medical measurement.',
              style: const TextStyle(fontSize: 12, color: mutedColor),
            ),
          ),
      ]),
    );
  }
}

Color inkColorOf(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFE8EAF6) : inkColor;

/// Assign guest (unclaimed) measurements to a profile.
class ClaimScreen extends StatelessWidget {
  const ClaimScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return GScaffold(
      appBar: AppBar(title: const Text('Unassigned measurements')),
      body: s.unclaimed.isEmpty
          ? const EmptyState(icon: Icons.check_circle_outline, text: 'Nothing to assign')
          : ListView(children: [
              for (final r in s.unclaimed)
                AppCard(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(children: [
                    const Icon(Icons.scale, color: brandBlue),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.fmtWeight(r.weight), style: const TextStyle(fontWeight: FontWeight.w700)), Text(DateFormat('MMM d, HH:mm').format(r.ts), style: const TextStyle(color: mutedColor, fontSize: 12))])),
                    PopupMenuButton<int>(
                      child: const Chip(label: Text('Assign to…')),
                      onSelected: (mid) => guarded(context, () async {
                        await s.api.post('/app/bodyData/claim', {'id': r.id, 'memberId': mid});
                        await s.loadRecords();
                      }, success: 'Assigned'),
                      itemBuilder: (_) => [for (final m in s.members) PopupMenuItem(value: m.id, child: Text('${m.avatar} ${m.name}'))],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, 'Delete measurement?', 'This cannot be undone.', ok: 'Delete')) {
                          await guarded(context, () async {
                            await s.api.post('/app/bodyData/delete', {'id': r.id});
                            await s.loadRecords();
                          });
                        }
                      },
                    ),
                  ]),
                ),
            ]),
    );
  }
}
