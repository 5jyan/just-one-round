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
    final cellSize = _positiveNumber(decoded, 'cellSize');
    final baseCeilingHeight = _nonNegativeNumber(decoded, 'baseCeilingHeight');
    final baseFloorHeight = _nonNegativeNumber(decoded, 'baseFloorHeight');
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
    int? gridHeight;
    for (final raw in rawPatterns) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Every pattern must be an object.');
      }
      final id = raw['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        throw FormatException('Pattern id "$id" is empty or duplicated.');
      }
      final unlock = _nonNegativeNumber(raw, 'unlockAfterSeconds');
      final rawGrid = raw['grid'];
      if (rawGrid is! List || rawGrid.isEmpty) {
        throw FormatException('Pattern "$id" needs a non-empty grid.');
      }
      gridHeight ??= rawGrid.length;
      if (rawGrid.length != gridHeight) {
        throw FormatException('Pattern "$id" must have $gridHeight grid rows.');
      }
      patterns.add(
        GravityMapPattern(
          id: id,
          unlockAfterSeconds: unlock,
          columns: _parseGrid(
            rawGrid,
            patternId: id,
            cellSize: cellSize,
            baseCeilingHeight: baseCeilingHeight,
            baseFloorHeight: baseFloorHeight,
          ),
        ),
      );
    }
    if (patterns.every((pattern) => pattern.unlockAfterSeconds > 0)) {
      throw const FormatException(
        'At least one pattern must unlock at 0 seconds.',
      );
    }

    return GravityMapLayout(
      columnWidth: cellSize,
      initialProfile: GravityMapProfile(
        floorTop: baseCeilingHeight + (gridHeight! * cellSize),
        ceilingBottom: baseCeilingHeight,
      ),
      initialColumnCount: initialColumnCount,
      patterns: patterns,
    );
  }

  static List<GravityMapProfile> _parseGrid(
    List<dynamic> rawGrid, {
    required String patternId,
    required double cellSize,
    required double baseCeilingHeight,
    required double baseFloorHeight,
  }) {
    if (rawGrid.any((row) => row is! String)) {
      throw FormatException('Pattern "$patternId" grid rows must be strings.');
    }
    final rows = rawGrid.cast<String>();
    final width = rows.first.runes.length;
    if (width == 0 || rows.any((row) => row.runes.length != width)) {
      throw FormatException(
        'Pattern "$patternId" grid rows must have equal width.',
      );
    }
    const wall = 'ㅁ';
    const empty = 'ㅇ';
    if (rows.any(
      (row) => row.runes
          .map(String.fromCharCode)
          .any((symbol) => symbol != wall && symbol != empty),
    )) {
      throw FormatException('Pattern "$patternId" grid may only use ㅁ and ㅇ.');
    }

    final screenHeight =
        baseCeilingHeight + (rows.length * cellSize) + baseFloorHeight;
    return List.generate(width, (column) {
      final cells = rows
          .map((row) => String.fromCharCode(row.runes.elementAt(column)))
          .toList(growable: false);
      var topWalls = 0;
      while (topWalls < cells.length && cells[topWalls] == wall) {
        topWalls++;
      }
      var bottomWalls = 0;
      while (bottomWalls < cells.length - topWalls &&
          cells[cells.length - 1 - bottomWalls] == wall) {
        bottomWalls++;
      }
      if (topWalls + bottomWalls == cells.length ||
          cells.sublist(topWalls, cells.length - bottomWalls).contains(wall)) {
        throw FormatException(
          'Pattern "$patternId" column ${column + 1} has a floating wall or no open corridor.',
        );
      }
      return GravityMapProfile(
        floorTop: screenHeight - baseFloorHeight - (bottomWalls * cellSize),
        ceilingBottom: baseCeilingHeight + (topWalls * cellSize),
      );
    }, growable: false);
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
