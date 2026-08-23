import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// Create a dedicated cache manager for map tiles so it doesn't bloat the user's phone
final mapTileCacheManager = CacheManager(
  Config(
    'sistcap_map_tiles',
    stalePeriod: const Duration(days: 14), // Auto-delete tiles not viewed in 14 days
    maxNrOfCacheObjects: 3000,             // Hard cap at ~3000 tiles (roughly 40-50MB maximum)
  ),
);

class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: headers,
      cacheManager: mapTileCacheManager, // Use our strictly controlled cache
    );
  }
}
