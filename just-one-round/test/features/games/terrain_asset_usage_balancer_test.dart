import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/terrain_asset_usage_balancer.dart';

void main() {
  test('v3와 v4를 배치 개수 기준 1대 3으로 맞춘다', () {
    final balancer = TerrainAssetUsageBalancer();
    final choices = <String>[];

    for (var index = 0; index < 40; index++) {
      final family = balancer.chooseFamily(const ['v3', 'v4']);
      choices.add(family);
      balancer.record(family: family, assetName: '$family-$index');
    }

    expect(choices.where((family) => family == 'v3').length, 10);
    expect(choices.where((family) => family == 'v4').length, 30);
  });

  test('이미 많이 나온 에셋보다 적게 나온 에셋을 먼저 고른다', () {
    final balancer = TerrainAssetUsageBalancer();
    balancer.record(family: 'v4', assetName: 'common');
    balancer.record(family: 'v4', assetName: 'common');
    balancer.record(family: 'v4', assetName: 'rare');

    final chosen = balancer.chooseLeastUsedAsset(
      assetNames: const ['common', 'rare'],
      stableValue: 0,
    );

    expect(chosen, 'rare');
  });

  test('동일한 최소 출현 횟수에서는 고정값으로 변형을 분산한다', () {
    final balancer = TerrainAssetUsageBalancer();

    expect(
      balancer.chooseLeastUsedAsset(
        assetNames: const ['a', 'b', 'c'],
        stableValue: 0,
      ),
      'a',
    );
    expect(
      balancer.chooseLeastUsedAsset(
        assetNames: const ['a', 'b', 'c'],
        stableValue: 1,
      ),
      'b',
    );
  });
}
