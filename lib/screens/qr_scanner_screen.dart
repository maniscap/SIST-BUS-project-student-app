import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for local caching
import 'package:lottie/lottie.dart';
import 'dart:convert'; // Added for JSON encoding
import 'dart:ui';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode], // Forces it to only look for QR Codes, making it blazing fast
    detectionSpeed: DetectionSpeed.noDuplicates, // Frees up CPU so the camera can auto-focus faster
  );
  bool _isProcessing = false;
  String _statusMessage = 'Scan your College ID Card';

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;

    // Immediately lock processing to prevent spamming multiple dialogs
    setState(() => _isProcessing = true);

    final String url = barcodes.first.rawValue!;
    
    // Validate that it's a Sathyabama ID card URL (but white-labeled to the user)
    if (!url.contains('idverify.sathyabama.ac.in')) {
      _scannerController.stop(); // Pause the camera
      _showErrorDialog('Invalid QR Code!\nPlease scan only your College ID Card.');
      return;
    }

    setState(() {
      _statusMessage = 'Extracting Student Data...';
    });

    _scannerController.stop();

    await _processStudentQR(url);
  }

  Future<void> _processStudentQR(String url) async {
    try {
      // 1. Scrape the website
      final studentData = await _scrapeStudentData(url);
      if (studentData == null) {
        _showErrorDialog('Could not extract data from the ID Card.');
        return;
      }

      String role = 'student';
      String? idNumber = studentData['Registration Number'];
      
      // If there's no Registration Number, assume it's a Staff card with an Employee ID
      if (idNumber == null) {
        idNumber = studentData['Employee ID'] ?? studentData['ID Number'] ?? studentData['Staff ID'];
        role = 'staff';
      }

      final dob = studentData['Date of Birth'];
      
      if (idNumber == null || dob == null) {
        _showErrorDialog('Incomplete data found on ID card.');
        return;
      }

      // Add the role to the data so we can easily check it later in the app
      studentData['role'] = role;

      setState(() => _statusMessage = 'Checking Registration...');

      final email = '$idNumber@sistcap.com';
      final password = dob;

      // 2. Check if user already exists
      try {
        // Try logging them in first
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        // Save to cache so Home Screen loads instantly
        await _saveToSharedPreferences(studentData, role);
        
        // If successful, they already have an account!
        if (mounted) {
          _showSuccessDialog('Account already exists!\nLogged in successfully.');
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          // 3. User does not exist, let's create the account!
          setState(() => _statusMessage = 'Creating Account...');
          
          final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );

          // 4. Save scraped data to the correct Firestore collection based on role
          String collectionName = role == 'student' ? 'students' : 'staff';
          await FirebaseFirestore.instance.collection(collectionName).doc(userCredential.user!.uid).set(studentData);

          // Save to cache so Home Screen loads instantly
          await _saveToSharedPreferences(studentData, role);

          if (mounted) {
            _showSuccessDialog('Account Created Successfully!');
          }
        } else {
          _showErrorDialog('Authentication error: ${e.message}');
        }
      }
    } catch (e) {
      _showErrorDialog('An error occurred: $e');
    }
  }

  Future<void> _saveToSharedPreferences(Map<String, dynamic> data, String role) async {
    final prefs = await SharedPreferences.getInstance();
    // Dynamically save ALL fields into a single JSON string!
    await prefs.setString('userData', jsonEncode(data));
    await prefs.setString('role', role);
  }

  Future<Map<String, dynamic>?> _scrapeStudentData(String url) async {
    try {
      // Use a standard mobile User-Agent to prevent getting blocked
      final response = await http.get(Uri.parse(url), headers: {
        "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
      });

      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final rows = document.querySelectorAll('tr');

      Map<String, dynamic> data = {};
      List<String> orderedKeys = [];
      
      for (var row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length == 3) {
          final key = cells[0].text.trim();
          final value = cells[2].text.trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            data[key] = value;
            orderedKeys.add(key);
          }
        }
      }

      data['orderedKeys'] = orderedKeys; // <--- The magic array that guarantees ordering!

      // Try to extract the photo URL
      final imgTags = document.querySelectorAll('img');
      for (var img in imgTags) {
        final src = img.attributes['src'];
        if (src != null && src.contains('photos/')) {
          data['Photo'] = src;
        }
      }

      return data.isNotEmpty ? data : null;
    } catch (e) {
      return null;
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, spreadRadius: 10),
                ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 70),
                  const SizedBox(height: 20),
                  const Text(
                    'INVALID ID CARD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop(); // This safely triggers the reset logic below
                    },
                    child: const Text('TRY AGAIN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      // GUARANTEE: No matter how the dialog closes (button click or hardware Back button),
      // we ALWAYS restart the camera and unlock the screen.
      if (mounted) {
        _scannerController.start();
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Scan your College ID Card';
        });
      }
    });
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent, // Let the background show!
        body: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/ADMIN - 2.jpg',
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            // Blur over the image to make the card pop
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),
            // Center Single Glass Card
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40), // Apple pill-style rounding
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Low blur, highly transparent acrylic feel
                      child: Container(
                        padding: const EdgeInsets.all(32),
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
                              blurRadius: 15,
                              offset: const Offset(0, 10),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Custom Animated Tick
                            const _AnimatedSuccessTick(),
                            const SizedBox(height: 32),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white, // White text for dark image
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '"Travel smarter with SISTCAP"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Premium Apple Liquid Glass Continue Button
                            GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop(); // Close dialog
                                // Boom! Take them straight to the Home Screen!
                                Navigator.of(context).pushReplacementNamed('/home'); 
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                                  child: Container(
                                    height: 56,
                                    width: double.infinity,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      // Volumetric Button Gradient
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.8), // Very bright edge
                                          Colors.white.withOpacity(0.05), // Slightly tinted center
                                          Colors.white.withOpacity(0.05),
                                          Colors.white.withOpacity(0.5),
                                        ],
                                        stops: const [0.0, 0.2, 0.8, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white.withOpacity(0.8), width: 2.0), // Sharp bright rim
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.15), 
                                          blurRadius: 10, 
                                          offset: const Offset(0, 5),
                                          spreadRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'CONTINUE', 
                                      style: TextStyle(
                                        color: Colors.white, 
                                        fontSize: 16, 
                                        fontWeight: FontWeight.w900, 
                                        letterSpacing: 2.0
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // The Camera Scanner
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          
          // Scanner Overlay overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(),
            ),
          ),

          // Floating Glass Back Button (since we removed the AppBar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),

          // Loading State / Status Message
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.white, // Fully solid white background per your exact request!
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Custom Lottie Bus Animation
                      RepaintBoundary(
                        child: SizedBox(
                          height: 150,
                          width: 150,
                          child: Lottie.asset(
                            'assets/images/bus.lottie',
                            fit: BoxFit.contain,
                            repeat: true, // Loop indefinitely while processing
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Colors.black87, // Deep dark text for contrast on solid white
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
          // Floating Apple Liquid Glass Instruction Badge
          if (!_isProcessing)
            Positioned(
              bottom: 80,
              left: 30,
              right: 30,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Optimized for 60fps
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), // Smaller padding
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15), // Apple frosted white
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min, // Hug the content tightly
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_scanner, color: Colors.white, size: 18), // Slightly smaller icon
                        const SizedBox(width: 8), // Tighter spacing
                        Text( // Removed Flexible to prevent aggressive wrapping
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13, // Slightly smaller font to guarantee single line
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}

// Draws the standard [   ] focus box for the QR Scanner
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final scanAreaSize = size.width * 0.7;
    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2), // Perfectly centered vertically
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw dark overlay covering everything EXCEPT the scan area
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final scanAreaPath = Path()..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(12)));
    
    final finalPath = Path.combine(PathOperation.difference, backgroundPath, scanAreaPath);
    canvas.drawPath(finalPath, paint);

    // Draw the 4 corner brackets
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final length = scanAreaSize * 0.15;
    
    // Top Left
    canvas.drawLine(scanArea.topLeft, scanArea.topLeft + Offset(length, 0), borderPaint);
    canvas.drawLine(scanArea.topLeft, scanArea.topLeft + Offset(0, length), borderPaint);
    
    // Top Right
    canvas.drawLine(scanArea.topRight, scanArea.topRight + Offset(-length, 0), borderPaint);
    canvas.drawLine(scanArea.topRight, scanArea.topRight + Offset(0, length), borderPaint);
    
    // Bottom Left
    canvas.drawLine(scanArea.bottomLeft, scanArea.bottomLeft + Offset(length, 0), borderPaint);
    canvas.drawLine(scanArea.bottomLeft, scanArea.bottomLeft + Offset(0, -length), borderPaint);
    
    // Bottom Right
    canvas.drawLine(scanArea.bottomRight, scanArea.bottomRight + Offset(-length, 0), borderPaint);
    canvas.drawLine(scanArea.bottomRight, scanArea.bottomRight + Offset(0, -length), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// Custom Animated Green Tick for the Success Screen
class _AnimatedSuccessTick extends StatefulWidget {
  const _AnimatedSuccessTick();

  @override
  State<_AnimatedSuccessTick> createState() => _AnimatedSuccessTickState();
}

class _AnimatedSuccessTickState extends State<_AnimatedSuccessTick> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 800),
    );
    // Elastic out gives it that premium Apple-style "pop and bounce" effect
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle_rounded, 
          color: Colors.green, 
          size: 80, // Perfectly balanced size
        ),
      ),
    );
  }
}

