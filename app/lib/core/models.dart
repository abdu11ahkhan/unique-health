class AppUser {
  final int id;
  final String email;
  final String nickname;
  AppUser(this.id, this.email, this.nickname);
  factory AppUser.fromJson(Map<String, dynamic> j) =>
      AppUser((j['id'] as num).toInt(), j['email'] ?? '', j['nickname'] ?? '');
}

class Member {
  final int id;
  final String name;
  final int gender; // 1 male, 0 female
  final String birthday;
  final double height;
  final String avatar;
  final bool isSelf;
  final bool athlete;
  Member({required this.id, required this.name, required this.gender, required this.birthday, required this.height, required this.avatar, required this.isSelf, required this.athlete});
  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: (j['id'] as num).toInt(),
        name: j['name'] ?? '',
        gender: (j['gender'] as num?)?.toInt() ?? 1,
        birthday: j['birthday'] ?? '1995-01-01',
        height: (j['height'] as num?)?.toDouble() ?? 170,
        avatar: j['avatar'] ?? '🙂',
        isSelf: j['isSelf'] == true,
        athlete: j['athlete'] == true,
      );
  int get age {
    final b = DateTime.tryParse(birthday) ?? DateTime(1995);
    final n = DateTime.now();
    var a = n.year - b.year;
    if (n.isBefore(DateTime(n.year, b.month, b.day))) a--;
    return a;
  }
}

class Device {
  final int id;
  final String mac;
  final String name;
  final String customName;
  final String kind; // body | food
  final String unit;
  final bool shared;
  Device({required this.id, required this.mac, required this.name, required this.customName, required this.kind, required this.unit, required this.shared});
  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: (j['id'] as num).toInt(),
        mac: j['mac'] ?? '',
        name: j['name'] ?? '',
        customName: j['customName'] ?? j['name'] ?? '',
        kind: j['kind'] ?? 'body',
        unit: j['unit'] ?? 'kg',
        shared: j['shared'] == true,
      );
  bool get isFood => kind == 'food';
  bool get isCoffee => kind == 'coffee';
}

class BodyRecord {
  final int id;
  final int? memberId;
  final double weight;
  final double impedance;
  final Map<String, double> metrics;
  final String source;
  final DateTime ts;
  BodyRecord({required this.id, required this.memberId, required this.weight, required this.impedance, required this.metrics, required this.source, required this.ts});
  factory BodyRecord.fromJson(Map<String, dynamic> j) => BodyRecord(
        id: (j['id'] as num).toInt(),
        memberId: (j['memberId'] as num?)?.toInt(),
        weight: (j['weight'] as num).toDouble(),
        impedance: (j['impedance'] as num?)?.toDouble() ?? 0,
        metrics: {for (final e in ((j['metrics'] ?? {}) as Map).entries) e.key as String: (e.value as num).toDouble()},
        source: j['source'] ?? '',
        ts: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()),
      );
  double? m(String k) => metrics[k];
}

class FoodItem {
  final int id;
  final String name;
  final double kcal, protein, fat, carb;
  final String icon;
  FoodItem(this.id, this.name, this.kcal, this.protein, this.fat, this.carb, this.icon);
  factory FoodItem.fromJson(Map<String, dynamic> j) => FoodItem(
        (j['id'] as num).toInt(), j['name'], (j['kcal'] as num).toDouble(), (j['protein'] as num).toDouble(),
        (j['fat'] as num).toDouble(), (j['carb'] as num).toDouble(), j['icon'] ?? '🍽️');
}

class FoodRecord {
  final int id;
  final String name;
  final double grams, kcal, protein, fat, carb;
  final String meal;
  final DateTime ts;
  FoodRecord({required this.id, required this.name, required this.grams, required this.kcal, required this.protein, required this.fat, required this.carb, required this.meal, required this.ts});
  factory FoodRecord.fromJson(Map<String, dynamic> j) => FoodRecord(
        id: (j['id'] as num).toInt(), name: j['name'], grams: (j['grams'] as num).toDouble(), kcal: (j['kcal'] as num).toDouble(),
        protein: (j['protein'] as num).toDouble(), fat: (j['fat'] as num).toDouble(), carb: (j['carb'] as num).toDouble(),
        meal: j['meal'] ?? 'snack', ts: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()));
}
