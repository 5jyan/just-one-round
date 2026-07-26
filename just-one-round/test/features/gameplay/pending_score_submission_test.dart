import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';

void main() {
  test('완료 결과는 재시도에 필요한 값만 직렬화한다', () {
    final pending = PendingScoreSubmission.fromGameResult(
      'attempt-1',
      const GameResult(
        score: 800,
        starsCollected: 3,
        collisions: 2,
        duration: Duration(seconds: 60),
        endType: GameEndType.gameOver,
      ),
    );

    final restored = PendingScoreSubmission.fromJson(pending.toJson());

    expect(restored.attemptId, 'attempt-1');
    expect(restored.rawScore, 800);
    expect(restored.starsCollected, 3);
    expect(restored.collisions, 2);
    expect(restored.durationMs, 60000);
  });

  test('전송 실패한 결과는 서버 복구 뒤 재전송하고 성공 시 제거한다', () async {
    final store = _MemoryPendingScoreStore();
    final retry = PendingScoreRetryService<String>(store);
    const submission = PendingScoreSubmission(
      attemptId: 'attempt-1',
      rawScore: 800,
      starsCollected: 3,
      collisions: 2,
      durationMs: 60000,
    );

    await expectLater(
      retry.sendAndPersist(
        submission,
        (_) async => throw StateError('offline'),
      ),
      throwsStateError,
    );
    expect(store.value, submission);

    final result = await retry.retry((saved) async {
      expect(saved, submission);
      return 'ranked';
    });

    expect(result, 'ranked');
    expect(store.value, isNull);
  });

  test('제출 마감이 지난 결과는 더 이상 재시도하지 않는다', () async {
    final store = _MemoryPendingScoreStore();
    final retry = PendingScoreRetryService<String>(store);
    const submission = PendingScoreSubmission(
      attemptId: 'attempt-expired',
      rawScore: 800,
      starsCollected: 3,
      collisions: 2,
      durationMs: 60000,
    );
    await store.save(submission);

    final result = await retry.retry(
      (_) async => throw StateError('score submission window closed'),
      discardWhen: (error) => error.toString().contains('window closed'),
    );

    expect(result, isNull);
    expect(store.value, isNull);
  });
}

class _MemoryPendingScoreStore implements PendingScoreStore {
  PendingScoreSubmission? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<PendingScoreSubmission?> load() async => value;

  @override
  Future<void> save(PendingScoreSubmission submission) async {
    value = submission;
  }
}
