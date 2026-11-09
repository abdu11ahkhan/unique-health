import 'package:flutter_test/flutter_test.dart';
import 'package:unique_clone/core/metrics.dart';
import 'package:unique_clone/core/models.dart';

Member man({String birthday = '1995-01-01', double h = 175}) => Member(id: 1, name: 'm', gender: 1, birthday: birthday, height: h, avatar: '', isSelf: true, athlete: false);

void main() {
  test('BMI levels match the original (4 levels)', () {
    expect(rate('bmi', 17, null)!.label, 'Underweight');
    expect(rate('bmi', 22, null)!.label, 'Standard');
    expect(rate('bmi', 27, null)!.label, 'Overweight');
    expect(rate('bmi', 31, null)!.label, 'Obese');
    expect(rangeFor('bmi', null)!.labels.length, 4);
  });
  test('body fat has 5 levels and age-specific bands', () {
    final young = rangeFor('bodyFat', man())!; // male 20-39: 8 / 20 / 25
    expect(young.labels, ['Underweight', 'Standard', 'Alert', 'Overweight', 'Obese']);
    expect(young.rating(15).label, 'Standard');
    expect(young.rating(18).label, 'Alert');
    expect(young.rating(22).label, 'Overweight');
    expect(young.rating(27).label, 'Obese');
    final old = rangeFor('bodyFat', man(birthday: '1960-01-01'))!; // male 60+: 13 / 25 / 30
    expect(old.rating(20).label, 'Standard');
    expect(old.rating(23).label, 'Alert');
    expect(old.rating(27).label, 'Overweight');
  });
  test('visceral fat, water, score', () {
    expect(rate('visceralFat', 9, null)!.label, 'Standard');
    expect(rate('visceralFat', 12, null)!.watch, isTrue);
    expect(rate('water', 55, null)!.label, 'Standard');
    expect(rate('score', 95, null)!.label, 'Very good');
    expect(rate('muscleMass', 30, null), isNull);
  });
}
