import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for local caching
import 'dart:convert'; // Added for JSON encoding
import 'dart:ui';
import 'qr_scanner_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _regNoController = TextEditingController();
  final _dobController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OKAY', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    final regNo = _regNoController.text.trim();
    final dob = _dobController.text.trim();

    if (regNo.isEmpty || dob.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Register Number and DOB')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Firebase Auth expects an email. We synthesize one using the register number.
      final email = '$regNo@sistcap.com';
      final password = dob; // e.g. 25-07-2005

      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Fetch user data from Firestore
      final uid = userCredential.user!.uid;
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('students').doc(uid).get();
      
      // Fallback check if it's a staff member instead of a student
      if (!userDoc.exists) {
        userDoc = await FirebaseFirestore.instance.collection('staff').doc(uid).get();
      }

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        
        // Cache the entire JSON map locally so the Home Screen loads instantly with all fields!
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', jsonEncode(data));
        await prefs.setString('role', data['role']?.toString() ?? 'student');
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Login Successful!', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
              ),
            ],
          ),
          backgroundColor: Colors.greenAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          margin: const EdgeInsets.all(24),
          elevation: 20,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // BOOM! Take them to the new Home Screen!
      Navigator.of(context).pushReplacementNamed('/home');

    } on FirebaseAuthException catch (e) {
      String title = 'Login Failed';
      String message = e.message ?? 'An unknown error occurred.';
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        title = 'Account Not Found';
        message = 'Invalid Register Number or DOB.\n\nFirst time user? Please scan your ID card to create an account.';
      }
      _showErrorDialog(title, message);
    } catch (e) {
      _showErrorDialog('Error', e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _regNoController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Fallback if image fails
      body: Stack(
        children: [
          // 1. Cinematic Background Image (Provided by User)
          Positioned.fill(
            child: Image.asset(
              'assets/images/ADMIN - 2.jpg',
              fit: BoxFit.cover,
              gaplessPlayback: true, // Prevents blinking when routes rebuild!
            ),
          ),
          // 2. Vibrant Background Overlay with very slight blur
          // Apple Glass requires a razor sharp, vibrant background behind it to create the 3D depth effect!
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0), // Decreased blur so the image is incredibly sharp!
              child: Container(
                color: Colors.black.withOpacity(0.15), // Very slight tint just for contrast
              ),
            ),
          ),
          
          // 3. Liquid Glass Login Form
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Low blur, highly transparent acrylic feel
                    child: Container(
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        // True "Liquid Glass" Volumetric Bevel Gradient!
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.7), // Intense top-left specular glare
                            Colors.white.withOpacity(0.0), // Completely clear center
                            Colors.white.withOpacity(0.0), // Completely clear center
                            Colors.white.withOpacity(0.4), // Intense bottom-right refractive glare
                          ],
                          stops: const [0.0, 0.15, 0.85, 1.0], // Pushed strictly to the edges to simulate 3D thickness!
                        ),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.6), // Bright sharp outer rim
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15), // Elegant drop shadow
                            blurRadius: 40,
                            offset: const Offset(0, 10),
                            spreadRadius: 0,
                          ),
                        ],
                      ),child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          
                          // Custom User Logo (Flawlessly transparent PNG!)
                          Image.asset(
                            'assets/images/OIP-removebg-preview.png',
                            height: 80, // Much smaller, cleaner, Apple-style balance
                            fit: BoxFit.contain,
                            color: Colors.white, // Magically turns the dark blue logo into pure white!
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'SIST CAP', 
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Login Form (Glassmorphism TextFields)
                          TextField(
                            controller: _regNoController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Register Number',
                              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                              prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white70),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _dobController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Date of Birth (Password)',
                              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                              hintText: 'DD-MM-YYYY',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                              prefixIcon: const Icon(Icons.calendar_month_outlined, color: Colors.white70),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Login Button
                          SizedBox(
                            height: 50, // Slightly reduced height to make it less bulky
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading 
                                ? const CircularProgressIndicator(color: Colors.black)
                                : const Text('LOGIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          
                          Row(
                            children: [
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text('OR', style: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.bold)),
                              ),
                              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                            ],
                          ),
                          
                          const SizedBox(height: 32),

                          // Scan ID Card Button (Glass Outline)
                          SizedBox(
                            height: 50, // Matched height with Login button
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                                );
                              },
                              icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.white),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'SCAN ID TO REGISTER OR LOGIN', // Removed "CARD" so it fits nicely
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                                backgroundColor: Colors.white.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
