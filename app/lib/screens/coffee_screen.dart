import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Coffee scale: live grams, brew timer, dose/water capture, ratio and brew log.
class CoffeeScreen extends StatefulWidget {
  final Device device;
  const CoffeeScreen({super.key, required this.device});
  @override
  State<CoffeeScreen> createState() => _CoffeeScreenState();
}

class _CoffeeScreenState extends State<CoffeeScreen> {
  StreamSubscription<ScaleReading>? _sub;
  late final AppState _state = context.read<AppState>();
  final _sw = Stopwatch();
  Timer? _tick;
  double _grams = 0;
  bool _stable = false;
  double? _dose, _water;
  String _method = 'V60';
  int _rating = 0;
  final _notes = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _state.measureActive++;
    _sub = _state.scale.readings.listen((r) {
      if (r.unit == 'g' && mounted) setState(() {
        _grams = r.value;
        _stable = r.stable;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _notes.dispose();
    _state.measureActive--;
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await _state.scale.connect(widget.device.mac);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'Coffee scale offline. Set the virtual scale type to "Coffee scale" and tap Connect.');
    }
  }

  void _toggleTimer() {
    if (_sw.isRunning) {
      _sw.stop();
      _tick?.cancel();
    } else {
      _sw.start();
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
    }
    setState(() {});
  }

  void _resetTimer() {
    _sw..stop()..reset();
    _tick?.cancel();
    setState(() {});
  }

  String get _time {
    final t = _sw.elapsed;
    return '${t.inMinutes.toString().padLeft(2, '0')}:${(t.inSeconds % 60).toString().padLeft(2, '0')}.${(t.inMilliseconds % 1000 ~/ 100)}';
  }

  Future<void> _save() async {
    final d = _dose, w = _water;
    if (d == null || w == null || d <= 0 || w <= 0) return toast(context, 'Capture the coffee dose and the water first', error: true);
    final s = _state;
    final ok = await guarded(context, () => s.api.post('/app/brew', {'name': _method, 'dose': d, 'water': w, 'seconds': _sw.elapsed.inMilliseconds / 1000, if (_rating > 0) 'rating': _rating, 'notes': _notes.text.trim()}), success: 'Brew saved');
    if (ok && mounted) {
      setState(() {
        _dose = _water = null;
        _rating = 0;
        _notes.clear();
      });
      _resetTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final linked = s.scale.state == LinkState.connected && s.scale.device?.mac == widget.device.mac;
    final ratio = (_dose != null && _water != null && _dose! > 0) ? _water! / _dose! : null;
    return GScaffold(
      appBar: AppBar(title: const Text('Coffee scale'), actions: [IconButton(tooltip: 'Brew history', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrewHistoryScreen())), icon: const Icon(Icons.history))]),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        AppCard(
          child: Column(children: [
            Row(children: [
              Chip(avatar: Icon(Icons.circle, size: 10, color: linked ? Colors.green : Colors.orange), label: Text(linked ? 'Connected' : 'Offline')),
              const Spacer(),
              TextButton.icon(onPressed: () => linked ? s.scale.command({'cmd': 'tare'}) : _connect(), icon: Icon(linked ? Icons.exposure_zero : Icons.refresh), label: Text(linked ? 'Tare' : 'Connect')),
            ]),
            Text('${_grams.toStringAsFixed(1)} g', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: brandBlue)),
            Text(_stable ? 'Stable' : 'Place your coffee or pour water', style: TextStyle(color: _stable ? Colors.green : mutedColor)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const Divider(height: 24),
            Text(_time, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(onPressed: _toggleTimer, icon: Icon(_sw.isRunning ? Icons.pause : Icons.play_arrow), label: Text(_sw.isRunning ? 'Pause' : 'Start timer')),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _resetTimer, child: const Text('Reset')),
            ]),
          ]),
        ),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recipe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Capture(label: 'Coffee dose', value: _dose, onCapture: () => setState(() => _dose = _grams))),
              const SizedBox(width: 12),
              Expanded(child: _Capture(label: 'Water', value: _water, onCapture: () => setState(() => _water = _grams))),
            ]),
            const SizedBox(height: 10),
            Text(ratio == null ? 'Ratio: capture both values' : 'Ratio 1 : ${ratio.toStringAsFixed(1)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [for (final m in ['V60', 'Espresso', 'French press', 'AeroPress', 'Moka'].toList()) ChoiceChip(label: Text(m), selected: _method == m, onSelected: (_) => setState(() => _method = m))]),
            const SizedBox(height: 10),
            Row(children: [const Text('Rating'), for (var i = 1; i <= 5; i++) IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _rating = i), icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: const Color(0xFFE5B83B)))]),
            TextField(controller: _notes, maxLength: 300, decoration: const InputDecoration(hintText: 'Tasting notes (optional)')),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save brew'))),
          ]),
        ),
      ]),
    );
  }
}

class _Capture extends StatelessWidget {
  final String label;
  final double? value;
  final VoidCallback onCapture;
  const _Capture({required this.label, required this.value, required this.onCapture});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: mutedColor, fontSize: 12)),
        Text(value == null ? '-- g' : '${value!.toStringAsFixed(1)} g', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        TextButton(onPressed: onCapture, child: const Text('Use current weight')),
      ]);
}

class BrewHistoryScreen extends StatefulWidget {
  const BrewHistoryScreen({super.key});
  @override
  State<BrewHistoryScreen> createState() => _BrewHistoryScreenState();
}

class _BrewHistoryScreenState extends State<BrewHistoryScreen> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      final l = await s.cachedGet('brews', '/app/brew/list') as List;
      if (mounted) setState(() => _list = [for (final e in l) Map<String, dynamic>.from(e)]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return GScaffold(
      appBar: AppBar(title: const Text('Brew history')),
      body: _list == null
          ? const Center(child: CircularProgressIndicator())
          : _list!.isEmpty
              ? const EmptyState(icon: Icons.coffee, text: 'No brews yet.')
              : ListView(padding: const EdgeInsets.only(top: 8), children: [
                  for (final b in _list!)
                    AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(children: [
                        const Icon(Icons.coffee, color: brandBlue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${b['name']} · 1:${b['ratio']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${(b['dose'] as num).toStringAsFixed(1)} g coffee · ${(b['water'] as num).toStringAsFixed(0)} g water · ${(b['seconds'] as num).round()} s', style: const TextStyle(fontSize: 12, color: mutedColor)),
                            Text(DateFormat('MMM d, HH:mm').format(DateTime.fromMillisecondsSinceEpoch((b['ts'] as num).toInt())) + (b['rating'] == null ? '' : '  ${'★' * (b['rating'] as int)}'), style: const TextStyle(fontSize: 12, color: mutedColor)),
                            if ((b['notes'] as String).isNotEmpty) Text('${b['notes']}', style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await guarded(context, () => s.api.post('/app/brew/delete', {'id': b['id']}));
                            _load();
                          },
                        ),
                      ]),
                    ),
                ]),
    );
  }
}
