import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('arcade v2 runtime atlases keep the approved cell contracts', () {
    final buttons = _pngSize(
      File('assets/images/number_rush/number_button_states.png'),
    );
    final effects = _pngSize(
      File('assets/images/number_rush/arcade_fx_sheet.png'),
    );
    final homeHero = _pngSize(
      File('assets/images/number_rush/home_gameplay_hero.png'),
    );

    expect(buttons, (56 * 3, 56 * 2));
    expect(effects, (64 * 4, 64 * 2));
    expect(homeHero, (1206, 1546));
  });
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24));
  expect(bytes.sublist(1, 4), [80, 78, 71]);
  final data = bytes.buffer.asByteData();
  return (data.getUint32(16), data.getUint32(20));
}
