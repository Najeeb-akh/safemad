import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_mapping_screen.dart';
import 'screens/enhanced_detection_results_screen.dart';

void main() {
  runApp(const SafeMadApp());
}

class SafeMadApp extends StatelessWidget {
  const SafeMadApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeMad',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home_mapping': (context) => const HomeMappingScreen(),
        '/enhanced_results': (context) => const EnhancedDetectionResultsScreen(detectionResult: {}),
        // Add more routes as needed
      },
    );
  }
} 