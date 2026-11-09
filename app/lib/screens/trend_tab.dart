import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/metrics.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'health_tab.dart';
import 'history_screen.dart';
import 'result_screen.dart';

class TrendTab extends StatefulWidget {
  const TrendTab({super.key});
  @override
  State<TrendTab> createState() => _TrendTabState();
}

class _TrendTabState extends State<TrendTab> {
  String _key = 'weight';
  int _days = 30;

  static const _keys = {'weight': 'Weight', 'bmi': 'BMI', 'bodyFat': 'Body fat', 'muscleRate': 'Muscle', 'water': 'Water', 'visceralFat': 'Visceral fat', 'bmr': 'BMR', 'score': 'Score'};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cutoff = DateTime.now().subtract(Duration(days: _days));
    final recs = s.records.where((r) => (_days >= 3650 || r.ts.isAfter(cutoff)) && (_key == 'weight' || r.m(_key) != null)).toList().reversed.toList();
    double val(BodyRecord r) => _key == 'weight' ? s.toDisplayWeight(r.weight) : r.m(_key)!;
    final vals = recs.map(val).toList();
    final unit = _key == 'weight' ? ' ${s.weightUnit}' : (defOf(_key)?.unit.isNotEmpty == true ? ' ${defOf(_key)!.unit}' : '');
    final df = DateFormat('MMM d');

    Widget stat(String l, double? v) => Expanded(child: Column(children: [Text(v == null ? '--' : v.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text(l, style: const TextStyle(fontSize: 11, color: mutedColor))]));
    final avg = vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;

    return GScaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            child: Row(children: [
              const MemberPill(),
              const Spacer(),
              IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())), icon: const Icon(Icons.history)),
            ]),
          ),
          const GroupTitle('Trend'),
          SizedBox(
            height: 42,
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal, children: [
              for (final e in _keys.entries)
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e.value), selected: _key == e.key, selectedColor: brandBlue, labelStyle: TextStyle(color: _key == e.key ? Colors.white : null), showCheckmark: false, onSelected: (_) => setState(() => _key = e.key))),
            ]),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (final d in const {7: '7D', 30: '30D', 90: '90D', 3650: 'All'}.entries)
                  Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(visualDensity: VisualDensity.compact, label: Text(d.value, style: const TextStyle(fontSize: 12)), selected: _days == d.key, onSelected: (_) => setState(() => _days = d.key))),
              ]),
              const SizedBox(height: 8),
              TrendChart(values: vals, unit: unit, labels: vals.length < 2 ? null : recs.map((r) => df.format(r.ts)).toList(), height: 200, color: brandBlue),
            ]),
          ),
          AppCard(
            child: Row(children: [
              stat('Latest', vals.isEmpty ? null : vals.last),
              stat('Average', avg),
              stat('Min', vals.isEmpty ? null : vals.reduce((a, b) => a < b ? a : b)),
              stat('Max', vals.isEmpty ? null : vals.reduce((a, b) => a > b ? a : b)),
            ]),
          ),
          if (vals.length > 1)
            AppCard(
              child: Row(children: [
                const Icon(Icons.swap_vert, color: brandBlue),
                const SizedBox(width: 10),
                Expanded(child: Text('Change over this period: ${(vals.last - vals.first) >= 0 ? '+' : ''}${(vals.last - vals.first).toStringAsFixed(1)}$unit', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          const GroupTitle('Recent records'),
          if (s.records.isEmpty) const AppCard(child: Text('No records yet.')),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (final r in s.records.take(6))
                MenuRow(
                  icon: Icons.monitor_weight_outlined,
                  title: s.fmtWeight(r.weight),
                  subtitle: DateFormat('MMM d, y · HH:mm').format(r.ts),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(record: r, member: s.member))),
                  trailing: r.m('bodyFat') == null ? null : Row(mainAxisSize: MainAxisSize.min, children: [Text('Fat ${r.m('bodyFat')!.toStringAsFixed(1)}%', style: const TextStyle(color: mutedColor, fontSize: 12)), const Icon(Icons.chevron_right, color: mutedColor)]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(onPressed: s.member == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())), icon: const Icon(Icons.compare_arrows), label: const Text('All records & compare')),
          ),
        ]),
      ),
    );
  }
}
