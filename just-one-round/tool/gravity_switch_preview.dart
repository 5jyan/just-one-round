import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GravitySwitchPreviewApp());
}

class GravitySwitchPreviewApp extends StatelessWidget {
  const GravitySwitchPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget(
          game: GravitySwitchGame(
            countdownDuration: Duration.zero,
            onFinished: (_) {},
          ),
        ),
      ),
    );
  }
}
