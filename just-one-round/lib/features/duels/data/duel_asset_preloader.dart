import 'package:flame/cache.dart';
import 'package:flame/flame.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Warms the same image cache used by the Flame game runtimes before a duel
/// can be marked READY.
///
/// Runtime implementations load images relative to `assets/images/`. A few
/// games use a directory that differs from their public id, so the mapping is
/// explicit and the asset manifest remains the source of truth for files.
class DuelAssetPreloader {
  DuelAssetPreloader({AssetBundle? bundle, Images? images})
    : bundle = bundle ?? rootBundle,
      images =
          images ?? (bundle == null ? Flame.images : Images(bundle: bundle));

  static const imageRoot = 'assets/images/';

  /// Directories are relative to [imageRoot]. `temple_run` actively renders
  /// `homebound_run`; the legacy directory is included for old room versions.
  static const Map<String, List<String>> assetDirectories = {
    'dung_dodge_v2': ['dung_dodge_v2'],
    'gravity_switch': ['gravity_switch_v2'],
    'apple_game_v2': ['apple_game_v2'],
    'number_rush': ['number_rush'],
    'mama_duck_trail': ['mama_duck_trail'],
    'sausage_dachshund': ['sausage_dachshund'],
    'midnight_snake': ['midnight_snake'],
    'beat_the_dealer': ['beat_the_dealer'],
    'ten_pitch_slugger': ['ten_pitch_slugger'],
    'ramen_timer': ['ramen_timer'],
    'bathhouse_sort': ['bathhouse_sort'],
    'lily_frog': ['lily_frog'],
    'net_boat': ['net_boat'],
    'mole_reaction': ['mole_reaction'],
    'temple_run': ['homebound_run', 'temple_run'],
    // These are excluded by the duel-options RPC today, but an old room can
    // still be reopened and must not fall back to a misleading no-op.
    'western_duel': ['western_duel'],
    'wind_darts': ['wind_darts'],
  };

  static const _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'wbmp',
  };

  final AssetBundle bundle;
  final Images images;

  /// Loads all manifest images for [gameId] into the Flame cache. The map
  /// assets used by `gravity_switch` are read too, warming their bundle I/O.
  Future<void> preload({required String gameId, int? gameVersion}) async {
    final directories = assetDirectories[gameId];
    if (directories == null || directories.isEmpty) {
      throw DuelAssetPreloadException('지원하지 않는 대결 게임이에요: $gameId');
    }

    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final imagePaths = manifest
        .listAssets()
        .where((path) => _belongsToDirectory(path, directories))
        .where(_isImage)
        .toList(growable: false);
    final activeDirectory = directories.first;
    final hasActiveAssets = imagePaths.any(
      (path) => path.startsWith('$imageRoot$activeDirectory/'),
    );
    if (imagePaths.isEmpty || !hasActiveAssets) {
      throw DuelAssetPreloadException('게임 리소스를 찾을 수 없어요: $gameId');
    }

    final imageKeys = imagePaths
        .map((path) => path.substring(imageRoot.length))
        .toList(growable: false);
    await images.loadAll(imageKeys);

    if (gameId == 'gravity_switch') {
      final mapPaths = manifest.listAssets().where(
        (path) => path.startsWith('assets/maps/'),
      );
      await Future.wait(mapPaths.map(bundle.load));
    }
  }

  static bool _belongsToDirectory(String path, List<String> directories) {
    for (final directory in directories) {
      if (path.startsWith('$imageRoot$directory/')) return true;
    }
    return false;
  }

  static bool _isImage(String path) {
    final separator = path.lastIndexOf('.');
    if (separator < 0 || separator == path.length - 1) return false;
    return _imageExtensions.contains(
      path.substring(separator + 1).toLowerCase(),
    );
  }
}

class DuelAssetPreloadException implements Exception {
  const DuelAssetPreloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

final duelAssetPreloaderProvider = Provider<DuelAssetPreloader>(
  (ref) => DuelAssetPreloader(),
);
