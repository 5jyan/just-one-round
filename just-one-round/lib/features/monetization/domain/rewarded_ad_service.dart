import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RewardedAdStatus { disabled, loading, ready, unavailable }

enum RewardedAdOutcome { earned, dismissed, failed }

abstract interface class RewardedAdService {
  ValueListenable<RewardedAdStatus> get status;

  Future<void> initialize();

  Future<void> preload();

  Future<bool> showPrivacyOptions();

  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  });

  void dispose();
}

final rewardedAdServiceProvider = Provider<RewardedAdService>(
  (ref) => DisabledRewardedAdService(),
);

class DisabledRewardedAdService implements RewardedAdService {
  final ValueNotifier<RewardedAdStatus> _status = ValueNotifier(
    RewardedAdStatus.disabled,
  );

  @override
  ValueListenable<RewardedAdStatus> get status => _status;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> preload() async {}

  @override
  Future<bool> showPrivacyOptions() async => false;

  @override
  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  }) async => RewardedAdOutcome.failed;

  @override
  void dispose() => _status.dispose();
}

class FakeRewardedAdService implements RewardedAdService {
  FakeRewardedAdService({
    this.outcome = RewardedAdOutcome.earned,
    this.showDelay = Duration.zero,
  });

  final RewardedAdOutcome outcome;
  final Duration showDelay;
  final ValueNotifier<RewardedAdStatus> _status = ValueNotifier(
    RewardedAdStatus.ready,
  );

  @override
  ValueListenable<RewardedAdStatus> get status => _status;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> preload() async {
    _status.value = RewardedAdStatus.ready;
  }

  @override
  Future<bool> showPrivacyOptions() async => false;

  @override
  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  }) async {
    if (showDelay > Duration.zero) await Future<void>.delayed(showDelay);
    return outcome;
  }

  @override
  void dispose() => _status.dispose();
}
