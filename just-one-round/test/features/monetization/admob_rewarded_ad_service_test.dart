import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as ads;
import 'package:google_mobile_ads/src/ump/user_messaging_channel.dart' as ump;
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart' as ump;
import 'package:just_one_round/features/monetization/data/admob_rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AdsHarness harness;
  final services = <AdMobRewardedAdService>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = _AdsHarness()..install();
  });

  tearDown(() {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    harness.dispose();
  });

  AdMobRewardedAdService createService() {
    final service = AdMobRewardedAdService(
      const AdMobRewardedAdConfig(enabled: true, adUnitId: 'test-ad-unit'),
    );
    services.add(service);
    return service;
  }

  testWidgets('a native load that never answers fails show within 12 seconds', (
    tester,
  ) async {
    harness.pendingNativeLoad = true;
    final service = createService();
    await service.initialize();

    final show = service.show(
      userId: 'user-id',
      verificationSessionId: 'verification-session',
    );
    await tester.pump();
    for (var frame = 0; frame < 4 && harness.loadAdIds.isEmpty; frame++) {
      await tester.pump();
    }
    expect(harness.loadAdIds, hasLength(1));
    await tester.pump(const Duration(seconds: 12));

    expect(await show, RewardedAdOutcome.failed);
    expect(service.status.value, RewardedAdStatus.unavailable);

    final lateAd = harness.adForLoad(0);
    expect(lateAd, isNotNull);
    lateAd!.rewardedAdLoadCallback.onAdLoaded(lateAd);
    await tester.pump();
    expect(service.status.value, RewardedAdStatus.unavailable);
    expect(harness.loadAdIds, hasLength(1));
  });

  testWidgets(
    'a failed initialization can retry without duplicate concurrent work',
    (tester) async {
      harness.canRequestAdsResults.addAll([false, true]);
      final service = createService();

      final first = service.initialize();
      final concurrent = service.initialize();
      await Future.wait([first, concurrent]);
      expect(harness.consentUpdateRequests, 1);
      expect(harness.canRequestAdsRequests, 1);
      expect(harness.mobileAdsInitializeRequests, 0);

      await service.initialize();
      expect(harness.consentUpdateRequests, 2);
      expect(harness.canRequestAdsRequests, 2);
      expect(harness.mobileAdsInitializeRequests, 1);
      expect(service.status.value, RewardedAdStatus.unavailable);
    },
  );

  testWidgets('a shown ad keeps the five minute completion window', (
    tester,
  ) async {
    final service = createService();
    await service.preload();
    final ad = harness.adForLoad(0)!;

    final show = service.show(
      userId: 'user-id',
      verificationSessionId: 'verification-session',
    );
    await tester.pump(const Duration(seconds: 1));
    ad.fullScreenContentCallback!.onAdShowedFullScreenContent!(ad);
    var completed = false;
    show.then((_) => completed = true);
    await tester.pump(const Duration(seconds: 12));
    expect(completed, isFalse);

    ad.onUserEarnedRewardCallback!(ad, RewardItem(1, 'test'));
    ad.fullScreenContentCallback!.onAdDismissedFullScreenContent!(ad);
    await tester.pump();
    expect(await show, RewardedAdOutcome.earned);
  });

  testWidgets('earned reward wins over a later fullscreen failure', (
    tester,
  ) async {
    final service = createService();
    await service.preload();
    final ad = harness.adForLoad(0)!;

    final show = service.show(
      userId: 'user-id',
      verificationSessionId: 'verification-session',
    );
    await tester.pump();
    ad.fullScreenContentCallback!.onAdShowedFullScreenContent!(ad);
    ad.onUserEarnedRewardCallback!(ad, RewardItem(1, 'test'));
    ad.fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
      ad,
      AdError(1, 'test', 'late failure'),
    );
    await tester.pump();

    expect(await show, RewardedAdOutcome.earned);
  });

  testWidgets('a late native show error after reward completes promptly', (
    tester,
  ) async {
    harness.pendingShowRequest = true;
    final service = createService();
    await service.preload();
    final ad = harness.adForLoad(0)!;

    final show = service.show(
      userId: 'user-id',
      verificationSessionId: 'verification-session',
    );
    await tester.pump();
    ad.fullScreenContentCallback!.onAdShowedFullScreenContent!(ad);
    ad.onUserEarnedRewardCallback!(ad, RewardItem(1, 'test'));
    final pendingShow = harness.pendingShowRequests.single;
    pendingShow.completeError(PlatformException(code: 'late_show_error'));
    await tester.pump();

    expect(await show, RewardedAdOutcome.earned);
  });

  testWidgets(
    'callbacks from a timed out presentation cannot change the refill',
    (tester) async {
      final service = createService();
      await service.preload();
      final staleAd = harness.adForLoad(0)!;

      final show = service.show(
        userId: 'user-id',
        verificationSessionId: 'verification-session',
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      expect(await show, RewardedAdOutcome.failed);
      await tester.pump();

      final refill = harness.adForLoad(1);
      expect(refill, isNotNull);
      expect(service.status.value, RewardedAdStatus.ready);

      staleAd.fullScreenContentCallback!.onAdShowedFullScreenContent!(staleAd);
      staleAd.onUserEarnedRewardCallback!(staleAd, RewardItem(1, 'test'));
      staleAd.fullScreenContentCallback!.onAdDismissedFullScreenContent!(
        staleAd,
      );
      await tester.pump();

      expect(service.status.value, RewardedAdStatus.ready);
      expect(harness.loadAdIds, hasLength(2));
    },
  );
}

