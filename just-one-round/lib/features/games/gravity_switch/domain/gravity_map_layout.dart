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

  bool isAvailableAt(double elapsedSeconds) {
    final tokens = id.split('_');
    if (tokens.contains('easy') && elapsedSeconds >= 30) return false;
    if (tokens.contains('hard') && elapsedSeconds < 30) return false;
    return unlockAfterSeconds <= elapsedSeconds;
  }
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

  static Future<GravityMapLayout> load() async {
    final source = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['patterns'] is! List) {
      throw const FormatException('Gravity map needs a patterns list.');
    }
    final mapFiles = <String, String>{};
    for (final raw in decoded['patterns'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final mapFile = raw['mapFile'];
      if (mapFile is String && !mapFiles.containsKey(mapFile)) {
        _validateMapFilePath(mapFile);
        mapFiles[mapFile] = await rootBundle.loadString('assets/maps/$mapFile');
      }
    }
    return fromJsonString(source, mapFiles: mapFiles);
  }

  static GravityMapLayout fromJsonString(
    String source, {
    required Map<String, String> mapFiles,
  }) {
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
      final mapFile = raw['mapFile'];
      if (mapFile is! String || mapFile.isEmpty) {
        throw FormatException('Pattern "$id" needs a mapFile.');
      }
      _validateMapFilePath(mapFile);
      final mapSource = mapFiles[mapFile];
      if (mapSource == null) {
        throw FormatException('Pattern "$id" map file "$mapFile" is missing.');
      }
      final grid = _readMapRows(mapSource, patternId: id);
      gridHeight ??= grid.length;
      if (grid.length != gridHeight) {
        throw FormatException('Pattern "$id" must have $gridHeight grid rows.');
      }
      patterns.add(
        GravityMapPattern(
          id: id,
          unlockAfterSeconds: unlock,
          columns: _parseGrid(
            grid,
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
      initialProfile: patterns.first.columns.first,
      initialColumnCount: initialColumnCount,
      patterns: patterns,
    );
  }

  static List<String> _readMapRows(String source, {required String patternId}) {
    final rows = source.replaceAll('\r\n', '\n').split('\n');
    if (rows.isNotEmpty && rows.last.isEmpty) rows.removeLast();
    if (rows.isEmpty) {
      throw FormatException('Pattern "$patternId" map file is empty.');
    }
    final bounded = rows.every(
      (row) => row.startsWith('|') && row.endsWith('|'),
    );
    final hasPartialBoundary = rows.any(
      (row) => row.startsWith('|') || row.endsWith('|'),
    );
    if (!bounded && hasPartialBoundary) {
      throw FormatException(
        'Pattern "$patternId" must use | on both sides of every row.',
      );
    }
    return bounded
        ? rows.map((row) => row.substring(1, row.length - 1)).toList()
        : rows;
  }

  static void _validateMapFilePath(String path) {
    if (path.startsWith('/') ||
        path.contains('..') ||
        path.contains(r'\') ||
        !path.endsWith('.map')) {
      throw FormatException('Invalid mapFile path "$path".');
    }
  }

  static List<GravityMapProfile> _parseGrid(
    List<String> rows, {
    required String patternId,
    required double cellSize,
    required double baseCeilingHeight,
    required double baseFloorHeight,
  }) {
    final width = rows.first.runes.length;
    if (width == 0 || rows.any((row) => row.runes.length != width)) {
      throw FormatException(
        'Pattern "$patternId" grid rows must have equal width.',
      );
    }
    const wall = '■';
    const markedEmpty = '□';
    const blank = ' ';
    if (rows.any(
      (row) => row.runes
          .map(String.fromCharCode)
          .any(
            (symbol) =>
                symbol != wall && symbol != markedEmpty && symbol != blank,
          ),
    )) {
      throw FormatException(
        'Pattern "$patternId" grid may only use ■, □, and spaces.',
      );
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
