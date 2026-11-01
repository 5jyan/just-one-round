import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// The HTTP test client is supplied transitively by Supabase's public client.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'Firebase Test Lab clients do not send social actions or gifts',
    () async {
      final requests = <String>[];
      final repository = SupabaseDailyGameRepository(
        SupabaseClient(
          'http://supabase.test',
          'test-key',
          httpClient: MockClient((request) async {
            requests.add(request.url.toString());
            return http.Response('{}', 200, request: request);
          }),
        ),
        isFirebaseTestLab: true,
      );

      await repository.sendSocialAction(
        targetUserId: 'recipient',
        action: 'poke',
      );
      await repository.giftShopItem(
        targetUserId: 'recipient',
        itemId: 'challenge_ticket',
      );

      expect(requests, isEmpty);
    },
  );

  test('regular clients still send social actions and gifts', () async {
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
          rpcNames.add(request.url.path.split('/').last);
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
      deviceHashLoader: () async => 'test-device-hash',
    );

    await repository.sendSocialAction(
      targetUserId: 'recipient',
      action: 'poke',
    );
    await repository.giftShopItem(
      targetUserId: 'recipient',
      itemId: 'challenge_ticket',
    );

    expect(
      rpcNames,
      containsAll(<String>[
        'register_device_installation',
        'send_social_action',
        'gift_shop_item',
      ]),
    );
  });
}
