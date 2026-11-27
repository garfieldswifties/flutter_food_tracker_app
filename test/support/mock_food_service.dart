import 'package:flutter_food_tracker_app/models/food_photo.dart';
import 'package:flutter_food_tracker_app/models/food_tracker.dart';
import 'package:flutter_food_tracker_app/services/food_service.dart';

class MockFoodService implements FoodService {
  MockFoodService([Iterable<FoodTracker> initial = const []])
    : foods = [...initial];

  final List<FoodTracker> foods;
  int reads = 0;
  int writes = 0;
  bool failReads = false;

  @override
  Future<List<FoodTracker>> fetchFoods() async {
    reads++;
    if (failReads) throw StateError('offline');
    return [...foods];
  }

  @override
  Future<FoodChange> addFood(FoodInput input, FoodPhoto? photo) async {
    writes++;
    final food = FoodTracker(
      id: 'mock-$writes',
      createdAt: DateTime.utc(2026, 11, 27),
      input: input,
    );
    foods.insert(0, food);
    return FoodChange(food);
  }

  @override
  Future<FoodChange> updateFood(
    FoodTracker original,
    FoodInput input,
    FoodPhoto? photo,
  ) async {
    writes++;
    final updated = FoodTracker(
      id: original.id,
      createdAt: original.createdAt,
      input: input,
      imageUrl: original.imageUrl,
    );
    foods[foods.indexOf(original)] = updated;
    return FoodChange(updated);
  }

  @override
  Future<FoodChange> deleteFood(FoodTracker original) async {
    writes++;
    foods.remove(original);
    return FoodChange(original);
  }

  @override
  String? displayImage(String? url) => url;
}
