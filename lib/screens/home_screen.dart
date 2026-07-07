import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      // 1. Data exists in cache, load instantly!
      setState(() {
        _userData = jsonDecode(userDataString);
        _isLoading = false;
      });
    } else {
      // 2. Data is missing! (New device, cleared storage, etc.)
      // Auto-Sync Fallback Engine
      await _syncFromFirebase();
    }
  }
  
  Future<void> _syncFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
      return;
    }
    
    try {
      final uid = user.uid;
      // Try students first
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('students').doc(uid).get();
      if (!doc.exists) {
         doc = await FirebaseFirestore.instance.collection('staff').doc(uid).get();
      }
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Save to cache for next time
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', jsonEncode(data));
        
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      } else {
        // Edge case: No data in Firebase at all
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // Error fetching
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    }

    final String? photoUrl = _userData['Photo']?.toString();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                // Navigate to the Profile Screen!
                Navigator.of(context).pushNamed('/profile');
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.grey),
                        )
                      : const Icon(Icons.person, color: Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'Bus Routes / Map Coming Soon!',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}


