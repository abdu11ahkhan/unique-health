import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import '../core/i18n.dart';

/// Drop-in replacement for [m.Text] that translates literal UI strings through [I18n].
/// It reads the current locale from [Localizations], so even `const Text(...)` widgets
/// rebuild when the language changes. Strings without a translation are shown as written.
class Text extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  const Text(this.data, {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap});

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return m.Text(I18n.tr(data, lang), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap);
  }
}
