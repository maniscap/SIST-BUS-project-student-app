import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode], // Forces it to only look for QR Codes, making it blazing fast
  );
  bool _isProcessing = false;
  String _statusMessage = 'Point camera at your College ID Card';

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;

    final String url = barcodes.first.rawValue!;
    
    // Validate that it's a Sathyabama ID card URL (but white-labeled to the user)
    if (!url.contains('idverify.sathyabama.ac.in')) {
      _scannerController.stop(); // Pause the camera so it doesn't spam errors
      _showErrorDialog('Invalid QR Code! Please scan only your College ID Card.');
      return;
    }

    setState(() {
      _isProcessing = true;
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

  Future<Map<String, String>?> _scrapeStudentData(String url) async {
    try {
      // Use a standard mobile User-Agent to prevent getting blocked
      final response = await http.get(Uri.parse(url), headers: {
        "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
      });

      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final rows = document.querySelectorAll('tr');

      Map<String, String> data = {};
      
      for (var row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length == 3) {
          final key = cells[0].text.trim();
          final value = cells[2].text.trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            data[key] = value;
          }
        }
      }

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
    setState(() => _isProcessing = false);
    _scannerController.start(); // Restart scanner
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to login
              },
              child: const Text('Continue to Login'),
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
      appBar: AppBar(
        title: const Text('Scan ID Card'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
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

          // Loading State / Status Message
          if (_isProcessing)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.blueAccent),
                          const SizedBox(height: 20),
                          Text(
                            _statusMessage,
                            style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
          // Bottom instruction text
          if (!_isProcessing)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
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
      center: Offset(size.width / 2, size.height / 2.5),
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