class _AdsHarness {
  static const _adsChannelName = 'plugins.flutter.io/google_mobile_ads';
  static const _umpChannelName = 'plugins.flutter.io/google_mobile_ads/ump';

  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final canRequestAdsResults = <bool>[];
  final pendingNativeLoads = <Completer<void>>[];
  final pendingShowRequests = <Completer<void>>[];
  final loadAdIds = <int>[];
  var pendingNativeLoad = false;
  var pendingShowRequest = false;
  var consentUpdateRequests = 0;
  var canRequestAdsRequests = 0;
  var mobileAdsInitializeRequests = 0;
  late MethodChannel adsChannel;
  late MethodChannel umpChannel;

  void install() {
    ads.instanceManager = ads.AdInstanceManager(_adsChannelName);
    adsChannel = ads.instanceManager.channel;
    binaryMessenger.setMockMethodCallHandler(adsChannel, _handleAdsCall);

    umpChannel = MethodChannel(
      _umpChannelName,
      StandardMethodCodec(ump.UserMessagingCodec()),
    );
    ump.UserMessagingChannel.instance = ump.UserMessagingChannel(umpChannel);
    binaryMessenger.setMockMethodCallHandler(umpChannel, _handleUmpCall);
  }

  Future<Object?> _handleAdsCall(MethodCall call) async {
    switch (call.method) {
      case '_init':
      case 'MobileAds#updateRequestConfiguration':
      case 'setServerSideVerificationOptions':
      case 'disposeAd':
        return null;
      case 'showAdWithoutView':
        if (pendingShowRequest) {
          final pending = Completer<void>();
          pendingShowRequests.add(pending);
          await pending.future;
        }
        return null;
      case 'MobileAds#initialize':
        mobileAdsInitializeRequests++;
        return InitializationStatus(<String, AdapterStatus>{});
      case 'loadRewardedAd':
        final adId = call.arguments['adId'] as int;
        loadAdIds.add(adId);
        if (pendingNativeLoad) {
          final pending = Completer<void>();
          pendingNativeLoads.add(pending);
          await pending.future;
          return null;
        }
        Future<void>.microtask(() {
          final ad = ads.instanceManager.adFor(adId);
          if (ad is RewardedAd) {
            ad.rewardedAdLoadCallback.onAdLoaded(ad);
          }
        });
        return null;
      default:
        throw PlatformException(
          code: 'unexpected_method',
          message: 'Unexpected ads method ${call.method}',
        );
    }
  }

  Future<Object?> _handleUmpCall(MethodCall call) async {
    switch (call.method) {
      case 'ConsentInformation#requestConsentInfoUpdate':
        consentUpdateRequests++;
        return null;
      case 'UserMessagingPlatform#loadAndShowConsentFormIfRequired':
        return null;
      case 'ConsentInformation#canRequestAds':
        canRequestAdsRequests++;
        return canRequestAdsResults.isEmpty
            ? true
            : canRequestAdsResults.removeAt(0);
      case 'ConsentInformation#getPrivacyOptionsRequirementStatus':
        return 0;
      case 'ConsentInformation#isConsentFormAvailable':
        return false;
      default:
        throw PlatformException(
          code: 'unexpected_method',
          message: 'Unexpected UMP method ${call.method}',
        );
    }
  }

  RewardedAd? adForLoad(int index) {
    if (index >= loadAdIds.length) return null;
    final ad = ads.instanceManager.adFor(loadAdIds[index]);
    return ad is RewardedAd ? ad : null;
  }

  void dispose() {
    for (final pending in pendingNativeLoads) {
      if (!pending.isCompleted) pending.complete();
    }
    for (final pending in pendingShowRequests) {
      if (!pending.isCompleted) pending.complete();
    }
    binaryMessenger.setMockMethodCallHandler(adsChannel, null);
    binaryMessenger.setMockMethodCallHandler(umpChannel, null);
  }
}
