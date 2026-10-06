import 'package:flutter/material.dart';

/// Text that never clips a word at the edge of its available width.
///
/// Text with spaces is laid out as whole words, so Korean endings do not get
/// stranded on a line by themselves. A single word that is wider than the
/// available box is allowed to wrap by glyph instead of being clipped. Use
/// [singleLine] only for values that are deliberately constrained by a
/// surrounding scale-down layout, such as a score HUD or button label.
class WordSafeText extends Text {
  const WordSafeText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.singleLine = false,
  });

  /// Opt into the native one-line behavior for intentionally compact values.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final value = data!;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = style == null || style!.inherit
        ? defaultStyle.merge(style)
        : style!;
    final effectiveDirection = textDirection ?? Directionality.of(context);
    final effectiveScaler = textScaler ?? MediaQuery.textScalerOf(context);
    if (singleLine) return super.build(context);

    final alignment = switch (textAlign) {
      TextAlign.center => WrapAlignment.center,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.start,
    };

    final spacePainter = TextPainter(
      text: TextSpan(text: ' ', style: effectiveStyle),
      textDirection: effectiveDirection,
      textScaler: effectiveScaler,
      locale: locale,
    )..layout();

    Widget buildWord(String word) {
      // Wrap keeps a normal word together. RichText still receives the
      // parent's width constraint, so an oversized word can wrap by glyph
      // instead of escaping or being clipped at the edge.
      final breakableWord = word.characters.join('\u200B');
      return RichText(
        text: TextSpan(text: breakableWord, style: effectiveStyle),
        textAlign: textAlign ?? TextAlign.start,
        textDirection: effectiveDirection,
        locale: locale,
        strutStyle: strutStyle,
        softWrap: true,
        overflow: TextOverflow.visible,
        textScaler: effectiveScaler,
        maxLines: null,
        textWidthBasis: textWidthBasis ?? TextWidthBasis.longestLine,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }

    Widget buildLine(String line) {
      final words = RegExp(r'\S+')
          .allMatches(line)
          .map((match) => match.group(0)!)
          .toList(growable: false);
      if (words.isEmpty) {
        return const SizedBox(height: 1);
      }
      return Wrap(
        alignment: alignment,
        textDirection: effectiveDirection,
        spacing: spacePainter.width,
        children: [for (final word in words) buildWord(word)],
      );
    }

    final lines = value.split('\n');
    final child = lines.length == 1
        ? buildLine(lines.single)
        : Column(
            crossAxisAlignment: switch (alignment) {
              WrapAlignment.center => CrossAxisAlignment.center,
              WrapAlignment.end => CrossAxisAlignment.end,
              _ => CrossAxisAlignment.start,
            },
            children: [for (final line in lines) buildLine(line)],
          );
    return Semantics(
      label: semanticsLabel ?? value,
      child: ExcludeSemantics(child: child),
    );
  }
}
