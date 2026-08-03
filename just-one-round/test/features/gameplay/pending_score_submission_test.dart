import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('이미 저장한 결과는 중복 저장 없이 전송하고 성공 후 제거한다', () async {
    final store = _MemoryPendingScoreStore();
    final retry = PendingScoreRetryService<String>(store);
    const submission = PendingScoreSubmission(
      attemptId: 'attempt-persisted',
      rawScore: 500,
      starsCollected: 0,
      collisions: 0,
      durationMs: 50000,
    );
    await store.save(submission);
    final savesBeforeSend = store.saveCount;

    final result = await retry.sendPersisted(submission, (_) async => 'ranked');

    expect(result, 'ranked');
    expect(store.saveCount, savesBeforeSend);
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

  test('서버가 영구 거절한 결과만 보류 저장소에서 제거한다', () {
    expect(
      isTerminalScoreSubmissionError(
        const PostgrestException(message: 'attempt expired'),
      ),
      isTrue,
    );
    expect(
      isTerminalScoreSubmissionError(
        const PostgrestException(message: 'invalid midnight snake result'),
      ),
      isTrue,
    );
    expect(
      isTerminalScoreSubmissionError(
        const PostgrestException(message: 'connection reset'),
      ),
      isFalse,
    );
  });

  test('보류 점수 복구 성공 직후 서버 상태를 다시 읽는다', () async {
    var refreshCount = 0;
    final refreshed = await refreshStateAfterPendingRetry<String, String>(
      currentState: 'before-submit',
      retry: () async => 'ranked',
      refresh: () async {
        refreshCount += 1;
        return 'after-submit';
      },
    );

    expect(refreshed, 'after-submit');
    expect(refreshCount, 1);
  });

  test('보류 점수가 없거나 복구되지 않으면 불필요하게 다시 읽지 않는다', () async {
    var refreshCount = 0;
    final unchanged = await refreshStateAfterPendingRetry<String, String>(
      currentState: 'current',
      retry: () async => null,
      refresh: () async {
        refreshCount += 1;
        return 'unexpected';
      },
    );

    expect(unchanged, 'current');
    expect(refreshCount, 0);
  });

  test('영구 거절로 보류 값이 사라지면 같은 새로고침에서 시도를 만료한다', () {
    final state = TodayState(
      playDate: DateTime(2026, 8, 1),
      game: null,
      attempts: [
        PlayAttempt(
          id: 'terminal-attempt',
          ordinal: 1,
          status: 'issued',
          grantType: 'daily',
          issuedAt: DateTime.utc(2026, 8, 1),
          gameDurationSeconds: 300,
        ),
      ],
      adAttemptAvailable: false,
      testMode: false,
      result: null,
      nickname: null,
    );

    expect(
      issuedAttemptsWithoutPending(
        state,
        const {},
        now: DateTime.utc(2026, 8, 1, 0, 8),
      ),
      hasLength(1),
    );
    expect(
      issuedAttemptsWithoutPending(state, const {'terminal-attempt'}),
      isEmpty,
    );
  });

  test('최근 발급된 시도는 상태 새로고침 중 만료하지 않는다', () {
    final state = TodayState(
      playDate: DateTime(2026, 8, 1),
      game: null,
      attempts: [
        PlayAttempt(
          id: 'active-attempt',
          ordinal: 2,
          status: 'issued',
          grantType: 'rewarded_ad',
          issuedAt: DateTime.utc(2026, 8, 1),
          gameDurationSeconds: 300,
        ),
      ],
      adAttemptAvailable: false,
      testMode: false,
      result: null,
      nickname: null,
    );

    expect(
      issuedAttemptsWithoutPending(
        state,
        const {},
        now: DateTime.utc(2026, 8, 1, 0, 1),
      ),
      isEmpty,
    );
  });

  test('먼저 보낸 결과의 성공 콜백은 나중에 저장된 결과를 지우지 않는다', () async {
    final store = _MemoryPendingScoreStore();
    final retry = PendingScoreRetryService<String>(store);
    final sendStarted = Completer<void>();
    final finishSend = Completer<void>();
    const first = PendingScoreSubmission(
      attemptId: 'attempt-a',
      rawScore: 100,
      starsCollected: 0,
      collisions: 0,
      durationMs: 1000,
    );
    const second = PendingScoreSubmission(
      attemptId: 'attempt-b',
      rawScore: 200,
      starsCollected: 0,
      collisions: 0,
      durationMs: 2000,
    );
    await store.save(first);

    final sending = retry.sendPersisted(first, (_) async {
      sendStarted.complete();
      await finishSend.future;
      return 'ranked-a';
    });
    await sendStarted.future;
    await store.save(second);
    finishSend.complete();

    expect(await sending, 'ranked-a');
    expect((await store.loadAll()).map((item) => item.attemptId), [
      'attempt-b',
    ]);
  });

  test('저장된 점수 여러 개를 각각 재전송하고 성공한 항목만 제거한다', () async {
    final store = _MemoryPendingScoreStore();
    final retry = PendingScoreRetryService<String>(store);
    await store.save(_submission('attempt-a'));
    await store.save(_submission('attempt-b'));
    await store.save(_submission('attempt-c'));

    final result = await retry.retry((submission) async {
      if (submission.attemptId == 'attempt-b') {
        throw StateError('offline');
      }
      return submission.attemptId;
    });

    expect(result, 'attempt-c');
    expect((await store.loadAll()).map((item) => item.attemptId), [
      'attempt-b',
    ]);
  });

  test('기존 v1 단일 저장값을 v2 큐로 손실 없이 이전한다', () async {
    SharedPreferences.setMockInitialValues({
      'pending_score_submission_v1': jsonEncode(_submission('legacy')),
    });
    final store = SharedPreferencesPendingScoreStore();

    final restored = await store.loadAll();

    expect(restored.single.attemptId, 'legacy');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('pending_score_submission_v1'), isNull);
    expect(preferences.getString('pending_score_submissions_v2'), isNotNull);
  });

  test('v1 복구 전에 새 점수가 저장돼도 두 결과를 모두 보존한다', () async {
    SharedPreferences.setMockInitialValues({
      'pending_score_submission_v1': jsonEncode(_submission('legacy')),
    });
    final store = SharedPreferencesPendingScoreStore();

    await store.save(_submission('new'));

    expect((await store.loadAll()).map((item) => item.attemptId), [
      'legacy',
      'new',
    ]);
  });
}

PendingScoreSubmission _submission(String attemptId) => PendingScoreSubmission(
  attemptId: attemptId,
  rawScore: 100,
  starsCollected: 0,
  collisions: 0,
  durationMs: 1000,
);

class _MemoryPendingScoreStore implements PendingScoreStore {
  final values = <PendingScoreSubmission>[];
  var saveCount = 0;

  PendingScoreSubmission? get value => values.isEmpty ? null : values.first;

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<PendingScoreSubmission?> load() async => value;

  @override
  Future<List<PendingScoreSubmission>> loadAll() async => List.of(values);

  @override
  Future<void> remove(String attemptId) async {
    values.removeWhere((item) => item.attemptId == attemptId);
  }

  @override
  Future<void> save(PendingScoreSubmission submission) async {
    saveCount += 1;
    final index = values.indexWhere(
      (item) => item.attemptId == submission.attemptId,
    );
    if (index < 0) {
      values.add(submission);
    } else {
      values[index] = submission;
    }
  }
}
