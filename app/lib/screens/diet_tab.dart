import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../widgets/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/scale_transport.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'add_device_screen.dart';
import 'food_screen.dart';
import 'scan_screen.dart';

class DietTab extends StatefulWidget {
  const DietTab({super.key});
  @override
  State<DietTab> createState() => _DietTabState();
}

class _DietTabState extends State<DietTab> {
  List<FoodItem> _foods = [];
  List<FoodRecord> _today = [];
  Map<String, dynamic> _sum = {};
  String _q = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    await guarded(context, () async {
      final from = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0).millisecondsSinceEpoch;
      final f = await s.cachedGet('foodBank', '/food/scale/defaultFood') as List;
      final l = await s.cachedGet('foodToday', '/food/record/list', query: {'from': from, 'to': from + 86400000}) as List;
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
        _today = [...pend, ...l.map((e) => FoodRecord.fromJson(Map<String, dynamic>.from(e)))];
        _sum = t;
        _loaded = true;
      });
    });
  }

  Future<void> _open(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) _load();
  }

  Future<void> _scanBarcode() async {
    final s = context.read<AppState>();
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scan food barcode', hint: 'Try 5000000000017 (apple) or 5000000000031 (egg). Only a small demo set of barcodes is in the local database.', manualLabel: 'Enter the barcode number', keyboard: TextInputType.number)));
    if (code == null || !mounted) return;
    Map<String, dynamic>? food;
    final ok = await guarded(context, () async => food = Map<String, dynamic>.from(await s.api.get('/food/barcode', query: {'code': code})));
    if (!ok || food == null || !mounted) return;
    final f = FoodItem.fromJson(food!);
    final fd = _foodDevice(s);
    await _open(FoodDetailScreen(food: f, device: fd));
  }

  Device? _foodDevice(AppState s) {
    for (final d in s.devices) {
      if (d.isFood) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final fd = _foodDevice(s);
    final linked = fd != null && s.scale.state == LinkState.connected && s.scale.device?.mac == fd.mac;
    final foods = _foods.where((f) => f.name.toLowerCase().contains(_q.toLowerCase())).toList();
    final kcal = (_sum['kcal'] ?? 0).toDouble();
    return GScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Material(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Search for food calories',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan a food barcode', onPressed: _scanBarcode),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            AppCard(
              onTap: () => fd == null ? _open(const AddDeviceScreen()) : _open(FoodScreen(device: fd)),
              child: Row(children: [
                const BrandLogo(size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Unique Health', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(fd == null ? 'No food scale yet — tap to add one' : '${fd.customName} · ${linked ? 'Connected' : 'Tap to weigh food'}', style: const TextStyle(fontSize: 12, color: mutedColor)),
                  ]),
                ),
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.scale, color: linked ? brandBlue : mutedColor)),
              ]),
            ),
            GroupTitle('Diet · ${DateFormat('MMM d').format(DateTime.now())}'),
            AppCard(
              child: Column(children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(kcal.round().toString(), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: brandBlue)),
                    const Text('kcal eaten today', style: TextStyle(color: mutedColor, fontSize: 12)),
                  ])),
                  OutlinedButton.icon(onPressed: () => _open(FoodScreen(device: fd)), icon: const Icon(Icons.add), label: const Text('Add food')),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  _Macro('Protein', (_sum['protein'] ?? 0).toDouble(), const Color(0xFF3F6BF4)),
                  _Macro('Fat', (_sum['fat'] ?? 0).toDouble(), const Color(0xFFF08A3C)),
                  _Macro('Carbs', (_sum['carb'] ?? 0).toDouble(), const Color(0xFF3DB88B)),
                ]),
              ]),
            ),
            if (_today.isNotEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  for (final r in _today)
                    MenuRow(
                      icon: Icons.restaurant_menu,
                      title: '${r.name} · ${r.grams.round()} g',
                      subtitle: '${r.meal} · ${DateFormat('HH:mm').format(r.ts)}',
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${r.kcal.round()} kcal', style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => guarded(context, () async {
                              await s.api.post('/food/record/delete', {'id': r.id});
                              await _load();
                            })),
                      ]),
                    ),
                ]),
              ),
            const GroupTitle('Food database'),
            if (!_loaded) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (_loaded && foods.isEmpty) const AppCard(child: Text('No foods match your search.')),
            if (foods.isNotEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  for (final f in foods)
                    InkWell(
                      onTap: () => _open(FoodDetailScreen(food: f, device: fd)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(10)), child: Text(f.icon, style: const TextStyle(fontSize: 22))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('${f.kcal.round()} kcal/100g', style: const TextStyle(color: mutedColor, fontSize: 12)),
                          const Icon(Icons.chevron_right, color: mutedColor),
                        ]),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;
  const _Macro(this.label, this.grams, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: mutedColor)),
            Text('${grams.toStringAsFixed(0)} g', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (grams / 150).clamp(0.02, 1.0), minHeight: 5, color: color, backgroundColor: color.withAlpha(36))),
          ]),
        ),
      );
}

