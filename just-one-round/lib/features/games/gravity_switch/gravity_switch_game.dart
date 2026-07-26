import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_map_layout.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_motion.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/terrain_asset_usage_balancer.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/terrain_block_cache.dart';

enum GravitySurface { ceiling, floor }

class GravitySwitchGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  GravitySwitchGame({
    required this.onFinished,
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random(),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: null,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static const maxVisibleHeight = 784.0;
  static const playerX = 92.0;
  static const playerSize = 48.0;
  static const playerContactHalfHeight = 15.0;

  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _PrismRunner _player;
  late final List<_TerrainModuleAsset> _terrainAssets;
  late final _TerrainRenderer _terrainRenderer;
  late final List<Sprite> _landingSprites;
  late final GravityMapLayout _map;
  final List<_MazeColumn> _columns = [];
  final List<GravityMapProfile> _patternQueue = [];
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _score = 0;
  var _distance = 0;
  var _lastDisplayedSecond = -1;
  var _nextTerrainColumnIndex = 0;
  String? _lastPatternId;
  var _hasFinished = false;

  @override
  Color backgroundColor() => const Color(0xFF020617);

  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) {
      return logicalSize.clone();
    }
    final visibleHeight = (canvasSize.y * logicalSize.x / canvasSize.x).clamp(
      logicalSize.y,
      maxVisibleHeight,
    );
    return Vector2(logicalSize.x, visibleHeight);
  }

  void _configureViewport(Vector2 canvasSize) {
    camera.viewport = FixedResolutionViewport(
      resolution: viewportResolutionForCanvas(canvasSize),
    );
    // Keep the original 360×640 gameplay and collision core centered. Taller
    // screens reveal visual-only wall overscan above and below that core.
    camera.viewfinder.position = logicalSize / 2;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    _map = await GravityMapLayout.load();

    final loaded = await images.loadAll([
      'gravity_switch_v2/space_background.png',
      'gravity_switch_v2/player_magnet_mite_sheet_v3.png',
      'gravity_switch_v2/landing_impact_sheet.png',
      ..._terrainModuleSpecs.map((spec) => spec.runtimePath),
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final playerSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(48));
    _landingSprites = _spritesFrom2x2(
      SpriteSheet(image: loaded[2], srcSize: Vector2.all(16)),
    );
    _terrainAssets = [
      for (var index = 0; index < _terrainModuleSpecs.length; index++)
        _TerrainModuleAsset(
          spec: _terrainModuleSpecs[index],
          sprite: Sprite(loaded[index + 3]),
        ),
    ];
    _terrainRenderer = _TerrainRenderer(
      columns: _columns,
      assets: _terrainAssets,
    );
    await world.add(_terrainRenderer);
    _player = _PrismRunner(
      position: Vector2(
        playerX,
        _map.initialProfile.floorTop - playerContactHalfHeight,
      ),
      sprites: _spritesFrom2x2(playerSheet),
      onLanded: _showLandingImpact,
    );

    for (var index = 0; index < _map.initialColumnCount; index++) {
      _appendColumn(
        -_map.columnWidth + (index * _map.columnWidth),
        forceSafe: true,
      );
    }
    await world.add(_player);

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _configureViewport(size);
    }
  }

  void _showLandingImpact(GravitySurface surface, Vector2 position) {
    world.add(
      _LandingImpact(
        position: position,
        sprites: _landingSprites,
        ceiling: surface == GravitySurface.ceiling,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        if (_countdownElapsed >=
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond) {
          _phase = MiniGamePhase.playing;
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        _updatePlaying(dt);
      case MiniGamePhase.finished:
        return;
    }
  }

  void _updatePlaying(double dt) {
    _playingElapsed += dt;
    _score = (_playingElapsed * 1000).floor();
    final speed = GravitySwitchRules.scrollSpeed(_playingElapsed);
    _scrollTerrain(speed * dt);

    final support = _supportAtPlayer();
    if (support != null) {
      _player.updateSurface(
        dt,
        floorTop: support.floorTop,
        ceilingBottom: support.ceilingBottom,
      );
    }
    for (final column in _columns) {
      if (column.collidesWith(_player)) {
        _finish();
        return;
      }
    }
    _publishHud();
  }

  void _scrollTerrain(double distance) {
    for (final column in List<_MazeColumn>.of(_columns)) {
      column.position.x -= distance;
      if (!column.wasPassed && column.position.x + _map.columnWidth < playerX) {
        column.wasPassed = true;
        _distance += 1;
      }
      if (column.position.x + _map.columnWidth < 0) {
        _columns.remove(column);
        column.removeFromParent();
      }
    }

    while (_columns.isEmpty ||
        _columns.last.position.x < logicalSize.x + _map.columnWidth * 2) {
      final x = _columns.isEmpty
          ? logicalSize.x
          : _columns.last.position.x + _map.columnWidth;
      _appendColumn(x);
    }
  }

  ({double floorTop, double ceilingBottom})? _supportAtPlayer() {
    final left = playerX - _player.hitbox.width / 2;
    final right = playerX + _player.hitbox.width / 2;
    final supporting = _columns.where(
      (column) =>
          column.position.x < right &&
          column.position.x + _map.columnWidth > left,
    );
    if (supporting.isEmpty) return null;
    return (
      floorTop: supporting.map((column) => column.floorTop).reduce(min),
      ceilingBottom: supporting
          .map((column) => column.ceilingBottom)
          .reduce(max),
    );
  }

  void _appendColumn(double x, {bool forceSafe = false}) {
    final profile = forceSafe ? _map.initialProfile : _nextProfile();
    final column = _MazeColumn(
      floorTop: profile.floorTop,
      ceilingBottom: profile.ceilingBottom,
      columnWidth: _map.columnWidth,
      position: Vector2(x, 0),
      terrainIndex: _nextTerrainColumnIndex++,
    );
    _columns.add(column);
    _terrainRenderer.syncCompletedBlocks();
    world.add(column);
  }

  GravityMapProfile _nextProfile() {
    if (_patternQueue.isEmpty) _queueNextPattern();
    return _patternQueue.removeAt(0);
  }

  void _queueNextPattern() {
    final available = _map.patterns
        .where((pattern) => pattern.isAvailableAt(_playingElapsed))
        .toList(growable: false);
    var next = available[_random.nextInt(available.length)];
    if (available.length > 1 && next.id == _lastPatternId) {
      next = available[(available.indexOf(next) + 1) % available.length];
    }
    _patternQueue.addAll(next.columns);
    _lastPatternId = next.id;
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_phase == MiniGamePhase.playing) _player.switchGravity();
  }

  void _finish() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: 0,
        collisions: 1,
        duration: Duration(milliseconds: _score),
      ),
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _publishHud(force: true);
    pauseEngine();
  }

  void _publishHud({bool force = false}) {
    final elapsedSecond = _playingElapsed.floor();
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    if (!force &&
        elapsedSecond == _lastDisplayedSecond &&
        hud.value.score == _score &&
        hud.value.distance == _distance &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastDisplayedSecond = elapsedSecond;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: null,
      countdownNumber: countdown,
      distance: _distance,
    );
  }

  @override
  void disposeController() => hud.dispose();
}

