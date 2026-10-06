import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/pending_play_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('재실행해도 같은 날의 연습 요청 ID를 복구한다', () async {
    SharedPreferences.setMockInitialValues({});
    final firstStore = SharedPreferencesPendingPlayRequestStore();
    final playDate = DateTime(2026, 8, 14);

    await firstStore.save(playDate, 'aaaaaaaa-0000-4000-8000-000000000001');

    final restartedStore = SharedPreferencesPendingPlayRequestStore();
    expect(
      await restartedStore.load(playDate),
      'aaaaaaaa-0000-4000-8000-000000000001',
    );
  });

  test('실제 시작 후에만 저장된 요청 ID를 제거한다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPendingPlayRequestStore();
    final playDate = DateTime(2026, 8, 14);
    const requestId = 'bbbbbbbb-0000-4000-8000-000000000001';

    await store.save(playDate, requestId);
    await store.remove(playDate, 'bbbbbbbb-0000-4000-8000-000000000002');
    expect(await store.load(playDate), requestId);

    await store.remove(playDate, requestId);
    expect(await store.load(playDate), isNull);
  });

  test('날짜가 바뀌면 이전 요청 ID를 폐기한다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPendingPlayRequestStore();
    await store.save(
      DateTime(2026, 8, 14),
      'cccccccc-0000-4000-8000-000000000001',
    );

    expect(await store.load(DateTime(2026, 8, 15)), isNull);
  });
}
