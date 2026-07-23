import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/licenses/Galmuri-OFL-1.1.txt',
    );
    yield LicenseEntryWithLineBreaks(['Galmuri'], license);
  });
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  const supabaseKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final repository = await isIosSimulator()
      ? PreviewDailyGameRepository(testMode: true)
      : SupabaseDailyGameRepository(Supabase.instance.client);

  runApp(
    ProviderScope(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
      child: const JustOneRoundApp(),
    ),
  );
}
