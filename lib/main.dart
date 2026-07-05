import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SistcapBusApp());
}

class SistcapBusApp extends StatelessWidget {
  const SistcapBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SISTCAP Bus App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Warm cream & charcoal aesthetic
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1C1C1E), // Charcoal
          primary: const Color(0xFF1C1C1E),
          secondary: const Color(0xFF8E8E93),
          surface: const Color(0xFFFAF9F6), // Warm cream
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
        fontFamily: 'Inter',
      ),
      // Here is the web-like routing you asked for!
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
