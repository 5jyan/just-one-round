import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('빙글개굴 런타임 에셋 크기와 아틀라스 계약을 고정한다', () async {
    final expected = <String, (int, int)>{
      'assets/images/lily_frog/frog_actions_atlas.png': (224, 224),
      'assets/images/lily_frog/lily_pad_atlas.png': (1280, 768),
      'assets/images/lily_frog/golden_lily_pad_atlas.png': (768, 256),
      'assets/images/lily_frog/fly_sheet.png': (128, 32),
      'assets/images/lily_frog/fly_collect_fx_atlas.png': (320, 64),
      'assets/images/lily_frog/water_fx_atlas.png': (256, 128),
      'assets/images/lily_frog/pond_background.png': (180, 480),
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

  test('황금 연잎은 별도 128px 금색 에셋으로 회전 여백을 지킨다', () async {
    final report =
        jsonDecode(
              await File(
                'assets/source/imagegen/lily_frog/runtime-qc.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final golden = report['golden_lilies'] as Map<String, dynamic>;
    final bounds = golden['occupied_bounds'] as List<dynamic>;
    final radii = (golden['rotation_radii'] as List<dynamic>).cast<num>();

    expect(golden['grid'], [1, 3]);
    expect(golden['palette'], 'polished 24K gold');
    final averageRgb = (golden['average_opaque_rgb'] as List<dynamic>)
        .cast<num>();
    expect(averageRgb[0], greaterThan(220));
    expect(averageRgb[1], greaterThan(165));
    expect(averageRgb[2], lessThan(70));
    expect(golden['average_opaque_luminance'] as num, greaterThan(175));
    expect(bounds, hasLength(3));
    expect(radii, hasLength(3));
    for (var index = 0; index < bounds.length; index++) {
      final box = (bounds[index] as List<dynamic>).cast<int>();
      expect(max(box[2] - box[0], box[3] - box[1]), lessThanOrEqualTo(128));
      expect(radii[index], lessThanOrEqualTo(64));
    }
  });

  test('파리 수집 이펙트는 5프레임 모두 비지 않고 64px 셀 안에 있다', () async {
    final report =
        jsonDecode(
              await File(
                'assets/source/imagegen/lily_frog/runtime-qc.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final effect = report['fly_collect_fx'] as Map<String, dynamic>;
    final bounds = effect['occupied_bounds'] as List<dynamic>;

    expect(effect['frames'], 5);
    expect(effect['duration_ms'], 280);
    expect(bounds, hasLength(5));
    for (final rawBox in bounds) {
      final box = (rawBox as List<dynamic>).cast<int>();
      expect(box[0], greaterThanOrEqualTo(0));
      expect(box[1], greaterThanOrEqualTo(0));
      expect(box[2], lessThanOrEqualTo(64));
      expect(box[3], lessThanOrEqualTo(64));
    }
  });

  test('모든 연잎은 회전 셀 안에 최소 24px 여백을 둔다', () async {
    final report =
        jsonDecode(
              await File(
                'assets/source/imagegen/lily_frog/runtime-qc.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final lilies = report['lilies'] as Map<String, dynamic>;
    final bounds = lilies['occupied_bounds'] as List<dynamic>;
    final rotationRadii = (lilies['rotation_radii'] as List<dynamic>)
        .cast<num>();
    const expectedExtents = [128, 160, 176, 192, 208];

    expect(bounds, hasLength(15));
    expect(rotationRadii, hasLength(15));
    for (var index = 0; index < bounds.length; index++) {
      final box = (bounds[index] as List<dynamic>).cast<int>();
      expect(box[0], greaterThanOrEqualTo(24));
      expect(box[1], greaterThanOrEqualTo(24));
      expect(box[2], lessThanOrEqualTo(232));
      expect(box[3], lessThanOrEqualTo(232));
      final occupiedExtent = max(box[2] - box[0], box[3] - box[1]);
      expect(occupiedExtent, lessThanOrEqualTo(expectedExtents[index % 5]));
      expect(
        occupiedExtent,
        greaterThanOrEqualTo(expectedExtents[index % 5] - 12),
      );
      expect(
        rotationRadii[index],
        lessThanOrEqualTo(expectedExtents[index % 5] / 2),
      );
    }
  });

  test('파리 네 프레임은 32px 셀 안에서 충분히 크게 보인다', () async {
    final report =
        jsonDecode(
              await File(
                'assets/source/imagegen/lily_frog/runtime-qc.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final fly = report['fly'] as Map<String, dynamic>;
    final bounds = fly['occupied_bounds'] as List<dynamic>;

    expect(fly['subject_extent'], 24);
    expect(bounds, hasLength(4));
    for (final rawBox in bounds) {
      final box = (rawBox as List<dynamic>).cast<int>();
      expect(box[0], greaterThanOrEqualTo(4));
      expect(box[1], greaterThanOrEqualTo(4));
      expect(box[2], lessThanOrEqualTo(28));
      expect(box[3], lessThanOrEqualTo(28));
      expect(max(box[2] - box[0], box[3] - box[1]), greaterThanOrEqualTo(15));
    }
  });
}
