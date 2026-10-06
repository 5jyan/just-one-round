import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/core/auth/kakao_auth_service.dart';
import 'package:just_one_round/core/auth/shared_test_profile.dart';
import 'package:just_one_round/core/update/critical_ota_update.dart';
import 'package:just_one_round/features/monetization/data/admob_rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeKakaoSdk();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/licenses/Galmuri-OFL-1.1.txt',
    );
    yield LicenseEntryWithLineBreaks(['Galmuri'], license);
  });
  const configuredSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const configuredSupabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const usePreviewRepository = bool.fromEnvironment(
    'USE_PREVIEW_REPOSITORY',
    defaultValue: false,
  );
  const previewGameId = String.fromEnvironment(
    'PREVIEW_GAME_ID',
    defaultValue: 'dung_dodge_v2',
  );
  const useReleaseBackend = kReleaseMode || kProfileMode;
  final appBuildInfo = await readAppBuildInfo();
  final supabaseUrl = configuredSupabaseUrl.isNotEmpty
      ? configuredSupabaseUrl
      : useReleaseBackend
      ? 'https://yvowpyeoaexdrycgtyri.supabase.co'
      : 'http://127.0.0.1:54321';
  final supabaseKey = configuredSupabaseKey.isNotEmpty
      ? configuredSupabaseKey
      : useReleaseBackend
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
  const sharedTestProfile = SharedTestProfileConfig.fromEnvironment();
  try {
    await signInSharedTestProfile(
      Supabase.instance.client,
      sharedTestProfile,
    ).timeout(const Duration(seconds: 8));
  } catch (error, stackTrace) {
    // Never hold the first frame hostage to a slow or temporarily unavailable
    // auth endpoint. The repository retries with the same shared profile when
    // the first data request runs.
    debugPrint('[Startup] Shared test profile sign-in deferred: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  // Refresh the persisted user before the first repository request. This
  // keeps identity data (including Kakao linking) current on a restored
  // device session while still allowing the repository to recover a new
  // anonymous session when no session exists or the network is unavailable.
  if (Supabase.instance.client.auth.currentSession != null) {
    try {
      await Supabase.instance.client.auth.getUser().timeout(
        const Duration(seconds: 5),
      );
    } catch (error, stackTrace) {
      // The repository's session guard remains the source of truth for
      // retrying or creating the session during startup.
      debugPrint('[Startup] Restored user refresh deferred: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
  final DailyGameRepository repository = usePreviewRepository
      ? PreviewDailyGameRepository(testMode: true, initialGameId: previewGameId)
      : SupabaseDailyGameRepository(
          Supabase.instance.client,
          sharedTestProfile: sharedTestProfile,
        );
  final rewardedAdService = AdMobRewardedAdService(
    AdMobRewardedAdConfig.fromEnvironment(),
  );

  runApp(
    ProviderScope(
      overrides: [
        appBuildInfoProvider.overrideWithValue(appBuildInfo),
        kakaoAuthServiceProvider.overrideWithValue(
          SupabaseKakaoAuthService(
            Supabase.instance.client,
            configured: kakaoLoginConfigured,
          ),
        ),
        dailyGameRepositoryProvider.overrideWithValue(repository),
        criticalOtaUpdateServiceProvider.overrideWithValue(
          const InactiveCriticalOtaUpdateService(),
        ),
        rewardedAdServiceProvider.overrideWithValue(rewardedAdService),
      ],
      child: const JustOneRoundApp(),
    ),
  );
}
