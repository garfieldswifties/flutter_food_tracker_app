import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_food_tracker_app/main.dart';
import 'package:flutter_food_tracker_app/widgets/food_form.dart';

import 'support/mock_food_service.dart';

void main() {
  Future<void> viewport(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextField).at(index);

  Future<void> date(WidgetTester tester) async {
    await tap(tester, field(3));
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
  }

  testWidgets('Splash, empty list, add, edit, delete, and navigation refresh', (
    tester,
  ) async {
    await viewport(tester, const Size(390, 844));
    final service = MockFoodService();
    await tester.pumpWidget(FoodTrackerApp(service: service));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(service.reads, 1);
    expect(find.byType(ListView), findsNothing);

    await tap(tester, find.byTooltip('เพิ่มรายการอาหาร'));
    await tap(tester, find.text('บันทึก'));
    expect(find.text('กรุณากรอกชื่ออาหาร'), findsOneWidget);
    expect(service.writes, 0);
    await tester.enterText(field(0), 'อาหารทดสอบ');
    await tester.enterText(field(1), '0');
    await tester.enterText(field(2), '2');
    await tap(tester, find.text('ว่าง'));
    await date(tester);
    await tap(tester, find.text('บันทึก'));
    expect(find.text('กิน: อาหารทดสอบ'), findsOneWidget);
    expect(service.reads, 2);

    await tap(tester, find.text('กิน: อาหารทดสอบ'));
    expect(find.text('0.00'), findsOneWidget);
    await tester.enterText(field(0), 'อาหารทดสอบแก้ไข');
    await tester.enterText(field(1), '299.50');
    await tap(tester, find.text('บันทึกแก้ไข'));
    expect(find.text('กิน: อาหารทดสอบแก้ไข'), findsOneWidget);
    expect(service.reads, 3);

    await tap(tester, find.text('กิน: อาหารทดสอบแก้ไข'));
    await tap(tester, find.text('ลบข้อมูล'));
    await tap(tester, find.widgetWithText(TextButton, 'ลบข้อมูล'));
    expect(service.reads, 4);
    expect(service.writes, 3);
    expect(service.foods, isEmpty);
  });

  testWidgets('camera and calendar cancel, reset form, and narrow layout', (
    tester,
  ) async {
    await viewport(tester, const Size(320, 568));
    final service = MockFoodService();
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodForm(
            service: service,
            pickImage: () async {
              opens++;
              return null;
            },
          ),
        ),
      ),
    );
    await tap(tester, find.byIcon(Icons.camera_alt_outlined));
    expect(opens, 1);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);

    await tester.enterText(field(0), 'ข้อมูลรอเคลียร์');
    await tester.enterText(field(1), '45.20');
    await tester.enterText(field(2), '3');
    for (final meal in ['กลางวัน', 'เย็น', 'ว่าง', 'เช้า', 'เย็น']) {
      await tap(tester, find.text(meal));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, meal))
            .selected,
        isTrue,
      );
    }
    await date(tester);
    final beforeCancel = tester.widget<TextField>(field(3)).controller!.text;
    expect(beforeCancel, matches(RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$')));
    await tap(tester, field(3));
    await tap(tester, find.widgetWithText(TextButton, 'ยกเลิก'));
    expect(tester.widget<TextField>(field(3)).controller!.text, beforeCancel);
    await tap(tester, find.text('ยกเลิก'));
    for (var i = 0; i < 4; i++) {
      expect(tester.widget<TextField>(field(i)).controller!.text, isEmpty);
    }
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'เช้า'))
          .selected,
      isTrue,
    );
    expect(service.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list error has a working retry', (tester) async {
    final service = MockFoodService()..failReads = true;
    await tester.pumpWidget(FoodTrackerApp(service: service));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('โหลดรายการอาหารไม่สำเร็จ'), findsOneWidget);
    service.failReads = false;
    await tap(tester, find.text('ลองใหม่'));
    expect(find.text('โหลดรายการอาหารไม่สำเร็จ'), findsNothing);
    expect(service.reads, 2);
  });
}
