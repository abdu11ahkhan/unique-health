import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// CSV text for [records] (oldest first). Works everywhere; used for the export card.
String recordsToCsv(List<BodyRecord> records, {String weightUnit = 'kg'}) {
  const cols = ['bodyFat', 'bmi', 'muscleMass', 'muscleRate', 'water', 'boneMass', 'visceralFat', 'bmr', 'score'];
  final b = StringBuffer('date,weight_kg,impedance_ohm,${cols.join(',')},source\n');
  for (final r in records.reversed) {
    b.writeln([r.ts.toIso8601String(), r.weight.toStringAsFixed(2), r.impedance.round(), for (final c in cols) r.m(c)?.toString() ?? '', r.source].join(','));
  }
  return b.toString();
}

class HealthSyncScreen extends StatefulWidget {
  const HealthSyncScreen({super.key});
  @override
  State<HealthSyncScreen> createState() => _HealthSyncScreenState();
}

class _HealthSyncScreenState extends State<HealthSyncScreen> {
  bool _busy = false;
  String? _msg;
  static bool get hcSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Writes weight (and body fat when known) of the selected profile to Health Connect / HealthKit.
  /// Only records newer than the last successful sync are sent, so running it twice does not duplicate data.
  Future<void> _syncHealth() async {
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final health = Health();
      await health.configure();
      if (Platform.isAndroid) {
        final st = await health.getHealthConnectSdkStatus();
        if (st != HealthConnectSdkStatus.sdkAvailable) {
          await health.installHealthConnect();
          throw 'Health Connect is not installed or needs an update. Install it from the Play Store, then try again.';
        }
      }
      const types = [HealthDataType.WEIGHT, HealthDataType.BODY_FAT_PERCENTAGE];
      final ok = await health.requestAuthorization(types, permissions: const [HealthDataAccess.READ_WRITE, HealthDataAccess.READ_WRITE]);
      if (!ok) throw 'Permission was not granted in Health Connect.';
      final key = 'hc_last_${s.memberId}';
      final last = s.prefs.getInt(key) ?? 0;
      final fresh = s.records.where((r) => r.id > 0 && r.ts.millisecondsSinceEpoch > last).toList().reversed.toList();
      var sent = 0;
      for (final r in fresh) {
        final okW = await health.writeHealthData(value: r.weight, unit: HealthDataUnit.KILOGRAM, type: HealthDataType.WEIGHT, startTime: r.ts, endTime: r.ts, recordingMethod: RecordingMethod.automatic);
        if (okW) sent++;
        final bf = r.m('bodyFat');
        if (bf != null) await health.writeHealthData(value: bf, unit: HealthDataUnit.PERCENT, type: HealthDataType.BODY_FAT_PERCENTAGE, startTime: r.ts, endTime: r.ts, recordingMethod: RecordingMethod.automatic);
        await s.prefs.setInt(key, r.ts.millisecondsSinceEpoch);
      }
      _msg = fresh.isEmpty ? 'Already up to date.' : 'Sent $sent measurement(s) to ${Platform.isIOS ? 'Apple Health' : 'Health Connect'}.';
    } catch (e) {
      _msg = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return GScaffold(
      appBar: AppBar(title: const Text('Health sync & export')),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.health_and_safety, color: brandBlue), SizedBox(width: 10), Text('Health Connect', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
            const SizedBox(height: 6),
            const Text('Sends weight and body fat to Android Health Connect (or Apple Health on iOS). Samsung Health and Google Fit apps read these values through Health Connect.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            if (!hcSupported) const Text('Available in the Android or iOS app only.', style: TextStyle(color: mutedColor, fontSize: 12)),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: !hcSupported || _busy ? null : _syncHealth, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: Text(_busy ? 'Sending…' : 'Send ${s.member?.name ?? 'my'} data'))),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!)),
          ]),
        ),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.table_chart, color: brandBlue), SizedBox(width: 10), Text('Export as CSV', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
            const SizedBox(height: 6),
            Text('${s.records.length} measurement(s) for ${s.member?.name ?? 'this profile'}. Copies a spreadsheet-ready CSV to the clipboard.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: s.records.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: recordsToCsv(s.records)));
                        if (context.mounted) toast(context, 'CSV copied. Paste it into a spreadsheet or a file.');
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copy CSV'),
              ),
            ),
          ]),
        ),
        const AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.info_outline, color: mutedColor), SizedBox(width: 10), Text('Not included', style: TextStyle(fontWeight: FontWeight.w800))]),
            SizedBox(height: 6),
            Text('• Fitbit needs a Fitbit developer app (client ID and secret) registered by you, so it is not built in.\n• Google Fit APIs are being retired by Google in favour of Health Connect.\n• Samsung Health direct access needs Samsung partner approval; use Health Connect instead.', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}
