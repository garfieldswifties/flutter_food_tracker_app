class FoodInput {
  const FoodInput({
    required this.name,
    required this.meal,
    required this.price,
    required this.person,
    required this.date,
  });

  static const meals = ['เช้า', 'กลางวัน', 'เย็น', 'ว่าง'];
  static const maxPerson = 2147483647;
  static final _datePattern = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  static final _personPattern = RegExp(r'^[0-9]+$');

  final String name;
  final String meal;
  final double price;
  final int person;
  final String date;

  static DateTime? parseDate(String text) {
    final match = _datePattern.firstMatch(text);
    if (match == null || match.end != text.length) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (year == 0) return null;
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }

  static String formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static double? parsePrice(String text) {
    final value = double.tryParse(text.trim());
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  static int? parsePerson(String text) {
    final input = text.trim();
    if (!_personPattern.hasMatch(input)) return null;
    final value = int.tryParse(input, radix: 10);
    return value != null && value >= 1 && value <= maxPerson ? value : null;
  }

  Map<String, Object> values() => {
    'foodDate': date,
    'foodMeal': meal,
    'foodName': name,
    'foodPrice': price,
    'foodPerson': person,
  };

  Map<String, Object?> writeValues(String? imageUrl) {
    if (name.trim().isEmpty ||
        !meals.contains(meal) ||
        !price.isFinite ||
        price < 0 ||
        person < 1 ||
        person > maxPerson ||
        parseDate(date) == null) {
      throw const FormatException('กรุณาตรวจข้อมูลอาหารก่อนบันทึก');
    }
    return {...values(), 'foodName': name.trim(), 'foodImageUrl': imageUrl};
  }
}

class FoodTracker {
  const FoodTracker({
    required this.id,
    required this.createdAt,
    required this.input,
    this.imageUrl,
  });

  final String id;
  final DateTime createdAt;
  final FoodInput input;
  // เก็บค่าดิบสำหรับเงื่อนไขเทียบรายการเดิม แม้ URL จะเป็นค่าว่าง
  final String? imageUrl;

  factory FoodTracker.fromJson(Map<String, dynamic> json) => FoodTracker(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    input: FoodInput(
      name: json['foodName'] as String,
      meal: json['foodMeal'] as String,
      price: (json['foodPrice'] as num).toDouble(),
      person: json['foodPerson'] as int,
      date: json['foodDate'] as String,
    ),
    imageUrl: json['foodImageUrl'] as String?,
  );

  Map<String, Object?> get userValues => {
    ...input.values(),
    'foodImageUrl': imageUrl,
  };
}
