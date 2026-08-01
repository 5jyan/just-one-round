import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/presentation/midnight_snake_path.dart';

void main() {
  test('moving body keeps only real orthogonal corners', () {
    const previous = [
      SnakeCell(4, 4),
      SnakeCell(4, 3),
      SnakeCell(5, 3),
      SnakeCell(6, 3),
    ];
    const current = [
      SnakeCell(4, 5),
      SnakeCell(4, 4),
      SnakeCell(4, 3),
      SnakeCell(5, 3),
    ];

    final path = buildMidnightSnakePath(
      body: current,
      previousBody: previous,
      progress: 0.5,
    );

    expect(path, hasLength(3));
    expect((path[0].row, path[0].column), (4.0, 4.5));
    expect((path[1].row, path[1].column), (4.0, 3.0));
    expect((path[2].row, path[2].column), (5.5, 3.0));
    for (var index = 1; index < path.length; index++) {
      expect(
        path[index - 1].row == path[index].row ||
            path[index - 1].column == path[index].column,
        isTrue,
      );
    }
  });

  test('eating extends the head while leaving the tail fixed', () {
    const previous = [
      SnakeCell(7, 4),
      SnakeCell(7, 3),
      SnakeCell(7, 2),
      SnakeCell(7, 1),
    ];
    const current = [
      SnakeCell(7, 5),
      SnakeCell(7, 4),
      SnakeCell(7, 3),
      SnakeCell(7, 2),
      SnakeCell(7, 1),
    ];

    final path = buildMidnightSnakePath(
      body: current,
      previousBody: previous,
      progress: 0.5,
    );

    expect(path, hasLength(2));
    expect((path.first.row, path.first.column), (7.0, 4.5));
    expect((path.last.row, path.last.column), (7.0, 1.0));
  });
}
