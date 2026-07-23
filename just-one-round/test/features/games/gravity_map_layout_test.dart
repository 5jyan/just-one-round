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
    expect(layout.initialProfile.floorTop, 512);
    expect(layout.initialProfile.ceilingBottom, 128);
    expect(layout.initialColumnCount, 12);
    expect(layout.patterns, hasLength(6));
    expect(layout.patterns.first.id, 'floor_stairs');
    expect(layout.patterns.first.columns, hasLength(15));

    final floor = layout.patterns[0].columns;
    final ceiling = layout.patterns[1].columns;
    expect(ceiling, hasLength(floor.length));
    for (var index = 0; index < floor.length; index++) {
      expect(
        ceiling[index].ceilingBottom - 128,
        512 - floor[index].floorTop,
        reason: 'ceiling_stairs column $index must mirror floor_stairs',
      );
    }
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
