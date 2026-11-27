import 'package:material_ui/material_ui.dart';

import '../services/food_service.dart';
import '../widgets/food_form.dart';

class AddFoodTrackerUi extends StatelessWidget {
  const AddFoodTrackerUi({super.key, required this.service});

  final FoodService service;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Food Tracker (เพิ่ม)')),
    body: FoodForm(service: service),
  );
}
