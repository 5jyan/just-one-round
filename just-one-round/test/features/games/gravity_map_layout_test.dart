import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_map_layout.dart';

void main() {
  test('parses the editable gravity switch map asset', () {
    final source = File(
      'assets/maps/gravity_switch_map.json',
    ).readAsStringSync();

    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final mapFiles = {
      for (final pattern in decoded['patterns'] as List)
        (pattern as Map<String, dynamic>)['mapFile'] as String: File(
          'assets/maps/${pattern['mapFile']}',
        ).readAsStringSync(),
    };

    final layout = GravityMapLayout.fromJsonString(source, mapFiles: mapFiles);

    expect(layout.columnWidth, 48);
    expect(layout.initialProfile.floorTop, 416);
    expect(layout.initialProfile.ceilingBottom, 272);
    expect(layout.initialColumnCount, 12);
    expect(layout.patterns, hasLength(9));
    expect(layout.patterns.first.id, 'large_m');
    expect(layout.patterns.first.columns, hasLength(25));

    final v = layout.patterns.singleWhere((pattern) => pattern.id == 'v_easy');
    expect(v.unlockAfterSeconds, 0);
    expect(v.columns, hasLength(15));

    final beforeThreshold = layout.patterns.where(
      (pattern) => pattern.isAvailableAt(29.999),
    );
    expect(beforeThreshold, isNotEmpty);
    expect(
      beforeThreshold.every((pattern) => !pattern.id.contains('_hard')),
      isTrue,
    );
    expect(
      beforeThreshold.any((pattern) => pattern.id == 'large_m'),
      isTrue,
    );

    final afterThreshold = layout.patterns.where(
      (pattern) => pattern.isAvailableAt(30),
    );
    expect(afterThreshold, isNotEmpty);
    expect(
      afterThreshold.every((pattern) => !pattern.id.contains('_easy')),
      isTrue,
    );
    expect(
      afterThreshold.any((pattern) => pattern.id.contains('_hard')),
      isTrue,
    );
    expect(afterThreshold.any((pattern) => pattern.id == 'large_m'), isTrue);
    expect(beforeThreshold.any((pattern) => pattern.id == 'snake'), isTrue);
    expect(afterThreshold.any((pattern) => pattern.id == 'snake'), isTrue);
  });

  test('reports a floating wall in a visual grid', () {
    const source = '''
{
  "cellSize": 48,
  "baseCeilingHeight": 128,
  "baseFloorHeight": 128,
  "initialColumnCount": 4,
  "patterns": [
    {
      "id": "broken",
      "unlockAfterSeconds": 0,
      "mapFile": "patterns/broken.map"
    }
  ]
}
''';

    expect(
      () => GravityMapLayout.fromJsonString(
        source,
        mapFiles: const {"patterns/broken.map": "□\n■\n□"},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('floating wall'),
        ),
      ),
    );
  });
}
