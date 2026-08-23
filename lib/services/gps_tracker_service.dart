import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:math' show cos, sqrt, asin;
import '../config/gps_config.dart';

/// Live bus location data from the ESP32 GPS tracker
class BusGpsData {
  final double lat;
  final double lng;
  final double speed;
  final double altitude;
  final int satellites;
  final DateTime timestamp;

  BusGpsData({
    required this.lat,
    required this.lng,
    this.speed = 0,
    this.altitude = 0,
    this.satellites = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'BusGpsData(lat: $lat, lng: $lng, speed: $speed)';
}

/// Service that connects to the friend's ESP32 Firebase RTDB
/// and streams live GPS coordinates.
///
/// Usage:
///   final gps = GpsTrackerService();
///   gps.locationStream.listen((data) {
///     print('Bus at: ${data.lat}, ${data.lng}');
///   });
///   gps.start();
class GpsTrackerService {
  final _controller = StreamController<BusGpsData>.broadcast();
  final ValueNotifier<List<Map<String, dynamic>>> historyNotifier = ValueNotifier([]);
  final ValueNotifier<bool> isStaleNotifier = ValueNotifier(true);
  DateTime? _lastEspTimestamp;
  DateTime _lastReceivedNewData = DateTime.now();
  
  Timer? _timer;
  bool _isConnected = false;
  String? _lastError;

  /// Stream of live GPS data
  Stream<BusGpsData> get locationStream => _controller.stream;

  /// Whether we're receiving data
  bool get isConnected => _isConnected;
  String? get lastError => _lastError;

  /// Start polling the ESP32's Firebase for GPS data
  void start() {
    if (!GpsConfig.isConfigured) {
      _lastError = 'GPS config not set. Update lib/config/gps_config.dart';
      debugPrint('⚠️ GPS Tracker: $_lastError');
      return;
    }

    debugPrint('🚀 GPS Tracker: Starting (polling every ${GpsConfig.pollInterval}s)');
    _fetchGps(); // Fetch immediately
    _timer = Timer.periodic(
      Duration(seconds: GpsConfig.pollInterval),
      (_) => _fetchGps(),
    );
  }

  /// Stop polling
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispose resources
  void dispose() {
    stop();
    _controller.close();
  }

  /// Fetch GPS data from friend's Firebase RTDB via REST API
  Future<void> _fetchGps() async {
    try {
      final authParam = GpsConfig.secretKey.isNotEmpty ? '?auth=${GpsConfig.secretKey}' : '';
      final url = '${GpsConfig.firebaseUrl}${GpsConfig.dataPath}.json$authParam';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final data = jsonDecode(response.body);
      if (data != null) {
        final location = _normalizeGpsData(data);
        if (location != null) {
          _isConnected = true;
          _lastError = null;

          if (_lastEspTimestamp == null || location.timestamp != _lastEspTimestamp) {
            _lastEspTimestamp = location.timestamp;
            _lastReceivedNewData = DateTime.now();
          }
          
          final age = DateTime.now().difference(_lastReceivedNewData).inSeconds;
          isStaleNotifier.value = age > 20;

          _controller.add(location);
          _updateHistory(location);
        }
      }
    } catch (e) {
      _isConnected = false;
      _lastError = e.toString();
      debugPrint('❌ GPS Tracker error: $e');
    }
  }

  /// Normalizes various ESP32 data formats into BusGpsData
  BusGpsData? _normalizeGpsData(dynamic data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);

    // Direct format: { lat, lng/lon/longitude }
    if (map.containsKey('lat') || map.containsKey('latitude')) {
      double lat = _toDouble(map['lat'] ?? map['latitude']);
      double lng = _toDouble(map['lng'] ?? map['lon'] ?? map['longitude']);

      // 🔥 Intercept the ESP32's hardcoded Bangalore fallback and replace it with Sathyabama University
      if ((lat - 12.9716).abs() < 0.001 && (lng - 77.5946).abs() < 0.001) {
        lat = 12.8731; // Sathyabama University
        lng = 80.2219;
      }

      return BusGpsData(
        lat: lat,
        lng: lng,
        speed: _toDouble(map['speed'] ?? map['spd'] ?? 0),
        altitude: _toDouble(map['altitude'] ?? map['alt'] ?? 0),
        satellites: _toInt(map['satellites'] ?? map['sats'] ?? map['sat'] ?? 0),
      );
    }

    // Nested format: { location: { lat, lng } } or { gps: { lat, lng } }
    final nested = map['location'] ?? map['gps'] ?? map['position'] ?? map['coords'];
    if (nested is Map) {
      return _normalizeGpsData(nested);
    }

    // Push ID format: get the last entry
    if (map.isNotEmpty) {
      final lastKey = map.keys.last;
      if (map[lastKey] is Map) {
        return _normalizeGpsData(map[lastKey]);
      }
    }

    return null;
  }

  double _toDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
  int _toInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * 1000 * asin(sqrt(a));
  }

  Future<void> _updateHistory(BusGpsData location) async {
    final currentHistory = historyNotifier.value;
    final lastPoint = currentHistory.isNotEmpty ? currentHistory.first : null;

    if (lastPoint == null || _getDistance(lastPoint['lat'], lastPoint['lng'], location.lat, location.lng) > 50) {
      final newEntry = {
        'id': location.timestamp.millisecondsSinceEpoch.toString(),
        'lat': location.lat,
        'lng': location.lng,
        'timestamp': location.timestamp,
        'address': 'Fetching location name...',
      };

      final updated = [newEntry, ...currentHistory];
      if (updated.length > 50) updated.removeLast();
      historyNotifier.value = List.from(updated);

      try {
        final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${location.lat}&lon=${location.lng}'));
        if (res.statusCode == 200) {
          final geoData = jsonDecode(res.body);
          if (geoData['display_name'] != null) {
            newEntry['address'] = geoData['display_name'];
            historyNotifier.value = List.from(updated); // trigger rebuild
          }
        }
      } catch (e) {
        debugPrint("Geocoding failed: $e");
      }
    }
  }
}
