import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:provider/provider.dart';
import '../core/body_calc.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'add_device_screen.dart';
import 'result_screen.dart';

enum MeasureMode { me, guest, baby }

/// Entry point used by the Health tab and device screens.
Future<void> startMeasureFlow(BuildContext context, {Device? device}) async {
  final s = context.read<AppState>();
  if (s.member == null) return;
  final body = s.devices.where((d) => !d.isFood).toList();
  Device? dev = device;
  if (dev == null) {
    if (body.isEmpty) {
      toast(context, 'Add a body scale first');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
      return;
    }
    dev = body.first;
  }
  final mode = await showModalBottomSheet<MeasureMode>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('Measure on ${dev!.customName}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ListTile(leading: Text(s.member!.avatar, style: const TextStyle(fontSize: 24)), title: Text('Me (${s.member!.name})'), subtitle: const Text('Saved to the selected profile'), onTap: () => Navigator.pop(c, MeasureMode.me)),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Guest mode'), subtitle: const Text('Someone without a profile'), onTap: () => Navigator.pop(c, MeasureMode.guest)),
        ListTile(leading: const Icon(Icons.child_care), title: const Text('Hold a baby'), subtitle: const Text('Weigh yourself, then with the baby'), onTap: () => Navigator.pop(c, MeasureMode.baby)),
      ]),
    ),
  );
  if (mode == null || !context.mounted) return;
  Member? target = s.member;
  Map<String, num>? guest;
  if (mode == MeasureMode.guest) {
    guest = await _askGuest(context);
    if (guest == null || !context.mounted) return;
  }
  if (mode == MeasureMode.baby) {
    target = await showDialog<Member>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Whose weight is it?'), children: [for (final m in s.members) SimpleDialogOption(onPressed: () => Navigator.pop(c, m), child: Text('${m.avatar}  ${m.name}'))]),
    );
    if (target == null || !context.mounted) return;
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => MeasureScreen(device: dev!, mode: mode, member: target!, guest: guest)));
}

Future<Map<String, num>?> _askGuest(BuildContext context) {
  var gender = 1;
  final h = TextEditingController(text: '170'), a = TextEditingController(text: '30');
  return showDialog<Map<String, num>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Guest details'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('Male')), ButtonSegment(value: 0, label: Text('Female'))], selected: {gender}, onSelectionChanged: (v) => set(() => gender = v.first)),
          const SizedBox(height: 12),
          TextField(controller: h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height (cm)')),
          const SizedBox(height: 12),
          TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final hv = double.tryParse(h.text), av = int.tryParse(a.text);
              if (hv == null || av == null || hv < 50 || hv > 250 || av < 3 || av > 120) return;
              Navigator.pop(c, {'gender': gender, 'height': hv, 'age': av});
            },
            child: const Text('Start'),
          ),
        ],
      ),
    ),
  );
}

