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

  Widget _buildCupertinoInfoRow(IconData icon, String title, String value, {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.blueAccent, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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
            padding: const EdgeInsets.only(left: 64.0),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F2F7),
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    final String name = _userData['Name']?.toString() ?? 'Student Profile';
    final String regNo = _userData['Registration Number']?.toString() ?? _userData['Employee ID']?.toString() ?? 'N/A';
    final String? photoUrl = _userData['Photo']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // Light, clean iOS background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Premium Avatar Design
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15), width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.0), // Creates a thin white ring inside the border
                    child: ClipOval(
                      child: photoUrl != null && photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, size: 60, color: Colors.grey),
                            )
                          : const Icon(Icons.person_rounded, size: 60, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Name
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              // Role / ID pill badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  regNo,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Dynamic Info Group: Simple Fast Container (Light Mode)
              Builder(
                builder: (context) {
                  List<Map<String, dynamic>> allDetails = [];
                  
                  List<String> keys = [];
                  if (_userData['orderedKeys'] != null && _userData['orderedKeys'] is List) {
                    keys = List<String>.from(_userData['orderedKeys']);
                  } else {
                    keys = _userData.keys.toList();
                  }

                  for (var key in keys) {
                    final value = _userData[key]?.toString().trim() ?? '';
                    
                    if (key == 'Photo' || key == 'role' || key == 'Name' || key == 'orderedKeys' || value.isEmpty) continue;

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
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white, // Crisp white card
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Theme(
                        // Remove the ugly top/bottom borders of ExpansionTile
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: false, // Closed by default as requested!
                          collapsedIconColor: Colors.black54,
                          iconColor: Colors.blueAccent,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.assignment_ind_rounded, color: Colors.blueAccent, size: 22),
                          ),
                          title: const Text(
                            'Academic Details',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16),
                          ),
                          subtitle: const Text(
                            'Tap to expand',
                            style: TextStyle(color: Colors.black45, fontSize: 13),
                          ),
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
                    ),
                  );
                }
              ),
              const SizedBox(height: 32),

              // Logout Button (Light Mode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: GestureDetector(
                  onTap: _logout,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
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
      ),
    );
  }
}
