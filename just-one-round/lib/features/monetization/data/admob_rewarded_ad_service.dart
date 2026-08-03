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
  static const _operationTimeout = Duration(seconds: 12);
  static const _showTimeout = Duration(seconds: 90);

  final AdMobRewardedAdConfig config;
  final ValueNotifier<RewardedAdStatus> _status = ValueNotifier(
    RewardedAdStatus.disabled,
  );

  RewardedAd? _ad;
  Future<void>? _initialization;
  Completer<void>? _loadCompleter;
  Future<void>? _loadFuture;
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
      await MobileAds.instance
          .updateRequestConfiguration(
            RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
          )
          .timeout(_operationTimeout);
      await MobileAds.instance.initialize().timeout(_operationTimeout);
      await MobileAds.instance.setAppMuted(true).timeout(_operationTimeout);
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
      () {
        if (!update.isCompleted) update.complete();
      },
      (error) {
        debugPrint(
          '[AdMob] Consent info update failed '
          '(code: ${error.errorCode}): ${error.message}',
        );
        if (!update.isCompleted) update.complete();
      },
    );
    try {
      await update.future.timeout(_operationTimeout);
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) {
          debugPrint(
            '[AdMob] Consent form failed '
            '(code: ${error.errorCode}): ${error.message}',
          );
        }
      }).timeout(_operationTimeout);
    } on TimeoutException {
      debugPrint('[AdMob] Consent operation timed out.');
      return false;
    } catch (error, stackTrace) {
      debugPrint('[AdMob] Consent operation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
    final canRequestAds = await ConsentInformation.instance
        .canRequestAds()
        .timeout(_operationTimeout);
    debugPrint('[AdMob] Consent allows ad requests: $canRequestAds');
    return canRequestAds;
  }

  @override
  Future<void> preload() async {
    if (_disposed || !config.enabled || _ad != null) return;
    await initialize();
    if (!_canRequestAds) return;
    final activeLoad = _loadFuture;
    if (activeLoad != null) return activeLoad;

    final completer = Completer<void>();
    var timedOut = false;
    _loadCompleter = completer;
    _setStatus(RewardedAdStatus.loading);
    final loadFuture = completer.future.timeout(
      _operationTimeout,
      onTimeout: () {
        timedOut = true;
        if (identical(_loadCompleter, completer)) {
          _loadCompleter = null;
          _loadFuture = null;
          _setStatus(RewardedAdStatus.unavailable);
        }
      },
    );
    _loadFuture = loadFuture;

    void finishLoad() {
      if (identical(_loadCompleter, completer)) {
        _loadCompleter = null;
        _loadFuture = null;
      }
      if (!completer.isCompleted) completer.complete();
    }

    try {
      await RewardedAd.load(
        adUnitId: config.adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (timedOut) {
              ad.dispose();
              return;
            }
            unawaited(_recordDiagnostic(null));
            if (_disposed) {
              ad.dispose();
            } else {
              _ad = ad;
              _setStatus(RewardedAdStatus.ready);
            }
            finishLoad();
          },
          onAdFailedToLoad: (error) {
            if (timedOut) return;
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
            finishLoad();
          },
        ),
      );
    } catch (error, stackTrace) {
      unawaited(_recordDiagnostic('load-request:$error'));
      debugPrint('[AdMob] Rewarded ad load request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setStatus(RewardedAdStatus.unavailable);
      finishLoad();
    }
    return loadFuture;
  }

  @override
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      await initialize();
      final requirement = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus()
          .timeout(_operationTimeout);
      return requirement == PrivacyOptionsRequirementStatus.required;
    } catch (error) {
      debugPrint('[AdMob] Privacy options status unavailable: $error');
      return false;
    }
  }

  @override
  Future<bool> showPrivacyOptions() async {
    if (!await isPrivacyOptionsRequired()) return false;
    var hasError = false;
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        hasError = error != null;
        if (error != null) {
          debugPrint(
            '[AdMob] Privacy options form failed '
            '(code: ${error.errorCode}): ${error.message}',
          );
        }
      }).timeout(_operationTimeout);
      return !hasError;
    } catch (error) {
      debugPrint('[AdMob] Privacy options form unavailable: $error');
      return false;
    }
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
    try {
      await ad
          .setServerSideOptions(
            ServerSideVerificationOptions(
              userId: userId,
              customData: verificationSessionId,
            ),
          )
          .timeout(_operationTimeout);
    } catch (error, stackTrace) {
      debugPrint('[AdMob] Failed to configure SSV: $error');
      debugPrintStack(stackTrace: stackTrace);
      ad.dispose();
      _setStatus(RewardedAdStatus.unavailable);
      unawaited(preload());
      return RewardedAdOutcome.failed;
    }

    final result = Completer<RewardedAdOutcome>();
    var earned = false;
    var adDisposed = false;
    void disposeAd() {
      if (adDisposed) return;
      adDisposed = true;
      ad.dispose();
    }

    void complete(RewardedAdOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        disposeAd();
        complete(
          earned ? RewardedAdOutcome.earned : RewardedAdOutcome.dismissed,
        );
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
        disposeAd();
        complete(RewardedAdOutcome.failed);
        unawaited(preload());
      },
    );
    try {
      await ad
          .show(onUserEarnedReward: (_, _) => earned = true)
          .timeout(_showTimeout);
    } catch (error, stackTrace) {
      debugPrint('[AdMob] Rewarded ad show threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      disposeAd();
      complete(RewardedAdOutcome.failed);
      unawaited(preload());
    }
    return result.future.timeout(
      _showTimeout,
      onTimeout: () {
        disposeAd();
        _setStatus(RewardedAdStatus.unavailable);
        complete(RewardedAdOutcome.failed);
        unawaited(preload());
        return RewardedAdOutcome.failed;
      },
    );
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
