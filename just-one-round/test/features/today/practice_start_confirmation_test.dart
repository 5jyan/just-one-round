import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// The HTTP test client is supplied transitively by Supabase's public client.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/data/pending_play_request.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'specialized start RPCs clear only a valid, successful practice start',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesPendingPlayRequestStore();
      final playDate = DateTime(2026, 8, 14);
      const westernRequestId = 'aaaaaaaa-0000-4000-8000-000000000001';
      const windRequestId = 'bbbbbbbb-0000-4000-8000-000000000001';
      var westernResponseValid = false;
      final rpcNames = <String>[];
      final client = SupabaseClient(
        'http://supabase.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/v1/signup')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-access-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'test-refresh-token',
                'user': {
                  'id': 'test-user',
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': null,
                  'created_at': '2026-01-01T00:00:00Z',
                  'app_metadata': <String, dynamic>{},
                  'user_metadata': <String, dynamic>{},
                  'is_anonymous': true,
                },
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.contains('/rest/v1/rpc/')) {
            final name = request.url.path.split('/').last;
            rpcNames.add(name);
            if (name == 'confirm_western_duel_started') {
              if (!westernResponseValid) {
                return http.Response(
                  jsonEncode({'nickname': '맥크리', 'is_bot': true}),
                  200,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response(
                jsonEncode({
                  'nickname': '맥크리',
                  'reaction_ms': 440,
                  'is_bot': true,
                }),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (name == 'confirm_wind_darts_started') {
              return http.Response(
                jsonEncode({
                  'nickname': '서부의 단골',
                  'shot_scores': [7, 19, 10, 20, 6, 9, 22],
                  'is_bot': true,
                }),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{}',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repository = SupabaseDailyGameRepository(
        client,
        pendingPlayRequestStore: store,
        deviceHashLoader: () async => 'test-device-hash',
      );

      await store.save(playDate, westernRequestId);
      final westernAttempt = _attempt(
        id: 'western-attempt',
        gameId: 'western_duel',
        gameVersion: 1,
        playDate: playDate,
        requestId: westernRequestId,
      );
      await expectLater(
        repository.confirmWesternDuelStarted(westernAttempt),
        throwsA(anything),
      );
      expect(await store.load(playDate), westernRequestId);

      westernResponseValid = true;
      final westernOpponent = await repository.confirmWesternDuelStarted(
        westernAttempt,
      );
      expect(westernOpponent.reactionMilliseconds, 440);
      expect(await store.load(playDate), isNull);

      await store.save(playDate, windRequestId);
      final windOpponent = await repository.confirmWindDartsStarted(
        _attempt(
          id: 'wind-attempt',
          gameId: 'wind_darts',
          gameVersion: 4,
          playDate: playDate,
          requestId: windRequestId,
        ),
      );
      expect(windOpponent, isA<WindDartsOpponent>());
      expect(windOpponent.shotScores, hasLength(7));
      expect(await store.load(playDate), isNull);

      // Preview practice charges today's balance but the issued attempt is for
      // tomorrow's game. Cleanup must use the attempt's target play date.
      final targetPlayDate = playDate.add(const Duration(days: 1));
      const previewRequestId = 'dddddddd-0000-4000-8000-000000000001';
      await store.save(targetPlayDate, previewRequestId);
      await repository.confirmWindDartsStarted(
        _attempt(
          id: 'wind-preview-attempt',
          gameId: 'wind_darts',
          gameVersion: 4,
          playDate: targetPlayDate,
          requestId: previewRequestId,
        ),
      );
      expect(await store.load(targetPlayDate), isNull);

      const genericRequestId = 'eeeeeeee-0000-4000-8000-000000000001';
      await store.save(playDate, genericRequestId);
      await repository.confirmPlayStarted(
        _attempt(
          id: 'generic-attempt',
          gameId: 'dung_dodge_v2',
          gameVersion: 1,
          playDate: playDate,
          requestId: genericRequestId,
        ),
      );
      expect(await store.load(playDate), isNull);

      expect(
        rpcNames,
        containsAll(<String>[
          'register_device_installation',
          'confirm_western_duel_started',
          'confirm_wind_darts_started',
        ]),
      );
    },
  );

  test('authoritative no-pending state replaces an old request ID', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPendingPlayRequestStore();
    final playDate = DateTime(2026, 8, 14);
    const staleRequestId = 'cccccccc-0000-4000-8000-000000000001';
    await store.save(playDate, staleRequestId);

    final repository = _RequestIdRepository(store);
    final reused = await repository.getOrCreatePracticeRequestId(playDate);
    expect(reused, staleRequestId);

    final fresh = await repository.getOrCreatePracticeRequestId(
      playDate,
      reuseExisting: false,
    );
    expect(fresh, isNot(staleRequestId));
    expect(await store.load(playDate), fresh);
  });
}

PlayAttempt _attempt({
  required String id,
  required String gameId,
  required int gameVersion,
  required DateTime playDate,
  required String requestId,
}) => PlayAttempt(
  id: id,
  ordinal: 1,
  status: 'practice',
  grantType: 'practice_daily',
  gameId: gameId,
  gameVersion: gameVersion,
  gameDurationSeconds: 300,
  playDate: playDate,
  clientRequestId: requestId,
);

class _RequestIdRepository implements DailyPracticeRepository {
  _RequestIdRepository(this.store);

  final PendingPlayRequestStore store;

  @override
  Future<String> getOrCreatePracticeRequestId(
    DateTime expectedPlayDate, {
    bool reuseExisting = true,
  }) async {
    if (reuseExisting) {
      final saved = await store.load(expectedPlayDate);
      if (saved != null) return saved;
    }
    final requestId = 'fresh-${DateTime.now().microsecondsSinceEpoch}';
    await store.save(expectedPlayDate, requestId);
    return requestId;
  }

  @override
  Future<PlayAttempt> claimDailyPractice(
    DateTime expectedPlayDate, {
    required String requestId,
    DateTime? gameDate,
  }) => throw UnimplementedError();
}
