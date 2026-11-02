import 'package:flame/cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/duels/data/duel_asset_preloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps temple_run to its active homebound_run asset directory', () {
    expect(
      DuelAssetPreloader.assetDirectories['temple_run'],
      containsAll(<String>['homebound_run', 'temple_run']),
    );
  });

  test('preloads a runtime image into the Flame image cache', () async {
    final images = Images(bundle: rootBundle);
    final preloader = DuelAssetPreloader(images: images);

    await preloader.preload(gameId: 'temple_run', gameVersion: 1);

    expect(images.containsKey('homebound_run/alley_background.png'), isTrue);
    images.clearCache();
  });
}
