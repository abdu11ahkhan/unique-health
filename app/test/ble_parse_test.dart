import 'package:flutter_test/flutter_test.dart';
import 'package:unique_clone/core/ble_parse.dart';

void main() {
  test('weight measurement, SI units: 72.5 kg = 14500 * 0.005', () {
    final m = parseWeightMeasurement([0x00, 0xA4, 0x38])!; // 0x38A4 = 14500
    expect(m.kg, closeTo(72.5, 1e-9));
    expect(m.userId, isNull);
  });

  test('weight measurement, imperial units: 160.00 lb = 16000 * 0.01', () {
    final m = parseWeightMeasurement([0x01, 0x80, 0x3E])!; // 0x3E80 = 16000
    expect(m.kg, closeTo(160 * 0.45359237, 1e-6));
  });

  test('weight measurement with timestamp, user id and BMI/height', () {
    final m = parseWeightMeasurement([
      0x0E, // timestamp + user + bmi/height, SI
      0xA4, 0x38,
      0xEA, 0x07, 0x0B, 0x09, 0x0A, 0x1E, 0x00, // 2026-11-09 10:30:00
      0x03, // user 3
      0x0C, 0x01, // BMI 26.8
      0xA0, 0x06, // height 1.696 m
    ])!;
    expect(m.kg, closeTo(72.5, 1e-9));
    expect(m.userId, 3);
    expect(m.timestamp, DateTime(2026, 11, 9, 10, 30));
    expect(m.bmi, closeTo(26.8, 1e-9));
    expect(m.heightM, closeTo(1.696, 1e-9));
  });

  test('unsuccessful weight (0xFFFF) and truncated packets', () {
    expect(parseWeightMeasurement([0x00, 0xFF, 0xFF])!.kg, isNull);
    expect(parseWeightMeasurement([0x00, 0x01]), isNull);
    expect(parseWeightMeasurement([0x02, 0xA4, 0x38, 0x01])!.timestamp, isNull); // timestamp flag but too short
  });

  test('body composition with impedance and weight', () {
    final m = parseBodyComposition([
      0x00, 0x06, // flags: impedance (0x200) + weight (0x400), SI
      0xE9, 0x00, // body fat 23.3 %
      0x4C, 0x14, // impedance 0x144C = 5196 -> 519.6 ohm
      0xA4, 0x38, // weight 72.5 kg
    ])!;
    expect(m.bodyFatPct, closeTo(23.3, 1e-9));
    expect(m.impedanceOhm, closeTo(519.6, 1e-9));
    expect(m.weightKg, closeTo(72.5, 1e-9));
  });

  test('body composition optional fields are read in spec order', () {
    // flags 0x007A = timestamp, user id, muscle %, muscle mass, fat free mass (bits 1,3? -> use explicit bits)
    const flags = 0x0002 | 0x0004 | 0x0010 | 0x0020 | 0x0040;
    final m = parseBodyComposition([
      flags & 0xFF, flags >> 8,
      0xE9, 0x00,
      0xEA, 0x07, 0x0B, 0x09, 0x0A, 0x1E, 0x00, // timestamp
      0x02, // user
      0x75, 0x01, // muscle % 37.3
      0x20, 0x17, // muscle mass 0x1720 = 5920 * 0.005 = 29.6
      0x2C, 0x2A, // fat-free mass 0x2A2C = 10796 * 0.005 = 53.98
    ])!;
    expect(m.userId, 2);
    expect(m.musclePct, closeTo(37.3, 1e-9));
    expect(m.muscleMassKg, closeTo(29.6, 1e-9));
    expect(m.fatFreeMassKg, closeTo(53.98, 1e-9));
  });

  test('unsuccessful body fat (0xFFFF) and short packet', () {
    expect(parseBodyComposition([0x00, 0x00, 0xFF, 0xFF])!.bodyFatPct, isNull);
    expect(parseBodyComposition([0x00, 0x00, 0x01]), isNull);
  });
}