GravitySurface _opposite(GravitySurface surface) =>
    surface == GravitySurface.floor
    ? GravitySurface.ceiling
    : GravitySurface.floor;

List<Sprite> _spritesFrom2x2(SpriteSheet sheet) => [
  sheet.getSprite(0, 0),
  sheet.getSprite(0, 1),
  sheet.getSprite(1, 0),
  sheet.getSprite(1, 1),
];

class _PrismRunner extends PositionComponent {
  _PrismRunner({
    required super.position,
    required this.sprites,
    required this.onLanded,
  }) : super(
         size: Vector2.all(GravitySwitchGame.playerSize),
         anchor: Anchor.center,
         priority: 20,
       );

  final List<Sprite> sprites;
  final void Function(GravitySurface surface, Vector2 position) onLanded;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  final GravitySwitchGate _switchGate = GravitySwitchGate();
  GravitySurface surface = GravitySurface.floor;
  var _animationElapsed = 0.0;
  var _verticalVelocity = 0.0;
  var _isAttached = true;

  Rect get hitbox => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: 26,
    height: 26,
  );

  void switchGravity() {
    if (!_switchGate.tryStartSwitch()) return;
    surface = _opposite(surface);
    _verticalVelocity = 0;
    _isAttached = false;
  }

  void updateSurface(
    double dt, {
    required double floorTop,
    required double ceilingBottom,
  }) {
    _animationElapsed += dt;
    final wasAttached = _isAttached;
    final direction = surface == GravitySurface.floor ? 1.0 : -1.0;
    final targetY = surface == GravitySurface.floor
        ? floorTop - GravitySwitchGame.playerContactHalfHeight
        : ceilingBottom + GravitySwitchGame.playerContactHalfHeight;
    final motion = GravityMotion.step(
      y: position.y,
      verticalVelocity: _verticalVelocity,
      targetY: targetY,
      gravityDirection: direction,
      dt: dt,
    );
    position.y = motion.y;
    _verticalVelocity = motion.verticalVelocity;
    _isAttached = motion.attached;
    if (motion.attached) {
      if (!wasAttached) {
        _switchGate.landed();
        onLanded(
          surface,
          Vector2(
            position.x,
            surface == GravitySurface.floor ? floorTop : ceilingBottom,
          ),
        );
      }
      angle = 0;
      return;
    }
    angle += direction * dt * 8.5;
  }

  @override
  void render(Canvas canvas) {
    if (sprites.isEmpty) return;
    final index = _isAttached
        ? (_animationElapsed / 0.09).floor() % 2
        : 2 + ((_animationElapsed / 0.09).floor() % 2);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _LandingImpact extends PositionComponent {
  _LandingImpact({
    required super.position,
    required this.sprites,
    required this.ceiling,
  }) : super(
         size: Vector2.all(48),
         anchor: ceiling ? Anchor.topCenter : Anchor.bottomCenter,
         priority: 21,
       );

  static const _frameTime = 0.055;
  final List<Sprite> sprites;
  final bool ceiling;
  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _frameTime * sprites.length) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (sprites.isEmpty) return;
    final index = min(sprites.length - 1, (_elapsed / _frameTime).floor());
    canvas.save();
    if (ceiling) {
      canvas.translate(0, size.y);
      canvas.scale(1, -1);
    }
    sprites[index].render(canvas, size: size, overridePaint: _pixelPaint);
    canvas.restore();
  }
}

