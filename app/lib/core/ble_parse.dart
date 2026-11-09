/// Parsers for the Bluetooth SIG Weight Scale and Body Composition profiles.
/// Weight Measurement   0x2A9D (service 0x181D)
/// Body Composition     0x2A9C (service 0x181B)
/// Fields are little-endian; 0xFFFF means "measurement unsuccessful".
library;

const lbToKg = 0.45359237;
const inToM = 0.0254;

class WeightMeasurement {
  final double? kg; // null when the scale reported an unsuccessful measurement
  final int? userId;
  final DateTime? timestamp;
  final double? bmi, heightM;
  const WeightMeasurement({this.kg, this.userId, this.timestamp, this.bmi, this.heightM});
}

class BodyCompositionMeasurement {
  final double? bodyFatPct; // null when unsuccessful
  final double? impedanceOhm, weightKg, muscleMassKg, fatFreeMassKg, bodyWaterKg, musclePct;
  final int? bmrKj, userId;
  final DateTime? timestamp;
  const BodyCompositionMeasurement({this.bodyFatPct, this.impedanceOhm, this.weightKg, this.muscleMassKg, this.fatFreeMassKg, this.bodyWaterKg, this.musclePct, this.bmrKj, this.userId, this.timestamp});
}

class _Reader {
  final List<int> b;
  int i = 0;
  _Reader(this.b);
  bool has(int n) => i + n <= b.length;
  int u8() => b[i++];
  int u16() {
    final v = b[i] | (b[i + 1] << 8);
    i += 2;
    return v;
  }

  DateTime ts() {
    final y = u16(), mo = u8(), d = u8(), h = u8(), mi = u8(), s = u8();
    return DateTime(y == 0 ? 1970 : y, mo == 0 ? 1 : mo, d == 0 ? 1 : d, h, mi, s);
  }
}

WeightMeasurement? parseWeightMeasurement(List<int> data) {
  if (data.length < 3) return null;
  final r = _Reader(data);
  final flags = r.u8();
  final imperial = flags & 0x01 != 0;
  final raw = r.u16();
  final kg = raw == 0xFFFF ? null : (imperial ? raw * 0.01 * lbToKg : raw * 0.005);
  DateTime? ts;
  int? user;
  double? bmi, height;
  if (flags & 0x02 != 0 && r.has(7)) ts = r.ts();
  if (flags & 0x04 != 0 && r.has(1)) user = r.u8();
  if (flags & 0x08 != 0 && r.has(4)) {
    bmi = r.u16() * 0.1;
    final h = r.u16();
    height = imperial ? h * 0.1 * inToM : h * 0.001;
  }
  return WeightMeasurement(kg: kg, userId: user, timestamp: ts, bmi: bmi, heightM: height);
}

BodyCompositionMeasurement? parseBodyComposition(List<int> data) {
  if (data.length < 4) return null;
  final r = _Reader(data);
  final flags = r.u16();
  final imperial = flags & 0x0001 != 0;
  double mass(int raw) => imperial ? raw * 0.01 * lbToKg : raw * 0.005;
  final fatRaw = r.u16();
  final fat = fatRaw == 0xFFFF ? null : fatRaw * 0.1;
  DateTime? ts;
  int? user, bmr;
  double? musclePct, muscleMass, ffm, water, imp, weight;
  if (flags & 0x0002 != 0 && r.has(7)) ts = r.ts();
  if (flags & 0x0004 != 0 && r.has(1)) user = r.u8();
  if (flags & 0x0008 != 0 && r.has(2)) bmr = r.u16();
  if (flags & 0x0010 != 0 && r.has(2)) musclePct = r.u16() * 0.1;
  if (flags & 0x0020 != 0 && r.has(2)) muscleMass = mass(r.u16());
  if (flags & 0x0040 != 0 && r.has(2)) ffm = mass(r.u16());
  if (flags & 0x0080 != 0 && r.has(2)) r.u16(); // soft lean mass (unused)
  if (flags & 0x0100 != 0 && r.has(2)) water = mass(r.u16());
  if (flags & 0x0200 != 0 && r.has(2)) imp = r.u16() * 0.1;
  if (flags & 0x0400 != 0 && r.has(2)) {
    final w = r.u16();
    weight = w == 0xFFFF ? null : mass(w);
  }
  return BodyCompositionMeasurement(bodyFatPct: fat, impedanceOhm: imp, weightKg: weight, muscleMassKg: muscleMass, fatFreeMassKg: ffm, bodyWaterKg: water, musclePct: musclePct, bmrKj: bmr, userId: user, timestamp: ts);
}
