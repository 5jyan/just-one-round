import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/social/domain/social_notification.dart';

void main() {
  test('찌르기 문구는 짧고 재치 있게 반응을 유도한다', () {
    final notification = SocialNotification(
      id: 'poke',
      actionType: 'poke',
      senderNickname: '장난꾸러기',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(notification.message, '장난꾸러기님이 콕 찔렀어요. 이건 못 참죠?');
  });

  test('자랑 문구는 기록·등수만 한 문장으로 보여준다', () {
    final notification = SocialNotification(
      id: 'notice',
      actionType: 'boast',
      senderNickname: '금빛고래',
      senderRank: 3,
      senderScore: 987,
      senderGameId: 'apple_game_v2',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(notification.message, '금빛고래님은 기록이 987개로 오늘 3등으로 자랑했어요.');
  });

  test('자랑 문구는 센티미터 점수를 미터로 변환한다', () {
    final notification = SocialNotification(
      id: 'meter-notice',
      actionType: 'boast',
      senderNickname: '홈런왕',
      senderRank: 1,
      senderScore: 10465,
      senderGameId: 'ten_pitch_slugger',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(notification.message, '홈런왕님은 기록이 104.65m로 오늘 1등으로 자랑했어요.');
  });

  test('자랑 문구는 딱 한 발 점수를 소수 셋째 자리 초로 변환한다', () {
    final notification = SocialNotification(
      id: 'western-notice',
      actionType: 'boast',
      senderNickname: '총잡이',
      senderRank: 1,
      senderScore: 999650,
      senderGameId: 'western_duel',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(notification.message, '총잡이님은 기록이 0.350초로 오늘 1등으로 자랑했어요.');
  });

  test('자랑 문구는 두더지 점수를 밀리초로 변환한다', () {
    final notification = SocialNotification(
      id: 'mole-notice',
      actionType: 'boast',
      senderNickname: '두더지왕',
      senderRank: 2,
      senderScore: 999650,
      senderGameId: 'mole_reaction',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(notification.message, '두더지왕님은 기록이 350ms로 오늘 2등으로 자랑했어요.');
  });

  test('이전 알림도 새 점수 필드가 없어도 읽을 수 있다', () {
    final notification = SocialNotification.fromJson({
      'id': 'legacy',
      'action_type': 'boast',
      'sender_nickname': '옛친구',
      'sender_rank': 8,
      'created_at': '2026-08-21T00:00:00Z',
    });

    expect(notification.message, '옛친구님은 기록이 -로 오늘 8등으로 자랑했어요.');
  });
}