/// "Every 100 g" detail with the three major nutrients, like the original.
class FoodDetailScreen extends StatefulWidget {
  final FoodItem food;
  final Device? device;
  const FoodDetailScreen({super.key, required this.food, this.device});
  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  bool _fav = false;
  String get _favKey => 'fav_${widget.food.id}';

  @override
  void initState() {
    super.initState();
    _fav = context.read<AppState>().prefs.getBool(_favKey) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final s = context.read<AppState>();
    final pk = f.protein * 4, ck = f.carb * 4, fk = f.fat * 9;
    final tot = math.max(1.0, pk + ck + fk);
    Widget row(String label, double g, Color c) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(children: [
            Row(children: [Text(label, style: const TextStyle(color: mutedColor)), const Spacer(), Text('${g.toStringAsFixed(2)}g', style: const TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: (g / 100).clamp(0.01, 1.0), minHeight: 4, color: c, backgroundColor: c.withAlpha(30))),
          ]),
        );
    return GScaffold(
      appBar: AppBar(title: const Text('Food details')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Every 100 g', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(children: [
              Container(width: 52, height: 52, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(12)), child: Text(f.icon, style: const TextStyle(fontSize: 28))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), Text('${f.kcal.round()}Calories / 100g', style: const TextStyle(color: brandBlue, fontWeight: FontWeight.w600))])),
              IconButton(
                icon: Icon(_fav ? Icons.star : Icons.star_border, color: _fav ? const Color(0xFFE5B83B) : mutedColor, size: 28),
                onPressed: () async {
                  setState(() => _fav = !_fav);
                  await s.prefs.setBool(_favKey, _fav);
                },
              ),
            ]),
            row('Protein', f.protein, const Color(0xFF3F6BF4)),
            row('Fat', f.fat, const Color(0xFFF08A3C)),
            row('Carbohydrate', f.carb, const Color(0xFF3DB88B)),
          ]),
        ),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Three major nutrients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _DonutPainter([pk / tot, fk / tot, ck / tot], const [Color(0xFF3F6BF4), Color(0xFFF08A3C), Color(0xFF3DB88B)]),
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${f.kcal.round()}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)), const Text('kcal', style: TextStyle(fontSize: 11, color: mutedColor))])),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(children: [
                  _Legend('Protein', pk / tot, const Color(0xFF3F6BF4)),
                  _Legend('Fat', fk / tot, const Color(0xFFF08A3C)),
                  _Legend('Carbohydrate', ck / tot, const Color(0xFF3DB88B)),
                ]),
              ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add 100 g'),
                onPressed: () => guarded(context, () => s.uploadFood({'name': f.name, 'grams': 100, 'per100': {'kcal': f.kcal, 'protein': f.protein, 'fat': f.fat, 'carb': f.carb}, 'meal': 'snack', 'memberId': s.memberId}), success: 'Added 100 g ${f.name}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(icon: const Icon(Icons.scale), label: const Text('Weigh it'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FoodScreen(device: widget.device, initialFood: f))))),
          ]),
        ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final double share;
  final Color color;
  const _Legend(this.label, this.share, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('${(share * 100).toStringAsFixed(2)}%', style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
        ]),
      );
}

class _DonutPainter extends CustomPainter {
  final List<double> parts;
  final List<Color> colors;
  _DonutPainter(this.parts, this.colors);
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(8, 8, s.width - 16, s.height - 16);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 12;
    var a = -math.pi / 2;
    for (var i = 0; i < parts.length; i++) {
      final sweep = parts[i] * math.pi * 2;
      if (sweep > 0.001) c.drawArc(r, a, math.max(0.0, sweep - 0.04), false, p..color = colors[i]);
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.parts != parts;
}
