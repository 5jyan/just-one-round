import 'dart:convert';

import 'package:flutter/services.dart';

class GravityMapProfile {
  const GravityMapProfile({
    required this.floorTop,
    required this.ceilingBottom,
  });

  final double floorTop;
  final double ceilingBottom;
}

class GravityMapPattern {
  const GravityMapPattern({
    required this.id,
    required this.unlockAfterSeconds,
    required this.columns,
  });

  final String id;
  final double unlockAfterSeconds;
  final List<GravityMapProfile> columns;
}

class GravityMapLayout {
  const GravityMapLayout({
    required this.columnWidth,
    required this.initialProfile,
    required this.initialColumnCount,
    required this.patterns,
  });

  static const assetPath = 'assets/maps/gravity_switch_map.json';

  final double columnWidth;
  final GravityMapProfile initialProfile;
  final int initialColumnCount;
  final List<GravityMapPattern> patterns;

  static Future<GravityMapLayout> load() async =>
      fromJsonString(await rootBundle.loadString(assetPath));

  static GravityMapLayout fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Gravity map root must be a JSON object.');
    }
    final screenHeight = _positiveNumber(decoded, 'screenHeight');
    final columnWidth = _positiveNumber(decoded, 'columnWidth');
    final rawProfiles = decoded['profiles'];
    if (rawProfiles is! Map<String, dynamic> || rawProfiles.isEmpty) {
      throw const FormatException('Gravity map needs at least one profile.');
    }

    final profiles = <String, GravityMapProfile>{};
    for (final entry in rawProfiles.entries) {
      final raw = entry.value;
      if (raw is! Map<String, dynamic>) {
        throw FormatException('Profile "${entry.key}" must be an object.');
      }
      final floorHeight = _nonNegativeNumber(raw, 'floorHeight');
      final ceilingHeight = _nonNegativeNumber(raw, 'ceilingHeight');
      if (floorHeight + ceilingHeight >= screenHeight) {
        throw FormatException(
          'Profile "${entry.key}" leaves no open corridor.',
        );
      }
      profiles[entry.key] = GravityMapProfile(
        floorTop: screenHeight - floorHeight,
        ceilingBottom: ceilingHeight,
      );
    }

    final initialName = decoded['initialProfile'];
    final initialProfile = profiles[initialName];
    if (initialName is! String || initialProfile == null) {
      throw FormatException('Unknown initialProfile "$initialName".');
    }
    final initialColumnCount = decoded['initialColumnCount'];
    if (initialColumnCount is! int || initialColumnCount < 1) {
      throw const FormatException(
        'initialColumnCount must be a positive integer.',
      );
    }

    final rawPatterns = decoded['patterns'];
    if (rawPatterns is! List || rawPatterns.isEmpty) {
      throw const FormatException('Gravity map needs at least one pattern.');
    }
    final patterns = <GravityMapPattern>[];
    final ids = <String>{};
    for (final raw in rawPatterns) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Every pattern must be an object.');
      }
      final id = raw['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw FormatException('Pattern id "$id" is empty or duplicated.');
      }
      final unlock = _nonNegativeNumber(raw, 'unlockAfterSeconds');
      final rawColumns = raw['columns'];
      if (rawColumns is! List || rawColumns.isEmpty) {
        throw FormatException('Pattern "$id" needs at least one column.');
      }
      final columns = rawColumns
          .map((name) {
            final profile = profiles[name];
            if (name is! String || profile == null) {
              throw FormatException(
                'Pattern "$id" uses unknown profile "$name".',
              );
            }
            return profile;
          })
          .toList(growable: false);
      patterns.add(
        GravityMapPattern(id: id, unlockAfterSeconds: unlock, columns: columns),
      );
    }
    if (patterns.every((pattern) => pattern.unlockAfterSeconds > 0)) {
      throw const FormatException(
        'At least one pattern must unlock at 0 seconds.',
      );
    }

    return GravityMapLayout(
      columnWidth: columnWidth,
      initialProfile: initialProfile,
      initialColumnCount: initialColumnCount,
      patterns: patterns,
    );
  }

  static double _positiveNumber(Map<String, dynamic> json, String key) {
    final value = _nonNegativeNumber(json, key);
    if (value == 0) throw FormatException('$key must be greater than zero.');
    return value;
  }

  static double _nonNegativeNumber(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num || !value.isFinite || value < 0) {
      throw FormatException('$key must be a non-negative number.');
    }
    return value.toDouble();
  }
}
