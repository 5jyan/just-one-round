import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdMobRewardedAdConfig {
  const AdMobRewardedAdConfig({required this.enabled, required this.adUnitId});

  factory AdMobRewardedAdConfig.fromEnvironment() {
    const sharedConfiguredId = String.fromEnvironment(
      'ADMOB_REWARDED_AD_UNIT_ID',
    );
    const androidConfiguredId = String.fromEnvironment(
      'ADMOB_ANDROID_REWARDED_AD_UNIT_ID',
    );
    const iosConfiguredId = String.fromEnvironment(
      'ADMOB_IOS_REWARDED_AD_UNIT_ID',
    );
    const explicitlyEnabled = bool.fromEnvironment(
      'ADS_ENABLED',
      defaultValue: true,
    );
    if (!explicitlyEnabled) {
      return const AdMobRewardedAdConfig(enabled: false, adUnitId: '');
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (!isAndroid && !isIos) {
      return const AdMobRewardedAdConfig(enabled: false, adUnitId: '');
    }

    final platformConfiguredId = isAndroid
        ? androidConfiguredId
        : iosConfiguredId;
    final configuredId = platformConfiguredId.isNotEmpty
        ? platformConfiguredId
        : sharedConfiguredId;
    if (configuredId.isNotEmpty) {
      return AdMobRewardedAdConfig(enabled: true, adUnitId: configuredId);
    }

    if (!kReleaseMode) {
      return AdMobRewardedAdConfig(
        enabled: true,
        adUnitId: isAndroid
            ? 'ca-app-pub-3940256099942544/5224354917'
            : 'ca-app-pub-3940256099942544/1712485313',
      );
    }

    return AdMobRewardedAdConfig(
      enabled: true,
      adUnitId: isAndroid
          ? 'ca-app-pub-8518567556283844/1476407770'
          : 'ca-app-pub-8518567556283844/8947557896',
    );
  }

  final bool enabled;
  final String adUnitId;
}

class AdMobRewardedAdService implements RewardedAdService {
  AdMobRewardedAdService(this.config);

  static const _diagnosticKey = 'admob_rewarded_last_diagnostic_v1';

  final AdMobRewardedAdConfig config;
  final ValueNotifier<RewardedAdStatus> _status = ValueNotifier(
    RewardedAdStatus.disabled,
  );

  RewardedAd? _ad;
  Future<void>? _initialization;
  Completer<void>? _loadCompleter;
  var _disposed = false;
  var _canRequestAds = false;

  @override
  ValueListenable<RewardedAdStatus> get status => _status;

  @override
  Future<void> initialize() => _initialization ??= _initializeMobileAds();

  Future<void> _initializeMobileAds() async {
    if (!config.enabled || config.adUnitId.isEmpty) {
      _setStatus(RewardedAdStatus.disabled);
      return;
    }
    try {
      final consentReady = await _requestConsent();
      if (!consentReady) {
        unawaited(_recordDiagnostic('consent:cannot_request_ads'));
        _setStatus(RewardedAdStatus.unavailable);
        return;
      }
      _canRequestAds = true;
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      await MobileAds.instance.setAppMuted(true);
      await MobileAds.instance.initialize();
      debugPrint('[AdMob] Mobile Ads initialized.');
      _setStatus(RewardedAdStatus.unavailable);
    } catch (error, stackTrace) {
      unawaited(_recordDiagnostic('initialization:$error'));
      debugPrint('[AdMob] Initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setStatus(RewardedAdStatus.unavailable);
    }
  }

  Future<bool> _requestConsent() async {
    final update = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      update.complete,
      (error) {
        debugPrint(
          '[AdMob] Consent info update failed '
          '(code: ${error.errorCode}): ${error.message}',
        );
        update.complete();
      },
    );
    await update.future;

    final form = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        debugPrint(
          '[AdMob] Consent form failed '
          '(code: ${error.errorCode}): ${error.message}',
        );
      }
      form.complete();
    });
    await form.future;
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    debugPrint('[AdMob] Consent allows ad requests: $canRequestAds');
    return canRequestAds;
  }

  @override
  Future<void> preload() async {
    if (_disposed || !config.enabled || _ad != null) return;
    await initialize();
    if (!_canRequestAds) return;
    final activeLoad = _loadCompleter;
    if (activeLoad != null) return activeLoad.future;

    final completer = Completer<void>();
    _loadCompleter = completer;
    _setStatus(RewardedAdStatus.loading);
    await RewardedAd.load(
      adUnitId: config.adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          unawaited(_recordDiagnostic(null));
          if (_disposed) {
            ad.dispose();
          } else {
            _ad = ad;
            _setStatus(RewardedAdStatus.ready);
          }
          if (!completer.isCompleted) completer.complete();
          _loadCompleter = null;
        },
        onAdFailedToLoad: (error) {
          unawaited(
            _recordDiagnostic(
              'load:${error.code}:${error.domain}:${error.message}',
            ),
          );
          debugPrint(
            '[AdMob] Rewarded ad load failed '
            '(code: ${error.code}, domain: ${error.domain}): ${error.message}',
          );
          _setStatus(RewardedAdStatus.unavailable);
          if (!completer.isCompleted) completer.complete();
          _loadCompleter = null;
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<bool> showPrivacyOptions() async {
    await initialize();
    final requirement = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    if (requirement != PrivacyOptionsRequirementStatus.required) return false;
    final completed = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => completed.complete());
    await completed.future;
    return true;
  }

  @override
  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  }) async {
    await initialize();
    if (_ad == null) await preload();
    final ad = _ad;
    if (ad == null) return RewardedAdOutcome.failed;

    _ad = null;
    _setStatus(RewardedAdStatus.loading);
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(
        userId: userId,
        customData: verificationSessionId,
      ),
    );

    final result = Completer<RewardedAdOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!result.isCompleted) {
          result.complete(
            earned ? RewardedAdOutcome.earned : RewardedAdOutcome.dismissed,
          );
        }
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        unawaited(
          _recordDiagnostic(
            'show:${error.code}:${error.domain}:${error.message}',
          ),
        );
        debugPrint(
          '[AdMob] Rewarded ad failed to show '
          '(code: ${error.code}, domain: ${error.domain}): ${error.message}',
        );
        ad.dispose();
        if (!result.isCompleted) result.complete(RewardedAdOutcome.failed);
        unawaited(preload());
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (error, stackTrace) {
      debugPrint('[AdMob] Rewarded ad show threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      ad.dispose();
      if (!result.isCompleted) result.complete(RewardedAdOutcome.failed);
      unawaited(preload());
    }
    return result.future;
  }

  void _setStatus(RewardedAdStatus next) {
    if (!_disposed && _status.value != next) _status.value = next;
  }

  Future<void> _recordDiagnostic(String? value) async {
    final preferences = await SharedPreferences.getInstance();
    if (value == null) {
      await preferences.remove(_diagnosticKey);
    } else {
      await preferences.setString(_diagnosticKey, value);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ad?.dispose();
    _ad = null;
    _status.dispose();
  }
}
