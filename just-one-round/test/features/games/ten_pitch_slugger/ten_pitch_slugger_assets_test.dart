import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = <String, (int, int)>{
    'background_hitter_v4.png': (360, 720),
    'background_preview_v4.png': (360, 460),
    'batter_rear_idle_v3.png': (480, 720),
    'batter_rear_swing_v4.png': (960, 960),
    'batter_rear_whiff_v3.png': (960, 720),
    'batter_rear_result_v3.png': (960, 480),
    'pitcher_front_idle_v3.png': (192, 288),
    'pitcher_front_pitch_v3.png': (384, 288),
    'pitcher_front_magic_v3.png': (384, 384),
    'ball_spin_v4.png': (72, 48),
    'hit_fx_v4.png': (384, 192),
    'trail_fx_v3.png': (256, 128),
  };

  test(
    'runtime asset set is complete and has the contracted dimensions',
    () async {
      for (final entry in assets.entries) {
        final name = entry.key;
        final file = File('assets/images/ten_pitch_slugger/$name');
        expect(file.existsSync(), isTrue, reason: name);
        expect(file.lengthSync(), greaterThan(0), reason: name);
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        expect(frame.image.width, entry.value.$1, reason: name);
        expect(frame.image.height, entry.value.$2, reason: name);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );

  test(
    'contact frame contains an opaque bat tip at the authored coordinate',
    () async {
      final file = File(
        'assets/images/ten_pitch_slugger/batter_rear_swing_v4.png',
      );
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull);

      // Frame index 8 is column 0, row 2 in the 4x4 atlas.
      const pixelX = 215;
      const pixelY = 480 + 136;
      final alphaOffset = (pixelY * frame.image.width + pixelX) * 4 + 3;
      expect(bytes!.getUint8(alphaOffset), greaterThan(200));
      frame.image.dispose();
      codec.dispose();
    },
  );
}
