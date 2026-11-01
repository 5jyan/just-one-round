import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/reviews/app_review_service.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 10, 12, 3);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('처음에는 서로 다른 완료일 3개가 모일 때까지 요청하지 않는다', () async {
    final client = _RecordingReviewClient();
    final service = _service(client);

    service.markPending();
    await service.consumePending(
      fetchHistory: () async => _history('2026-10-10', '2026-10-09'),
      canRequest: () => true,
    );
    expect(client.requestCalls, 0);
    expect(service.hasPendingRequest, isFalse);

    service.markPending();
    await service.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    expect(client.requestCalls, 1);
  });

  test('같은 날짜의 중복 기록은 한 번으로 센다', () async {
    final client = _RecordingReviewClient();
    final service = _service(client);
    service.markPending();

    await service.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-10', '2026-10-09'),
      canRequest: () => true,
    );

    expect(client.requestCalls, 0);
    service.markPending();
    await service.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );

    expect(client.requestCalls, 1);
  });

  test('90일 전에는 기다리고 90일 경계에서는 요청한다', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppReviewService.lastRequestedAtStorageKey,
      now.subtract(const Duration(days: 90)).toIso8601String(),
    );

    final client = _RecordingReviewClient();
    final service = _service(client);
    service.markPending();
    await service.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    expect(client.requestCalls, 1);

    SharedPreferences.setMockInitialValues({
      AppReviewService.lastRequestedAtStorageKey: now
          .subtract(const Duration(days: 89, hours: 23))
          .toIso8601String(),
    });
    final beforeBoundaryClient = _RecordingReviewClient();
    final beforeBoundaryService = _service(beforeBoundaryClient);
    beforeBoundaryService.markPending();
    await beforeBoundaryService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    expect(beforeBoundaryClient.requestCalls, 0);
  });

  test('저장한 마지막 요청 시각은 서비스 재생성 후에도 유지된다', () async {
    final firstClient = _RecordingReviewClient();
    final firstService = _service(firstClient);
    firstService.markPending();
    await firstService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );

    final restartedClient = _RecordingReviewClient();
    final restartedService = AppReviewService(
      client: restartedClient,
      preferences: SharedPreferences.getInstance(),
      now: () => now.add(const Duration(days: 89)),
    )..markPending();
    await restartedService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );

    expect(restartedClient.requestCalls, 0);
  });

  test('스토어 미지원이나 네이티브 오류는 기록하지 않는다', () async {
    final unavailableClient = _RecordingReviewClient(available: false);
    final unavailableService = _service(unavailableClient)..markPending();
    await unavailableService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    var preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppReviewService.lastRequestedAtStorageKey),
      isNull,
    );
    expect(unavailableService.hasPendingRequest, isFalse);

    SharedPreferences.setMockInitialValues({});
    final throwingClient = _RecordingReviewClient(throwOnAvailability: true);
    final throwingService = _service(throwingClient)..markPending();
    await throwingService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppReviewService.lastRequestedAtStorageKey),
      isNull,
    );
    expect(throwingService.hasPendingRequest, isFalse);

    SharedPreferences.setMockInitialValues({});
    final requestThrowingClient = _RecordingReviewClient(throwOnRequest: true);
    final requestThrowingService = _service(requestThrowingClient)
      ..markPending();
    await requestThrowingService.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppReviewService.lastRequestedAtStorageKey),
      isNull,
    );
  });

  test('동시 소비는 네이티브 요청을 한 번만 실행한다', () async {
    final client = _RecordingReviewClient();
    final service = _service(client);
    service.markPending();
    final historyCompleter = Completer<List<PlayHistoryEntry>>();

    final first = service.consumePending(
      fetchHistory: () => historyCompleter.future,
      canRequest: () => true,
    );
    final second = service.consumePending(
      fetchHistory: () async =>
          _history('2026-10-10', '2026-10-09', '2026-10-08'),
      canRequest: () => true,
    );
    expect(identical(first, second), isTrue);

    historyCompleter.complete(
      _history('2026-10-10', '2026-10-09', '2026-10-08'),
    );
    await first;
    expect(client.requestCalls, 1);
  });

  test('기록을 읽는 중 홈을 떠나면 요청하지 않고 보류를 유지한다', () async {
    final client = _RecordingReviewClient();
    final service = _service(client);
    service.markPending();
    final historyCompleter = Completer<List<PlayHistoryEntry>>();
    final historyStarted = Completer<void>();
    var canRequest = true;

    final consume = service.consumePending(
      fetchHistory: () {
        historyStarted.complete();
        return historyCompleter.future;
      },
      canRequest: () => canRequest,
    );
    await historyStarted.future;
    canRequest = false;
    historyCompleter.complete(
      _history('2026-10-10', '2026-10-09', '2026-10-08'),
    );
    await consume;

    expect(client.requestCalls, 0);
    expect(service.hasPendingRequest, isTrue);
  });
}

AppReviewService _service(_RecordingReviewClient client) => AppReviewService(
  client: client,
  preferences: SharedPreferences.getInstance(),
  now: () => DateTime.utc(2026, 10, 12, 3),
);

List<PlayHistoryEntry> _history(
  String first,
  String second, [
  String? third,
  String? fourth,
]) => [
  for (final date in [first, second, ?third, ?fourth])
    PlayHistoryEntry(
      playDate: DateTime.parse(date),
      gameId: 'dung_dodge_v2',
      displayName: '똥피하기',
      score: 100,
      rank: 1,
      participants: 1,
    ),
];

class _RecordingReviewClient implements AppReviewClient {
  _RecordingReviewClient({
    this.available = true,
    this.throwOnAvailability = false,
    this.throwOnRequest = false,
  });

  final bool available;
  final bool throwOnAvailability;
  final bool throwOnRequest;
  var availabilityCalls = 0;
  var requestCalls = 0;

  @override
  Future<bool> isAvailable() async {
    availabilityCalls++;
    if (throwOnAvailability) throw StateError('availability failed');
    return available;
  }

  @override
  Future<void> requestReview() async {
    requestCalls++;
    if (throwOnRequest) throw StateError('native review failed');
  }
}