class _MazeColumn extends PositionComponent {
  _MazeColumn({
    required this.floorTop,
    required this.ceilingBottom,
    required this.columnWidth,
    required this.terrainIndex,
    required super.position,
  }) : super(
         size: Vector2(columnWidth, GravitySwitchGame.logicalSize.y),
         priority: 5,
       );

  final double floorTop;
  final double ceilingBottom;
  final double columnWidth;
  final int terrainIndex;
  bool wasPassed = false;

  bool collidesWith(_PrismRunner player) {
    final x = position.x;
    final width = columnWidth;
    final floorRect = Rect.fromLTWH(
      x,
      floorTop,
      width,
      GravitySwitchGame.logicalSize.y - floorTop,
    );
    final ceilingRect = Rect.fromLTWH(x, 0, width, ceilingBottom);
    return floorRect.overlaps(player.hitbox) ||
        ceilingRect.overlaps(player.hitbox);
  }
}

class _TerrainModuleSpec {
  const _TerrainModuleSpec(
    this.name,
    this.unitsWide,
    this.unitsHigh, {
    required this.family,
  });

  final String name;
  final int unitsWide;
  final int unitsHigh;
  final String family;

  String get runtimePath =>
      'gravity_switch_v2/platform_modules_$family/$name.png';
}

