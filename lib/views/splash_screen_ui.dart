import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/food_service.dart';
import '../widgets/food_visuals.dart';
import 'show_all_food_tracker_ui.dart';

class SplashScreenUi extends StatefulWidget {
  const SplashScreenUi({super.key, required this.service});

  final FoodService service;

  @override
  State<SplashScreenUi> createState() => _SplashScreenUiState();
}

class _SplashScreenUiState extends State<SplashScreenUi> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ShowAllFoodTrackerUi(service: widget.service),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: foodRed,
    body: const SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              child: OverflowBox(maxHeight: 210, child: FoodLogo(size: 210)),
            ),
            SizedBox(height: 12),
            Text(
              'Food Tracker',
              style: TextStyle(
                color: foodYellow,
                fontSize: 32,
                fontWeight: FontWeight.w500,
              ),
            ),
            Image(
              image: AssetImage('assets/images/splash_foods.png'),
              width: 213,
              height: 39,
              excludeFromSemantics: true,
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: foodYellow),
          ],
        ),
      ),
    ),
  );
}
