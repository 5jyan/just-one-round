import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expected = <String, (int, int)>{
    'apartment_background.png': (360, 640),
    'snake_head_slither_atlas.png': (128, 128),
    'snake_head_eat_atlas.png': (128, 128),
    'snake_tail_atlas.png': (64, 128),
    'snake_skin_tile.png': (32, 32),
    'snake_scale_pattern.png': (32, 32),
    'midnight_food_atlas.png': (192, 64),
    'crumb_burst_sheet.png': (64, 64),
    'golden_sausage_sheet.png': (32, 64),
    'mouse_walk_atlas.png': (64, 128),
    'arcade_controls.png': (360, 195),
    'kitchen_playfield.png': (360, 764),
  };

  test('runtime asset contract has exact dimensions', () {
    for (final entry in expected.entries) {
      final file = File('assets/images/midnight_snake/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      final bytes = file.readAsBytesSync();
      expect(bytes.sublist(1, 4), [
        0x50,
        0x4e,
        0x47,
      ], reason: '${entry.key} must be PNG');
      final data = ByteData.sublistView(bytes);
      expect(
        (data.getUint32(16), data.getUint32(20)),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('sprite atlases are non-empty production files', () {
    for (final name in [
      'snake_head_slither_atlas.png',
      'snake_head_eat_atlas.png',
      'snake_tail_atlas.png',
      'midnight_food_atlas.png',
      'crumb_burst_sheet.png',
      'golden_sausage_sheet.png',
      'mouse_walk_atlas.png',
    ]) {
      expect(
        File('assets/images/midnight_snake/$name').lengthSync(),
        greaterThan(256),
        reason: name,
      );
    }
  });

  test('body scale pattern is a transparent production PNG', () {
    final file = File('assets/images/midnight_snake/snake_scale_pattern.png');
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(128));
    expect(bytes[25], 6, reason: 'PNG color type must be RGBA');
  });
}
