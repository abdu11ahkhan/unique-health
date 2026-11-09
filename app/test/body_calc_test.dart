import 'package:flutter_test/flutter_test.dart';
import 'package:unique_clone/core/body_calc.dart';

// Expected values were produced by the backend's computeMetrics (backend/server.js).
void main() {
  test('Dart body calculation matches the backend for every metric', () {
    final cases = <(double, double, double, int, int, bool, Map<String, double>)>[
    (72.5, 520, 170, 30, 1, false, {'method': 1.0, 'bmi': 25.1, 'bodyFat': 24.6, 'fatMass': 17.8, 'leanMass': 54.7, 'muscleMass': 29.1, 'muscleRate': 40.1, 'water': 54.2, 'boneMass': 2.5, 'protein': 17.9, 'visceralFat': 9.0, 'subcutaneousFat': 20.9, 'bmr': 1643.0, 'bodyAge': 33.0, 'idealWeight': 63.6, 'score': 90.0}),
    (61, 600, 163, 28, 0, false, {'method': 1.0, 'bmi': 23.0, 'bodyFat': 28.9, 'fatMass': 17.6, 'leanMass': 43.4, 'muscleMass': 20.9, 'muscleRate': 34.2, 'water': 49.8, 'boneMass': 1.7, 'protein': 18.5, 'visceralFat': 7.0, 'subcutaneousFat': 24.5, 'bmr': 1328.0, 'bodyAge': 28.0, 'idealWeight': 58.5, 'score': 98.0}),
    (95, 430, 182, 45, 1, false, {'method': 1.0, 'bmi': 28.7, 'bodyFat': 23.5, 'fatMass': 22.3, 'leanMass': 72.7, 'muscleMass': 36.6, 'muscleRate': 38.5, 'water': 55.8, 'boneMass': 3.3, 'protein': 17.3, 'visceralFat': 12.0, 'subcutaneousFat': 20.0, 'bmr': 1868.0, 'bodyAge': 48.0, 'idealWeight': 72.9, 'score': 78.0}),
    (55, 0, 160, 22, 0, false, {'method': 2.0, 'bmi': 21.5, 'bodyFat': 25.4, 'fatMass': 14.0, 'leanMass': 41.0, 'muscleMass': 21.3, 'muscleRate': 38.8, 'water': 51.9, 'boneMass': 1.6, 'protein': 19.6, 'visceralFat': 5.0, 'subcutaneousFat': 21.6, 'bmr': 1279.0, 'bodyAge': 21.0, 'idealWeight': 56.3, 'score': 99.0}),
    (80, 700, 175, 60, 1, true, {'method': 1.0, 'bmi': 26.1, 'bodyFat': 31.3, 'fatMass': 25.0, 'leanMass': 55.0, 'muscleMass': 22.2, 'muscleRate': 27.8, 'water': 44.1, 'boneMass': 2.5, 'protein': 21.5, 'visceralFat': 13.0, 'subcutaneousFat': 26.6, 'bmr': 1599.0, 'bodyAge': 66.0, 'idealWeight': 67.4, 'score': 76.0}),
    ];
    for (final c in cases) {
      final got = computeMetrics(weight: c.$1, impedance: c.$2, height: c.$3, age: c.$4, gender: c.$5, athlete: c.$6);
      for (final e in c.$7.entries) {
        expect(got[e.key], closeTo(e.value, 0.051), reason: '${e.key} for ${c.$1} kg / ${c.$2} ohm / ${c.$3} cm / age ${c.$4}');
      }
    }
  });
}
