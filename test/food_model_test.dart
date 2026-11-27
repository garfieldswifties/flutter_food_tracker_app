import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_food_tracker_app/models/food_photo.dart';
import 'package:flutter_food_tracker_app/models/food_tracker.dart';

import 'support/synthetic_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dates require calendar validity, padding, and a four-digit AD year',
    () {
      for (final value in ['2024-02-29', '0001-01-01', '9999-12-31']) {
        expect(FoodInput.formatDate(FoodInput.parseDate(value)!), value);
      }
      for (final value in [
        '2026-02-29',
        '2026-02-30',
        '2026-4-01',
        '2026-00-01',
        '2026-10-00',
        '0000-01-01',
        '10000-01-01',
        '2026-01-01\n',
      ]) {
        expect(FoodInput.parseDate(value), isNull, reason: value);
      }
    },
  );

  test('prices and people respect database ranges', () {
    expect(FoodInput.parsePrice('0'), 0);
    expect(FoodInput.parsePrice('299.50'), 299.5);
    for (final value in [
      '-0.01',
      'NaN',
      'Infinity',
      '-Infinity',
      '1e999',
      '',
    ]) {
      expect(FoodInput.parsePrice(value), isNull, reason: value);
    }
    expect(FoodInput.parsePerson('1'), 1);
    expect(FoodInput.parsePerson('2147483647'), FoodInput.maxPerson);
    for (final value in ['0', '-1', '2.0', '2147483648', '2e1', '']) {
      expect(FoodInput.parsePerson(value), isNull, reason: value);
    }
  });

  test('JSON keys match the schema and server fields are read-only', () {
    for (final meal in ['เช้า', 'กลางวัน', 'เย็น', 'ว่าง']) {
      final json = {
        'id': '00000000-0000-4000-8000-000000000001',
        'created_at': '2026-11-27T00:00:00Z',
        'foodDate': '2026-11-27',
        'foodMeal': meal,
        'foodName': 'ข้าวสังเคราะห์',
        'foodPrice': 0,
        'foodPerson': 1,
        'foodImageUrl': '',
      };
      final row = FoodTracker.fromJson(json);
      expect(row.id, json['id']);
      expect(row.createdAt, DateTime.utc(2026, 11, 27));
      expect(row.imageUrl, '');
      expect(row.input.writeValues(null), {
        'foodDate': '2026-11-27',
        'foodMeal': meal,
        'foodName': 'ข้าวสังเคราะห์',
        'foodPrice': 0.0,
        'foodPerson': 1,
        'foodImageUrl': null,
      });
    }
  });

  test(
    'photo validation checks size, signature, and actual decoding',
    () async {
      final bytes = await syntheticPng(0xff41b786);
      final photo = await FoodPhoto.decode(bytes);
      expect(photo.mimeType, 'image/png');
      expect(photo.extension, 'png');
      await expectLater(FoodPhoto.decode(Uint8List(5)), throwsFormatException);
      await expectLater(
        FoodPhoto.decode(Uint8List(FoodPhoto.maxBytes + 1)),
        throwsFormatException,
      );
      await expectLater(
        FoodPhoto.decode(bytes.sublist(0, 9)),
        throwsFormatException,
      );
    },
  );
}
