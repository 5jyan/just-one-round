import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = <String, (int, int, int, int)>{
    'office_background.png': (180, 400, 1, 1),
    'counter_front.png': (180, 72, 1, 1),
    'raccoon_idle_sheet.png': (192, 48, 4, 1),
    'raccoon_pose_atlas.png': (192, 96, 4, 2),
    'ramen_cup_atlas.png': (128, 32, 4, 1),
    'ramen_fx_atlas.png': (96, 64, 3, 2),
    'ramen_result_atlas.png': (192, 64, 3, 1),
  };

  test('runtime asset set is complete at the contracted dimensions', () async {
    for (final entry in assets.entries) {
      final file = File('assets/images/ramen_timer/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(file.lengthSync(), greaterThan(0), reason: entry.key);
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, entry.value.$1, reason: entry.key);
      expect(frame.image.height, entry.value.$2, reason: entry.key);
      expect(frame.image.width % entry.value.$3, 0, reason: entry.key);
      expect(frame.image.height % entry.value.$4, 0, reason: entry.key);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('every transparent atlas frame is non-empty and edge-safe', () async {
    for (final entry in assets.entries.where((entry) => entry.value.$3 > 1)) {
      final file = File('assets/images/ramen_timer/${entry.key}');
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull, reason: entry.key);
      final rgba = bytes!;
      final columns = entry.value.$3;
      final rows = entry.value.$4;
      final cellWidth = frame.image.width ~/ columns;
      final cellHeight = frame.image.height ~/ rows;
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          var opaqueCount = 0;
          var edgeCount = 0;
          for (var y = 0; y < cellHeight; y++) {
            for (var x = 0; x < cellWidth; x++) {
              final imageX = column * cellWidth + x;
              final imageY = row * cellHeight + y;
              final offset = (imageY * frame.image.width + imageX) * 4;
              final alpha = rgba.getUint8(offset + 3);
              if (alpha == 0) continue;
              opaqueCount++;
              if (x == 0 ||
                  y == 0 ||
                  x == cellWidth - 1 ||
                  y == cellHeight - 1) {
                edgeCount++;
              }
              final red = rgba.getUint8(offset);
              final green = rgba.getUint8(offset + 1);
              final blue = rgba.getUint8(offset + 2);
              expect(
                red > 245 && green < 12 && blue > 245,
                isFalse,
                reason: '${entry.key} retains magenta at $imageX,$imageY',
              );
            }
          }
          expect(
            opaqueCount,
            greaterThan(4),
            reason: '${entry.key} $column,$row',
          );
          expect(edgeCount, 0, reason: '${entry.key} $column,$row');
        }
      }
      frame.image.dispose();
      codec.dispose();
    }
  });

  test(
    'raw prompts, processor metadata, and runtime manifest are preserved',
    () {
      const sourceRoot = 'assets/source/imagegen/ramen_timer';
      expect(File('$sourceRoot/master_raccoon/raw.png').existsSync(), isTrue);
      expect(
        File('$sourceRoot/master_raccoon/prompt.txt').existsSync(),
        isTrue,
      );
      expect(File('$sourceRoot/raccoon_idle/raw.png').existsSync(), isTrue);
      expect(
        File(
          '$sourceRoot/raccoon_idle/processed_runtime/pipeline-meta.json',
        ).existsSync(),
        isTrue,
      );
      expect(File('$sourceRoot/runtime_manifest.json').existsSync(), isTrue);

      const refreshRoot = '$sourceRoot/ui_refresh_v2';
      expect(File('$refreshRoot/README.md').existsSync(), isTrue);
      expect(
        File('$refreshRoot/raccoon_master/prompt-used.txt').existsSync(),
        isTrue,
      );
      expect(
        File(
          '$refreshRoot/raccoon_idle/processed/pipeline-meta.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('$refreshRoot/ramen_result/too_late/prompt-used.txt').existsSync(),
        isTrue,
      );

      final manifest =
          jsonDecode(
                File('$sourceRoot/runtime_manifest.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(manifest['version'], 2);
      expect(
        manifest['source_contract'],
        'assets/source/imagegen/ramen_timer/ui_refresh_v2',
      );
    },
  );
}
