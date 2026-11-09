import 'package:flutter_test/flutter_test.dart';
import 'package:unique_clone/core/i18n.dart';

void main() {
  test('every language translates the same set of strings', () {
    final base = I18n.keys.toSet();
    for (final code in I18n.languages.keys.where((c) => c != 'en')) {
      final t = I18n.table(code)!;
      expect(t.keys.toSet().difference(base), isEmpty, reason: '$code has extra keys');
      expect(base.difference(t.keys.toSet()), isEmpty, reason: '$code is missing keys');
      expect(t.values.any((v) => v.trim().isEmpty), isFalse, reason: '$code has empty translations');
    }
  });

  test('falls back to English for unknown text and languages', () {
    expect(I18n.tr('Home', 'es'), 'Inicio');
    expect(I18n.tr('Home', 'en'), 'Home');
    expect(I18n.tr('Some brand new text', 'es'), 'Some brand new text');
    expect(I18n.tr('Home', 'xx'), 'Home');
  });
}
