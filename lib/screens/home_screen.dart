import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/cached_tile_provider.dart';
import '../widgets/glowing_bus_marker.dart';
import '../services/gps_tracker_service.dart';
import 'dart:convert';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _settingsChannel = MethodChannel('com.sistcap.bus/settings');
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  bool _hasLocationPermission = false;
  int _currentIndex = 0;
  late final StreamSubscription<ServiceStatus> _locationServiceStream;
  bool _isLocationPopupShowing = false;
  String _currentMapLayer = 'm'; // m = Standard, s = Satellite, y = Hybrid, p = Terrain

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  final ValueNotifier<Position?> _positionNotifier = ValueNotifier(null);

  // 🚌 ESP32 GPS Bus Tracker
  final GpsTrackerService _gpsTracker = GpsTrackerService();
  final ValueNotifier<BusGpsData?> _busLocationNotifier = ValueNotifier(null);
  StreamSubscription<BusGpsData>? _busGpsSubscription;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _loadUserData();
    _initLocationStream();
    _initBusGpsTracker();

    // Live listener: instantly detects if user turns location ON or OFF while using the app
    _locationServiceStream = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (status == ServiceStatus.disabled) {
        setState(() => _hasLocationPermission = false);
        _showLocationPopup();
      } else {
        // Location turned back on — re-check permissions automatically
        _checkLocationPermission();
      }
    });
  }

  // 🚌 Start listening to ESP32 GPS
  void _initBusGpsTracker() {
    _gpsTracker.start();
    _busGpsSubscription = _gpsTracker.locationStream.listen((data) {
      _busLocationNotifier.value = data;
    });
  }

  // 🎯 Buttery Smooth Location Tracking
  void _initLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    // Throttled settings to prevent UI lag (update only if moved 1 meter)
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1, 
    );
    
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (mounted) {
        // We use ValueNotifier instead of setState to strictly prevent the map from re-rendering and lagging
        _positionNotifier.value = position;
      }
    });
  }

  @override
  void dispose() {
    _locationServiceStream.cancel();
    _positionStream?.cancel();
    _busGpsSubscription?.cancel();
    _gpsTracker.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _hasLocationPermission = false);
      // Show popup after first frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLocationPopup());
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      setState(() => _hasLocationPermission = true);
      if (_isLocationPopupShowing) {
        _isLocationPopupShowing = false;
        if (mounted) Navigator.pop(context);
      }
      return;
    }

    // Only request if not permanently denied
    if (permission != LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      setState(() => _hasLocationPermission = true);
      if (_isLocationPopupShowing) {
        _isLocationPopupShowing = false;
        if (mounted) Navigator.pop(context);
      }
    } else {
      setState(() => _hasLocationPermission = false);
    }
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

  Future<void> _goToCurrentLocation() async {
    if (!_hasLocationPermission) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission is strictly required.')));
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Locating you...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      _mapController.move(LatLng(position.latitude, position.longitude), 16.5);
    } catch (e) {
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        _mapController.move(LatLng(lastPosition.latitude, lastPosition.longitude), 16.5);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS Signal weak. Please try again.')));
      }
    }
  }

  void _showLocationPopup() {
    if (_isLocationPopupShowing) return;
    _isLocationPopupShowing = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.15), // Very light barrier so the map colors remain vibrant behind the glass
      elevation: 0,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white, // Fast solid color
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15), 
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                    spreadRadius: 2,
                  )
                ],
              ),
              child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dynamic Island inspired indicator
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20), // Reduced
                    
                    // Floating Icon
                    Container(
                      padding: const EdgeInsets.all(12), // Reduced
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on_rounded, size: 40, color: Colors.black87), // Reduced
                    ),
                    const SizedBox(height: 16), // Reduced
                    
                    const Text(
                      'Location Required',
                      style: TextStyle(
                        fontSize: 20, // Reduced
                        fontWeight: FontWeight.w800, 
                        letterSpacing: -0.5,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8), // Reduced
                    
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        // Nested glass card look instead of a harsh black border
                        color: Colors.white.withOpacity(0.5), 
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.0),
                      ),
                      child: const Text(
                        'Enable device location for a better experience\nand to access all app features.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black87, 
                          height: 1.4, 
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24), // Reduced
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          elevation: 10,
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                        onPressed: () async {
                          try {
                            await _settingsChannel.invokeMethod('openLocationSettings');
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please turn on location manually in settings.')),
                              );
                            }
                          }
                        },
                        child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 8), // Reduced
                    
                    TextButton(
                      onPressed: () async {
                        await _checkLocationPermission();
                        if (_hasLocationPermission) {
                          _isLocationPopupShowing = false;
                          if (mounted) Navigator.pop(context);
                        } else {
                          try {
                            await _settingsChannel.invokeMethod('openAppSettings');
                          } catch (_) {}
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8), // Reduced
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'I have granted it', 
                        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ), // closes Column
               ), // closes SingleChildScrollView
              ), // closes Container
            ), // closes ClipRRect
        ); // closes Padding
      },
    ).whenComplete(() {
      _isLocationPopupShowing = false;
    });
  }

  void _showHistoryBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Testing History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _gpsTracker.historyNotifier,
                  builder: (context, history, child) {
                    if (history.isEmpty) {
                      return const Center(child: Text('No history found.'));
                    }
                    return ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final h = history[index];
                        final isLatest = index == 0;
                        return ListTile(
                          leading: Icon(Icons.circle, color: isLatest ? Colors.green : Colors.grey, size: 16),
                          title: Text(h['address'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${h['timestamp']}\n📍 ${h['lat']}, ${h['lng']}'),
                          isThreeLine: true,
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
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

    // Main App Shell (always visible, popup appears on top if location is off)
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true, // Crucial: lets the map body flow UNDER the bottom nav bar
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMapTab(), // Tab 0: Home (Map)
          const Center(child: Text('Bus Navigator Tab', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), // Tab 1
          const Center(child: Text('Notifications Tab', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), // Tab 2
          const Center(child: Text('Settings Tab', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), // Tab 3
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          // Decreased horizontal margin to make the capsule wider and bigger
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4), 
              decoration: BoxDecoration(
                color: Colors.white, // Solid color for blazing fast rendering
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.grey.shade200, width: 1.0), 
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 0, offset: const Offset(0, 10)),
                ],
              ),
              child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (index) => setState(() => _currentIndex = index),
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.transparent, 
                  selectedItemColor: Colors.black87,
                  unselectedItemColor: Colors.black45,
                  showSelectedLabels: true,
                  showUnselectedLabels: true,
                  // Slightly increased font sizes for a bolder, more substantial look
                  selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: -0.3),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: -0.3),
                  elevation: 0,
                  items: const [
                    // Removed extra gap padding to pull the text perfectly close to the icon
                    BottomNavigationBarItem(icon: Icon(CupertinoIcons.house_fill, size: 26), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.map_rounded, size: 26), label: 'Navigator'),
                    BottomNavigationBarItem(icon: Icon(CupertinoIcons.bell_fill, size: 26), label: 'Alerts'),
                    BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear_alt_fill, size: 26), label: 'Settings'),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildMapTab() {
    final String? photoUrl = _userData['Photo']?.toString();

    return Stack(
      children: [
        // 1. OpenStreetMap with Tile Caching (Free, Fast, Offline!)
        SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(12.8615, 80.0732),
                initialZoom: 16.0,
                // 🔥 PRO SENSITIVITY: Allows seamless transition between panning and pinching without lifting your finger
                interactionOptions: const InteractionOptions(
                  enableMultiFingerGestureRace: true,
                  flags: InteractiveFlag.all,
                  // Balanced sensitivity (0.3). Fast response, but avoids the zoom-lock bug
                  pinchZoomThreshold: 0.3,
                  pinchMoveThreshold: 0.3,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=$_currentMapLayer&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  tileProvider: CachedTileProvider(
                    headers: {
                      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    },
                  ),
                  maxNativeZoom: 20,
                  // 🔥 MASSIVE BUFFER: Pre-loads tiles far outside the screen edge so aggressive flings never show gray borders!
                  keepBuffer: 5,
                  tileSize: 256,
                ),
                
                // Wrap in ValueListenableBuilder so ONLY the markers rebuild, NOT the heavy Map/Tiles!
                ValueListenableBuilder<Position?>(
                  valueListenable: _positionNotifier,
                  builder: (context, pos, child) {
                    final LatLng loc = pos != null ? LatLng(pos.latitude, pos.longitude) : const LatLng(12.8615, 80.0732);
                    final double acc = pos?.accuracy ?? 0.0;
                    
                    return Stack(
                      children: [
                        // Accuracy Ring
                        if (pos != null)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: loc,
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderColor: Colors.blue.withValues(alpha: 0.5),
                                borderStrokeWidth: 1,
                                useRadiusInMeter: true,
                                radius: acc, 
                              ),
                            ],
                          ),
                        // Your Location Marker (Blue Dot)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: loc,
                              width: 24,
                              height: 24,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                ),

                // 🚌 LIVE BUS from ESP32 GPS — Separate ValueListenableBuilder for zero lag
                ValueListenableBuilder<BusGpsData?>(
                  valueListenable: _busLocationNotifier,
                  builder: (context, busData, child) {
                    if (busData == null) return const SizedBox.shrink();
                    final busLoc = LatLng(busData.lat, busData.lng);
                    return Stack(
                      children: [
                        // Bus Marker with GlowingBusMarker widget
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: busLoc,
                              width: 120,
                              height: 120,
                              child: GestureDetector(
                                onTap: () => _showHistoryBottomSheet(context),
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _gpsTracker.isStaleNotifier,
                                  builder: (context, isStale, child) {
                                    return GlowingBusMarker(isStale: isStale);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // 1.5 Layer Toggle Button (Satellite / Terrain / Standard)
        Positioned(
          right: 16,
          bottom: 120, // Above the bottom nav bar
          child: FloatingActionButton(
            heroTag: 'map_layer_btn',
            backgroundColor: Colors.white,
            mini: true,
            onPressed: () {
              setState(() {
                if (_currentMapLayer == 'm') {
                  _currentMapLayer = 's'; // Satellite
                } else if (_currentMapLayer == 's') {
                  _currentMapLayer = 'y'; // Hybrid
                } else if (_currentMapLayer == 'y') {
                  _currentMapLayer = 'p'; // Terrain
                } else {
                  _currentMapLayer = 'm'; // Back to Standard
                }
              });
            },
            child: Icon(
              _currentMapLayer == 'm' ? Icons.map :
              _currentMapLayer == 's' ? Icons.satellite :
              _currentMapLayer == 'y' ? Icons.layers :
              Icons.terrain,
              color: Colors.blueAccent,
            ),
          ),
        ),

        // 2. Safe Area Top Overlay (Dynamic Island, Profile)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 48),

                // Dynamic Island
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, spreadRadius: 2),
                    ]
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Text('BUS 42', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      const SizedBox(width: 12),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      )
                    ],
                  ),
                ),

                // Profile Avatar
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 1),
                      ]
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
              ],
            ),
          ),
        ),

        // 3. Floating Overlay: Count near Buses
        Positioned(
          left: 16,
          top: 140,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300, width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, spreadRadius: 1)
              ]
            ),
            child: const Column(
              children: [
                Text('3', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
                Text('Nearby', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
              ],
            ),
          ),
        ),

        // 4. Floating Location Button (Bottom Right, above Nav Bar)
        Positioned(
          right: 16,
          bottom: 110,
          child: FloatingActionButton(
            heroTag: 'location_fab',
            onPressed: _goToCurrentLocation,
            backgroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.my_location_rounded, color: Colors.black, size: 24),
          ),
        ),
      ],
    );
  }
}
