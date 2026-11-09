import 'dart:math' as math;

/// Client-side port of the backend's computeMetrics (same published equations),
/// so results can be shown while offline and for guests. See backend/server.js
/// for references: Sun 2003, Janssen 2000, Deurenberg 1991, Watson 1980, Mifflin-St Jeor.
/// Heuristic estimates: bone mass, protein, visceral fat, subcutaneous fat, body age, score.
Map<String, double> computeMetrics({
  required double weight,
  required double impedance,
  required double height,
  required int age,
  required int gender, // 1 male, 0 female
  bool athlete = false,
}) {
  final w = weight, h = height <= 0 ? 170.0 : height, male = gender == 1, sex = male ? 1 : 0;
  final a = age <= 0 ? 30 : age;
  double clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
  double r(double v, [int d = 1]) => double.parse(v.toStringAsFixed(d));
  final bmi = w / math.pow(h / 100, 2);
  final useBia = impedance >= 150 && impedance <= 1500 && a >= 18;
  double ffm, tbw, smm;
  if (useBia) {
    final hz = (h * h) / impedance;
    ffm = male ? -10.68 + 0.65 * hz + 0.26 * w + 0.02 * impedance : -9.53 + 0.69 * hz + 0.17 * w + 0.02 * impedance;
    tbw = male ? 1.20 + 0.45 * hz + 0.18 * w : 3.75 + 0.45 * hz + 0.11 * w;
    smm = 0.401 * hz + 3.825 * sex - 0.071 * a + 5.102;
  } else {
    final bf0 = a >= 18 ? 1.20 * bmi + 0.23 * a - 10.8 * sex - 5.4 : 1.51 * bmi - 0.70 * a - 3.6 * sex + 1.4;
    ffm = w * (1 - clamp(bf0, 3, 60) / 100);
    tbw = male ? 2.447 - 0.09156 * a + 0.1074 * h + 0.3362 * w : -2.097 + 0.1069 * h + 0.2466 * w;
    smm = ffm * 0.52;
  }
  if (athlete) ffm += w * 0.03;
  ffm = clamp(ffm, w * 0.40, w * 0.97);
  tbw = clamp(tbw, ffm * 0.60, ffm * 0.80);
  smm = clamp(smm, ffm * 0.30, ffm * 0.65);
  final fatMass = w - ffm, bf = fatMass / w * 100;
  final bone = clamp(ffm * (male ? 0.045 : 0.040), 1.2, 4.5);
  final proteinKg = math.max(ffm - tbw - bone, ffm * 0.10);
  final visceral = r(clamp(bmi * 0.55 + a * 0.08 - (male ? 8 : 9) + (bf - 20) * 0.15, 1, 30), 0);
  final bodyAge = clamp((a + (bf - (male ? 18 : 28)) * 0.35 + (visceral - 7) * 0.3).roundToDouble(), 18, 80);
  return {
    'method': useBia ? 1 : 2,
    'bmi': r(bmi),
    'bodyFat': r(bf),
    'fatMass': r(fatMass),
    'leanMass': r(ffm),
    'muscleMass': r(smm),
    'muscleRate': r(smm / w * 100),
    'water': r(tbw / w * 100),
    'boneMass': r(bone),
    'protein': r(clamp(proteinKg / w * 100, 8, 25)),
    'visceralFat': visceral,
    'subcutaneousFat': r(clamp(bf * 0.85, 2, 55)),
    'bmr': (10 * w + 6.25 * h - 5 * a + (male ? 5 : -161)).roundToDouble(),
    'bodyAge': bodyAge,
    'idealWeight': r(22 * (h / 100) * (h / 100)),
    'score': clamp((100 - (bmi - 22).abs() * 2.2 - math.max(0.0, bf - (male ? 20 : 30)) * 0.8 - math.max(0.0, visceral - 9) * 1.5).roundToDouble(), 40, 100),
  };
}
