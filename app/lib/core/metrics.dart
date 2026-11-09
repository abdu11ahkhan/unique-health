import 'package:flutter/material.dart';
import 'models.dart';

class MetricDef {
  final String key, label, unit, help;
  final IconData icon;
  final int decimals;
  const MetricDef(this.key, this.label, this.unit, this.icon, this.help, {this.decimals = 1});
}

const metricDefs = <MetricDef>[
  MetricDef('bmi', 'BMI', '', Icons.straighten, 'Body mass index = weight / height². 18.5 to 24.9 is considered standard.'),
  MetricDef('bodyFat', 'Body fat', '%', Icons.opacity, 'Share of your weight that is fat. Healthy ranges depend on sex and age.'),
  MetricDef('muscleRate', 'Muscle rate', '%', Icons.fitness_center, 'Skeletal muscle as a share of body weight.'),
  MetricDef('water', 'Body water', '%', Icons.water_drop, 'Total body water as a share of body weight.'),
  MetricDef('visceralFat', 'Visceral fat', '', Icons.favorite, 'Fat around the organs (an estimate). Keep it at or below 9.', decimals: 0),
  MetricDef('boneMass', 'Bone mass', 'kg', Icons.accessibility_new, 'Estimated mineral content of bone.'),
  MetricDef('protein', 'Protein', '%', Icons.egg_alt, 'Protein as a share of body weight. About 16–20% is standard.'),
  MetricDef('muscleMass', 'Muscle mass', 'kg', Icons.sports_gymnastics, 'Estimated skeletal muscle weight.'),
  MetricDef('fatMass', 'Fat mass', 'kg', Icons.scale, 'Estimated fat weight.'),
  MetricDef('leanMass', 'Lean mass', 'kg', Icons.monitor_weight, 'Fat-free mass: your weight excluding fat.'),
  MetricDef('subcutaneousFat', 'Subcutaneous fat', '%', Icons.layers, 'Fat under the skin (an estimate).'),
  MetricDef('bmr', 'BMR', 'kcal', Icons.local_fire_department, 'Calories your body burns at rest (Mifflin-St Jeor).', decimals: 0),
  MetricDef('bodyAge', 'Body age', 'yrs', Icons.cake, 'Your body composition compared with the average for your age (an estimate).', decimals: 0),
  MetricDef('idealWeight', 'Ideal weight', 'kg', Icons.flag, 'Weight that corresponds to a BMI of 22.'),
];

MetricDef? defOf(String key) {
  for (final d in metricDefs) {
    if (d.key == key) return d;
  }
  return null;
}

// Colors and level names follow the original app's BodyParam.json.
const _amber = Color(0xFFF5A623), _teal = Color(0xFF14CCAD), _red = Color(0xFFF43F31), _darkRed = Color(0xFFC23227), _deepRed = Color(0xFF8F251D), _green = Color(0xFF0F9982), _brown = Color(0xFFC2831C);

/// Result of rating a value against a [RangeSpec].
class Rating {
  final String label;
  final Color color;
  final int index, count;
  final bool watch; // a level the user should keep an eye on
  const Rating(this.label, this.color, this.index, this.count, this.watch);
  bool get isLowSide => index == 0;
}

/// Colored reference scale: [cuts] split [min,max] into cuts.length+1 levels.
class RangeSpec {
  final List<double> cuts;
  final List<String> labels;
  final List<Color> colors;
  final Set<int> watch;
  final double min, max;
  const RangeSpec(this.cuts, this.labels, this.colors, this.watch, this.min, this.max);
  int indexOf(double v) {
    var i = 0;
    while (i < cuts.length && v >= cuts[i]) {
      i++;
    }
    return i;
  }

  Rating rating(double v) {
    final i = indexOf(v);
    return Rating(labels[i], colors[i], i, labels.length, watch.contains(i));
  }
}

const _std3 = ['Slightly low', 'Standard', 'Excellent'];

/// Gallagher et al. 2000 (Am J Clin Nutr 72:694) healthy body-fat ranges by sex and age,
/// the BMI-equivalent bands many scales use: [underfat below, overweight from, obese from].
List<double> _fatBands(bool male, int age) {
  final row = age >= 60 ? 2 : age >= 40 ? 1 : 0;
  const m = [[8.0, 20.0, 25.0], [11.0, 22.0, 28.0], [13.0, 25.0, 30.0]];
  const f = [[21.0, 33.0, 39.0], [23.0, 34.0, 40.0], [24.0, 36.0, 42.0]];
  return male ? m[row] : f[row];
}

