import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'services/ad_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Launch UI immediately on frame 1 - zero black screen waiting
  runApp(const PdfSignVerifyApp());

  // Initialize Firebase and AdService concurrently in the background
  _initServices();
}

Future<void> _initServices() async {
  await Future.wait([
    Firebase.initializeApp().catchError((e) {
      debugPrint('Firebase initialization error: $e');
      return Firebase.app();
    }),
    AdService.initialize(),
  ]);
}

class PdfSignVerifyApp extends StatelessWidget {
  const PdfSignVerifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Sign Verify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
