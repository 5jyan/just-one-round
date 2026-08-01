import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('엄마 어디가 런타임 에셋의 셀과 아틀라스 규격이 고정된다', () {
    const expected = <String, (int, int)>{
      'duckling_idle.png': (72, 72),
      'duckling_life_face.png': (24, 24),
      'duckling_walk_sheet.png': (216, 144),
      'duckling_cheer_sheet.png': (216, 144),
      'mother_duck_idle.png': (72, 72),
      'mother_duck_walk_sheet.png': (216, 144),
      'mother_duck_cheer_sheet.png': (216, 144),
      'mother_duck_hug.png': (72, 72),
      'wolf_idle.png': (96, 96),
      'wolf_failure_sheet.png': (288, 192),
      'marsh_board_map.png': (180, 252),
      'footprints_atlas.png': (192, 144),
      'feather_poof_sheet.png': (64, 64),
      'marsh_background.png': (180, 420),
      'home_gameplay_hero.png': (360, 640),
      'guide_observe.png': (360, 640),
      'guide_recall.png': (360, 640),
      'guide_failure.png': (360, 640),
    };

    for (final MapEntry(key: name, value: size) in expected.entries) {
      final file = File('assets/images/mama_duck_trail/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(_pngSize(file), size, reason: name);
    }
  });

  test('새끼 오리는 모든 동작에서 50px 몸체와 같은 발 기준선을 유지한다', () async {
    for (final name in const [
      'duckling_walk_sheet.png',
      'duckling_cheer_sheet.png',
    ]) {
      final bounds = await _frameAlphaBounds(
        File('assets/images/mama_duck_trail/$name'),
        cellSize: 72,
      );
      expect(bounds, hasLength(6), reason: name);
      expect(
        bounds.map((frame) => frame.height),
        everyElement(50),
        reason: name,
      );
      expect(
        bounds.map((frame) => frame.bottom),
        everyElement(68),
        reason: name,
      );
    }

    final mother = await _frameAlphaBounds(
      File('assets/images/mama_duck_trail/mother_duck_idle.png'),
      cellSize: 72,
    );
    expect(mother.single.height, 60);
    expect(mother.single.height, greaterThan(50));
  });
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.take(8), const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: file.path);
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

Future<List<({int height, int bottom})>> _frameAlphaBounds(
  File file, {
  required int cellSize,
}) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final result = <({int height, int bottom})>[];

  for (var frameY = 0; frameY < image.height; frameY += cellSize) {
    for (var frameX = 0; frameX < image.width; frameX += cellSize) {
      var minY = cellSize;
      var maxY = -1;
      for (var localY = 0; localY < cellSize; localY++) {
        for (var localX = 0; localX < cellSize; localX++) {
          final pixelOffset =
              (((frameY + localY) * image.width + frameX + localX) * 4) + 3;
          if (bytes[pixelOffset] == 0) continue;
          minY = localY < minY ? localY : minY;
          maxY = localY > maxY ? localY : maxY;
        }
      }
      expect(maxY, greaterThanOrEqualTo(0), reason: file.path);
      result.add((height: maxY - minY + 1, bottom: maxY + 1));
    }
  }

  image.dispose();
  codec.dispose();
  return result;
}