RangeSpec? rangeFor(String key, Member? m, {double? weight}) {
  final male = (m?.gender ?? 1) == 1;
  final age = m?.age ?? 30;
  final hm = ((m?.height ?? 170) / 100);
  switch (key) {
    case 'weight':
      return RangeSpec([18.5 * hm * hm, 25 * hm * hm], const ['Slightly low', 'Standard', 'Slightly high'], const [_amber, _teal, _red], const {0, 2}, 12 * hm * hm, 38 * hm * hm);
    case 'bmi':
      return const RangeSpec([18.5, 25, 30], ['Underweight', 'Standard', 'Overweight', 'Obese'], [_amber, _teal, _red, _darkRed], {0, 2, 3}, 12, 38);
    case 'bodyFat':
      final b = _fatBands(male, age);
      return RangeSpec([b[0], b[1] - 3, b[1], b[2]], const ['Underweight', 'Standard', 'Alert', 'Overweight', 'Obese'], const [_amber, _teal, _red, _darkRed, _deepRed], const {0, 2, 3, 4}, (b[0] - 8).clamp(2, 100).toDouble(), b[2] + 15);
    case 'water':
      return male ? const RangeSpec([50, 65], _std3, [_amber, _teal, _green], {0}, 35, 80) : const RangeSpec([45, 60], _std3, [_amber, _teal, _green], {0}, 30, 75);
    case 'muscleRate': // skeletal muscle % of weight (Omron adult reference ranges)
      return male ? const RangeSpec([33.3, 39.4], ['Insufficient', 'Standard', 'Excellent'], [_amber, _teal, _green], {0}, 22, 52) : const RangeSpec([24.3, 30.4], ['Insufficient', 'Standard', 'Excellent'], [_amber, _teal, _green], {0}, 16, 42);
    case 'protein':
      return const RangeSpec([16, 20], _std3, [_amber, _teal, _green], {0}, 8, 28);
    case 'boneMass':
      final w = weight ?? 70;
      final ref = male ? (w < 60 ? 2.5 : w <= 75 ? 2.9 : 3.2) : (w < 45 ? 1.8 : w <= 60 ? 2.2 : 2.5);
      return RangeSpec([ref - 0.3, ref + 0.3], const ['Insufficient', 'Standard', 'Excellent'], const [_amber, _teal, _green], const {0}, ref - 1.2, ref + 1.5);
    case 'visceralFat':
      return const RangeSpec([10, 15], ['Standard', 'High', 'Very high'], [_teal, _amber, _red], {1, 2}, 1, 25);
    case 'subcutaneousFat':
      return male ? const RangeSpec([8.6, 16.7], ['Insufficient', 'Standard', 'Slightly high'], [_amber, _teal, _red], {0, 2}, 3, 32) : const RangeSpec([18.5, 26.7], ['Insufficient', 'Standard', 'Slightly high'], [_amber, _teal, _red], {0, 2}, 8, 42);
    case 'bmr':
      final iw = 22 * hm * hm;
      final ref = 10 * iw + 6.25 * (m?.height ?? 170) - 5 * age + (male ? 5 : -161);
      return RangeSpec([ref], const ['Slightly low', 'Excellent'], const [_amber, _teal], const {0}, ref * 0.6, ref * 1.6);
    case 'score':
      return const RangeSpec([60, 75, 90], ['Not good', 'Average', 'Good', 'Very good'], [_brown, _amber, _teal, _green], {0, 1}, 40, 100);
    case 'bodyAge':
      return RangeSpec([age.toDouble()], const ['Younger physical age', 'Older physical age'], const [_teal, _red], const {}, age - 20.0, age + 20.0);
    default:
      return null;
  }
}

/// Rating of [v] for [key], or null for metrics without a reference range.
Rating? rate(String key, double v, Member? m, {double? weight}) => rangeFor(key, m, weight: weight)?.rating(v);

String adviceFor(String key, Rating? r) {
  if (r == null || !r.watch) return 'Looks good. Keep your current routine.';
  final low = r.isLowSide && key != 'visceralFat';
  switch (key) {
    case 'weight':
    case 'bmi':
      return low ? 'Consider a balanced diet with enough calories and strength training.' : 'Aim for gradual weight loss with a modest calorie deficit and regular activity.';
    case 'bodyFat':
      return low ? 'Body fat is low. Make sure you eat enough calories and healthy fats.' : 'Combine cardio, strength training and a moderate calorie deficit.';
    case 'visceralFat':
      return 'Reduce refined sugar and alcohol, and add aerobic exercise.';
    case 'water':
      return 'Drink water regularly through the day, and weigh at the same time each day.';
    case 'muscleRate':
      return 'Add resistance training and enough protein.';
    case 'protein':
      return 'Include lean protein such as fish, eggs and legumes.';
    case 'boneMass':
      return 'Get enough calcium and vitamin D, and do weight-bearing exercise.';
    case 'bmr':
      return 'Build muscle and avoid crash diets to support your resting metabolism.';
    case 'subcutaneousFat':
      return low ? 'Keep eating enough healthy fats.' : 'Regular cardio and a steady calorie balance help.';
    case 'score':
      return 'Improving sleep, activity and diet will raise your score over time.';
    default:
      return '';
  }
}

String explainFor(String label, Rating r) {
  if (!r.watch) return 'Your $label is rated "${r.label}". Keep up your current routine.';
  return 'Your $label is rated "${r.label}", which is worth watching. Small, steady changes to diet and activity usually help.';
}

String scoreLabel(num s) => s >= 90 ? 'Very good' : s >= 75 ? 'Good' : s >= 60 ? 'Average' : 'Not good';

String fmtNum(double v, int decimals) => v.toStringAsFixed(decimals);
