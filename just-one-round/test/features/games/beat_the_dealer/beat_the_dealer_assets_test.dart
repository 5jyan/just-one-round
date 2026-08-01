import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trump v3 runtime assets keep the approved pixel contracts', () {
    const expectedSizes = {
      'background_map_v3.png': (360, 840),
      'dealer_idle_sheet_v3.png': (128, 128),
      'dealer_idle_frame_v3.png': (64, 64),
      'dealer_deal_sheet_v3.png': (192, 128),
      'dealer_win_sheet_v3.png': (128, 128),
      'dealer_lose_sheet_v3.png': (128, 128),
      'player_idle_sheet_v3.png': (96, 96),
      'player_idle_frame_v3.png': (48, 48),
      'player_win_sheet_v3.png': (96, 96),
      'player_lose_sheet_v3.png': (96, 96),
      'card_front_v3.png': (72, 100),
      'card_back_v3.png': (72, 100),
      'coin_v3.png': (24, 24),
      'suit_icons_v3.png': (48, 12),
      'suit_icons_small_v3.png': (40, 10),
      'rank_glyphs_v3.png': (234, 36),
      'royal_faces_v3.png': (144, 120),
      'chip_fx_sheet_v3.png': (48, 48),
    };

    for (final entry in expectedSizes.entries) {
      final file = File('assets/images/beat_the_dealer/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(_pngSize(file), entry.value, reason: entry.key);
    }
  });

  test('transparent v3 sprites use RGBA PNG color type', () {
    for (final name in [
      'dealer_idle_sheet_v3.png',
      'dealer_idle_frame_v3.png',
      'dealer_deal_sheet_v3.png',
      'dealer_win_sheet_v3.png',
      'dealer_lose_sheet_v3.png',
      'player_idle_sheet_v3.png',
      'player_idle_frame_v3.png',
      'player_win_sheet_v3.png',
      'player_lose_sheet_v3.png',
      'coin_v3.png',
      'suit_icons_v3.png',
      'suit_icons_small_v3.png',
      'rank_glyphs_v3.png',
      'royal_faces_v3.png',
      'chip_fx_sheet_v3.png',
    ]) {
      final bytes = File(
        'assets/images/beat_the_dealer/$name',
      ).readAsBytesSync();
      expect(bytes[25], 6, reason: '$name must be RGBA');
    }
  });

  test('v3 chroma cleanup leaves no visible magenta residue', () async {
    for (final file
        in Directory('assets/images/beat_the_dealer')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('_v3.png'))) {
      final decoded = await _decodeRgba(file);
      var contaminatedPixels = 0;
      for (var offset = 0; offset < decoded.bytes.length; offset += 4) {
        final red = decoded.bytes[offset];
        final green = decoded.bytes[offset + 1];
        final blue = decoded.bytes[offset + 2];
        final alpha = decoded.bytes[offset + 3];
        if (alpha > 0 && red > 235 && blue > 235 && green < 35) {
          contaminatedPixels++;
        }
      }
      expect(contaminatedPixels, 0, reason: file.path);
    }
  });

  test('every animation frame stays inside its own cell', () async {
    const contracts = {
      'dealer_idle_sheet_v3.png': (64, 64, 4, 2),
      'dealer_deal_sheet_v3.png': (64, 64, 6, 3),
      'dealer_win_sheet_v3.png': (64, 64, 4, 2),
      'dealer_lose_sheet_v3.png': (64, 64, 4, 2),
      'player_idle_sheet_v3.png': (48, 48, 4, 2),
      'player_win_sheet_v3.png': (48, 48, 4, 2),
      'player_lose_sheet_v3.png': (48, 48, 4, 2),
      'chip_fx_sheet_v3.png': (24, 24, 4, 2),
    };
    for (final entry in contracts.entries) {
      final decoded = await _decodeRgba(
        File('assets/images/beat_the_dealer/${entry.key}'),
      );
      final (cellWidth, cellHeight, frameCount, columns) = entry.value;
      final signatures = <int>{};
      for (var frame = 0; frame < frameCount; frame++) {
        final originX = (frame % columns) * cellWidth;
        final originY = (frame ~/ columns) * cellHeight;
        var opaquePixels = 0;
        var signature = 17;
        for (var y = 0; y < cellHeight; y++) {
          for (var x = 0; x < cellWidth; x++) {
            final alpha = decoded.alphaAt(originX + x, originY + y);
            if (alpha > 0) opaquePixels++;
            final pixelOffset =
                ((originY + y) * decoded.width + originX + x) * 4;
            signature =
                (37 * signature +
                    decoded.bytes[pixelOffset] +
                    decoded.bytes[pixelOffset + 1] +
                    decoded.bytes[pixelOffset + 2] +
                    alpha) &
                0x7fffffff;
            final onEdge =
                x == 0 || y == 0 || x == cellWidth - 1 || y == cellHeight - 1;
            if (onEdge) {
              expect(
                alpha,
                0,
                reason: '${entry.key} frame ${frame + 1} touches its cell edge',
              );
            }
          }
        }
        expect(
          opaquePixels,
          greaterThan(0),
          reason: '${entry.key} frame ${frame + 1}',
        );
        signatures.add(signature);
      }
      expect(
        signatures.length,
        frameCount,
        reason: '${entry.key} contains an accidental duplicate frame',
      );
    }
  });

  test(
    'front, back, suits, and royal cells keep safe visible bounds',
    () async {
      final front = await _decodeRgba(
        File('assets/images/beat_the_dealer/card_front_v3.png'),
      );
      final back = await _decodeRgba(
        File('assets/images/beat_the_dealer/card_back_v3.png'),
      );
      for (final image in [front, back]) {
        expect(_alphaBounds(image), (0, 0, 72, 100));
        expect(image.alphaAt(0, 0), 0);
        expect(image.alphaAt(71, 0), 0);
        expect(image.alphaAt(0, 99), 0);
        expect(image.alphaAt(71, 99), 0);
        expect(image.alphaAt(36, 0), greaterThan(0));
        expect(image.alphaAt(36, 99), greaterThan(0));
        expect(image.alphaAt(0, 50), greaterThan(0));
        expect(image.alphaAt(71, 50), greaterThan(0));
      }

      final suits = await _decodeRgba(
        File('assets/images/beat_the_dealer/suit_icons_v3.png'),
      );
      for (var suit = 0; suit < 4; suit++) {
        for (var offset = 0; offset < 12; offset++) {
          expect(suits.alphaAt(suit * 12 + offset, 0), 0);
          expect(suits.alphaAt(suit * 12 + offset, 11), 0);
          expect(suits.alphaAt(suit * 12, offset), 0);
          expect(suits.alphaAt(suit * 12 + 11, offset), 0);
        }
      }

      final smallSuits = await _decodeRgba(
        File('assets/images/beat_the_dealer/suit_icons_small_v3.png'),
      );
      final smallSuitSignatures = <String>{};
      for (var suit = 0; suit < 4; suit++) {
        var visible = 0;
        var minX = 10;
        var minY = 10;
        var maxX = -1;
        var maxY = -1;
        final signature = StringBuffer();
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            final alpha = smallSuits.alphaAt(suit * 10 + x, y);
            signature.write(alpha > 0 ? '#' : '.');
            if (alpha > 0) {
              visible++;
              minX = minX < x ? minX : x;
              minY = minY < y ? minY : y;
              maxX = maxX > x ? maxX : x;
              maxY = maxY > y ? maxY : y;
            }
            expect(
              alpha,
              smallSuits.alphaAt(suit * 10 + (9 - x), y),
              reason: 'small suit $suit is not horizontally symmetric',
            );
            if (x == 0 || x == 9 || y == 0 || y == 9) {
              expect(
                alpha,
                0,
                reason: 'small suit $suit touches its cell edge',
              );
            }
          }
        }
        expect(visible, greaterThan(10), reason: 'small suit $suit is empty');
        expect(maxX - minX + 1, lessThanOrEqualTo(8));
        expect(maxY - minY + 1, lessThanOrEqualTo(8));
        smallSuitSignatures.add(signature.toString());
      }
      expect(smallSuitSignatures, hasLength(4));

      final ranks = await _decodeRgba(
        File('assets/images/beat_the_dealer/rank_glyphs_v3.png'),
      );
      for (var row = 0; row < 2; row++) {
        for (var column = 0; column < 13; column++) {
          var visible = 0;
          for (var y = 0; y < 18; y++) {
            for (var x = 0; x < 18; x++) {
              if (ranks.alphaAt(column * 18 + x, row * 18 + y) > 0) {
                visible++;
              }
            }
          }
          expect(visible, greaterThan(20), reason: 'rank cell $row,$column');
        }
      }

      final royals = await _decodeRgba(
        File('assets/images/beat_the_dealer/royal_faces_v3.png'),
      );
      for (var row = 0; row < 2; row++) {
        for (var column = 0; column < 3; column++) {
          var visible = 0;
          for (var y = 0; y < 60; y++) {
            for (var x = 0; x < 48; x++) {
              final alpha = royals.alphaAt(column * 48 + x, row * 60 + y);
              if (alpha > 0) visible++;
              if (x == 0 || x == 47 || y == 0 || y == 59) {
                expect(alpha, 0, reason: 'royal cell $row,$column edge');
              }
            }
          }
          expect(visible, greaterThan(500), reason: 'royal cell $row,$column');
        }
      }
    },
  );
}

class _DecodedRgba {
  const _DecodedRgba(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;

  int alphaAt(int x, int y) => bytes[(y * width + x) * 4 + 3];
}

Future<_DecodedRgba> _decodeRgba(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final decoded = _DecodedRgba(
    frame.image.width,
    frame.image.height,
    data!.buffer.asUint8List(),
  );
  frame.image.dispose();
  codec.dispose();
  return decoded;
}

(int, int, int, int)? _alphaBounds(_DecodedRgba image) {
  var left = image.width;
  var top = image.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.alphaAt(x, y) == 0) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  return right < 0 ? null : (left, top, right + 1, bottom + 1);
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24));
  expect(bytes.sublist(1, 4), [80, 78, 71]);
  final data = bytes.buffer.asByteData();
  return (data.getUint32(16), data.getUint32(20));
}
