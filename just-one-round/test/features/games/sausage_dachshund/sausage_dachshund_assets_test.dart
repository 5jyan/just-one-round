import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('닥스훈트 런타임 에셋이 모두 존재한다', () {
    const names = [
      'dog_head_walk_atlas_v4.png',
      'dog_head_eat_atlas_v4.png',
      'dog_body_atlas_v4.png',
      'dog_tail_walk_atlas_v4.png',
      'sausage_idle_sheet.png',
      'bite_fx_sheet.png',
      'kitchen_background_v3.png',
    ];

    for (final name in names) {
      expect(
        File('assets/images/sausage_dachshund/$name').existsSync(),
        isTrue,
        reason: name,
      );
    }
  });
}
