import 'package:material_ui/material_ui.dart';

const foodRed = Color(0xFFF44336);
const foodGreen = Color(0xFF4CAF50);
const foodGrey = Color(0xFF9E9E9E);
const foodYellow = Color(0xFFFFEB3B);
const foodSurface = Color(0xFFFEF7FF);
const foodMintCard = Color(0xFFE8F5E9);
const foodGreyCard = Color(0xFFF5F5F5);

class FoodLogo extends StatelessWidget {
  const FoodLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/food_logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class FoodNetworkPhoto extends StatelessWidget {
  const FoodNetworkPhoto({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String? url;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: url == null
        ? fallback
        : Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
  );
}
