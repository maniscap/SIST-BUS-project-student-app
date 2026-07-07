import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for auto-login
import 'dart:async';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    
    // Hard cutoff at exactly 3.5 seconds to make it lightning fast
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        // Auto-Login Check!
        if (FirebaseAuth.instance.currentUser != null) {
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache the exact original image so it shares the exact same memory footprint
    // as the LoginScreen, guaranteeing it doesn't decode twice and blink!
    precacheImage(const AssetImage('assets/images/ADMIN - 2.jpg'), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateToLogin() {
    if (mounted) {
      // Instantly snaps to the pre-loaded login screen with zero delay/fade
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF001F3F), // Navy Blue to match native splash screen
      body: Center(
        child: RepaintBoundary(
          child: Lottie.asset(
            'assets/images/bus.lottie',
            controller: _controller,
            onLoaded: (composition) {
              // Speed it up heavily so the loading bar finishes exactly at the 3.5s mark
              _controller.duration = composition.duration * (1 / 1.5);
              _controller.forward(); // Start the animation
            },
            width: MediaQuery.of(context).size.width * 0.8,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
