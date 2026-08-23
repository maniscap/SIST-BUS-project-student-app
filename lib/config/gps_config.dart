/// ╔══════════════════════════════════════════════════════════════════════╗
/// ║  🔧 GPS TRACKER CONFIG — PASTE YOUR FRIEND'S DETAILS HERE         ║
/// ║                                                                    ║
/// ║  Your friend will give you 2 things:                               ║
/// ║    1. Firebase Database URL (the "project link")                   ║
/// ║    2. Database Secret Key (the "secret key")                       ║
/// ║                                                                    ║
/// ║  Paste the SAME values here as in the Admin PWA config!            ║
/// ╚══════════════════════════════════════════════════════════════════════╝

class GpsConfig {
  // ⬇️ PASTE YOUR FRIEND'S FIREBASE DATABASE URL HERE ⬇️
  // Example: "https://my-gps-tracker-default-rtdb.firebaseio.com"
  static const String firebaseUrl = "https://elderly-fall-detection-a0f34-default-rtdb.firebaseio.com";

  // ⬇️ PASTE YOUR FRIEND'S SECRET KEY HERE (LEAVE EMPTY IF NO AUTH) ⬇️
  static const String secretKey = "";

  // ⬇️ DATA PATH — Same as in Admin PWA config ⬇️
  // Common paths: "/gps", "/location", "/bus", "/tracker"
  static const String dataPath = "/telemetry/live";

  // How often to fetch GPS data (in seconds)
  static const int pollInterval = 2;

  // Check if config is ready (credentials have been pasted)
  static bool get isConfigured =>
      firebaseUrl != "PASTE_DATABASE_URL_HERE";
}
