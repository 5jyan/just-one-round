import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_map_layout.dart';

void main() {
  test('parses the editable gravity switch map asset', () {
    final source = File(
      'assets/maps/gravity_switch_map.json',
    ).readAsStringSync();

    final layout = GravityMapLayout.fromJsonString(source);

    expect(layout.columnWidth, 48);
    expect(layout.initialProfile.floorTop, 512);
    expect(layout.initialProfile.ceilingBottom, 128);
    expect(layout.initialColumnCount, 12);
    expect(layout.patterns, hasLength(6));
    expect(layout.patterns.first.id, 'floor_stairs');
    expect(layout.patterns.first.columns, hasLength(7));
  });

  test('reports a pattern that references an unknown profile', () {
    const source = '''
{
  "screenHeight": 640,
  "columnWidth": 48,
  "initialProfile": "safe",
  "initialColumnCount": 4,
  "profiles": {
    "safe": {"floorHeight": 128, "ceilingHeight": 128}
  },
  "patterns": [
    {
      "id": "broken",
      "unlockAfterSeconds": 0,
      "columns": ["missing"]
    }
  ]
}
''';

    expect(
      () => GravityMapLayout.fromJsonString(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unknown profile "missing"'),
        ),
      ),
    );
  });
}
