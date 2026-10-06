import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = <String, (int, int)>{
    'sea_background.png': (360, 960),
    'boat_navigation_atlas.png': (384, 256),
    'boat_result_atlas.png': (256, 128),
    'sardine_atlas.png': (168, 168),
    'piranha_atlas.png': (336, 84),
    'marlin_atlas.png': (672, 114),
    'shark_fin_atlas.png': (296, 38),
    'shark_wake_atlas.png': (288, 36),
    'whale_atlas.png': (640, 106),
    'reef_modules_atlas.png': (192, 96),
    'net_capture_fx_atlas.png': (256, 128),
  };

  test('승인된 런타임 에셋 11종이 정확한 크기로 존재한다', () async {
    for (final entry in assets.entries) {
      final file = File('assets/images/net_boat/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(file.lengthSync(), greaterThan(0), reason: entry.key);
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, entry.value.$1, reason: entry.key);
      expect(frame.image.height, entry.value.$2, reason: entry.key);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('투명 아틀라스의 셀 모서리는 비어 있어 이웃 프레임을 침범하지 않는다', () async {
    for (final name in assets.keys.where(
      (name) => name != 'sea_background.png',
    )) {
      final file = File('assets/images/net_boat/$name');
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull, reason: name);
      for (final point in <(int, int)>[
        (0, 0),
        (frame.image.width - 1, 0),
        (0, frame.image.height - 1),
        (frame.image.width - 1, frame.image.height - 1),
      ]) {
        final alpha = bytes!.getUint8(
          (point.$2 * frame.image.width + point.$1) * 4 + 3,
        );
        expect(alpha, 0, reason: '$name ${point.$1},${point.$2}');
      }
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('고밀도 물고기는 부드러운 색상과 반투명 경계를 보존한다', () async {
    for (final name in <String>[
      'sardine_atlas.png',
      'piranha_atlas.png',
      'marlin_atlas.png',
    ]) {
      final file = File('assets/images/net_boat/$name');
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull, reason: name);
      final colors = <int>{};
      var fractionalAlphaPixels = 0;
      for (var offset = 0; offset < bytes!.lengthInBytes; offset += 4) {
        final alpha = bytes.getUint8(offset + 3);
        if (alpha > 0 && alpha < 255) fractionalAlphaPixels += 1;
        if (alpha == 255) colors.add(bytes.getUint32(offset));
      }
      expect(colors.length, greaterThan(100), reason: name);
      expect(fractionalAlphaPixels, greaterThan(0), reason: name);
      frame.image.dispose();
      codec.dispose();
    }
  });
}
