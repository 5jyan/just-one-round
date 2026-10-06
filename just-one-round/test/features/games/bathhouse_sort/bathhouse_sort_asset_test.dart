import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('목욕탕 런타임 에셋의 크기와 아틀라스 계약을 고정한다', () async {
    final expected = <String, (int, int)>{
      'assets/images/bathhouse_sort/bathhouse_background.png': (180, 360),
      'assets/images/bathhouse_sort/bathhouse_doors_atlas.png': (128, 96),
      'assets/images/bathhouse_sort/bathhouse_ryokan_background.png': (
        180,
        360,
      ),
      'assets/images/bathhouse_sort/bathhouse_noren_atlas.png': (240, 160),
      'assets/images/bathhouse_sort/bathhouse_corridor_background.png': (
        180,
        360,
      ),
      'assets/images/bathhouse_sort/bathhouse_hanja_noren_atlas.png': (
        240,
        160,
      ),
      'assets/images/bathhouse_sort/bathhouse_guests_atlas.png': (448, 448),
      'assets/images/bathhouse_sort/bathhouse_feedback_fx_atlas.png': (128, 96),
    };

    for (final entry in expected.entries) {
      final data = await rootBundle.load(entry.key);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      expect((frame.image.width, frame.image.height), entry.value);
      frame.image.dispose();
    }
  });

  test('남탕 가운은 남색이고 여탕 가운은 빨간색이다', () async {
    final data = await rootBundle.load(
      'assets/images/bathhouse_sort/bathhouse_guests_atlas.png',
    );
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(bytes, isNotNull);

    var topBlue = 0;
    var topRed = 0;
    var bottomBlue = 0;
    var bottomRed = 0;
    for (var y = 0; y < frame.image.height; y++) {
      for (var x = 0; x < frame.image.width; x++) {
        final offset = (y * frame.image.width + x) * 4;
        final red = bytes!.getUint8(offset);
        final green = bytes.getUint8(offset + 1);
        final blue = bytes.getUint8(offset + 2);
        final alpha = bytes.getUint8(offset + 3);
        if (alpha < 128) continue;
        final isBlue = blue > red * 1.3 && blue > green * 1.15;
        final isRed = red > blue * 1.3 && red > green * 1.15;
        if (y < 224) {
          if (isBlue) topBlue++;
          if (isRed) topRed++;
        } else {
          if (isBlue) bottomBlue++;
          if (isRed) bottomRed++;
        }
      }
    }
    frame.image.dispose();

    expect(topBlue, greaterThan(topRed * 1.2));
    expect(bottomRed, greaterThan(bottomBlue * 1.2));
  });
}
