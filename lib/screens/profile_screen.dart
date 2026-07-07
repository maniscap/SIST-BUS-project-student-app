import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:ui';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userDataString = prefs.getString('userData');
    
    if (userDataString != null && userDataString.isNotEmpty) {
      setState(() {
        _userData = jsonDecode(userDataString);
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
  }

  String _getYearOrBatch() {
    if (_userData.containsKey('Year')) return _userData['Year'].toString();
    if (_userData.containsKey('Batch')) return _userData['Batch'].toString();
    if (_userData.containsKey('Duration')) return _userData['Duration'].toString();
    if (_userData.containsKey('Course Period')) return _userData['Course Period'].toString();
    return '2023-2027'; 
  }

  Widget _buildCupertinoInfoRow(IconData icon, String title, String value, {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Icon(icon, color: Colors.blueAccent, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 56.0), // Align with text
            child: Divider(height: 1, color: Colors.grey.shade300),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F2F7), // Apple iOS System Grouped Background
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    final String name = _userData['Name']?.toString() ?? 'Student Profile';
    final String regNo = _userData['Registration Number']?.toString() ?? _userData['Employee ID']?.toString() ?? 'N/A';
    final String branch = _userData['Branch']?.toString() ?? _userData['Department']?.toString() ?? _userData['Course']?.toString() ?? 'N/A';
    final String year = _getYearOrBatch();
    final String? photoUrl = _userData['Photo']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // Apple iOS System Light Gray
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Avatar
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade300,
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 50, color: Colors.white),
                        )
                      : const Icon(Icons.person, size: 50, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Name
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            // Role / ID
            Text(
              regNo,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),

            // Dynamic Info Group: Maps every single scraped detail from Firebase in STRICT SCALING ORDER!
            Builder(
              builder: (context) {
                List<Map<String, dynamic>> allDetails = [];
                
                // Use the strict scraping order if available, otherwise fallback to standard map keys
                List<String> keys = [];
                if (_userData['orderedKeys'] != null && _userData['orderedKeys'] is List) {
                  keys = List<String>.from(_userData['orderedKeys']);
                } else {
                  keys = _userData.keys.toList();
                }

                for (var key in keys) {
                  final value = _userData[key]?.toString().trim() ?? '';
                  
                  // Exclude Photo, role, and the array itself (they are not text details for the card)
                  // Also exclude Name as it's already big and bold at the top
                  if (key == 'Photo' || key == 'role' || key == 'Name' || key == 'orderedKeys' || value.isEmpty) continue;

                  // Dynamically assign an icon based on the key name
                  IconData icon = Icons.info_outline;
                  final lowerKey = key.toLowerCase();
                  if (lowerKey.contains('branch') || lowerKey.contains('department') || lowerKey.contains('course')) icon = Icons.school_rounded;
                  else if (lowerKey.contains('year') || lowerKey.contains('batch') || lowerKey.contains('duration') || lowerKey.contains('period')) icon = Icons.date_range_rounded;
                  else if (lowerKey.contains('blood')) icon = Icons.bloodtype_rounded;
                  else if (lowerKey.contains('phone') || lowerKey.contains('mobile') || lowerKey.contains('contact')) icon = Icons.phone_rounded;
                  else if (lowerKey.contains('address') || lowerKey.contains('hostel') || lowerKey.contains('room')) icon = Icons.home_rounded;
                  else if (lowerKey.contains('dob') || lowerKey.contains('birth')) icon = Icons.cake_rounded;
                  else if (lowerKey.contains('email') || lowerKey.contains('mail')) icon = Icons.email_rounded;
                  else if (lowerKey.contains('number') || lowerKey.contains('id') || lowerKey.contains('reg')) icon = Icons.badge_rounded;

                  allDetails.add({'title': key, 'value': value, 'icon': icon});
                }

                if (allDetails.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: List.generate(allDetails.length, (index) {
                        final item = allDetails[index];
                        return _buildCupertinoInfoRow(
                          item['icon'], 
                          item['title'], 
                          item['value'], 
                          isLast: index == allDetails.length - 1
                        );
                      }),
                    ),
                  ),
                );
              }
            ),
            const SizedBox(height: 32),

            // Logout Button (iOS style Destructive button)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GestureDetector(
                onTap: _logout,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Log Out',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
