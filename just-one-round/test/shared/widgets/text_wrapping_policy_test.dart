import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime UI text uses the project word-wrapping policy', () {
    final rawTextConstructors = <String>[];
    final clippingOverflow = <String>[];
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final relativePath = file.path.replaceFirst(
        '${Directory.current.path}/',
        '',
      );
      if (relativePath == 'lib/shared/widgets/word_safe_text.dart') continue;

      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (RegExp(r'\bText\s*\(').hasMatch(line)) {
          rawTextConstructors.add('$relativePath:${index + 1}');
        }
        if (RegExp(r'TextOverflow\.(ellipsis|clip|fade)\b').hasMatch(line)) {
          clippingOverflow.add('$relativePath:${index + 1}');
        }
      }
    }

    expect(
      rawTextConstructors,
      isEmpty,
      reason: 'Use WordSafeText for visible runtime text: $rawTextConstructors',
    );
    expect(
      clippingOverflow,
      isEmpty,
      reason: 'Do not clip visible text: $clippingOverflow',
    );
  });
}
