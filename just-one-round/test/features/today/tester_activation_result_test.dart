import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';

void main() {
  test('테스터 활성화 성공 응답을 파싱한다', () {
    final result = TesterActivationResult.fromJson({'status': 'activated'});

    expect(result.status, TesterActivationStatus.activated);
  });

  test('잘못된 PIN과 잠금 응답의 남은 정보를 파싱한다', () {
    final invalid = TesterActivationResult.fromJson({
      'status': 'invalid',
      'attempts_remaining': 3,
    });
    final locked = TesterActivationResult.fromJson({
      'status': 'locked',
      'retry_after_seconds': 899,
    });

    expect(invalid.status, TesterActivationStatus.invalid);
    expect(invalid.attemptsRemaining, 3);
    expect(locked.status, TesterActivationStatus.locked);
    expect(locked.retryAfterSeconds, 899);
  });
}
