import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:just_one_round/features/duels/data/duel_result_retry.dart';

void main() {
  test('no-result duel submissions survive durable JSON round trip', () {
    const submission = DuelResultSubmission(
      matchId: 'match-1',
      runId: 'run-1',
      runToken: 'token-1',
      resultKind: 'no_result',
      rawScore: 0,
      durationMs: 60_000,
    );

    final restored = DuelResultSubmission.fromJson(submission.toJson());

    expect(restored.resultKind, 'no_result');
    expect(restored.rawScore, 0);
    expect(restored.key, 'match-1:run-1');
  });

  test(
    'retry service forwards no_result and removes it after success',
    () async {
      final repository = _RecordingDuelRepository();
      final store = _MemoryDuelResultStore();
      final service = DuelResultRetryService(repository, store);
      const submission = DuelResultSubmission(
        matchId: 'match-1',
        runId: 'run-1',
        runToken: 'token-1',
        resultKind: 'no_result',
        rawScore: 0,
        durationMs: 60_000,
      );

      await service.submit(submission);

      expect(repository.resultKind, 'no_result');
      expect(store.values, isEmpty);
    },
  );
}

class _RecordingDuelRepository extends NoopDuelRepository {
  String? resultKind;

  @override
  Future<void> submitDuelResult({
    required String matchId,
    required String runId,
    required String runToken,
    required int rawScore,
    required int durationMs,
    String resultKind = 'valid',
    int starsCollected = 0,
    int collisions = 0,
    List<int>? windDartsShotScores,
  }) async {
    this.resultKind = resultKind;
  }
}

class _MemoryDuelResultStore implements DuelResultStore {
  final values = <String, DuelResultSubmission>{};

  @override
  Future<List<DuelResultSubmission>> loadAll() async => values.values.toList();

  @override
  Future<void> save(DuelResultSubmission submission) async {
    values[submission.key] = submission;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
