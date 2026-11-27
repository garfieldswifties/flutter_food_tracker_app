import 'package:material_ui/material_ui.dart';

import '../models/food_tracker.dart';
import '../services/food_service.dart';
import '../widgets/food_visuals.dart';
import 'add_food_tracker_ui.dart';
import 'update_delete_food_tracker_ui.dart';

class ShowAllFoodTrackerUi extends StatefulWidget {
  const ShowAllFoodTrackerUi({super.key, required this.service});

  final FoodService service;

  @override
  State<ShowAllFoodTrackerUi> createState() => _ShowAllFoodTrackerUiState();
}

class _ShowAllFoodTrackerUiState extends State<ShowAllFoodTrackerUi> {
  late Future<List<FoodTracker>> _foods;

  @override
  void initState() {
    super.initState();
    _foods = widget.service.fetchFoods();
  }

  void _load() {
    final foods = widget.service.fetchFoods();
    setState(() {
      _foods = foods;
    });
  }

  Future<void> _open(Widget page) async {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final notice = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _load();
    if (notice != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Widget _list(AsyncSnapshot<List<FoodTracker>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('โหลดรายการอาหารไม่สำเร็จ'),
            TextButton(onPressed: _load, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }

    final foods = snapshot.data ?? [];
    if (foods.isEmpty) return const ColoredBox(color: foodGreyCard);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 84),
      itemCount: foods.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final food = foods[index];
        final input = food.input;
        final shape = BorderRadius.circular(12);
        return Material(
          color: index.isEven ? foodMintCard : foodGreyCard,
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: () => _open(
              UpdateDeleteFoodTrackerUi(
                service: widget.service,
                original: food,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  FoodNetworkPhoto(
                    size: 51,
                    url: widget.service.displayImage(food.imageUrl),
                    fallback: const Icon(Icons.restaurant, color: foodGrey),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'กิน: ${input.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17),
                        ),
                        Text(
                          'วันที่: ${input.date} มื้อ: ${input.meal}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: foodRed, size: 29),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Food Tracker')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FoodLogo(
                    size: MediaQuery.sizeOf(context).height < 650 ? 130 : 195,
                  ),
                ),
                Expanded(
                  child: FutureBuilder(
                    future: _foods,
                    builder: (_, snap) => _list(snap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    floatingActionButton: FloatingActionButton(
      tooltip: 'เพิ่มรายการอาหาร',
      backgroundColor: foodRed,
      foregroundColor: Colors.white,
      onPressed: () => _open(AddFoodTrackerUi(service: widget.service)),
      child: const Icon(Icons.add),
    ),
  );
}
