import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import '../widgets/ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class FoodScreen extends StatefulWidget {
  final Device? device;
  final FoodItem? initialFood;
  const FoodScreen({super.key, this.device, this.initialFood});
  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  StreamSubscription<ScaleReading>? _sub;
  late final AppState _state = context.read<AppState>();
  List<FoodItem> _foods = [];
  List<FoodRecord> _today = [];
  List<Map<String, dynamic>> _week = [];
  Map<String, dynamic> _sum = {};
  FoodItem? _food;
  double _grams = 0;
  bool _stable = false, _manual = false, _wrongMode = false;
  String _meal = 'lunch', _q = '';
  String? _error;
  final _gramsCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _food = widget.initialFood;
    if (widget.device == null) _manual = true;
    s.measureActive++;
    _sub = s.scale.readings.listen((r) {
      if (!mounted) return;
      if (r.unit != 'g') {
        // a body-scale frame: the virtual scale is still in body mode
        if (!_wrongMode) setState(() => _wrongMode = true);
        return;
      }
      if (_wrongMode) _wrongMode = false;
      if (_manual) return;
      setState(() {
        _grams = r.value;
        _stable = r.stable;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
      _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _state.measureActive--;
    _gramsCtl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final s = context.read<AppState>();
    if (widget.device == null) return;
    try {
      await s.scale.connect(widget.device!.mac);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Food scale not found. On the virtual scale page set type to "Food / kitchen scale", check its MAC matches this device (${widget.device?.mac}), then tap Connect. You can also enter grams manually.');
    }
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      final from = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0).millisecondsSinceEpoch;
      final f = await s.cachedGet('foodBank', '/food/scale/defaultFood') as List;
      final l = await s.cachedGet('foodToday', '/food/record/list', query: {'from': from, 'to': from + 86400000}) as List;
      final w = await s.cachedGet('foodWeek', '/food/record/countLastSevenCalorie', query: {'from': from}) as List;
      final t = Map<String, dynamic>.from(await s.cachedGet('foodSum', '/food/record/countTodayNutrition', query: {'from': from}));
      final pend = s.pendingFoods(DateTime.fromMillisecondsSinceEpoch(from), DateTime.fromMillisecondsSinceEpoch(from + 86400000));
      for (final p in pend) {
        t['kcal'] = (t['kcal'] as num) + p.kcal;
        t['protein'] = (t['protein'] as num) + p.protein;
        t['fat'] = (t['fat'] as num) + p.fat;
        t['carb'] = (t['carb'] as num) + p.carb;
      }
      if (!mounted) return;
      setState(() {
        _foods = f.map((e) => FoodItem.fromJson(Map<String, dynamic>.from(e))).toList();
        _today = l.map((e) => FoodRecord.fromJson(Map<String, dynamic>.from(e))).toList();
        _week = w.map((e) => Map<String, dynamic>.from(e)).toList();
        _sum = Map<String, dynamic>.from(t);
      });
    });
  }

  Future<void> _add() async {
    final s = context.read<AppState>();
    final f = _food;
    if (f == null) return toast(context, 'Pick a food first', error: true);
    if (_grams <= 0) return toast(context, 'Put the food on the scale (or enter grams)', error: true);
    await guarded(context, () async {
      final sent = await s.uploadFood({'name': f.name, 'grams': _grams, 'per100': {'kcal': f.kcal, 'protein': f.protein, 'fat': f.fat, 'carb': f.carb}, 'meal': _meal, 'memberId': s.memberId});
      await _load();
      if (!sent && mounted) toast(context, 'Offline: saved on this device, will sync automatically');
    }, success: 'Added ${f.name} · ${_grams.round()} g');
  }

  Future<void> _custom() async {
    final name = await askText(context, 'Food name');
    if (name == null || name.isEmpty || !mounted) return;
    final k = await askText(context, 'Calories per 100 g', type: TextInputType.number);
    final kcal = double.tryParse(k ?? '');
    if (kcal == null || !mounted) return;
    setState(() => _food = FoodItem(-1, name, kcal, 0, 0, 0, '🍽️'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final linked = widget.device != null && s.scale.state == LinkState.connected && s.scale.device?.mac == widget.device?.mac;
    final foods = _foods.where((f) => f.name.toLowerCase().contains(_q.toLowerCase())).toList();
    final f = _food;
    final k = _grams / 100;
    final maxKcal = _week.fold<double>(1, (m, e) => (e['kcal'] as num).toDouble() > m ? (e['kcal'] as num).toDouble() : m);
    return GScaffold(
      appBar: AppBar(title: const Text('Food scale'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
        Section(
          child: Column(children: [
            Row(children: [
              Chip(avatar: Icon(Icons.circle, size: 10, color: linked ? Colors.green : Colors.orange), label: Text(linked ? 'Connected' : 'Offline')),
              const Spacer(),
              TextButton.icon(onPressed: () => linked ? s.scale.command({'cmd': 'tare'}) : _connect(), icon: Icon(linked ? Icons.exposure_zero : Icons.refresh), label: Text(linked ? 'Tare' : 'Connect')),
            ]),
            if (_manual)
              TextField(controller: _gramsCtl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(suffixText: 'g', labelText: 'Grams'), onChanged: (v) => setState(() => _grams = double.tryParse(v) ?? 0))
            else
              Text('${_grams.round()} g', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (!_manual) Text(_stable ? 'Stable' : 'Place food on the scale', style: TextStyle(color: _stable ? Colors.green : Theme.of(context).colorScheme.outline)),
            if (_wrongMode) Text('The scale is sending body-scale readings (kg). On the virtual scale page set type to "Food / kitchen scale".', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Enter grams manually'), value: _manual, onChanged: (v) => setState(() => _manual = v)),
            if (f != null && _grams > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 14, children: [
                  Text('${f.icon} ${f.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${(f.kcal * k).round()} kcal'),
                  Text('P ${(f.protein * k).toStringAsFixed(1)} g'),
                  Text('F ${(f.fat * k).toStringAsFixed(1)} g'),
                  Text('C ${(f.carb * k).toStringAsFixed(1)} g'),
                ]),
              ),
          ]),
        ),
        Section(
          title: 'Choose food',
          child: Column(children: [
            TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search foods', isDense: true), onChanged: (v) => setState(() => _q = v)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final x in foods)
                ChoiceChip(label: Text('${x.icon} ${x.name}'), selected: _food?.id == x.id, onSelected: (_) => setState(() => _food = x)),
              ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Custom'), onPressed: _custom),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              DropdownButton<String>(value: _meal, items: [for (final m in ['breakfast', 'lunch', 'dinner', 'snack']) DropdownMenuItem(value: m, child: Text(m))], onChanged: (v) => setState(() => _meal = v ?? 'lunch')),
              const Spacer(),
              FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add to diary')),
            ]),
          ]),
        ),
        Section(
          title: 'Today',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Stat('${(_sum['kcal'] ?? 0).round()}', 'kcal'),
              _Stat('${(_sum['protein'] ?? 0).toStringAsFixed(0)} g', 'protein'),
              _Stat('${(_sum['fat'] ?? 0).toStringAsFixed(0)} g', 'fat'),
              _Stat('${(_sum['carb'] ?? 0).toStringAsFixed(0)} g', 'carbs'),
            ]),
            const SizedBox(height: 12),
            if (_today.isEmpty) const Text('Nothing logged yet.'),
            for (final r in _today)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${r.name} · ${r.grams.round()} g'),
                subtitle: Text('${r.meal} · ${DateFormat('HH:mm').format(r.ts)} · ${r.kcal.round()} kcal'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => guarded(context, () async {
                      await s.api.post('/food/record/delete', {'id': r.id});
                      await _load();
                    })),
              ),
          ]),
        ),
        Section(
          title: 'Last 7 days (kcal)',
          child: SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final e in _week)
                Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${(e['kcal'] as num).round()}', style: const TextStyle(fontSize: 10)),
                  Container(width: 22, height: 4 + 76 * ((e['kcal'] as num).toDouble() / maxKcal), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 4),
                  Text(DateFormat('E').format(DateTime.fromMillisecondsSinceEpoch((e['day'] as num).toInt())), style: const TextStyle(fontSize: 10)),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String v, l;
  const _Stat(this.v, this.l);
  @override
  Widget build(BuildContext context) => Column(children: [Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text(l, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline))]);
}
