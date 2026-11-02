import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/duels/presentation/duel_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('hides raw test-account PostgREST errors', () {
    final error = PostgrestException(
      message: 'duels unavailable for test accounts',
      code: 'P0001',
      details: 'feature gate',
    );

    expect(duelFriendlyError(error), '테스트 계정에서는 1:1 대결을 이용할 수 없어요.');
    expect(duelFriendlyError(error), isNot(contains('P0001')));
    expect(duelFriendlyError(error), isNot(contains('duels unavailable')));
  });

  test('maps known server failures and preserves local user errors', () {
    expect(
      duelFriendlyError(
        const PostgrestException(message: 'duel maintenance is unavailable'),
      ),
      '지금은 대결을 시작할 수 없어요. 잠시 후 다시 시도해 주세요.',
    );
    expect(
      duelFriendlyError(
        const PostgrestException(
          message: 'insufficient coin balance',
          code: 'P0001',
        ),
      ),
      '코인이 부족해서 대결을 시작할 수 없어요.',
    );
    expect(
      duelFriendlyError(StateError('대결 서버에 연결할 수 없어요.')),
      '대결 서버에 연결할 수 없어요.',
    );
  });

  test('does not expose unknown server exception details', () {
    const error = PostgrestException(
      message: 'internal duel trigger failed',
      code: 'XX999',
      details: 'private database detail',
      hint: 'do not show this',
    );

    final message = duelFriendlyError(error);
    expect(message, '대결 서버와 통신하지 못했어요. 잠시 후 다시 시도해 주세요.');
    expect(message, isNot(contains('internal duel')));
    expect(message, isNot(contains('private database')));
  });
}
