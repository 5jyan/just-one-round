import 'dart:io';
import 'dart:typed_data';
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
    'batter_slugger_idle_v1.png': (480, 720),
    'batter_slugger_swing_v1.png': (960, 960),
    'batter_slugger_whiff_v1.png': (960, 720),
    'batter_slugger_result_v1.png': (960, 480),
    'batter_slugger_idle_v2.png': (480, 720),
    'batter_slugger_swing_v2.png': (960, 960),
    'batter_slugger_whiff_v2.png': (960, 720),
    'batter_slugger_result_v2.png': (960, 480),
    'batter_slugger_idle_v3.png': (480, 720),
    'batter_slugger_swing_v3.png': (960, 960),
    'batter_slugger_whiff_v3.png': (960, 720),
    'batter_slugger_result_v3.png': (960, 480),
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

  test(
    'slugger sheets keep every frame contained, aligned, and populated',
    () async {
      const sluggerSheets = <String, (int, int, int)>{
        'batter_slugger_idle_v1.png': (2, 3, 6),
        'batter_slugger_swing_v1.png': (4, 4, 16),
        'batter_slugger_whiff_v1.png': (4, 3, 12),
        'batter_slugger_result_v1.png': (4, 2, 8),
        'batter_slugger_idle_v2.png': (2, 3, 6),
        'batter_slugger_swing_v2.png': (4, 4, 16),
        'batter_slugger_whiff_v2.png': (4, 3, 12),
        'batter_slugger_result_v2.png': (4, 2, 8),
        'batter_slugger_idle_v3.png': (2, 3, 6),
        'batter_slugger_swing_v3.png': (4, 4, 16),
        'batter_slugger_whiff_v3.png': (4, 3, 12),
        'batter_slugger_result_v3.png': (4, 2, 8),
      };
      const visibleBaselinePx = 226;
      const visibleBaselineTolerancePx = 2;

      for (final entry in sluggerSheets.entries) {
        final file = File('assets/images/ten_pitch_slugger/${entry.key}');
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(bytes, isNotNull, reason: entry.key);
        final pixelBytes = bytes!;
        final cellWidth = image.width ~/ entry.value.$1;
        final cellHeight =
            image.height ~/ ((entry.value.$3 / entry.value.$1).ceil());
        var magentaFringePixels = 0;
        for (var offset = 0; offset < pixelBytes.lengthInBytes; offset += 4) {
          final red = pixelBytes.getUint8(offset);
          final green = pixelBytes.getUint8(offset + 1);
          final blue = pixelBytes.getUint8(offset + 2);
          final alpha = pixelBytes.getUint8(offset + 3);
          if (alpha > 8 &&
              red > 170 &&
              blue > 130 &&
              green < 100 &&
              blue > red * 0.65) {
            magentaFringePixels++;
          }
        }
        expect(magentaFringePixels, 0, reason: '${entry.key} magenta fringe');

        final visibleBaselines = <int>[];
        for (var index = 0; index < entry.value.$3; index++) {
          final column = index % entry.value.$1;
          final row = index ~/ entry.value.$1;
          final bounds = _alphaBounds(
            pixelBytes,
            image.width,
            image.height,
            column * cellWidth,
            row * cellHeight,
            cellWidth,
            cellHeight,
          );
          expect(bounds, isNotNull, reason: '${entry.key} frame $index');
          expect(
            bounds!.left,
            greaterThan(0),
            reason: '${entry.key} frame $index',
          );
          expect(
            bounds.top,
            greaterThan(0),
            reason: '${entry.key} frame $index',
          );
          expect(
            bounds.right,
            lessThan(cellWidth),
            reason: '${entry.key} frame $index',
          );
          expect(
            bounds.bottom,
            inInclusiveRange(
              visibleBaselinePx - visibleBaselineTolerancePx,
              visibleBaselinePx + visibleBaselineTolerancePx,
            ),
            reason: '${entry.key} frame $index visible baseline',
          );
          visibleBaselines.add(bounds.bottom.toInt());
        }
        final minimumBaseline = visibleBaselines.reduce(
          (a, b) => a < b ? a : b,
        );
        final maximumBaseline = visibleBaselines.reduce(
          (a, b) => a > b ? a : b,
        );
        expect(
          maximumBaseline - minimumBaseline,
          lessThanOrEqualTo(visibleBaselineTolerancePx),
          reason: '${entry.key} grounded baseline drift',
        );

        image.dispose();
        codec.dispose();
      }
    },
  );

  test('slugger swings preserve the frame 8 contact coordinate', () async {
    for (final version in [1, 3]) {
      final file = File(
        'assets/images/ten_pitch_slugger/batter_slugger_swing_v$version.png',
      );
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull);

      const pixelX = 215;
      const pixelY = 480 + 136;
      final alphaOffset = (pixelY * frame.image.width + pixelX) * 4 + 3;
      expect(
        bytes!.getUint8(alphaOffset),
        greaterThan(200),
        reason: 'slugger swing v$version',
      );
      frame.image.dispose();
      codec.dispose();
    }
  });
}

ui.Rect? _alphaBounds(
  ByteData bytes,
  int imageWidth,
  int imageHeight,
  int originX,
  int originY,
  int cellWidth,
  int cellHeight,
) {
  var minX = cellWidth;
  var minY = cellHeight;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < cellHeight; y++) {
    for (var x = 0; x < cellWidth; x++) {
      final imageX = originX + x;
      final imageY = originY + y;
      if (imageX >= imageWidth || imageY >= imageHeight) continue;
      final offset = (imageY * imageWidth + imageX) * 4 + 3;
      if (bytes.getUint8(offset) <= 8) continue;
      minX = x < minX ? x : minX;
      minY = y < minY ? y : minY;
      maxX = x > maxX ? x : maxX;
      maxY = y > maxY ? y : maxY;
    }
  }
  if (maxX < 0) return null;
  return ui.Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    (maxX + 1).toDouble(),
    (maxY + 1).toDouble(),
  );
}
