import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Current value for a goal type from the latest record.
double? _current(AppState s, String type) {
  final r = s.latest;
  if (r == null) return null;
  return type == 'weight' ? r.weight : r.m('bodyFat');
}

/// Days until [target] at the recent pace (least-squares over the last 21 days), or null if not moving toward it.
int? projectedDays(List<BodyRecord> records, String type, double target) {
  final cutoff = DateTime.now().subtract(const Duration(days: 21));
  final pts = records.where((r) => r.ts.isAfter(cutoff) && (type == 'weight' || r.m('bodyFat') != null)).toList();
  if (pts.length < 3) return null;
  final t0 = pts.map((r) => r.ts.millisecondsSinceEpoch).reduce(math.min);
  final xs = pts.map((r) => (r.ts.millisecondsSinceEpoch - t0) / 86400000).toList();
  final ys = pts.map((r) => type == 'weight' ? r.weight : r.m('bodyFat')!).toList();
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den == 0) return null;
  final slope = num / den; // units per day
  final cur = ys.last;
  final need = target - cur;
  if (slope == 0 || (need > 0) != (slope > 0)) return null;
  final days = need / slope;
  return days.isFinite && days >= 0 && days < 3650 ? days.ceil() : null;
}

Future<void> showGoalDialog(BuildContext context) async {
  final s = context.read<AppState>();
  var type = s.goal?['type'] as String? ?? 'weight';
  final cur = s.goal?['target'] as num?;
  final ctl = TextEditingController(text: cur == null ? '' : (type == 'weight' ? s.toDisplayWeight(cur.toDouble()) : cur.toDouble()).toStringAsFixed(1));
  DateTime? date = s.goal?['targetDate'] == null ? null : DateTime.fromMillisecondsSinceEpoch((s.goal!['targetDate'] as num).toInt());
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Set a goal'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'weight', label: Text('Weight')), ButtonSegment(value: 'bodyFat', label: Text('Body fat'))],
            selected: {type},
            onSelectionChanged: (v) => set(() {
              type = v.first;
              ctl.clear();
            }),
          ),
          const SizedBox(height: 14),
          TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Target', suffixText: type == 'weight' ? s.weightUnit : '%')),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(date == null ? 'No target date' : DateFormat('MMM d, y').format(date!)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: c, initialDate: date ?? DateTime.now().add(const Duration(days: 60)), firstDate: DateTime.now().add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 1500)));
              if (d != null) set(() => date = d);
            },
          ),
        ]),
        actions: [
          if (s.goal != null) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Remove goal')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (res == null || !context.mounted) return;
  if (res == false) {
    await guarded(context, s.deleteGoal, success: 'Goal removed');
    return;
  }
  final v = double.tryParse(ctl.text.trim());
  if (v == null) return toast(context, 'Enter a number', error: true);
  final target = type == 'weight' ? s.fromDisplayWeight(v) : v;
  await guarded(context, () => s.saveGoal(type, double.parse(target.toStringAsFixed(2)), date), success: 'Goal saved');
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final g = s.goal;
    if (g == null) {
      return AppCard(
        onTap: () => showGoalDialog(context),
        child: const Row(children: [
          Icon(Icons.flag_outlined, color: brandBlue),
          SizedBox(width: 12),
          Expanded(child: Text('Set a goal to track your progress')),
          Icon(Icons.chevron_right, color: mutedColor),
        ]),
      );
    }
    final type = g['type'] as String;
    final start = (g['start'] as num).toDouble(), target = (g['target'] as num).toDouble();
    final cur = _current(s, type) ?? start;
    final total = target - start;
    final done = total == 0 ? 1.0 : ((cur - start) / total).clamp(0.0, 1.0);
    final reached = total < 0 ? cur <= target : cur >= target;
    String f(double v) => type == 'weight' ? s.fmtWeight(v) : '${v.toStringAsFixed(1)}%';
    final left = (target - cur).abs();
    final eta = reached ? null : projectedDays(s.records, type, target);
    final td = g['targetDate'] == null ? null : DateTime.fromMillisecondsSinceEpoch((g['targetDate'] as num).toInt());
    final daysLeft = td?.difference(DateTime.now()).inDays;
    return AppCard(
      onTap: () => showGoalDialog(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag, color: brandBlue, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Goal: ${f(target)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text(reached ? 'Reached' : '${(done * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: reached ? Colors.green : brandBlue)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: reached ? 1 : done, minHeight: 10, color: reached ? Colors.green : brandBlue, backgroundColor: brandBlue.withAlpha(30))),
        const SizedBox(height: 8),
        Row(children: [
          Text('Start ${f(start)}', style: const TextStyle(fontSize: 12, color: mutedColor)),
          const Spacer(),
          Text('Now ${f(cur)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(
          reached
              ? 'Goal reached. Nice work!'
              : '${f(left)} to go${eta != null ? ' · about $eta days at your current pace' : ''}${daysLeft != null ? ' · ${daysLeft < 0 ? 'target date passed' : '$daysLeft days left'}' : ''}',
          style: const TextStyle(fontSize: 13),
        ),
      ]),
    );
  }
}

class WeeklyCard extends StatelessWidget {
  const WeeklyCard({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.weekly;
    if (w == null) return const SizedBox.shrink();
    final days = (w['daysWithWeighIn'] as List).cast<bool>();
    final from = DateTime.fromMillisecondsSinceEpoch((w['from'] as num).toInt());
    final streak = (w['streak'] as num).toInt();
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('This week', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          if (streak > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFF1E0), borderRadius: BorderRadius.circular(99)), child: Text('🔥 $streak-day streak', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB36B00)))),
          const Icon(Icons.chevron_right, color: mutedColor),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < 7; i++)
            Column(children: [
              Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: days[i] ? brandBlue : brandBlue.withAlpha(26)), child: days[i] ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
              const SizedBox(height: 4),
              Text(DateFormat('E').format(from.add(Duration(days: i))).substring(0, 1), style: const TextStyle(fontSize: 11, color: mutedColor)),
            ]),
        ]),
        const SizedBox(height: 10),
        Text('${w['weighIns']} weigh-in${w['weighIns'] == 1 ? '' : 's'}${w['avgWeight'] != null ? ' · avg ${s.fmtWeight((w['avgWeight'] as num).toDouble())}' : ''}', style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}

