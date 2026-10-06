import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';
import 'package:just_one_round/features/games/western_duel/presentation/western_duel_preview.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  test('the duel has one player-facing name without changing its ID', () async {
    final preview = PreviewDailyGameRepository(initialGameId: 'western_duel');
    final today = await preview.fetchToday();
    final developerGames = await preview.fetchDeveloperGames();
    expect(today.game?.id, 'western_duel');
    expect(today.game?.displayName, '딱 한 발만');
    expect(
      developerGames
          .singleWhere((game) => game.id == 'western_duel')
          .displayName,
      '딱 한 발만',
    );
    final renameSql = File(
      'supabase/migrations/20260930000100_rename_western_duel_to_just_one_shot.sql',
    ).readAsStringSync();
    expect(renameSql, contains("where game_id = 'western_duel'"));
    expect(renameSql, contains("where id = 'western_duel'"));
    expect(renameSql, contains("set display_name = '딱 한 발만'"));
  });

  test(
    'pixel full-body v11 atlas is preserved and clipped by the viewport composition',
    () async {
      const cellWidth = 540;
      const cellHeight = 1080;
      final atlasCodec = await ui.instantiateImageCodec(
        File(
          'assets/images/western_duel/first_person/player_detail_action_v11/sheet-transparent.png',
        ).readAsBytesSync(),
      );
      try {
        final atlasFrame = await atlasCodec.getNextFrame();
        final image = atlasFrame.image;
        try {
          expect(image.width, 2160);
          expect(image.height, 4320);
          final pixelData = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixelData, isNotNull);
          final rgba = pixelData!.buffer.asUint8List(
            pixelData.offsetInBytes,
            pixelData.lengthInBytes,
          );

          for (
            var actionFrame = 0;
            actionFrame < WesternDuelGame.playerActionFrameCount;
            actionFrame++
          ) {
            final cellX =
                actionFrame %
                WesternDuelGame.playerActionSheetColumns *
                cellWidth;
            final cellY =
                actionFrame ~/
                WesternDuelGame.playerActionSheetColumns *
                cellHeight;
            var minX = cellWidth;
            var minY = cellHeight;
            var maxX = -1;
            var maxY = -1;

            for (var y = 0; y < cellHeight; y++) {
              for (var x = 0; x < cellWidth; x++) {
                final alphaIndex =
                    ((cellY + y) * image.width + cellX + x) * 4 + 3;
                if (rgba[alphaIndex] == 0) continue;
                if (x < minX) minX = x;
                if (y < minY) minY = y;
                if (x > maxX) maxX = x;
                if (y > maxY) maxY = y;
              }
            }
            final bounds = [minX, minY, maxX + 1, maxY + 1];
            expect(bounds[2] - bounds[0], greaterThan(300));
            expect(bounds[3] - bounds[1], greaterThan(700));
            expect(bounds[3], greaterThan(1010));

            for (final height in [640.0, 720.0, 800.0]) {
              final player = WesternDuelGame.playerActionRectForHeight(
                height,
                actionFrame,
              );
              expect(
                player,
                WesternDuelGame.playerUnifiedRectForHeight(height),
              );
              final artLeft =
                  player.left + bounds[0] * WesternDuelGame.playerActionScaleX;
              final artTop =
                  player.top + bounds[1] * WesternDuelGame.playerActionScaleY;
              final artRight =
                  player.left + bounds[2] * WesternDuelGame.playerActionScaleX;
              final artBottom =
                  player.top + bounds[3] * WesternDuelGame.playerActionScaleY;
              expect(artLeft, lessThan(0));
              expect(artTop, greaterThan(0));
              expect(artRight, greaterThan(120));
              expect(artRight, lessThan(300));
              expect(artBottom, greaterThan(height));
            }
          }
        } finally {
          image.dispose();
        }
      } finally {
        atlasCodec.dispose();
      }

      expect(WesternDuelGame.playerActionSourceCellWidth, cellWidth);
      expect(WesternDuelGame.playerActionSourceCellHeight, cellHeight);
      expect(WesternDuelGame.playerActionScaleX, 1);
      expect(WesternDuelGame.playerActionScaleY, 1);
      expect(WesternDuelGame.playerMuzzleSourceX, 410);
      expect(WesternDuelGame.playerMuzzleSourceY, 365);
      for (final height in [640.0, 720.0, 800.0]) {
        final opponent = WesternDuelGame.opponentRectForHeight(height);
        final muzzle = WesternDuelGame.playerMuzzlePositionForHeight(height);
        expect(opponent.left, closeTo(102.72, 0.01));
        expect(opponent.width, closeTo(154.56, 0.01));
        expect(opponent.height, closeTo(220.8, 0.01));
        expect(opponent.center.dx, 180);
        expect(opponent.bottom, closeTo(430 + (height - 720) / 2, 0.01));
        expect(muzzle.dx, 156);
        expect(muzzle.dy, height - 315);
        expect(muzzle.dx, lessThan(opponent.center.dx));
        expect(
          opponent.contains(
            WesternDuelGame.playerShotTargetPositionForHeight(height),
          ),
          isTrue,
        );
      }
    },
  );

  test('v11 action atlas loads sixteen distinct 4x4 layout cells', () async {
    const cellWidth = 540;
    const cellHeight = 1080;
    final codec = await ui.instantiateImageCodec(
      File(
        'assets/images/western_duel/first_person/player_detail_action_v11/sheet-transparent.png',
      ).readAsBytesSync(),
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        expect(
          image.width,
          cellWidth * WesternDuelGame.playerActionSheetColumns,
        );
        expect(
          image.height,
          cellHeight * WesternDuelGame.playerActionSheetRows,
        );
        final pixelData = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = pixelData.buffer.asUint8List(
          pixelData.offsetInBytes,
          pixelData.lengthInBytes,
        );
        final fingerprints = <int>{};
        for (
          var actionFrame = 0;
          actionFrame < WesternDuelGame.playerActionFrameCount;
          actionFrame++
        ) {
          final cellX =
              actionFrame %
              WesternDuelGame.playerActionSheetColumns *
              cellWidth;
          final cellY =
              actionFrame ~/
              WesternDuelGame.playerActionSheetColumns *
              cellHeight;
          var hash = 0xcbf29ce484222325;
          for (var y = 0; y < cellHeight; y++) {
            var index = ((cellY + y) * image.width + cellX) * 4;
            for (var x = 0; x < cellWidth; x++) {
              hash =
                  ((hash ^ bytes[index]) * 0x100000001b3) & 0xffffffffffffffff;
              hash =
                  ((hash ^ bytes[index + 1]) * 0x100000001b3) &
                  0xffffffffffffffff;
              hash =
                  ((hash ^ bytes[index + 2]) * 0x100000001b3) &
                  0xffffffffffffffff;
              hash =
                  ((hash ^ bytes[index + 3]) * 0x100000001b3) &
                  0xffffffffffffffff;
              index += 4;
            }
          }
          expect(
            fingerprints.add(hash),
            isTrue,
            reason: 'action frame $actionFrame duplicates another v11 cell',
          );
        }
        expect(fingerprints, hasLength(WesternDuelGame.playerActionFrameCount));
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  test('v11 idle atlas repeats one planted master in every cell', () async {
    const cellWidth = 540;
    const cellHeight = 1080;
    final codec = await ui.instantiateImageCodec(
      File(
        'assets/images/western_duel/first_person/player_detail_idle_v11/sheet-transparent.png',
      ).readAsBytesSync(),
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        expect(image.width, 1080);
        expect(image.height, 2160);
        final pixelData = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = pixelData.buffer.asUint8List(
          pixelData.offsetInBytes,
          pixelData.lengthInBytes,
        );
        for (var y = 0; y < cellHeight; y++) {
          for (var x = 0; x < cellWidth; x++) {
            final first = (y * image.width + x) * 4;
            for (var cell = 1; cell < 4; cell++) {
              final cellX = cell % 2 * cellWidth;
              final cellY = cell ~/ 2 * cellHeight;
              final other = ((cellY + y) * image.width + cellX + x) * 4;
              for (var channel = 0; channel < 4; channel++) {
                expect(bytes[first + channel], bytes[other + channel]);
              }
            }
          }
        }
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  test('v13 player forward fall atlas keeps the shared 2x4 layout', () async {
    const cellWidth = 540;
    const cellHeight = 1080;
    final codec = await ui.instantiateImageCodec(
      File(
        'assets/images/western_duel/first_person/player_forward_fall_v13/sheet-transparent.png',
      ).readAsBytesSync(),
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        expect(
          image.width,
          cellWidth * WesternDuelGame.playerForwardFallSheetColumns,
        );
        expect(
          image.height,
          cellHeight * WesternDuelGame.playerForwardFallSheetRows,
        );
        expect(WesternDuelGame.playerForwardFallFrameCount, 8);
        expect(
          WesternDuelGame.playerForwardFallDurationSeconds,
          closeTo(0.96, 0.0001),
        );
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0), 0);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.079), 0);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.08), 1);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.26), 3);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.42), 4);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.639), 4);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.64), 5);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.86), 7);
        expect(WesternDuelGame.playerForwardFallFrameForTesting(0.96), 7);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  });

  test('new duel is registered without removing historical mole records', () {
    expect(GameRegistry.supports('western_duel', 1), isTrue);
    expect(GameRegistry.supports('mole_reaction', 2), isTrue);
    expect(GameRegistry.formatScore('western_duel', 999877), '0.123초');
    final guide = GamePresentationRegistry.forId('western_duel');
    expect(guide.guidePages, hasLength(3));
    final copy = guide.guidePages
        .map((page) => '${page.title} ${page.description} ${page.detail}')
        .join(' ');
    expect(copy, contains('조기 입력'));
    expect(copy, contains('1.000초'));
    expect(copy, contains('상대가 먼저 쏴도'));
    expect(copy, contains('승패와 관계없이'));
  });

  test(
    'server migration contains atomic least-used snapshot and no-rank bounds',
    () {
      final sql = File(
        'supabase/migrations/20260924000100_western_duel.sql',
      ).readAsStringSync();
      expect(sql, contains('confirm_western_duel_started'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(
        sql,
        contains('primary key references public.daily_play_sessions'),
      );
      expect(
        sql,
        contains('order by coalesce(usage.selected_count, 0), random()'),
      );
      expect(sql, contains('not profile.is_test_account'));
      expect(sql, contains('score.user_id <> current_user_id'));
      expect(sql, contains('raw_score not between 998500 and 999999'));
      expect(sql, contains('submit_daily_score_before_western_duel'));
    },
  );

  testWidgets('three guide scenes render from game assets in narrow slots', (
    tester,
  ) async {
    for (final scene in WesternDuelPreviewScene.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 300,
              child: WesternDuelPreview(scene: scene),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  test('preview uses the pixel full-body player atlas', () {
    expect(
      WesternDuelPreview.playerAtlasAsset,
      'assets/images/western_duel/first_person/player_detail_action_v11/sheet-transparent.png',
    );
    expect(
      WesternDuelPreview.playerIdleAtlasAsset,
      'assets/images/western_duel/first_person/player_detail_idle_v11/sheet-transparent.png',
    );
  });
}
