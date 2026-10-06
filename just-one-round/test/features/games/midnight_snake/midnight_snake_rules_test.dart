import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';

void main() {
  test('starts centered and moves one cell to the right', () {
    final state = MidnightSnakeState.initial();
    final result = state.step(Random(1));
    expect(result.moved, isTrue);
    expect(state.head, const SnakeCell(7, 5));
    expect(state.body.length, MidnightSnakeRules.initialBodyLength);
  });

  test('eating adds one score and one continuous body coordinate', () {
    final state = MidnightSnakeState.initial();
    final first = state.step(Random(1));
    final second = state.step(Random(1));
    expect(first.ateFood, isFalse);
    expect(second.ateFood, isTrue);
    expect(state.score, 1);
    expect(state.body.length, MidnightSnakeRules.initialBodyLength + 1);
    expect(state.food, isNotNull);
    expect(state.foodTypeIndex, inInclusiveRange(0, 5));
  });

  test('queues up to three valid turns and applies them in order', () {
    final state = MidnightSnakeState.initial();
    expect(state.queueDirection(SnakeDirection.left), isFalse);
    expect(state.queueDirection(SnakeDirection.up), isTrue);
    expect(state.queueDirection(SnakeDirection.right), isTrue);
    expect(state.queueDirection(SnakeDirection.down), isTrue);
    expect(state.queueDirection(SnakeDirection.left), isFalse);

    state.step(Random(1));
    expect(state.direction, SnakeDirection.up);
    state.step(Random(1));
    expect(state.direction, SnakeDirection.right);
    state.step(Random(1));
    expect(state.direction, SnakeDirection.down);
  });

  test('food candidates are empty, reachable, and preferably not adjacent', () {
    final state = MidnightSnakeState.initial();
    final food = MidnightSnakeRules.chooseReachableFood(
      body: state.body,
      random: Random(7),
    );
    expect(food, isNotNull);
    expect(state.body, isNot(contains(food)));
    expect(state.head.manhattanDistanceTo(food!), greaterThanOrEqualTo(3));
  });

  test('speed curve accelerates without a sudden opening tick', () {
    expect(MidnightSnakeRules.moveIntervalAt(0), 0.60);
    expect(MidnightSnakeRules.moveIntervalAt(29), 0.46);
    expect(MidnightSnakeRules.moveIntervalAt(30), 0.42);
    expect(MidnightSnakeRules.moveIntervalAt(120), 0.25);
    expect(MidnightSnakeRules.moveIntervalAt(149), closeTo(0.2452, 0.0001));
    expect(MidnightSnakeRules.moveIntervalAt(180), closeTo(0.24, 0.0001));
    expect(MidnightSnakeRules.moveIntervalAt(240), closeTo(0.23, 0.0001));
    expect(MidnightSnakeRules.moveIntervalAt(299), closeTo(0.2202, 0.0001));
    expect(MidnightSnakeRules.moveIntervalAt(300), 0.22);
  });

  test(
    'the first golden spawn second is seeded and stays inside its window',
    () {
      final first = Random(17);
      final second = Random(17);
      final firstGolden = MidnightSnakeRules.spawnSecondInRange(
        random: first,
        startInclusive: 30,
        endInclusive: 60,
      );
      expect(firstGolden, inInclusiveRange(30, 60));
      expect(
        firstGolden,
        MidnightSnakeRules.spawnSecondInRange(
          random: second,
          startInclusive: 30,
          endInclusive: 60,
        ),
      );
      expect(MidnightSnakeRules.bonusCooldownSeconds, 30);
    },
  );

  test(
    'golden sausage appears once in a reachable empty corner and expires',
    () {
      final state = MidnightSnakeState.initial(goldenSpawnAtSeconds: 30);
      state.updateBonusEvents(elapsedSeconds: 29.9, random: Random(2));
      expect(state.goldenSausage, isNull);

      state.updateBonusEvents(elapsedSeconds: 30, random: Random(2));
      expect(MidnightSnakeRules.cornerCells, contains(state.goldenSausage));
      expect(state.body, isNot(contains(state.goldenSausage)));
      expect(state.food, isNot(state.goldenSausage));

      state.updateBonusEvents(elapsedSeconds: 40, random: Random(2));
      expect(state.goldenSausage, isNull);
      expect(state.goldenIsResolved, isTrue);
      expect(state.mouseSpawnAtSeconds, 70);
      state.updateBonusEvents(elapsedSeconds: 50, random: Random(2));
      expect(state.goldenSausage, isNull);
    },
  );

  test('golden sausage and mouse repeat after a 30-second cooldown', () {
    final state = MidnightSnakeState.initial(goldenSpawnAtSeconds: 30);

    state.updateBonusEvents(elapsedSeconds: 30, random: Random(2));
    expect(state.goldenSausage, isNotNull);
    state.updateBonusEvents(elapsedSeconds: 40, random: Random(2));
    expect(state.goldenSausage, isNull);
    expect(state.mouseSpawnAtSeconds, 70);
    state.updateBonusEvents(elapsedSeconds: 69.9, random: Random(2));
    expect(state.mouse, isNull);
    state.updateBonusEvents(elapsedSeconds: 70, random: Random(2));
    expect(state.mouse, isNotNull);

    state.updateBonusEvents(elapsedSeconds: 85, random: Random(2));
    expect(state.mouse, isNull);
    expect(state.goldenSpawnAtSeconds, 115);
    state.updateBonusEvents(elapsedSeconds: 114.9, random: Random(2));
    expect(state.goldenSausage, isNull);
    state.updateBonusEvents(elapsedSeconds: 115, random: Random(2));
    expect(state.goldenSausage, isNotNull);

    state.updateBonusEvents(elapsedSeconds: 125, random: Random(2));
    expect(state.goldenSausage, isNull);
    expect(state.mouseSpawnAtSeconds, 155);
    state.updateBonusEvents(elapsedSeconds: 155, random: Random(2));
    expect(state.mouse, isNotNull);
  });

  test(
    'eating golden sausage gives three points and starts the mouse cooldown',
    () {
      final state = MidnightSnakeState.forTesting(
        body: const [SnakeCell(1, 0), SnakeCell(1, 1)],
        direction: SnakeDirection.up,
        food: const SnakeCell(7, 7),
        goldenSausage: const SnakeCell(0, 0),
        goldenExpiresAt: 100,
      );

      final result = state.step(Random(1), elapsedSeconds: 25);

      expect(result.ateGoldenSausage, isTrue);
      expect(result.scoreGained, MidnightSnakeRules.goldenSausageScore);
      expect(state.score, 3);
      expect(state.body.length, 3);
      expect(state.goldenSausage, isNull);
      expect(state.goldenIsResolved, isTrue);
      expect(state.mouseSpawnAtSeconds, 55);
    },
  );

  test(
    'mouse waits 30 seconds after the golden event and avoids occupied cells',
    () {
      final waiting = MidnightSnakeState.forTesting(
        body: MidnightSnakeRules.initialBody,
        direction: SnakeDirection.right,
        food: MidnightSnakeRules.initialFood,
        goldenSausage: const SnakeCell(0, 0),
        goldenSpawnAtSeconds: 30,
        goldenExpiresAt: 70,
        mouseSpawnAtSeconds: 60,
      );
      waiting.updateBonusEvents(elapsedSeconds: 60, random: Random(4));
      expect(waiting.mouse, isNull);

      waiting.updateBonusEvents(elapsedSeconds: 70, random: Random(4));
      expect(waiting.goldenSausage, isNull);
      expect(waiting.mouse, isNull);
      expect(waiting.mouseSpawnAtSeconds, 100);

      waiting.updateBonusEvents(elapsedSeconds: 100, random: Random(4));
      expect(waiting.mouse, isNotNull);
      expect(waiting.body, isNot(contains(waiting.mouse)));
      expect(waiting.food, isNot(waiting.mouse));
    },
  );

  test('mouse movement avoids the snake and every visible food', () {
    const mouse = SnakeCell(5, 5);
    const regularFood = SnakeCell(4, 5);
    const golden = SnakeCell(5, 6);
    const body = [SnakeCell(6, 5), SnakeCell(6, 4)];
    for (var seed = 0; seed < 30; seed++) {
      final movement = MidnightSnakeRules.chooseMouseMovement(
        mouse: mouse,
        currentDirection: SnakeDirection.down,
        body: body,
        food: regularFood,
        goldenSausage: golden,
        random: Random(seed),
      );
      expect(movement, isNotNull);
      expect(body, isNot(contains(movement!.$2)));
      expect(movement.$2, isNot(regularFood));
      expect(movement.$2, isNot(golden));
      expect(mouse.manhattanDistanceTo(movement.$2), 1);
    }
  });

  test(
    'catching the mouse gives two points and starts the golden cooldown',
    () {
      final state = MidnightSnakeState.forTesting(
        body: const [SnakeCell(1, 0), SnakeCell(1, 1)],
        direction: SnakeDirection.up,
        food: const SnakeCell(7, 7),
        mouse: const SnakeCell(0, 0),
        mouseDirection: SnakeDirection.left,
        goldenResolved: true,
        mouseExpiresAt: 100,
        mouseNextMoveAt: 100,
      );

      final result = state.step(Random(3), elapsedSeconds: 80);

      expect(result.caughtMouse, isTrue);
      expect(result.scoreGained, MidnightSnakeRules.mouseScore);
      expect(state.score, 2);
      expect(state.body.length, 3);
      expect(state.mouse, isNull);
      expect(state.mouseIsResolved, isTrue);
      expect(state.goldenSpawnAtSeconds, 110);
      state.updateBonusEvents(elapsedSeconds: 109.9, random: Random(3));
      expect(state.goldenSausage, isNull);
      state.updateBonusEvents(elapsedSeconds: 110, random: Random(3));
      expect(state.goldenSausage, isNotNull);
    },
  );

  test('bonus score cap includes the repeating bonus loop', () {
    expect(MidnightSnakeRules.maximumBaseScore, 131);
    expect(MidnightSnakeRules.maximumScore, 145);
  });
}