class WeeklyScreen extends StatelessWidget {
  const WeeklyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.weekly;
    Widget row(IconData i, String label, String value, {String? sub, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(i, color: brandBlue),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: mutedColor))])),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ]),
        );
    String delta(num? cur, num? prev, String unit, {bool kg = false}) {
      if (cur == null || prev == null) return 'no data last week';
      final d = (cur - prev).toDouble();
      final v = kg ? s.toDisplayWeight(d.abs()) : d.abs();
      if (v < 0.05) return 'same as last week';
      return '${d > 0 ? '▲' : '▼'} ${v.toStringAsFixed(1)} $unit vs last week';
    }

    return GScaffold(
      appBar: AppBar(title: const Text('Weekly summary')),
      body: w == null
          ? const EmptyState(icon: Icons.insights, text: 'No data yet')
          : ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  row(Icons.local_fire_department, 'Streak', '${w['streak']} day${w['streak'] == 1 ? '' : 's'}', sub: 'Days in a row with a weigh-in'),
                  const Divider(height: 1),
                  row(Icons.monitor_weight, 'Weigh-ins', '${w['weighIns']} / 7 days', sub: '${(w['daysWithWeighIn'] as List).where((d) => d == true).length} different days'),
                  const Divider(height: 1),
                  row(Icons.scale, 'Average weight', w['avgWeight'] == null ? '--' : s.fmtWeight((w['avgWeight'] as num).toDouble()), sub: delta(w['avgWeight'] as num?, w['prevAvgWeight'] as num?, s.weightUnit, kg: true)),
                  const Divider(height: 1),
                  row(Icons.swap_vert, 'Change this week', w['changeKg'] == null ? '--' : '${(w['changeKg'] as num) > 0 ? '+' : ''}${s.toDisplayWeight((w['changeKg'] as num).toDouble()).toStringAsFixed(1)} ${s.weightUnit}', sub: 'First to last reading'),
                  const Divider(height: 1),
                  row(Icons.opacity, 'Average body fat', w['avgBodyFat'] == null ? '--' : '${(w['avgBodyFat'] as num).toStringAsFixed(1)}%', sub: delta(w['avgBodyFat'] as num?, w['prevAvgBodyFat'] as num?, '%')),
                  const Divider(height: 1),
                  row(Icons.restaurant, 'Calories eaten', (w['calories']['avgPerLoggedDay']) == null ? '--' : '${w['calories']['avgPerLoggedDay']} kcal/day', sub: '${w['calories']['loggedDays']} day(s) logged · ${w['calories']['total']} kcal total'),
                ]),
              ),
              if (w['minWeight'] != null)
                AppCard(child: Text('Range this week: ${s.fmtWeight((w['minWeight'] as num).toDouble())} to ${s.fmtWeight((w['maxWeight'] as num).toDouble())}')),
            ]),
    );
  }
}
