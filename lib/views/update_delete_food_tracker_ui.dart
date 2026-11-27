import 'package:material_ui/material_ui.dart';

import '../models/food_tracker.dart';
import '../services/food_service.dart';
import '../widgets/food_form.dart';

class UpdateDeleteFoodTrackerUi extends StatelessWidget {
  const UpdateDeleteFoodTrackerUi({
    super.key,
    required this.service,
    required this.original,
  });

  final FoodService service;
  final FoodTracker original;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Food Tracker (แก้ไข/ลบ)')),
    body: FoodForm(service: service, original: original),
  );
}
