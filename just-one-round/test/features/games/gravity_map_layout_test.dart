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
    expect(layout.initialColumnCount, 12);
    expect(layout.patterns, hasLength(20));
    expect(layout.patterns.first.id, 'basic_easy');
    expect(layout.patterns.first.columns, hasLength(15));

    final v = layout.patterns.singleWhere((pattern) => pattern.id == 'v_easy');
    expect(v.unlockAfterSeconds, 0);
    expect(v.columns, hasLength(15));

    final testPattern = layout.patterns.singleWhere(
      (pattern) => pattern.id == 'test',
    );
    expect(testPattern.testOnly, isTrue);
    expect(testPattern.isAvailableAt(0), isFalse);
    expect(testPattern.columns[3].interiorWalls, isEmpty);
    expect(testPattern.columns[4].interiorWalls, hasLength(1));
    expect(testPattern.columns[4].interiorWalls.single.top, 320);
    expect(testPattern.columns[4].interiorWalls.single.bottom, 368);

    void expectOnlyDifficulty(double elapsedSeconds, String difficulty) {
      final available = layout.patterns
          .where((pattern) => pattern.isAvailableAt(elapsedSeconds))
          .toList();

      expect(available, isNotEmpty);
      expect(
        available.every((pattern) => pattern.id.endsWith('_$difficulty')),
        isTrue,
      );
    }

    expectOnlyDifficulty(34.999, 'easy');
    expectOnlyDifficulty(35, 'medium');
    expectOnlyDifficulty(74.999, 'medium');
    expectOnlyDifficulty(75, 'hard');
  });

  test('reports a column with no open corridor', () {
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
        mapFiles: const {"patterns/broken.map": "■\n■\n■"},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('no open corridor'),
        ),
      ),
    );
  });
}
