import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'text.dart';

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Runs [fn], shows errors as a toast. Returns true on success.
Future<bool> guarded(BuildContext c, Future<void> Function() fn, {String? success}) async {
  try {
    await fn();
    if (success != null && c.mounted) toast(c, success);
    return true;
  } catch (e) {
    if (c.mounted) toast(c, e.toString(), error: true);
    return false;
  }
}

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String? hint, bool obscure = false, TextInputType? type}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, obscureText: obscure, keyboardType: type, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(c, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

class Section extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets margin;
  const Section({super.key, this.title, required this.child, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              child,
            ]),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  const ScoreRing({super.key, required this.score, this.size = 96});
  @override
  Widget build(BuildContext context) {
    final color = score >= 85 ? const Color(0xFF16A34A) : score >= 70 ? const Color(0xFF3B82F6) : score >= 55 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(score / 100, color, Theme.of(context).colorScheme.surfaceContainerHighest),
        child: Center(child: Text('$score', style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: color))),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(6, 6, s.width - 12, s.height - 12);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    c.drawArc(r, 0, math.pi * 2, false, p..color = track);
    c.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Simple line chart without any chart dependency.
class TrendChart extends StatelessWidget {
  final List<double> values; // oldest -> newest
  final List<String>? labels;
  final String unit;
  final Color? color;
  final double height;
  const TrendChart({super.key, required this.values, this.labels, this.unit = '', this.color, this.height = 170});
  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height, child: Center(child: Text('Need at least 2 records for a trend', style: TextStyle(color: Theme.of(context).colorScheme.outline))));
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ChartPainter(values, labels, unit, color ?? scheme.primary, scheme.outlineVariant, scheme.onSurfaceVariant)),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> v;
  final List<String>? labels;
  final String unit;
  final Color line, grid, text;
  _ChartPainter(this.v, this.labels, this.unit, this.line, this.grid, this.text);

  @override
  void paint(Canvas c, Size s) {
    const left = 38.0, bottom = 18.0, top = 8.0;
    final w = s.width - left - 8, h = s.height - bottom - top;
    var mn = v.reduce(math.min), mx = v.reduce(math.max);
    if ((mx - mn) < 0.5) {
      mn -= 0.5;
      mx += 0.5;
    }
    final pad = (mx - mn) * 0.15;
    mn -= pad;
    mx += pad;
    final gp = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + h * i / 3;
      c.drawLine(Offset(left, y), Offset(left + w, y), gp);
      final val = mx - (mx - mn) * i / 3;
      final tp = TextPainter(text: TextSpan(text: val.toStringAsFixed(1), style: TextStyle(color: text, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(0, y - tp.height / 2));
    }
    final pts = <Offset>[];
    for (var i = 0; i < v.length; i++) {
      pts.add(Offset(left + w * i / (v.length - 1), top + h * (1 - (v[i] - mn) / (mx - mn))));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)..lineTo(pts.last.dx, top + h)..lineTo(pts.first.dx, top + h)..close();
    c.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [line.withAlpha(70), line.withAlpha(0)]).createShader(Rect.fromLTWH(left, top, w, h)));
    c.drawPath(path, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    for (final p in pts) {
      c.drawCircle(p, 3, Paint()..color = line);
    }
    final last = pts.last;
    final tp = TextPainter(text: TextSpan(text: '${v.last.toStringAsFixed(1)}$unit', style: TextStyle(color: line, fontSize: 11, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(math.min(last.dx - tp.width / 2, s.width - tp.width), math.max(0, last.dy - 18)));
    if (labels != null && labels!.length == v.length) {
      for (final i in {0, v.length - 1}) {
        final lp = TextPainter(text: TextSpan(text: labels![i], style: TextStyle(color: text, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
        lp.paint(c, Offset(i == 0 ? left : s.width - lp.width - 8, s.height - lp.height));
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.v != v || o.line != line;
}
