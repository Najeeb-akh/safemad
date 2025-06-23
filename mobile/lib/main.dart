import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/start_screen.dart';
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
    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'SafeMad - Emergency Shelter Finder',
      debugShowCheckedModeBanner: false,
      
      // Modern Material 3 Theme
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      
      // Updated routing - start with start screen instead of login
      initialRoute: '/',
      routes: {
        '/': (context) => const StartScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home_mapping': (context) => const HomeMappingScreen(),
        '/enhanced_results': (context) => const EnhancedDetectionResultsScreen(detectionResult: {}),
      },
      
      // Error handling
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: child ?? const SizedBox(),
        );
      },
    );
  }
} 