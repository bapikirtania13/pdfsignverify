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

class PdfSignVerifyApp extends StatefulWidget {
  const PdfSignVerifyApp({super.key});

  @override
  State<PdfSignVerifyApp> createState() => _PdfSignVerifyAppState();
}

class _PdfSignVerifyAppState extends State<PdfSignVerifyApp> {
  @override
  void initState() {
    super.initState();
    // Only show App Open Ad once on initial app open
    _showAppOpenOnLaunch();
  }

  Future<void> _showAppOpenOnLaunch() async {
    await AdService.waitForInit;
    // Brief delay to allow initial Flutter frame and UI to render
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      AdService.showAppOpenAdIfAvailable();
    }
  }

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
