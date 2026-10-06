import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('런타임 에셋은 manifest의 2배 픽셀 셀 규격을 유지한다', () {
    const expected = <String, (int, int)>{
      'mole_reaction_background.png': (180, 480),
      'mole_idle_sheet.png': (96, 96),
      'mole_hurt_sheet.png': (96, 96),
      'mole_thumbs_up_sheet.png': (96, 96),
      'mole_gold_idle_sheet.png': (96, 96),
      'mole_gold_hurt_sheet.png': (96, 96),
      'mole_gold_thumbs_up_sheet.png': (96, 96),
      'hole_back.png': (48, 48),
      'hole_front.png': (48, 48),
      'hammer.png': (48, 48),
      'dirt_impact_sheet.png': (64, 64),
      'gold_burst_sheet.png': (64, 64),
      'ant_crawler_sheet.png': (128, 32),
      'worm_crawler_sheet.png': (576, 48),
      'wood_ui_panel.png': (96, 96),
    };

    for (final entry in expected.entries) {
      final file = File('assets/images/mole_reaction/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(file.lengthSync(), greaterThan(0), reason: entry.key);
      expect(_pngSize(file), entry.value, reason: entry.key);
    }
  });

  test('픽셀아트 일반·황금 두더지 시트는 256px 2x2 셀이다', () {
    const variants = <String>['01_honey'];
    for (final variant in variants) {
      for (final action in ['idle', 'hurt', 'thumbs_up']) {
        final file = File(
          'assets/images/mole_reaction/high_res/$variant/${action}_sheet.png',
        );
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(_pngSize(file), (512, 512), reason: file.path);
      }
    }
    for (final action in ['idle', 'hurt', 'thumbs_up']) {
      final file = File(
        'assets/images/mole_reaction/high_res/'
        'gold_from_attached_thumb_reference/${action}_sheet.png',
      );
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(_pngSize(file), (512, 512), reason: file.path);
    }
  });

  test('manifest는 승인된 준비 1회·진짜 1회·golden x2 계약을 기록한다', () {
    final manifest =
        jsonDecode(
              File(
                'assets/source/imagegen/mole_reaction/asset-manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest['asset_revision'], 'pixel_art_variant_v2_mole_anatomy');
    expect(manifest['status'], 'runtime_ready_pixel_art');
    final board = manifest['approved_rules']['board'] as Map<String, dynamic>;
    final events =
        manifest['approved_rules']['round_events'] as Map<String, dynamic>;
    expect(board['columns'], 2);
    expect(board['rows'], 2);
    expect(board['slots'], 4);
    expect(board['max_hole_uses_per_run'], 1);
    expect(events['normal_moles'], 1);
    expect(events['golden_moles'], 1);
    expect(events['total'], 2);
    expect(events['golden_position'], 'event_2_last');
    expect(events['preparation_events'], 1);
    expect(events['scored_events'], 1);
    expect(manifest['approved_rules']['normal_color_variants'], 1);
    expect(manifest['approved_rules']['golden_reaction_time_multiplier'], 2);
    expect(manifest['approved_rules']['random_appearance_delay_seconds'], [
      3,
      8,
    ]);
    expect(
      manifest['approved_rules']['waiting_ambient_element'],
      'ant_crawler_sheet',
    );
    expect(manifest['approved_rules']['waiting_ambient_elements'], [
      'ant_crawler_sheet',
      'worm_crawler_sheet',
    ]);
    expect(
      manifest['quality_checks']['gold_source_locked_to_attached_thumb_reference'],
      isFalse,
    );
    expect(
      manifest['quality_checks']['gold_source_locked_to_pixel_master'],
      isTrue,
    );
    expect(manifest['quality_checks']['normal_filter'], contains('nearest'));
    expect(manifest['quality_checks']['mole_anatomy_distinct'], isTrue);
    expect(manifest['quality_checks']['upper_body_visible'], isTrue);
    final gold =
        manifest['runtime_assets']['gold_mole_pixel_variant']
            as Map<String, dynamic>;
    expect(gold['event_index'], 1);
  });

  test('투명 아틀라스의 프레임은 비어 있지 않고 magenta가 없다', () async {
    const atlases = <String, int>{
      'mole_idle_sheet.png': 48,
      'mole_hurt_sheet.png': 48,
      'mole_thumbs_up_sheet.png': 48,
      'mole_gold_idle_sheet.png': 48,
      'mole_gold_hurt_sheet.png': 48,
      'mole_gold_thumbs_up_sheet.png': 48,
      'dirt_impact_sheet.png': 32,
      'gold_burst_sheet.png': 32,
      'ant_crawler_sheet.png': 32,
      'worm_crawler_sheet.png': 96,
    };
    for (final entry in atlases.entries) {
      final file = File('assets/images/mole_reaction/${entry.key}');
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull, reason: entry.key);
      final rgba = data!;
      var offset = 0;
      for (var y = 0; y < frame.image.height; y++) {
        for (var x = 0; x < frame.image.width; x++) {
          final alpha = rgba.getUint8(offset + 3);
          if (alpha > 0) {
            final red = rgba.getUint8(offset);
            final green = rgba.getUint8(offset + 1);
            final blue = rgba.getUint8(offset + 2);
            expect(
              red > 245 && green < 12 && blue > 245,
              isFalse,
              reason: '${entry.key} retains magenta at $x,$y',
            );
          }
          offset += 4;
        }
      }
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('픽셀아트 두더지 로스터에도 마젠타 픽셀이 남지 않는다', () async {
    const variants = <String>['01_honey', 'gold_from_attached_thumb_reference'];
    for (final variant in variants) {
      for (final action in ['idle', 'hurt', 'thumbs_up']) {
        final file = File(
          'assets/images/mole_reaction/high_res/$variant/${action}_sheet.png',
        );
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(data, isNotNull, reason: file.path);
        final rgba = data!;
        for (var offset = 0; offset < rgba.lengthInBytes; offset += 4) {
          final alpha = rgba.getUint8(offset + 3);
          if (alpha == 0) continue;
          final red = rgba.getUint8(offset);
          final green = rgba.getUint8(offset + 1);
          final blue = rgba.getUint8(offset + 2);
          expect(
            red > 245 && green < 12 && blue > 245,
            isFalse,
            reason: '${file.path} retains magenta',
          );
        }
        frame.image.dispose();
        codec.dispose();
      }
    }
  });
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24), reason: file.path);
  expect(bytes.sublist(0, 8), const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: file.path);
  final data = bytes.buffer.asByteData();
  return (data.getUint32(16), data.getUint32(20));
}