class MeasureScreen extends StatefulWidget {
  final Device device;
  final MeasureMode mode;
  final Member member;
  final Map<String, num>? guest;
  const MeasureScreen({super.key, required this.device, required this.mode, required this.member, this.guest});
  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  StreamSubscription<ScaleReading>? _sub;
  late final AppState _state = context.read<AppState>();
  ScaleReading? _r;
  String? _error;
  bool _connecting = true;
  bool _handled = false; // a final reading was already consumed; wait for step-off
  int _babyStep = 1;
  double? _adultKg;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.measureActive++;
    _sub = s.scale.readings.listen(_onReading);
    _connect();
  }

  Future<void> _connect() async {
    final s = context.read<AppState>();
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await s.scale.connect(widget.device.mac);
    } catch (e) {
      _error = 'Could not connect to ${widget.device.customName}.\nStart the virtual scale (or turn on the scale) and retry.';
    }
    if (mounted) setState(() => _connecting = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _state.measureActive--;
    super.dispose();
  }

  String get _hint {
    if (widget.mode == MeasureMode.baby) return _babyStep == 1 ? 'Step 1 of 2: stand on the scale alone' : 'Step 2 of 2: step on again holding the baby';
    return 'Step on the scale barefoot';
  }

  Future<void> _onReading(ScaleReading r) async {
    if (!mounted) return;
    setState(() => _r = r);
    if ((r.stage == 'idle' && r.value < 1) || (r.stage == 'weighing' && !r.stable)) {
      _handled = false; // stepped off, or a new weighing cycle started
      if (r.stage == 'idle') return;
    }
    if (_handled) return;
    if (r.stage == 'done' || r.stage == 'error') {
      _handled = true;
      await _finish(r);
    }
  }

  Future<void> _finish(ScaleReading r) async {
    final s = context.read<AppState>();
    final kg = r.value;
    final err = r.stage == 'error';
    switch (widget.mode) {
      case MeasureMode.me:
        if (err) {
          final save = await _impedanceError();
          if (save != true || !mounted) {
            _handled = false;
            return;
          }
        }
        BodyRecord? rec;
        final ok = await guarded(context, () async {
          rec = await s.saveMeasurement(weight: kg, impedance: err ? 0 : r.impedance, memberId: widget.member.id, deviceId: widget.device.id, source: 'scale', metrics: err ? {'bmi': _bmi(kg, widget.member.height)} : null);
        });
        if (ok && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(record: rec!, member: widget.member)));
        break;
      case MeasureMode.guest:
        if (err) {
          _handled = false;
          await _impedanceError(retryOnly: true);
          return;
        }
        BodyRecord? rec;
        final g = widget.guest!;
        final ok = await guarded(context, () async {
          final m = computeMetrics(weight: kg, impedance: r.impedance, height: g['height']!.toDouble(), age: g['age']!.toInt(), gender: g['gender']!.toInt());
          rec = BodyRecord(id: -1, memberId: null, weight: kg, impedance: r.impedance, metrics: m, source: 'guest', ts: DateTime.now());
        });
        if (!ok || !mounted) return;
        final save = await confirm(context, 'Guest result ready', 'Save it as an unassigned measurement so it can be added to a profile later?', ok: 'Save');
        if (save && mounted) {
          await guarded(context, () async {
            await s.saveMeasurement(weight: kg, impedance: r.impedance, deviceId: widget.device.id, source: 'guest', metrics: rec!.metrics);
          });
        }
        if (mounted) {
          final guestMember = Member(id: -1, name: 'Guest', gender: g['gender']!.toInt(), birthday: '2000-01-01', height: g['height']!.toDouble(), avatar: '👤', isSelf: false, athlete: false);
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(record: rec!, member: guestMember)));
        }
        break;
      case MeasureMode.baby:
        if (_babyStep == 1) {
          setState(() {
            _adultKg = kg;
            _babyStep = 2;
          });
          toast(context, 'Captured ${s.fmtWeight(kg)}. Now step off, then step on holding the baby.');
        } else {
          final baby = kg - (_adultKg ?? 0);
          if (baby < 0.2) {
            setState(() => _babyStep = 1);
            return toast(context, 'Second reading must be heavier than the first. Start again.', error: true);
          }
          BodyRecord? rec;
          final ok = await guarded(context, () async {
            rec = await s.saveMeasurement(weight: double.parse(baby.toStringAsFixed(2)), memberId: widget.member.id, deviceId: widget.device.id, source: 'baby', metrics: {'bmi': _bmi(baby, widget.member.height)});
          });
          if (ok && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(record: rec!, member: widget.member)));
        }
        break;
    }
  }

  double _bmi(double kg, double cm) => double.parse((kg / ((cm / 100) * (cm / 100))).toStringAsFixed(1));

  Future<bool?> _impedanceError({bool retryOnly = false}) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Body composition failed'),
          content: const Text('The scale could not read impedance. Stand barefoot on both electrodes with dry feet and try again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Try again')),
            if (!retryOnly) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save weight only')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final linked = s.scale.state == LinkState.connected;
    final r = _r;
    final measuring = r != null && r.stage == 'measuring';
    final kg = r?.value ?? 0;
    return GScaffold(
      appBar: AppBar(title: Text(widget.mode == MeasureMode.baby ? 'Baby weight' : widget.mode == MeasureMode.guest ? 'Guest measurement' : 'Measure')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Chip(avatar: Icon(Icons.circle, size: 10, color: linked ? Colors.green : Colors.orange), label: Text(_connecting ? 'Connecting…' : linked ? 'Connected to ${widget.device.customName}' : 'Not connected')),
            const SizedBox(height: 32),
            Text(r == null ? '--.-' : s.fmtWeight(kg).split(' ').first, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(s.weightUnit, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            if (measuring) ...[const LinearProgressIndicator(), const SizedBox(height: 8), const Text('Measuring body composition… stay still')]
            else if (r != null && r.stable && r.value > 1) const Text('Stable', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700))
            else Text(r == null ? _hint : (r.value < 1 ? _hint : 'Weighing…')),
            if (_error != null) ...[const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)), const SizedBox(height: 12), FilledButton(onPressed: _connect, child: const Text('Retry'))],
            if (widget.mode == MeasureMode.baby && _adultKg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Adult: ${s.fmtWeight(_adultKg!)}')),
          ]),
        ),
      ),
    );
  }
}

/// Manual weight entry (used by the + sheet and the Home tab).
Future<void> addManualWeight(BuildContext context) async {
  final s = context.read<AppState>();
  if (s.member == null) return;
  final t = await askText(context, 'Enter weight (${s.weightUnit})', type: const TextInputType.numberWithOptions(decimal: true));
  final v = double.tryParse(t ?? '');
  if (v == null || !context.mounted) return;
  final kg = s.fromDisplayWeight(v);
  if (kg < 2 || kg > 400) return toast(context, 'Weight looks wrong', error: true);
  final ok = await guarded(context, () async {
    await s.saveMeasurement(weight: kg, memberId: s.member!.id, source: 'manual');
  }, success: 'Saved');
  if (ok && context.mounted && s.latest != null) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(record: s.latest!, member: s.member)));
  }
}
