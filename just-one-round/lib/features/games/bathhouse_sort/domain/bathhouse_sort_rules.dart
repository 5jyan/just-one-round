import 'dart:math';

enum BathEntrance { mens, womens }

enum BathhouseDifficulty { learn, establish, combine, mastery }

enum BathhouseSpecies {
  blackBear('흑곰', BathEntrance.mens),
  brownDog('갈색 강아지', BathEntrance.mens),
  grayBrownTanuki('너구리', BathEntrance.mens),
  grayWolf('회색 늑대', BathEntrance.mens),
  whiteRabbit('흰토끼', BathEntrance.womens),
  pinkPig('핑크돼지', BathEntrance.womens),
  creamSheep('크림 양', BathEntrance.womens),
  whiteCheeseCat('치즈 고양이', BathEntrance.womens);

  const BathhouseSpecies(this.label, this.entrance);

  final String label;
  final BathEntrance entrance;
}

class BathhouseSpeciesPair {
  const BathhouseSpeciesPair({required this.mens, required this.womens});

  final BathhouseSpecies mens;
  final BathhouseSpecies womens;
}

class BathhouseGuest {
  const BathhouseGuest({required this.species});

  final BathhouseSpecies species;
  BathEntrance get entrance => species.entrance;

  @override
  bool operator ==(Object other) =>
      other is BathhouseGuest && species == other.species;

  @override
  int get hashCode => species.hashCode;
}

class BathhouseGuestGenerator {
  BathhouseGuestGenerator(this._random);

  final Random _random;
  BathEntrance? _lastEntrance;
  var _sameEntranceRun = 0;

  BathhouseGuest next({int activePairCount = 1}) {
    final safePairCount = activePairCount.clamp(
      1,
      BathhouseSortRules.speciesPairs.length,
    );
    var entrance = _random.nextBool() ? BathEntrance.mens : BathEntrance.womens;
    if (_sameEntranceRun >= BathhouseSortRules.maximumSameEntranceRun) {
      entrance = _lastEntrance == BathEntrance.mens
          ? BathEntrance.womens
          : BathEntrance.mens;
    }

    if (entrance == _lastEntrance) {
      _sameEntranceRun++;
    } else {
      _lastEntrance = entrance;
      _sameEntranceRun = 1;
    }

    final pair =
        BathhouseSortRules.speciesPairs[_random.nextInt(safePairCount)];
    return BathhouseGuest(
      species: entrance == BathEntrance.mens ? pair.mens : pair.womens,
    );
  }
}

abstract final class BathhouseSortRules {
  static const gameId = 'bathhouse_sort';
  static const rulesVersion = 11;
  static const gameDuration = Duration(seconds: 60);
  static const wrongInputLock = Duration(milliseconds: 250);
  static const inputBufferCapacity = 32;
  static const inputCommitInterval = Duration(milliseconds: 20);
  static const inputReservationLifetime = Duration(milliseconds: 800);
  static const rosterRevealDuration = Duration(milliseconds: 800);
  static const unlockMilestones = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 45),
  ];
  static const speciesPairs = <BathhouseSpeciesPair>[
    BathhouseSpeciesPair(
      mens: BathhouseSpecies.blackBear,
      womens: BathhouseSpecies.whiteRabbit,
    ),
    BathhouseSpeciesPair(
      mens: BathhouseSpecies.brownDog,
      womens: BathhouseSpecies.pinkPig,
    ),
    BathhouseSpeciesPair(
      mens: BathhouseSpecies.grayBrownTanuki,
      womens: BathhouseSpecies.creamSheep,
    ),
    BathhouseSpeciesPair(
      mens: BathhouseSpecies.grayWolf,
      womens: BathhouseSpecies.whiteCheeseCat,
    ),
  ];
  static const routeTapSplitX = 180.0;
  static const routeTapTop = 543.0;
  static const routeTapBottom = 617.0;
  static const queueSize = 7;
  static const queueAdvanceDuration = Duration(milliseconds: 70);
  static const maximumSameEntranceRun = 4;
  static const maximumCombo = 50;
  static const maximumScore = 1000000;

  static List<BathhouseSpecies> activeSpecies(int pairCount) => [
    for (final pair in speciesPairs.take(
      pairCount.clamp(1, speciesPairs.length),
    )) ...[pair.mens, pair.womens],
  ];

  static bool isCorrect({
    required BathEntrance guestEntrance,
    required BathEntrance tappedEntrance,
  }) => guestEntrance == tappedEntrance;

  static BathEntrance? entranceForTap({required double x, required double y}) {
    if (x < 0 || x > 360 || y < routeTapTop || y > routeTapBottom) {
      return null;
    }
    return x < routeTapSplitX ? BathEntrance.mens : BathEntrance.womens;
  }

  static int pointsForCorrect(int comboAfterCorrect) {
    if (comboAfterCorrect <= 0) {
      throw ArgumentError.value(comboAfterCorrect, 'comboAfterCorrect');
    }
    return min(100 + (comboAfterCorrect - 1) * 10, 360);
  }

  static int comboAfterCorrect(int currentCombo) =>
      min(currentCombo + 1, maximumCombo);

  static int comboTier(int combo) {
    if (combo >= 27) return 3;
    if (combo >= 20) return 2;
    if (combo >= 10) return 1;
    return 0;
  }

  static double successEffectScale(int combo) =>
      1 + (combo - 1).clamp(0, 26) / 26 * 2.2;

  static int addCorrectScore({required int score, required int combo}) =>
      (score + pointsForCorrect(combo)).clamp(0, maximumScore);

  static BathhouseDifficulty difficultyForElapsed(Duration elapsed) {
    if (elapsed < unlockMilestones[0]) return BathhouseDifficulty.learn;
    if (elapsed < unlockMilestones[1]) return BathhouseDifficulty.establish;
    if (elapsed < unlockMilestones[2]) return BathhouseDifficulty.combine;
    return BathhouseDifficulty.mastery;
  }

  static String formatScore(int score) => '${_withThousands(score)}점';

  static String formatHudScore(int score) => _withThousands(score);

  static String _withThousands(int value) {
    final digits = value.clamp(0, maximumScore).toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