const _terrainModuleSpecs = [
  _TerrainModuleSpec('scrap_basic_1x1_01', 1, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x1_02', 1, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x1_03', 1, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x1_04', 1, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x2_01', 1, 2, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x2_02', 1, 2, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_2x1_01', 2, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_2x1_02', 2, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_2x2_01', 2, 2, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_2x2_02', 2, 2, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_3x1_01', 3, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_3x1_02', 3, 1, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x3_01', 1, 3, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_1x3_02', 1, 3, family: 'v4'),
  _TerrainModuleSpec('scrap_basic_3x2_01', 3, 2, family: 'v4'),
  _TerrainModuleSpec('scrap_module_1x1_01', 1, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x1_02', 1, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x1_03', 1, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x1_04', 1, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x2_01', 1, 2, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x2_02', 1, 2, family: 'v3'),
  _TerrainModuleSpec('scrap_module_2x1_01', 2, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_2x1_02', 2, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_2x2_01', 2, 2, family: 'v3'),
  _TerrainModuleSpec('scrap_module_2x2_02', 2, 2, family: 'v3'),
  _TerrainModuleSpec('scrap_module_3x1_01', 3, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_3x1_02', 3, 1, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x3_01', 1, 3, family: 'v3'),
  _TerrainModuleSpec('scrap_module_1x3_02', 1, 3, family: 'v3'),
  _TerrainModuleSpec('scrap_module_3x2_01', 3, 2, family: 'v3'),
  _TerrainModuleSpec('scrap_module_2x3_01', 2, 3, family: 'v3'),
];

class _TerrainModuleAsset {
  const _TerrainModuleAsset({required this.spec, required this.sprite});

  final _TerrainModuleSpec spec;
  final Sprite sprite;
}

class _TerrainPlacement {
  const _TerrainPlacement({
    required this.asset,
    required this.column,
    required this.row,
  });

  final _TerrainModuleAsset asset;
  final int column;
  final int row;
}

class _TerrainBlockLayout {
  const _TerrainBlockLayout({required this.ceiling, required this.floor});

  final List<_TerrainPlacement> ceiling;
  final List<_TerrainPlacement> floor;
}

class _TerrainRenderer extends Component {
  _TerrainRenderer({required this.columns, required this.assets})
    : super(priority: 5);

  static const _cell = 48.0;
  static const _gridOriginY = 128.0;
  // Covers y=-112..752, including the maximum responsive viewport
  // y=-72..712 with 40 logical pixels of visual-only margin on both sides.
  static const _minimumRow = -5;
  static const _maximumRow = 12;
  static const blockWidth = 3;

  final List<_MazeColumn> columns;
  final List<_TerrainModuleAsset> assets;
  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  late final TerrainBlockCache<_TerrainBlockLayout> _completedLayouts =
      TerrainBlockCache(blockWidth: blockWidth);
  final TerrainAssetUsageBalancer _usageBalancer = TerrainAssetUsageBalancer();

  void syncCompletedBlocks() {
    final blocks = _groupColumns();
    for (final entry in blocks.entries) {
      _completedLayouts.freezeIfComplete(
        blockIndex: entry.key,
        columnIndexes: entry.value.map((column) => column.terrainIndex),
        build: () => _buildLayout(entry.key, entry.value),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    syncCompletedBlocks();
    final blocks = _groupColumns();
    _completedLayouts.retainBlocks(blocks.keys);
    final blockIndexes = blocks.keys.toList()..sort();
    for (final blockIndex in blockIndexes) {
      final block = blocks[blockIndex]!
        ..sort(
          (left, right) => left.terrainIndex.compareTo(right.terrainIndex),
        );
      final layout = _completedLayouts[blockIndex];
      if (layout == null) continue;
      final blockStart = blockIndex * blockWidth;
      final anchorColumn = block.first;
      final blockX =
          anchorColumn.position.x -
          ((anchorColumn.terrainIndex - blockStart) * _cell);
      _renderPlacements(canvas, layout.ceiling, blockX: blockX, ceiling: true);
      _renderPlacements(canvas, layout.floor, blockX: blockX, ceiling: false);
    }
  }

  Map<int, List<_MazeColumn>> _groupColumns() {
    final blocks = <int, List<_MazeColumn>>{};
    for (final column in columns) {
      blocks
          .putIfAbsent(column.terrainIndex ~/ blockWidth, () => [])
          .add(column);
    }
    return blocks;
  }

  _TerrainBlockLayout _buildLayout(int blockIndex, List<_MazeColumn> block) =>
      _TerrainBlockLayout(
        ceiling: _pack(blockIndex, block, ceiling: true),
        floor: _pack(blockIndex, block, ceiling: false),
      );

  void _renderPlacements(
    Canvas canvas,
    List<_TerrainPlacement> placements, {
    required double blockX,
    required bool ceiling,
  }) {
    for (final placement in placements) {
      final asset = placement.asset;
      final width = asset.spec.unitsWide * _cell;
      final height = asset.spec.unitsHigh * _cell;
      final x = blockX + placement.column * _cell;
      final y = _gridOriginY + placement.row * _cell;
      if (ceiling) {
        canvas.save();
        canvas.translate(x, y + height);
        canvas.scale(1, -1);
        asset.sprite.render(
          canvas,
          size: Vector2(width, height),
          overridePaint: _pixelPaint,
        );
        canvas.restore();
      } else {
        asset.sprite.render(
          canvas,
          position: Vector2(x, y),
          size: Vector2(width, height),
          overridePaint: _pixelPaint,
        );
      }
    }
  }

  List<_TerrainPlacement> _pack(
    int blockIndex,
    List<_MazeColumn> block, {
    required bool ceiling,
  }) {
    const rowCount = _maximumRow - _minimumRow + 1;
    final occupied = List.generate(
      blockWidth,
      (_) => List.filled(rowCount, false),
    );
    final blockStart = blockIndex * blockWidth;
    final profiles = {
      for (final profile in block) profile.terrainIndex - blockStart: profile,
    };
    for (var column = 0; column < blockWidth; column++) {
      final profile = profiles[column];
      if (profile == null) continue;
      for (var row = _minimumRow; row <= _maximumRow; row++) {
        final top = _gridOriginY + row * _cell;
        final bottom = top + _cell;
        occupied[column][row - _minimumRow] = ceiling
            ? bottom <= profile.ceilingBottom
            : top >= profile.floorTop;
      }
    }

    final used = List.generate(
      blockWidth,
      (_) => List<String?>.filled(rowCount, null),
    );
    final placements = <_TerrainPlacement>[];
    final rowOrder = [
      for (var row = _minimumRow; row <= _maximumRow; row++) row,
    ];

    for (final row in rowOrder) {
      for (var column = 0; column < blockWidth; column++) {
        final rowIndex = row - _minimumRow;
        if (!occupied[column][rowIndex] || used[column][rowIndex] != null) {
          continue;
        }
        final fitting = assets.where((asset) {
          final spec = asset.spec;
          if (column + spec.unitsWide > blockWidth ||
              row + spec.unitsHigh - 1 > _maximumRow) {
            return false;
          }
          for (var dx = 0; dx < spec.unitsWide; dx++) {
            for (var dy = 0; dy < spec.unitsHigh; dy++) {
              final targetRow = row + dy - _minimumRow;
              if (!occupied[column + dx][targetRow] ||
                  used[column + dx][targetRow] != null) {
                return false;
              }
            }
          }
          return true;
        }).toList();
        final nonTouching = fitting
            .where((asset) => !_touchesSameAsset(used, row, column, asset.spec))
            .toList();
        final candidates = nonTouching.isEmpty ? fitting : nonTouching;
        final family = _usageBalancer.chooseFamily(
          candidates.map((asset) => asset.spec.family),
        );
        final familyCandidates = candidates
            .where((asset) => asset.spec.family == family)
            .toList();
        final chosenName = _usageBalancer.chooseLeastUsedAsset(
          assetNames: familyCandidates.map((asset) => asset.spec.name),
          stableValue: _stableValue(blockIndex, row, column, family, ceiling),
        );
        final chosen = familyCandidates.firstWhere(
          (asset) => asset.spec.name == chosenName,
        );
        _usageBalancer.record(
          family: chosen.spec.family,
          assetName: chosen.spec.name,
        );
        for (var dx = 0; dx < chosen.spec.unitsWide; dx++) {
          for (var dy = 0; dy < chosen.spec.unitsHigh; dy++) {
            used[column + dx][row + dy - _minimumRow] = chosen.spec.name;
          }
        }
        placements.add(
          _TerrainPlacement(asset: chosen, column: column, row: row),
        );
      }
    }
    return placements;
  }

  bool _touchesSameAsset(
    List<List<String?>> used,
    int row,
    int column,
    _TerrainModuleSpec spec,
  ) {
    for (var dx = 0; dx < spec.unitsWide; dx++) {
      for (var dy = 0; dy < spec.unitsHigh; dy++) {
        final x = column + dx;
        final y = row + dy - _minimumRow;
        for (final offset in const [
          (dx: -1, dy: 0),
          (dx: 1, dy: 0),
          (dx: 0, dy: -1),
          (dx: 0, dy: 1),
        ]) {
          final neighborX = x + offset.dx;
          final neighborY = y + offset.dy;
          if (neighborX < 0 ||
              neighborX >= used.length ||
              neighborY < 0 ||
              neighborY >= used[neighborX].length) {
            continue;
          }
          if (used[neighborX][neighborY] == spec.name) return true;
        }
      }
    }
    return false;
  }

  int _stableValue(
    int blockIndex,
    int row,
    int column,
    String name,
    bool ceiling,
  ) {
    var value =
        blockIndex * 73856093 ^
        row * 19349663 ^
        column * 83492791 ^
        (ceiling ? 0x5F356495 : 0x2C9277B5);
    for (final codeUnit in name.codeUnits) {
      value = ((value * 31) ^ codeUnit) & 0x7FFFFFFF;
    }
    return value;
  }
}
