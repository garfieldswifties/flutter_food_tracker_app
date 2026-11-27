import '../models/food_photo.dart';
import '../models/food_tracker.dart';

abstract interface class FoodService {
  Future<List<FoodTracker>> fetchFoods();
  Future<FoodChange> addFood(FoodInput input, FoodPhoto? photo);
  Future<FoodChange> updateFood(
    FoodTracker original,
    FoodInput input,
    FoodPhoto? photo,
  );
  Future<FoodChange> deleteFood(FoodTracker original);
  String? displayImage(String? url);
}

class FoodChange {
  const FoodChange(this.food, {this.cleanupIssue});
  final FoodTracker food;
  final FoodCleanupIssue? cleanupIssue;
}

class FoodCleanupIssue {
  const FoodCleanupIssue(this.message, {this.objectPath});

  final String message;
  final String? objectPath;

  String get notice {
    final path = objectPath;
    return path == null ? message : '$message กรุณาตรวจไฟล์ $path';
  }
}

class FoodActionException implements Exception {
  const FoodActionException(this.message, {this.refresh = false});
  final String message;
  final bool refresh;
}
