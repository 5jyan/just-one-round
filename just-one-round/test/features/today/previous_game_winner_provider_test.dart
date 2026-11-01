import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('성공한 지난 게임 1등은 provider를 닫았다 다시 열어도 재사용한다', () async {
    final repository = _PreviousWinnerRepository(result: _result('첫 번째 1등'));
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = previousGameWinnerProvider(_key('western_duel'));
    final subscription = container.listen(provider, (_, _) {});

    final first = await container.read(provider.future);
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    final reopened = await container.read(provider.future);

    expect(reopened, same(first));
    expect(repository.calls, 1);
  });

  test('지난 게임 1등이 없다는 성공 응답도 하루 동안 캐시한다', () async {
    final repository = _PreviousWinnerRepository();
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = previousGameWinnerProvider(_key('western_duel'));
    final subscription = container.listen(provider, (_, _) {});

    expect(await container.read(provider.future), isNull);
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(provider.future), isNull);

    expect(repository.calls, 1);
  });

  test('게임 ID나 기준 날짜가 다르면 각각 조회한다', () async {
    final repository = _PreviousWinnerRepository(result: _result('1등'));
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(
      previousGameWinnerProvider(_key('western_duel')).future,
    );
    await container.read(previousGameWinnerProvider(_key('wind_darts')).future);
    await container.read(
      previousGameWinnerProvider(
        _key('western_duel', beforeDate: DateTime(2026, 10, 12)),
      ).future,
    );

    expect(repository.calls, 3);
  });

  test('실패한 조회는 캐시하지 않고 다시 열 때 재시도한다', () async {
    final repository = _PreviousWinnerRepository(
      error: StateError('temporary failure'),
      result: _result('재시도한 1등'),
    );
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = previousGameWinnerProvider(_key('western_duel'));

    await expectLater(container.read(provider.future), throwsStateError);
    repository.error = null;
    await Future<void>.delayed(Duration.zero);

    final retried = await container.read(provider.future);

    expect(retried?.leaders.single.nickname, '재시도한 1등');
    expect(repository.calls, 2);
  });

  test('계정 전환 시 family 전체를 무효화하면 다시 조회한다', () async {
    final repository = _PreviousWinnerRepository(result: _result('기존 계정 1등'));
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = previousGameWinnerProvider(_key('western_duel'));

    await container.read(provider.future);
    container.invalidate(previousGameWinnerProvider);
    repository.result = _result('새 계정 1등');

    final refreshed = await container.read(provider.future);

    expect(refreshed?.leaders.single.nickname, '새 계정 1등');
    expect(repository.calls, 2);
  });
}

({String gameId, DateTime beforeDate}) _key(
  String gameId, {
  DateTime? beforeDate,
}) => (gameId: gameId, beforeDate: beforeDate ?? DateTime(2026, 10, 13));

DailyRankResult _result(String nickname) => DailyRankResult(
  score: null,
  rank: null,
  participants: 1,
  topPercent: null,
  nickname: null,
  nearby: const [],
  leaders: [NearbyRank(rank: 1, nickname: nickname, score: 100, isMe: false)],
);

class _PreviousWinnerRepository extends PreviewDailyGameRepository {
  _PreviousWinnerRepository({this.result, this.error});

  DailyRankResult? result;
  Object? error;
  var calls = 0;

  @override
  Future<DailyRankResult?> fetchPreviousGameWinner({
    required String gameId,
    required DateTime beforeDate,
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}
