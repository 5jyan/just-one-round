import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/features/monetization/data/admob_rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
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
  const configuredSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const configuredSupabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final appBuildInfo = await readAppBuildInfo();
  final supabaseUrl = configuredSupabaseUrl.isNotEmpty
      ? configuredSupabaseUrl
      : kReleaseMode
      ? 'https://yvowpyeoaexdrycgtyri.supabase.co'
      : 'http://127.0.0.1:54321';
  final supabaseKey = configuredSupabaseKey.isNotEmpty
      ? configuredSupabaseKey
      : kReleaseMode
      ? 'sb_publishable_WBennSQ3pBJ3HaBDgRPBNQ_V30Veh3v'
      : 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
    headers: {
      'x-app-build': '${appBuildInfo.buildNumber}',
      'x-app-platform': appBuildInfo.platform,
    },
  );
  final repository = await isIosSimulator()
      ? PreviewDailyGameRepository(testMode: true)
      : SupabaseDailyGameRepository(Supabase.instance.client);
  final rewardedAdService = AdMobRewardedAdService(
    AdMobRewardedAdConfig.fromEnvironment(),
  );

  runApp(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(repository),
        rewardedAdServiceProvider.overrideWithValue(rewardedAdService),
      ],
      child: const JustOneRoundApp(),
    ),
  );
}
