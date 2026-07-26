import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/terrain_block_cache.dart';

void main() {
  test('완성된 3열 블록은 일부 열이 사라져도 다시 생성하지 않는다', () {
    final cache = TerrainBlockCache<String>(blockWidth: 3);
    var buildCount = 0;

    final initial = cache.freezeIfComplete(
      blockIndex: 0,
      columnIndexes: const [0, 1, 2],
      build: () {
        buildCount++;
        return 'frozen-layout';
      },
    );
    final afterFirstColumnLeaves = cache.freezeIfComplete(
      blockIndex: 0,
      columnIndexes: const [1, 2],
      build: () {
        buildCount++;
        return 'changed-layout';
      },
    );

    expect(initial, 'frozen-layout');
    expect(afterFirstColumnLeaves, 'frozen-layout');
    expect(buildCount, 1);
  });

  test('블록 전체가 화면에서 사라졌을 때만 저장된 배치를 버린다', () {
    final cache = TerrainBlockCache<String>(blockWidth: 3);
    cache.freezeIfComplete(
      blockIndex: 2,
      columnIndexes: const [6, 7, 8],
      build: () => 'layout-2',
    );

    cache.retainBlocks(const [2]);
    expect(cache[2], 'layout-2');

    cache.retainBlocks(const []);
    expect(cache[2], isNull);
  });
}
