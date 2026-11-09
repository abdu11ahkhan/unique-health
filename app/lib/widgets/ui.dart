import 'package:flutter/material.dart' hide Text;
import 'text.dart';
import '../core/metrics.dart';

const brandBlue = Color(0xFF3F6BF4);

IconData deviceKindIcon(String kind) => kind == 'food' ? Icons.restaurant : kind == 'coffee' ? Icons.coffee : Icons.monitor_weight;
const inkColor = Color(0xFF1E2340);
const mutedColor = Color(0xFF8A90A6);

/// Scaffold with the soft lavender-to-white header gradient used by every page.
class GScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body, floatingActionButton, bottomNavigationBar;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  const GScaffold({super.key, this.appBar, this.body, this.floatingActionButton, this.bottomNavigationBar, this.floatingActionButtonLocation});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.3, 0.7],
          colors: dark ? const [Color(0xFF2B2F63), Color(0xFF171A2E), Color(0xFF12141F)] : const [Color(0xFFC3C6FA), Color(0xFFEDEEFD), Color(0xFFF6F7FB)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}

/// White rounded card used for list groups.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12), this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: margin,
      child: Material(
        color: dark ? const Color(0xFF1D2136) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF5B7CFA), Color(0xFF3F4FD8)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Text('UH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
      );
}

/// Row inside an [AppCard]: icon, title, optional trailing, chevron.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const MenuRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Icon(icon, size: 22, color: brandBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: mutedColor)),
              ]),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null) const Icon(Icons.chevron_right, color: mutedColor),
          ]),
        ),
      );
}

class GroupTitle extends StatelessWidget {
  final String text;
  const GroupTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)));
}

/// Colored reference scale with a marker at [value], like the original
/// app's "Slightly low / Standard / Slightly high" bar.
class RangeBar extends StatelessWidget {
  final RangeSpec spec;
  final double value;
  final String Function(double) fmt;
  const RangeBar({super.key, required this.spec, required this.value, required this.fmt});
  @override
  Widget build(BuildContext context) {
    final total = spec.max - spec.min;
    final edges = [spec.min, ...spec.cuts, spec.max];
    double pos(double v) => ((v - spec.min) / total).clamp(0.0, 1.0);
    int flexOf(int i) => (((edges[i + 1] - edges[i]) / total) * 1000).round().clamp(1, 1000);
    final cur = spec.indexOf(value);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return Column(children: [
        SizedBox(
          height: 18,
          child: Stack(clipBehavior: Clip.none, children: [
            for (final cut in spec.cuts)
              Positioned(
                left: (pos(cut) * w - 20).clamp(0.0, w - 40),
                width: 40,
                child: Text(fmt(cut), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: mutedColor)),
              ),
          ]),
        ),
        SizedBox(
          height: 22,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
            Row(children: [
              for (var i = 0; i < spec.labels.length; i++)
                Expanded(
                  flex: flexOf(i),
                  child: Container(height: 8, margin: EdgeInsets.only(right: i == spec.labels.length - 1 ? 0 : 2), decoration: BoxDecoration(color: spec.colors[i], borderRadius: BorderRadius.circular(4))),
                ),
            ]),
            Positioned(
              left: pos(value) * w - 9,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: brandBlue, width: 3), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < spec.labels.length; i++)
            Expanded(
              flex: flexOf(i),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: spec.colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(child: Text(spec.labels[i], overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: i == cur ? FontWeight.w800 : FontWeight.w400))),
              ]),
            ),
        ]),
      ]);
    });
  }
}

/// Small status chip: "Standard", "Slightly high"...
class StatusChip extends StatelessWidget {
  final Rating? rating;
  const StatusChip(this.rating, {super.key});
  @override
  Widget build(BuildContext context) => rating == null
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: rating!.color.withAlpha(38), borderRadius: BorderRadius.circular(99)),
          child: Text(rating!.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: rating!.color)),
        );
}
