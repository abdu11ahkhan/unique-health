import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/metrics.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'add_device_screen.dart';
import 'history_screen.dart';
import 'measure_screen.dart';
import 'insights.dart';
import 'messages_screen.dart';
import 'result_screen.dart';

/// Avatar + name dropdown that switches the active profile.
class MemberPill extends StatelessWidget {
  const MemberPill({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.member;
    return PopupMenuButton<int>(
      enabled: s.members.length > 1,
      onSelected: s.selectMember,
      itemBuilder: (_) => [for (final x in s.members) PopupMenuItem(value: x.id, child: Text('${x.avatar}  ${x.name}'))],
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: Colors.white.withAlpha(190), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 16, backgroundColor: const Color(0xFFE3E7FD), child: Text(m?.avatar ?? '🙂', style: const TextStyle(fontSize: 16))),
          const SizedBox(width: 8),
          Text(m?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, color: inkColor)),
          if (s.members.length > 1) const Icon(Icons.arrow_drop_down, color: inkColor),
        ]),
      ),
    );
  }
}

class HealthTab extends StatelessWidget {
  const HealthTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.member;
    final latest = s.latest;
    final df = DateFormat('MMM d, HH:mm');
    final linked = s.scale.state == LinkState.connected;
    void open(String key) => Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(record: latest!, member: m, initialKey: key)));

    return GScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => guarded(context, s.loadAll),
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(children: [
                const MemberPill(),
                const Spacer(),
                IconButton(
                  tooltip: linked ? 'Scale connected' : 'Scale offline',
                  onPressed: () => linked ? toast(context, 'Connected to ${s.scale.device?.name}') : Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen())),
                  icon: Icon(linked ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: linked ? brandBlue : mutedColor),
                ),
                IconButton(
                  tooltip: 'Messages',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen())),
                  icon: Badge(isLabelVisible: s.unread > 0, label: Text('${s.unread}'), child: const Icon(Icons.notifications_none)),
                ),
                IconButton(tooltip: 'History', onPressed: m == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())), icon: const Icon(Icons.history)),
              ]),
            ),
            if (s.unclaimed.isNotEmpty)
              AppCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClaimScreen())),
                child: Row(children: [
                  const Icon(Icons.help_outline, color: brandBlue),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${s.unclaimed.length} unassigned measurement(s) — tap to assign')),
                  const Icon(Icons.chevron_right, color: mutedColor),
                ]),
              ),
            if (latest == null)
              SizedBox(
                height: 380,
                child: EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  text: 'No measurements yet.\nStep on a scale or add a weight manually.',
                  action: Wrap(spacing: 8, children: [
                    FilledButton.icon(onPressed: () => startMeasureFlow(context), icon: const Icon(Icons.bluetooth_searching), label: const Text('Measure')),
                    OutlinedButton.icon(onPressed: () => addManualWeight(context), icon: const Icon(Icons.edit), label: const Text('Manual')),
                  ]),
                ),
              )
            else ...[
              // hero
              AppCard(
                onTap: () => open('weight'),
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Weight', style: TextStyle(color: mutedColor)),
                      Text(s.fmtWeight(latest.weight), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: brandBlue)),
                      const SizedBox(height: 4),
                      StatusChip(rate('weight', latest.weight, m)),
                      const SizedBox(height: 8),
                      Text(df.format(latest.ts), style: const TextStyle(fontSize: 12, color: mutedColor)),
                      if (s.records.length > 1) _Delta(s.records[0].weight - s.records[1].weight, s),
                    ]),
                  ),
                  if (latest.m('score') != null)
                    Column(children: [
                      ScoreRing(score: latest.m('score')!.round(), size: 92),
                      const SizedBox(height: 4),
                      Text(scoreLabel(latest.m('score')!), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                ]),
              ),
              const GoalCard(),
              const WeeklyCard(),
              const GroupTitle('Body Weight and Basic Indicators'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: _Mini(label: 'Weight', value: s.toDisplayWeight(latest.weight).toStringAsFixed(1), unit: s.weightUnit, level: rate('weight', latest.weight, m), onTap: () => open('weight'))),
                  const SizedBox(width: 12),
                  Expanded(child: _Mini(label: 'BMI (Body Mass Index)', value: (latest.m('bmi') ?? 0).toStringAsFixed(1), unit: '', level: rate('bmi', latest.m('bmi') ?? 0, m), onTap: () => open('bmi'))),
                ]),
              ),
              const SizedBox(height: 12),
              if (latest.metrics.length > 2) ...[
                const GroupTitle('Body data'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(children: [
                    for (final d in metricDefs.where((d) => d.key != 'bmi' && latest.m(d.key) != null))
                      MenuRow(
                        icon: d.icon,
                        title: d.label,
                        onTap: () => open(d.key),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          StatusChip(rate(d.key, latest.m(d.key)!, m, weight: latest.weight)),
                          const SizedBox(width: 8),
                          Text('${fmtNum(latest.m(d.key)!, d.decimals)}${d.unit.isEmpty ? '' : ' ${d.unit}'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Icon(Icons.chevron_right, color: mutedColor),
                        ]),
                      ),
                  ]),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label, value, unit;
  final Rating? level;
  final VoidCallback onTap;
  const _Mini({required this.label, required this.value, required this.unit, required this.level, required this.onTap});
  @override
  Widget build(BuildContext context) => AppCard(
        margin: EdgeInsets.zero,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: mutedColor), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (unit.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(unit, style: const TextStyle(fontSize: 12, color: mutedColor))),
          ]),
          const SizedBox(height: 6),
          StatusChip(level),
        ]),
      );
}

class _Delta extends StatelessWidget {
  final double d;
  final AppState s;
  const _Delta(this.d, this.s);
  @override
  Widget build(BuildContext context) {
    if (d.abs() < 0.05) return const Text('No change since last time', style: TextStyle(fontSize: 12, color: mutedColor));
    final up = d > 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: up ? Colors.orange : Colors.green),
      Text(' ${s.toDisplayWeight(d.abs()).toStringAsFixed(1)} ${s.weightUnit} since last time', style: const TextStyle(fontSize: 12, color: mutedColor)),
    ]);
  }
}
