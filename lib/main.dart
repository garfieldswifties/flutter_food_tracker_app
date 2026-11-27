// ส่วนเริ่มต้นโปรเจกต์และเชื่อมต่อ Supabase
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/food_service.dart';
import 'services/supabase_service.dart';
import 'views/splash_screen_ui.dart';
import 'widgets/food_visuals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final project = Uri.tryParse(url);
  if (project == null ||
      project.scheme != 'https' ||
      project.host.isEmpty ||
      project.userInfo.isNotEmpty ||
      !RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) {
    runApp(const FoodTrackerApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: project.origin,
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    runApp(
      FoodTrackerApp(
        service: SupabaseService(Supabase.instance.client, project),
      ),
    );
  } on Exception {
    runApp(const FoodTrackerApp());
  }
}

class FoodTrackerApp extends StatelessWidget {
  const FoodTrackerApp({super.key, this.service});

  final FoodService? service;

  @override
  Widget build(BuildContext context) {
    final foodService = service;
    return MaterialApp(
      title: 'Food Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Kanit',
        colorScheme: ColorScheme.fromSeed(seedColor: foodRed),
        scaffoldBackgroundColor: foodSurface,
        appBarTheme: const AppBarTheme(
          backgroundColor: foodRed,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: foodService == null
          ? const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'เชื่อมต่อ Food Tracker ไม่ได้ กรุณาตรวจการตั้งค่า',
                  ),
                ),
              ),
            )
          : SplashScreenUi(service: foodService),
    );
  }
}
