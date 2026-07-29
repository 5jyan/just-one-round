import 'dart:async';
import 'dart:math' show max, min, pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_definition.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';
import 'package:just_one_round/features/legal/legal_config.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/profile/presentation/nickname_dialog.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  var _isClaiming = false;
  var _isSavingProfile = false;
  var _isRunningDeveloperAction = false;
  late final RewardedAdService _rewardedAdService;
  late RewardedAdStatus _rewardedAdStatus;
  var _adPreloadRequested = false;
  var _accountDeleted = false;
  var _isCheckingDailyReset = false;
  var _isDailyResetDialogVisible = false;
  var _isCheckingPreviousResult = false;
  var _isPreviousResultDialogVisible = false;
  var _testerVersionTapCount = 0;
  Timer? _dailyResetTimer;
  Timer? _previousResultTimer;
  Timer? _testerVersionTapTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rewardedAdService = ref.read(rewardedAdServiceProvider);
    _rewardedAdStatus = _rewardedAdService.status.value;
    _rewardedAdService.status.addListener(_handleRewardedAdStatus);
    ref.listenManual(
      todayStateProvider,
      (_, next) => next.whenData(_handleTodayState),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _previousResultTimer?.cancel();
    _testerVersionTapTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _rewardedAdService.status.removeListener(_handleRewardedAdStatus);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    }
  }

  void _handleTodayState(TodayState state) {
    _preloadRewardedAdIfNeeded(state);
    _scheduleDailyResetCheck();
    _schedulePreviousResultCheck();
    if (!state.testMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_checkForPreviousDailyResult());
      });
    }
  }

  Future<void> _handleAppResumed() async {
    final changed = await _checkForDailyGameChange();
    if (!changed) await _checkForPreviousDailyResult();
  }

  void _scheduleDailyResetCheck() {
    _dailyResetTimer?.cancel();
    final delay =
        durationUntilNextDailyReset(DateTime.now()) +
        const Duration(seconds: 1);
    _dailyResetTimer = Timer(delay, () {
      unawaited(_checkForDailyGameChange());
    });
  }

  void _schedulePreviousResultCheck() {
    _previousResultTimer?.cancel();
    final delay =
        durationUntilNextPreviousResultAvailability(DateTime.now()) +
        const Duration(seconds: 1);
    _previousResultTimer = Timer(delay, () {
      unawaited(_checkForPreviousDailyResult());
    });
  }

  Future<void> _checkForPreviousDailyResult() async {
    if (_isCheckingPreviousResult ||
        _isDailyResetDialogVisible ||
        _isPreviousResultDialogVisible ||
        !mounted) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      _previousResultTimer?.cancel();
      _previousResultTimer = Timer(const Duration(seconds: 30), () {
        unawaited(_checkForPreviousDailyResult());
      });
      return;
    }
    final state = ref.read(todayStateProvider).value;
    if (state == null || state.testMode) return;

    _isCheckingPreviousResult = true;
    try {
      final result = await ref
          .read(dailyGameRepositoryProvider)
          .fetchUnseenPreviousDailyResult()
          .timeout(const Duration(seconds: 12));
      if (!mounted || result == null) {
        _schedulePreviousResultCheck();
        return;
      }
      await _showPreviousDailyResultDialog(result);
    } catch (_) {
      _schedulePreviousResultCheck();
    } finally {
      _isCheckingPreviousResult = false;
    }
  }

  Future<void> _showPreviousDailyResultDialog(
    PreviousDailyResult result,
  ) async {
    if (!mounted || _isPreviousResultDialogVisible) return;
    _isPreviousResultDialogVisible = true;
    try {
      final action = await showDialog<_PreviousResultAction>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          key: const Key('previous-daily-result-dialog'),
          backgroundColor: AppColors.surface,
          title: const Text('어제의 최종 결과'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                result.displayName,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                GameRegistry.formatScore(result.gameId, result.score),
                key: const Key('previous-result-score'),
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.reward,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '실제 기록 ${result.participants}개 중 '
                '${result.rank}위 · 상위 ${result.topPercent}%',
                key: const Key('previous-result-rank'),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PreviousResultAction.history),
              child: const Text('내 기록 보기'),
            ),
            FilledButton(
              key: const Key('acknowledge-previous-result'),
              onPressed: () =>
                  Navigator.of(context).pop(_PreviousResultAction.close),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      await ref
          .read(dailyGameRepositoryProvider)
          .acknowledgePreviousDailyResult(result.playDate, result.gameId);
      if (mounted && action == _PreviousResultAction.history) {
        context.push('/history');
      }
    } finally {
      _isPreviousResultDialogVisible = false;
      _schedulePreviousResultCheck();
    }
  }

  Future<bool> _checkForDailyGameChange({TodayState? displayedState}) async {
    if (_isCheckingDailyReset || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final currentState = displayedState ?? ref.read(todayStateProvider).value;
    if (currentState == null) return false;

    _isCheckingDailyReset = true;
    try {
      final latestState = await ref
          .read(dailyGameRepositoryProvider)
          .fetchToday()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return false;
      if (isSamePlayDate(currentState.playDate, latestState.playDate)) {
        _scheduleDailyResetCheck();
        return false;
      }
      await _showDailyGameChangedDialog();
      return true;
    } catch (_) {
      _scheduleDailyResetCheck();
      return false;
    } finally {
      _isCheckingDailyReset = false;
    }
  }

  Future<void> _showDailyGameChangedDialog() async {
    if (!mounted || _isDailyResetDialogVisible) return;
    _isDailyResetDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('오늘의 게임이 변경되었습니다.'),
          content: const Text('새로운 오늘의 게임을 불러올게요.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } finally {
      _isDailyResetDialogVisible = false;
      if (mounted) {
        _adPreloadRequested = false;
        ref.invalidate(todayStateProvider);
      }
    }
  }

  void _handleRewardedAdStatus() {
    if (!mounted) return;
    setState(() => _rewardedAdStatus = _rewardedAdService.status.value);
  }

  void _handleSettingsTap(TodayState state) {
    if (_isSavingProfile || _isRunningDeveloperAction) return;
    _openSettings(state);
  }

  Future<void> _openSettings(TodayState state) async {
    final showAdPrivacy = await _rewardedAdService.isPrivacyOptionsRequired();
    if (!mounted) return;
    final action = await showDialog<_SettingsAction>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('설정'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_SettingsAction.nickname),
            child: const ListTile(
              leading: Icon(Icons.badge_outlined, color: AppColors.text),
              title: Text('닉네임 설정'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SettingsAction.privacy),
            child: const ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: AppColors.text),
              title: Text('개인정보처리방침'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SettingsAction.terms),
            child: const ListTile(
              leading: Icon(Icons.description_outlined, color: AppColors.text),
              title: Text('서비스 이용약관'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_SettingsAction.community),
            child: const ListTile(
              leading: Icon(Icons.shield_outlined, color: AppColors.text),
              title: Text('커뮤니티 운영정책'),
            ),
          ),
          if (showAdPrivacy)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_SettingsAction.adPrivacy),
              child: const ListTile(
                leading: Icon(Icons.ads_click_outlined, color: AppColors.text),
                title: Text('광고 개인정보 선택'),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SettingsAction.delete),
            child: const ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
              title: Text(
                '계정 및 데이터 삭제',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
          if (state.testMode)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_SettingsAction.developer),
              child: const ListTile(
                key: Key('developer-mode-menu'),
                leading: Icon(Icons.developer_mode, color: AppColors.reward),
                title: Text('개발자 모드'),
                subtitle: Text('게임 변경 및 횟수 초기화'),
              ),
            ),
          GestureDetector(
            key: const Key('app-version-tap-target'),
            behavior: HitTestBehavior.opaque,
            onTap: state.testMode
                ? null
                : () => _handleTesterVersionTap(context),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Text(
                '앱 버전 1.0.0 (1)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _SettingsAction.nickname:
        await _editNickname(state.nickname);
      case _SettingsAction.privacy:
        await _openLegalUrl(LegalConfig.privacyUri);
      case _SettingsAction.terms:
        await _openLegalUrl(LegalConfig.termsUri);
      case _SettingsAction.community:
        await _openLegalUrl(LegalConfig.communityUri);
      case _SettingsAction.adPrivacy:
        await _showAdPrivacyOptions();
      case _SettingsAction.delete:
        await _deleteAccount();
      case _SettingsAction.developer:
        await _openDeveloperTools(state);
      case _SettingsAction.testerActivation:
        await _showTesterActivationDialog();
      case null:
        return;
    }
  }

  void _handleTesterVersionTap(BuildContext dialogContext) {
    _testerVersionTapTimer?.cancel();
    _testerVersionTapCount += 1;
    if (_testerVersionTapCount >= 7) {
      _testerVersionTapCount = 0;
      Navigator.of(dialogContext).pop(_SettingsAction.testerActivation);
      return;
    }
    _testerVersionTapTimer = Timer(const Duration(seconds: 4), () {
      _testerVersionTapCount = 0;
    });
  }

  Future<void> _showTesterActivationDialog() async {
    final activated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TesterPinDialog(
        onActivate: ref.read(dailyGameRepositoryProvider).activateTestMode,
      ),
    );
    if (activated != true || !mounted) return;
    ref.invalidate(todayStateProvider);
    _showMessage('테스트 모드가 활성화됐어요.');
  }

  Future<void> _openLegalUrl(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage('문서를 열지 못했어요.');
    }
  }

  Future<void> _showAdPrivacyOptions() async {
    final shown = await _rewardedAdService.showPrivacyOptions();
    if (mounted && !shown) {
      _showMessage('현재 지역에서는 변경할 광고 개인정보 선택이 없어요.');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('계정과 데이터를 삭제할까요?'),
        content: const Text(
          '닉네임, 모든 게임 기록과 광고 보상 기록이 영구 삭제됩니다. 이 작업은 되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRunningDeveloperAction = true);
    try {
      await ref.read(dailyGameRepositoryProvider).deleteAccount();
      if (mounted) setState(() => _accountDeleted = true);
    } catch (_) {
      if (mounted) _showMessage('계정을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

  Future<void> _openDeveloperTools(TodayState state) async {
    setState(() => _isRunningDeveloperAction = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final games = await repository.fetchDeveloperGames();
      if (!mounted) return;
      final action = await showDialog<_DeveloperAction>(
        context: context,
        builder: (context) =>
            _DeveloperToolsDialog(games: games, currentGameId: state.game?.id),
      );
      if (action == null || !mounted) return;
      if (action.resetProgress) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('오늘 기록을 초기화할까요?'),
            content: const Text('테스트 계정의 오늘 시도와 점수만 삭제됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('초기화'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await repository.resetDeveloperDailyProgress();
      } else {
        await repository.setDeveloperGame(action.gameId!);
      }
      ref.invalidate(todayStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action.resetProgress ? '오늘 기록을 초기화했어요.' : '테스트 게임을 변경했어요.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('개발자 기능을 실행하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

  Future<void> _start({
    required bool rewarded,
    required TodayState displayedState,
  }) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    try {
      if (await _checkForDailyGameChange(displayedState: displayedState)) {
        return;
      }
      final repository = ref.read(dailyGameRepositoryProvider);
      final attempt = rewarded
          ? await _claimRewardedAttempt(repository, displayedState.playDate)
          : await repository.claimDailyAttempt(displayedState.playDate);
      if (attempt == null) return;
      if (!mounted) return;
      setState(() => _isClaiming = false);
      await context.push('/play', extra: attempt);
      if (!mounted) return;
      ref.invalidate(todayStateProvider);
    } catch (error) {
      if (!mounted) return;
      if (_isAppUpdateRequiredError(error)) {
        ref.invalidate(todayStateProvider);
        _showMessage('새 버전이 필요해요. 업데이트 화면을 불러올게요.');
        return;
      }
      if (_isDailyGameChangedError(error)) {
        await _showDailyGameChangedDialog();
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('시작하지 못했어요: $error')));
    } finally {
      if (mounted && _isClaiming) setState(() => _isClaiming = false);
    }
  }

  Future<PlayAttempt?> _claimRewardedAttempt(
    DailyGameRepository repository,
    DateTime expectedPlayDate,
  ) async {
    final session = await repository.prepareRewardedAd(expectedPlayDate);

    final recoveredAttempt = await _claimVerifiedReward(
      repository,
      session.id,
      retries: 0,
    );
    if (recoveredAttempt != null) return recoveredAttempt;

    final outcome = await _rewardedAdService.show(
      userId: session.userId,
      verificationSessionId: session.id,
    );
    if (!mounted) return null;
    if (outcome == RewardedAdOutcome.dismissed) {
      _showMessage('광고를 끝까지 보면 한 판이 추가돼요.');
      return null;
    }
    if (outcome == RewardedAdOutcome.failed) {
      _showMessage('광고를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
      return null;
    }

    final verifiedAttempt = await _claimVerifiedReward(
      repository,
      session.id,
      retries: 8,
    );
    if (verifiedAttempt != null) return verifiedAttempt;
    _showMessage('광고 확인이 처리 중이에요. 잠시 후 버튼을 다시 눌러 주세요.');
    ref.invalidate(todayStateProvider);
    return null;
  }

  Future<PlayAttempt?> _claimVerifiedReward(
    DailyGameRepository repository,
    String sessionId, {
    required int retries,
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await repository.claimRewardedAttempt(sessionId);
      } on PostgrestException catch (error) {
        if (!_isRewardPending(error)) rethrow;
        if (attempt == retries) return null;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  bool _isRewardPending(PostgrestException error) =>
      error.message.contains('reward verification pending');

  bool _isDailyGameChangedError(Object error) =>
      error is PostgrestException &&
      (error.message.contains('daily game changed') ||
          error.message.contains('reward session not found'));

  bool _isAppUpdateRequiredError(Object error) =>
      error is AppUpdateRequiredException ||
      (error is PostgrestException &&
          error.message.contains('app update required'));

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editNickname(String? currentNickname) async {
    var nickname = await showNicknameDialog(
      context,
      initialNickname: currentNickname,
    );
    while (nickname != null && mounted) {
      setState(() => _isSavingProfile = true);
      try {
        await ref.read(dailyGameRepositoryProvider).setNickname(nickname);
        ref.invalidate(todayStateProvider);
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        await _showProfileResultDialog(title: '저장 완료', message: '닉네임이 저장됐어요.');
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        final retryNickname = showNicknameDialog(
          context,
          initialNickname: nickname,
        );
        await _showProfileResultDialog(
          title: '저장 오류',
          message: _profileSaveErrorMessage(error),
        );
        nickname = await retryNickname;
      }
    }
  }

  String _profileSaveErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('nickname already taken')) {
      return '이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요.';
    }
    return '닉네임을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _showProfileResultDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuide(TodayState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GameGuideSheet(game: state.game),
    );
  }

  Future<void> _showRanking(TodayState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RankingSheet(
        initialResult:
            state.result ??
            const DailyRankResult(
              score: null,
              rank: null,
              participants: 0,
              topPercent: null,
              nickname: null,
              nearby: [],
            ),
        gameId: state.game?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accountDeleted) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PixelPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primary,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '계정과 데이터가 삭제됐어요.',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '다시 시작하면 기존 기록과 연결되지 않는 새 익명 계정이 만들어집니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    PixelButton(
                      label: '새로 시작',
                      onPressed: () {
                        setState(() => _accountDeleted = false);
                        ref.invalidate(todayStateProvider);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final today = ref.watch(todayStateProvider);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _PixelGridBackground()),
            today.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PixelPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('서버에 연결하지 못했어요.'),
                        const SizedBox(height: 16),
                        PixelButton(
                          label: '다시 연결',
                          onPressed: () => ref.invalidate(todayStateProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              data: (state) => state.requiresUpdate
                  ? _RequiredUpdateView(
                      compatibility: state.compatibility,
                      onRetry: () => ref.invalidate(todayStateProvider),
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Header(
                                isSaving:
                                    _isSavingProfile ||
                                    _isRunningDeveloperAction,
                                onHistory: () => context.push('/history'),
                                onSettings: () => _handleSettingsTap(state),
                              ),
                              const SizedBox(height: 12),
                              _GamePreview(gameId: state.game?.id),
                              const SizedBox(height: 18),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      state.game?.displayName ?? '오늘의 게임 준비 중',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  if (state.testMode)
                                    const _StatusBadge(label: 'TEST MODE'),
                                ],
                              ),
                              const SizedBox(height: 9),
                              _TodaySummary(
                                gameId: state.game?.id,
                                result: state.result,
                              ),
                              if (state.result?.score case final score?) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '내 기록 ${GameRegistry.formatScore(state.game?.id, score)}'
                                  '${state.result?.rank == null ? '' : ' · ${state.result!.rank}등'}',
                                  style: const TextStyle(
                                    color: AppColors.reward,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: _HomeActionButton(
                                      key: const Key('game-guide-button'),
                                      label: '게임 설명',
                                      icon: Icons.menu_book_outlined,
                                      onPressed: () => _showGuide(state),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _HomeActionButton(
                                      key: const Key('ranking-button'),
                                      label: '오늘의 랭킹',
                                      icon: Icons.emoji_events_outlined,
                                      onPressed: () => _showRanking(state),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              if (state.canClaimDaily)
                                PixelButton(
                                  label: _isClaiming
                                      ? GamePresentationRegistry.forId(
                                          state.game?.id,
                                        ).loadingLabel
                                      : '딱 한 판만!',
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: _isClaiming
                                      ? null
                                      : () => _start(
                                          rewarded: false,
                                          displayedState: state,
                                        ),
                                )
                              else if (state.adAttemptAvailable)
                                PixelButton(
                                  label: _rewardedButtonLabel(state),
                                  icon: Icons.ondemand_video_outlined,
                                  onPressed:
                                      _isClaiming ||
                                          _rewardedAdStatus ==
                                              RewardedAdStatus.disabled ||
                                          _rewardedAdStatus ==
                                              RewardedAdStatus.loading
                                      ? null
                                      : () => _start(
                                          rewarded: true,
                                          displayedState: state,
                                        ),
                                )
                              else
                                const PixelButton(
                                  label: '오늘의 플레이 완료',
                                  icon: Icons.check_rounded,
                                  onPressed: null,
                                ),
                              const SizedBox(height: 14),
                              Text(
                                _statusText(state),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _preloadRewardedAdIfNeeded(TodayState state) {
    if (!state.adAttemptAvailable || _adPreloadRequested) return;
    _adPreloadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_rewardedAdService.preload());
    });
  }

  String _rewardedButtonLabel(TodayState state) {
    if (_isClaiming) {
      return GamePresentationRegistry.forId(state.game?.id).loadingLabel;
    }
    return switch (_rewardedAdStatus) {
      RewardedAdStatus.loading => '광고 준비 중…',
      RewardedAdStatus.disabled => '추가 플레이 준비 중',
      RewardedAdStatus.ready => '광고 보고 한 판 더',
      RewardedAdStatus.unavailable => '광고 다시 불러오기',
    };
  }

  String _statusText(TodayState state) {
    if (state.testMode) return '테스트 모드 · 제한 없이 계속 플레이할 수 있어요';
    if (state.canClaimDaily) return '아직 플레이하지 않았어요 · 기회 1회';
    if (state.adAttemptAvailable) return '첫 판 완료 · 광고로 기회 1회 추가 가능';
    if (state.hasPlayed) return '오늘의 플레이를 모두 마쳤어요';
    return '중단된 게임은 다시 시작할 수 없어요';
  }
}

class _RequiredUpdateView extends StatelessWidget {
  const _RequiredUpdateView({
    required this.compatibility,
    required this.onRetry,
  });

  final ClientCompatibility compatibility;
  final VoidCallback onRetry;

  Future<void> _openStore(BuildContext context) async {
    final rawUrl = compatibility.storeUrl;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('스토어를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('required-update-screen'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: PixelPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: AppColors.primary,
                size: 56,
              ),
              const SizedBox(height: 18),
              Text(
                compatibility.reason == 'unsupported_game'
                    ? '새 게임 업데이트가 필요해요'
                    : '앱 업데이트가 필요해요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '오늘의 게임을 안전하게 플레이하려면 최신 버전으로 업데이트해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '현재 빌드 ${compatibility.currentBuild}'
                ' · 필요 빌드 ${compatibility.minimumSupportedBuild}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 22),
              PixelButton(
                key: const Key('required-update-button'),
                label: '스토어에서 업데이트',
                icon: Icons.open_in_new_rounded,
                onPressed: () => _openStore(context),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const Key('required-update-retry'),
                onPressed: onRetry,
                child: const Text('업데이트 확인'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum _PreviousResultAction { history, close }

enum _SettingsAction {
  nickname,
  privacy,
  terms,
  community,
  adPrivacy,
  delete,
  developer,
  testerActivation,
}

class _DeveloperAction {
  const _DeveloperAction.changeGame(this.gameId) : resetProgress = false;
  const _DeveloperAction.reset() : gameId = null, resetProgress = true;

  final String? gameId;
  final bool resetProgress;
}

class _TesterPinDialog extends StatefulWidget {
  const _TesterPinDialog({required this.onActivate});

  final Future<TesterActivationResult> Function(String pin) onActivate;

  @override
  State<_TesterPinDialog> createState() => _TesterPinDialogState();
}

class _TesterPinDialogState extends State<_TesterPinDialog> {
  final _controller = TextEditingController();
  var _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || _controller.text.length != 6) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await widget.onActivate(_controller.text);
      if (!mounted) return;
      switch (result.status) {
        case TesterActivationStatus.activated:
          Navigator.of(context).pop(true);
        case TesterActivationStatus.invalid:
          _controller.clear();
          setState(() {
            final remaining = result.attemptsRemaining;
            _errorText = remaining == null
                ? 'PIN이 올바르지 않아요.'
                : 'PIN이 올바르지 않아요. $remaining회 남았어요.';
          });
        case TesterActivationStatus.locked:
          final seconds = result.retryAfterSeconds ?? 900;
          final minutes = (seconds / 60).ceil();
          setState(() {
            _errorText = '입력 횟수를 초과했어요. 약 $minutes분 후 다시 시도해 주세요.';
          });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = '인증하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('테스터 인증'),
      content: TextField(
        key: const Key('tester-pin-field'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          labelText: '6자리 PIN',
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const Key('activate-tester-mode'),
          onPressed: _isSubmitting ? null : _submit,
          child: Text(_isSubmitting ? '확인 중...' : '확인'),
        ),
      ],
    );
  }
}

class _DeveloperToolsDialog extends StatefulWidget {
  const _DeveloperToolsDialog({
    required this.games,
    required this.currentGameId,
  });

  final List<DeveloperGame> games;
  final String? currentGameId;

  @override
  State<_DeveloperToolsDialog> createState() => _DeveloperToolsDialogState();
}

class _DeveloperToolsDialogState extends State<_DeveloperToolsDialog> {
  late String? _selectedGameId =
      widget.games.any((game) => game.id == widget.currentGameId)
      ? widget.currentGameId
      : widget.games.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('개발자 모드'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('developer-game-dropdown'),
            initialValue: _selectedGameId,
            decoration: const InputDecoration(
              labelText: '테스트할 게임',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final game in widget.games)
                DropdownMenuItem(
                  value: game.id,
                  child: Text('${game.displayName} v${game.version}'),
                ),
            ],
            onChanged: (value) => setState(() => _selectedGameId = value),
          ),
          const SizedBox(height: 12),
          const Text(
            '게임 변경은 현재 테스트 계정에만 적용됩니다.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('reset-daily-progress'),
          onPressed: () =>
              Navigator.of(context).pop(const _DeveloperAction.reset()),
          child: const Text('게임 횟수 초기화'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          key: const Key('apply-developer-game'),
          onPressed: _selectedGameId == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_DeveloperAction.changeGame(_selectedGameId)),
          child: const Text('게임 적용'),
        ),
      ],
    );
  }
}

class _RankingSheet extends ConsumerWidget {
  const _RankingSheet({required this.initialResult, required this.gameId});

  final DailyRankResult initialResult;
  final String? gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = initialResult;
    final rankingItems = _mergeRankingEntries(
      leaders: result.leaders,
      nearby: result.nearby,
      participants: result.participants,
    );
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'DAILY LEADERBOARD',
            title: '오늘의 랭킹',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _RankSummaryValue(
                  value: '${result.participants}개',
                  label: '실제 기록',
                ),
              ),
              Container(width: 1, height: 42, color: AppColors.surfaceLight),
              Expanded(
                child: _RankSummaryValue(
                  value: result.bestScore == null
                      ? '-'
                      : GameRegistry.formatScore(gameId, result.bestScore!),
                  label: '현재 최고',
                ),
              ),
              if (result.rank case final rank?) ...[
                Container(width: 1, height: 42, color: AppColors.surfaceLight),
                Expanded(
                  child: _RankSummaryValue(value: '$rank등', label: '내 순위'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const _RankingSectionTitle(
            eyebrow: 'REAL PLAYERS',
            title: '전체 비교 랭킹',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rankingItems.isEmpty
                ? const Center(
                    child: Text(
                      '아직 등록된 기록이 없어요.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView(
                    key: const Key('overall-leaderboard'),
                    children: [
                      for (
                        var index = 0;
                        index < rankingItems.length;
                        index++
                      ) ...[
                        if (rankingItems[index].entry == null)
                          const _LeaderboardGapRow()
                        else
                          _LeaderboardRow(
                            entry: rankingItems[index].entry!,
                            gameId: gameId,
                            onModerate: (action) => _moderatePlayer(
                              context,
                              ref,
                              rankingItems[index].entry!,
                              action,
                            ),
                          ),
                        if (index < rankingItems.length - 1)
                          const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _moderatePlayer(
    BuildContext context,
    WidgetRef ref,
    NearbyRank entry,
    _PlayerModerationAction action,
  ) async {
    final userId = entry.userId;
    if (userId == null) return;
    final repository = ref.read(dailyGameRepositoryProvider);
    try {
      switch (action) {
        case _PlayerModerationAction.report:
          await repository.reportNickname(userId);
        case _PlayerModerationAction.block:
          await repository.blockUser(userId);
      }
      ref.invalidate(todayStateProvider);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == _PlayerModerationAction.report
                ? '닉네임을 신고했어요. 운영팀이 확인할게요.'
                : '이 사용자의 닉네임을 숨겼어요.',
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리하지 못했어요. 다시 시도해 주세요.')));
      }
    }
  }
}

List<_LeaderboardListItem> _mergeRankingEntries({
  required List<NearbyRank> leaders,
  required List<NearbyRank> nearby,
  required int participants,
}) {
  const targetEntryCount = 8;
  final sortedLeaders = [...leaders]..sort((a, b) => a.rank.compareTo(b.rank));
  final entriesByRank = <int, NearbyRank>{};

  void addEntry(NearbyRank entry) {
    final existing = entriesByRank[entry.rank];
    if (existing == null || entry.isMe) {
      entriesByRank[entry.rank] = entry;
    }
  }

  for (final entry in sortedLeaders.take(5)) {
    addEntry(entry);
  }
  for (final entry in nearby) {
    addEntry(entry);
  }
  for (final entry in sortedLeaders) {
    if (entriesByRank.length >= targetEntryCount) break;
    addEntry(entry);
  }

  final entries = entriesByRank.values.toList()
    ..sort((a, b) => a.rank.compareTo(b.rank));
  if (entries.isEmpty) return const [];

  final items = <_LeaderboardListItem>[];
  var previousRank = 0;
  for (final entry in entries) {
    if (entry.rank > previousRank + 1) {
      items.add(const _LeaderboardListItem.gap());
    }
    items.add(_LeaderboardListItem.entry(entry));
    previousRank = entry.rank;
  }
  if (previousRank < participants) {
    items.add(const _LeaderboardListItem.gap());
  }
  return items;
}

class _LeaderboardListItem {
  const _LeaderboardListItem.entry(this.entry);
  const _LeaderboardListItem.gap() : entry = null;

  final NearbyRank? entry;
}

class _LeaderboardGapRow extends StatelessWidget {
  const _LeaderboardGapRow();

  @override
  Widget build(BuildContext context) => const SizedBox(
    key: Key('leaderboard-gap'),
    height: 22,
    child: Center(
      child: Text(
        '•••',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
    ),
  );
}

class _RankingSectionTitle extends StatelessWidget {
  const _RankingSectionTitle({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Text(
        eyebrow,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

enum _PlayerModerationAction { report, block }

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.gameId,
    required this.onModerate,
  });

  final NearbyRank entry;
  final String? gameId;
  final ValueChanged<_PlayerModerationAction> onModerate;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.rank) {
      1 => AppColors.primary,
      2 => AppColors.border,
      3 => AppColors.primaryShadow,
      _ => AppColors.textMuted,
    };
    return Container(
      key: entry.isMe ? const Key('my-leaderboard-rank') : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: entry.isMe
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.backgroundDeep,
        border: Border.all(
          color: entry.isMe ? AppColors.primary : AppColors.surfaceLight,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: accent,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (entry.isMe) ...[
                  const SizedBox(width: 7),
                  Container(
                    key: const Key('my-rank-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: AppColors.primary,
                    child: const Text(
                      '나',
                      style: TextStyle(
                        color: AppColors.backgroundDeep,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            GameRegistry.formatScore(gameId, entry.score),
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.reward,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!entry.isMe && !entry.isNpc && entry.userId != null)
            PopupMenuButton<_PlayerModerationAction>(
              tooltip: '사용자 신고 또는 차단',
              onSelected: onModerate,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PlayerModerationAction.report,
                  child: Text('닉네임 신고'),
                ),
                PopupMenuItem(
                  value: _PlayerModerationAction.block,
                  child: Text('사용자 차단'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RankSummaryValue extends StatelessWidget {
  const _RankSummaryValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'Galmuri',
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _GameGuideSheet extends StatefulWidget {
  const _GameGuideSheet({required this.game});

  final TodayGame? game;

  @override
  State<_GameGuideSheet> createState() => _GameGuideSheetState();
}

class _GameGuideSheetState extends State<_GameGuideSheet> {
  late final PageController _pageController;
  var _pageIndex = 0;

  List<GameGuidePageDefinition> get _pages =>
      GamePresentationRegistry.forId(widget.game?.id).guidePages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_pageIndex == _pages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'HOW TO PLAY · ${_pageIndex + 1}/${pages.length}',
            title: '게임 설명',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              key: const Key('game-guide-pages'),
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => _pageIndex = value),
              itemBuilder: (context, index) =>
                  _GuidePage(index: index, page: pages[index]),
            ),
          ),
          const SizedBox(height: 12),
          if (pages.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < pages.length; index++)
                  AnimatedContainer(
                    key: Key('guide-page-dot-$index'),
                    duration: const Duration(milliseconds: 180),
                    width: index == _pageIndex ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    color: index == _pageIndex
                        ? AppColors.primary
                        : AppColors.surfaceLight,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('guide-previous-button'),
                    onPressed: _pageIndex == 0
                        ? null
                        : () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.text,
                      disabledForegroundColor: AppColors.textMuted,
                      side: BorderSide(
                        color: _pageIndex == 0
                            ? AppColors.surfaceLight
                            : AppColors.border,
                        width: 2,
                      ),
                      shape: const RoundedRectangleBorder(),
                      textStyle: const TextStyle(
                        fontFamily: 'Galmuri',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('이전'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PixelButton(
                  key: const Key('guide-next-button'),
                  label: _pageIndex == pages.length - 1 ? '설명 끝' : '다음',
                  icon: _pageIndex == pages.length - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.index, required this.page});

  final int index;
  final GameGuidePageDefinition page;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 268,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.backgroundDeep,
              border: Border.all(color: AppColors.surfaceLight, width: 2),
            ),
            child: ClipRect(child: _GuideVisual(kind: page.visual)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${index + 1}'.padLeft(2, '0'),
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Galmuri',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          page.title,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          page.description,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
        if (page.detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.detail,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _GuideVisual extends StatelessWidget {
  const _GuideVisual({required this.kind});

  final GameGuideVisualKind kind;

  @override
  Widget build(BuildContext context) => switch (kind) {
    GameGuideVisualKind.dungSwipe => const _SwipeGuideVisual(),
    GameGuideVisualKind.dungGameplay => const _GameplayGuideVisual(),
    GameGuideVisualKind.dungDifficulty => const _DifficultyGuideVisual(),
    GameGuideVisualKind.dungCollision => const _CollisionGuideVisual(),
    GameGuideVisualKind.dungSurvival => const _SurvivalGuideVisual(),
    GameGuideVisualKind.appleDrag => const _AppleDragGuideVisual(),
    GameGuideVisualKind.appleTarget => const _AppleTargetGuideVisual(),
    GameGuideVisualKind.appleSparseRectangle =>
      const _AppleSparseRectangleGuideVisual(),
    GameGuideVisualKind.appleScoring => const _AppleScoringGuideVisual(),
    GameGuideVisualKind.appleResult => const _AppleResultGuideVisual(),
    GameGuideVisualKind.gravityControl => const _GravityControlGuideVisual(),
    GameGuideVisualKind.gravityLanding => const _GravityLandingGuideVisual(),
    GameGuideVisualKind.gravityObstacle => const _GravityObstacleGuideVisual(),
    GameGuideVisualKind.gravityDifficulty =>
      const _GravityDifficultyGuideVisual(),
    GameGuideVisualKind.gravitySurvival => const _GravitySurvivalGuideVisual(),
    GameGuideVisualKind.numberSequence => const _NumberSequenceGuideVisual(),
    GameGuideVisualKind.numberNext => const _NumberNextGuideVisual(),
    GameGuideVisualKind.numberRefill => const _NumberRefillGuideVisual(),
    GameGuideVisualKind.numberMistake => const _NumberMistakeGuideVisual(),
    GameGuideVisualKind.numberResult => const _NumberResultGuideVisual(),
  };
}

class _AppleGuideScene extends StatelessWidget {
  const _AppleGuideScene({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/apple_game_v2/apple_game_background.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.22),
        filterQuality: FilterQuality.none,
      ),
      const ColoredBox(color: Color(0x4D010B27)),
      child,
    ],
  );
}

class _AppleDragGuideVisual extends StatelessWidget {
  const _AppleDragGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-drag-guide',
    assetPath: 'assets/images/apple_game_v2/guide_drag_sprite_sheet.png',
    frameCount: 8,
    frameDuration: Duration(milliseconds: 175),
  );
}

class _AppleTargetGuideVisual extends StatelessWidget {
  const _AppleTargetGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-target-guide',
    assetPath: 'assets/images/apple_game_v2/guide_target_pop_sprite_sheet.png',
    frameCount: 12,
    frameDuration: Duration(milliseconds: 125),
  );
}

class _AppleSparseRectangleGuideVisual extends StatelessWidget {
  const _AppleSparseRectangleGuideVisual();

  @override
  Widget build(BuildContext context) => const _AppleGuideSpriteAnimation(
    id: 'apple-sparse-guide',
    assetPath: 'assets/images/apple_game_v2/guide_sparse_pop_sprite_sheet.png',
    frameCount: 12,
    frameDuration: Duration(milliseconds: 125),
  );
}

class _AppleGuideSpriteAnimation extends StatefulWidget {
  const _AppleGuideSpriteAnimation({
    required this.id,
    required this.assetPath,
    required this.frameCount,
    required this.frameDuration,
  });

  final String id;
  final String assetPath;
  final int frameCount;
  final Duration frameDuration;

  @override
  State<_AppleGuideSpriteAnimation> createState() =>
      _AppleGuideSpriteAnimationState();
}

class _AppleGuideSpriteAnimationState
    extends State<_AppleGuideSpriteAnimation> {
  Timer? _frameTimer;
  var _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(widget.frameDuration, (_) {
      if (!mounted) return;
      setState(() => _frameIndex = (_frameIndex + 1) % widget.frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Center(
      child: SizedBox(
        key: Key('${widget.id}-sprite'),
        width: _AppleGuideLayout.sceneWidth,
        height: _AppleGuideLayout.sceneHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              key: Key('${widget.id}-frame-$_frameIndex'),
              left: -_frameIndex * _AppleGuideLayout.sceneWidth,
              top: 0,
              width: _AppleGuideLayout.sceneWidth * widget.frameCount,
              height: _AppleGuideLayout.sceneHeight,
              child: Image.asset(
                widget.assetPath,
                key: Key('${widget.id}-sheet'),
                width: _AppleGuideLayout.sceneWidth * widget.frameCount,
                height: _AppleGuideLayout.sceneHeight,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppleScoringGuideVisual extends StatelessWidget {
  const _AppleScoringGuideVisual();

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Row(
        children: [
          const Expanded(
            child: _AppleScoreExample(
              label: '4 + 6',
              values: [4, 6],
              score: '+2점',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.primary.withValues(alpha: 0.9),
              size: 26,
            ),
          ),
          const Expanded(
            child: _AppleScoreExample(
              label: '1 + 2 + 3 + 4',
              values: [1, 2, 3, 4],
              score: '+4점',
              emphasized: true,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppleResultGuideVisual extends StatelessWidget {
  const _AppleResultGuideVisual();

  @override
  Widget build(BuildContext context) => _AppleGuideScene(
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xE6011B19),
          border: Border.all(color: const Color(0xFFFFD24A), width: 2),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TIME  02:00',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: Color(0xFFFFD24A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '48개',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: Color(0xFFFFF3C4),
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '많이 지울수록 높은 순위',
              style: TextStyle(
                color: AppColors.reward,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppleGuideBoard extends StatelessWidget {
  const _AppleGuideBoard({required this.values});

  static const cellSize = 42.0;
  static const padding = 8.0;

  final List<List<int?>> values;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.all(padding),
      color: const Color(0xB3011B19),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in row)
                  value == null
                      ? const SizedBox.square(dimension: cellSize)
                      : _AppleGuideTile(value: value),
              ],
            ),
        ],
      ),
    ),
  );
}

class _AppleGuideTile extends StatelessWidget {
  const _AppleGuideTile({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _AppleGuideBoard.cellSize,
    child: Stack(
      alignment: Alignment.center,
      children: [
        _AppleAtlasFrame(value: value),
        Text(
          '$value',
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: const Color(0xFFFFF3C4),
            fontSize: _AppleGuideBoard.cellSize * 0.38,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: Color(0xFF591F2C), offset: Offset(1, 1)),
              Shadow(color: Color(0xFF591F2C), offset: Offset(-1, -1)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AppleAtlasFrame extends StatelessWidget {
  const _AppleAtlasFrame({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final index = value - 1;
    final row = index ~/ 3;
    final column = index % 3;
    const frameSize = _AppleGuideBoard.cellSize;
    const sheetSize = frameSize * 3;
    return SizedBox.square(
      dimension: frameSize,
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(-column * frameSize, -row * frameSize),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: sheetSize,
            maxWidth: sheetSize,
            minHeight: sheetSize,
            maxHeight: sheetSize,
            child: Image.asset(
              'assets/images/apple_game_v2/apple_faces_atlas.png',
              width: sheetSize,
              height: sheetSize,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppleSumBadge extends StatelessWidget {
  const _AppleSumBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    color: const Color(0xE67B352D),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: 'Galmuri',
        color: Color(0xFFFFF3C4),
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _AppleScoreExample extends StatelessWidget {
  const _AppleScoreExample({
    required this.label,
    required this.values,
    required this.score,
    this.emphasized = false,
  });

  final String label;
  final List<int> values;
  final String score;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xD9011B19),
      border: Border.all(
        color: emphasized ? const Color(0xFFFFD24A) : AppColors.border,
        width: 2,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          children: [for (final value in values) _AppleGuideTile(value: value)],
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFF3C4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          score,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: emphasized ? const Color(0xFFFFD24A) : AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

abstract final class _AppleGuideLayout {
  static const sceneWidth = 246.0;
  static const sceneHeight = 176.0;

  static double contentLeft(int columnCount) =>
      (sceneWidth -
              (columnCount * _AppleGuideBoard.cellSize +
                  _AppleGuideBoard.padding * 2)) /
          2 +
      _AppleGuideBoard.padding;

  static double contentTop(int rowCount) =>
      (sceneHeight -
              (rowCount * _AppleGuideBoard.cellSize +
                  _AppleGuideBoard.padding * 2)) /
          2 +
      _AppleGuideBoard.padding;
}

class _SwipeGuideVisual extends StatelessWidget {
  const _SwipeGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.72),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 40,
        left: 0,
        right: 0,
        child: Center(
          child: _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/player_run_sheet.png',
            frameSize: 82,
          ),
        ),
      ),
      Positioned(
        left: 34,
        right: 34,
        bottom: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: AppColors.primary,
              size: 38,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: AppColors.backgroundDeep.withValues(alpha: 0.8),
              child: const Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: AppColors.text,
                    size: 22,
                  ),
                  SizedBox(width: 5),
                  Text(
                    '누르고 드래그',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_double_arrow_right_rounded,
              color: AppColors.primary,
              size: 38,
            ),
          ],
        ),
      ),
    ],
  );
}

class _GameplayGuideVisual extends StatelessWidget {
  const _GameplayGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.none,
      ),
      const Positioned(left: 10, top: 10, child: _VisualLabel(label: '인게임 화면')),
    ],
  );
}

class _DifficultyGuideVisual extends StatelessWidget {
  const _DifficultyGuideVisual();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: _DifficultyLane(
          label: '초반',
          color: AppColors.reward,
          poopPositions: [Alignment(0.35, -0.45), Alignment(-0.55, 0.05)],
        ),
      ),
      Container(width: 2, color: AppColors.border),
      const Expanded(
        child: _DifficultyLane(
          label: '후반',
          color: AppColors.danger,
          poopPositions: [
            Alignment(-0.65, -0.75),
            Alignment(0.45, -0.55),
            Alignment(-0.1, -0.15),
            Alignment(0.7, 0.08),
            Alignment(-0.7, 0.38),
            Alignment(0.08, 0.62),
          ],
        ),
      ),
    ],
  );
}

class _DifficultyLane extends StatelessWidget {
  const _DifficultyLane({
    required this.label,
    required this.color,
    required this.poopPositions,
  });

  final String label;
  final Color color;
  final List<Alignment> poopPositions;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.55),
        filterQuality: FilterQuality.none,
      ),
      for (final position in poopPositions)
        Align(
          alignment: position,
          child: const _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
            frameSize: 35,
          ),
        ),
      Positioned(
        left: 8,
        top: 8,
        child: _VisualLabel(label: label, color: color),
      ),
    ],
  );
}

class _CollisionGuideVisual extends StatelessWidget {
  const _CollisionGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.75),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 36,
        left: 92,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/player_idle_sheet.png',
          frameSize: 86,
        ),
      ),
      const Positioned(
        bottom: 116,
        left: 111,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
          frameSize: 48,
        ),
      ),
      Positioned(
        right: 16,
        top: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          color: AppColors.danger.withValues(alpha: 0.92),
          child: const Text(
            '한 번 충돌 = 종료',
            style: TextStyle(
              color: AppColors.backgroundDeep,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ],
  );
}

class _SurvivalGuideVisual extends StatelessWidget {
  const _SurvivalGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        color: AppColors.backgroundDeep.withValues(alpha: 0.35),
        colorBlendMode: BlendMode.srcOver,
        filterQuality: FilterQuality.none,
      ),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          color: AppColors.backgroundDeep.withValues(alpha: 0.88),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primary,
                size: 34,
              ),
              SizedBox(height: 8),
              Text(
                '최대 5:00',
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '0.01초 단위로 랭킹 경쟁',
                style: TextStyle(
                  color: AppColors.reward,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _GravityControlGuideVisual extends StatelessWidget {
  const _GravityControlGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-control-sprite-animation'),
    mode: _GravityGuideMode.control,
  );
}

class _GravityLandingGuideVisual extends StatelessWidget {
  const _GravityLandingGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-landing-animation'),
    mode: _GravityGuideMode.landing,
  );
}

class _GravityObstacleGuideVisual extends StatelessWidget {
  const _GravityObstacleGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-obstacle-animation'),
    mode: _GravityGuideMode.obstacle,
  );
}

class _GravityDifficultyGuideVisual extends StatelessWidget {
  const _GravityDifficultyGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-difficulty-animation'),
    mode: _GravityGuideMode.difficulty,
  );
}

class _GravitySurvivalGuideVisual extends StatelessWidget {
  const _GravitySurvivalGuideVisual();

  @override
  Widget build(BuildContext context) => const _GravityGuideAnimation(
    key: Key('gravity-collision-game-over-animation'),
    mode: _GravityGuideMode.collision,
  );
}

class _NumberSequenceGuideVisual extends StatelessWidget {
  const _NumberSequenceGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-sequence-animation'),
    mode: _NumberRushSceneMode.sequence,
  );
}

class _NumberNextGuideVisual extends StatelessWidget {
  const _NumberNextGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-next-animation'),
    mode: _NumberRushSceneMode.next,
  );
}

class _NumberRefillGuideVisual extends StatelessWidget {
  const _NumberRefillGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-refill-animation'),
    mode: _NumberRushSceneMode.refill,
  );
}

class _NumberMistakeGuideVisual extends StatelessWidget {
  const _NumberMistakeGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-mistake-animation'),
    mode: _NumberRushSceneMode.mistake,
  );
}

class _NumberResultGuideVisual extends StatelessWidget {
  const _NumberResultGuideVisual();

  @override
  Widget build(BuildContext context) => const _NumberRushPreview(
    key: Key('number-rush-result-animation'),
    mode: _NumberRushSceneMode.result,
  );
}

class _VisualLabel extends StatelessWidget {
  const _VisualLabel({required this.label, this.color = AppColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: AppColors.backgroundDeep.withValues(alpha: 0.86),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: SafeArea(top: false, child: child),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.eyebrow,
    required this.title,
    required this.onClose,
  });

  final String eyebrow;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 44,
        height: 4,
        color: AppColors.border.withValues(alpha: 0.6),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.text),
          ),
        ],
      ),
    ],
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.gameId, required this.result});

  final String? gameId;
  final DailyRankResult? result;

  @override
  Widget build(BuildContext context) {
    final participants = result?.participants ?? 0;
    final bestScore = result?.bestScore;
    final challengeText = participants == 0
        ? '오늘 첫 기록에 도전해 보세요'
        : '오늘 비교 기록 $participants개';
    final bestText = bestScore == null
        ? null
        : '현재 최고 ${GameRegistry.formatScore(gameId, bestScore)}';
    return Text(
      bestText == null ? challengeText : '$challengeText · $bestText',
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.reward.withValues(alpha: 0.16),
      border: Border.all(color: AppColors.reward),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.reward,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    ),
  );
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      minimumSize: const Size.fromHeight(50),
      side: const BorderSide(color: AppColors.border, width: 2),
      shape: const RoundedRectangleBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    ),
  );
}

String _durationLabel(TodayGame? game) {
  return GamePresentationRegistry.forId(game?.id).durationLabel;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onSettings,
    required this.onHistory,
    required this.isSaving,
  });

  final VoidCallback onSettings;
  final VoidCallback onHistory;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '오늘의 게임',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_monthName(DateTime.now().month)} ${DateTime.now().day}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '내 기록',
              visualDensity: VisualDensity.compact,
              onPressed: onHistory,
              icon: const Icon(Icons.history, color: AppColors.text),
            ),
            IconButton(
              tooltip: '설정',
              visualDensity: VisualDensity.compact,
              onPressed: isSaving ? null : onSettings,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_outlined, color: AppColors.text),
            ),
          ],
        ),
      ],
    );
  }
}

String _monthName(int month) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return months[month - 1];
}

class _GamePreview extends StatelessWidget {
  const _GamePreview({required this.gameId});

  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final presentation = GamePresentationRegistry.forId(gameId);
    return AspectRatio(
      aspectRatio: presentation.homeAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: const [
            BoxShadow(color: AppColors.backgroundDeep, offset: Offset(6, 6)),
          ],
        ),
        child: switch (presentation.homePreview) {
          GameHomePreviewKind.dungDodgeV2 => const _DungDodgeV2Preview(),
          GameHomePreviewKind.gravitySwitch => const _GravityGamePreview(),
          GameHomePreviewKind.appleGameV2 => const _AppleGameV2Preview(),
          GameHomePreviewKind.numberRush => const _NumberRushHomePreview(),
        },
      ),
    );
  }
}

class _DungDodgeV2Preview extends StatelessWidget {
  const _DungDodgeV2Preview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('dung-dodge-v2-preview'),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/dung_dodge_v2/home_gameplay_hero.png',
          ),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _AtlasPreviewFrame extends StatelessWidget {
  const _AtlasPreviewFrame({required this.assetPath, required this.frameSize});

  final String assetPath;
  final double frameSize;

  @override
  Widget build(BuildContext context) {
    final sheetSize = frameSize * 2;
    return SizedBox.square(
      dimension: frameSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sheetSize,
          maxWidth: sheetSize,
          minHeight: sheetSize,
          maxHeight: sheetSize,
          child: Image.asset(
            assetPath,
            width: sheetSize,
            height: sheetSize,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
  }
}

class _NumberRushHomePreview extends StatefulWidget {
  const _NumberRushHomePreview();

  @override
  State<_NumberRushHomePreview> createState() => _NumberRushHomePreviewState();
}

class _NumberRushHomePreviewState extends State<_NumberRushHomePreview> {
  static const _frameCount = 40;

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cycleFrame = _frame % _frameCount;
    final progress = cycleFrame / _frameCount;
    final elapsed = 8.80 + cycleFrame / 10;
    final firstFrame = progress >= 0.12 && progress < 0.22
        ? 1
        : progress >= 0.22
        ? 2
        : 0;
    final secondFrame = progress >= 0.36 && progress < 0.46
        ? 1
        : progress >= 0.46
        ? 2
        : 0;
    final thirdFrame = progress >= 0.60 && progress < 0.70
        ? 1
        : progress >= 0.70
        ? 2
        : 0;
    final expected = progress < 0.22
        ? 1
        : progress < 0.46
        ? 2
        : progress < 0.70
        ? 3
        : 4;

    return DecoratedBox(
      key: const Key('number-rush-home-hero'),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/number_rush/home_gameplay_hero.png'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final tileSize = width * 0.1444;
          return Stack(
            key: const Key('number-rush-home-tap-animation'),
            fit: StackFit.expand,
            children: [
              Positioned(
                left: width * 0.2398,
                top: height * 0.1927,
                width: width * 0.167,
                height: height * 0.0743,
                child: ColoredBox(
                  color: const Color(0xFF020715),
                  child: Center(
                    child: Text(
                      elapsed.toStringAsFixed(2),
                      key: const Key('number-rush-home-time-value'),
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFF39F3FF),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              _NumberRushHomeTapTile(
                number: 1,
                frame: firstFrame,
                left: width * 0.1053,
                top: height * 0.575,
                size: tileSize,
              ),
              _NumberRushHomeTapTile(
                number: 2,
                frame: secondFrame,
                left: width * 0.1053,
                top: height * 0.4534,
                size: tileSize,
              ),
              _NumberRushHomeTapTile(
                number: 3,
                frame: thirdFrame,
                left: width * 0.4145,
                top: height * 0.4534,
                size: tileSize,
              ),
              Positioned(
                left: width * 0.6388,
                top: height * 0.1927,
                width: width * 0.0835,
                height: height * 0.0743,
                child: ColoredBox(
                  color: const Color(0xFF020715),
                  child: Center(
                    child: Text(
                      '$expected',
                      key: const Key('number-rush-home-next-value'),
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFF77CE),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NumberRushHomeTapTile extends StatelessWidget {
  const _NumberRushHomeTapTile({
    required this.number,
    required this.frame,
    required this.left,
    required this.top,
    required this.size,
  });

  final int number;
  final int frame;
  final double left;
  final double top;
  final double size;

  @override
  Widget build(BuildContext context) => Positioned(
    key: Key('number-rush-home-tile-$number'),
    left: left,
    top: top,
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        _NumberRushAtlasFrame(
          assetPath: 'assets/images/number_rush/number_button_states.png',
          columns: 3,
          rows: 2,
          frame: frame,
        ),
        Center(
          child: Text(
            '$number',
            style: TextStyle(
              fontFamily: 'Galmuri',
              color: frame == 2
                  ? const Color(0xFF183348)
                  : const Color(0xFF5DF5FF),
              fontSize: number >= 10 ? 17 : 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (frame == 1) ...[
          Positioned.fill(
            child: _NumberRushAtlasFrame(
              assetPath: 'assets/images/number_rush/arcade_fx_sheet.png',
              columns: 4,
              rows: 2,
              frame: 0,
            ),
          ),
          const Positioned(
            right: -3,
            bottom: -3,
            child: Icon(
              Icons.touch_app_rounded,
              color: Color(0xFFFFD84A),
              size: 18,
              shadows: [Shadow(color: Color(0xFF030713), blurRadius: 3)],
            ),
          ),
        ],
      ],
    ),
  );
}

enum _NumberRushSceneMode { main, sequence, next, refill, mistake, result }

class _NumberRushPreview extends StatefulWidget {
  const _NumberRushPreview({this.mode = _NumberRushSceneMode.main, super.key});

  final _NumberRushSceneMode mode;

  @override
  State<_NumberRushPreview> createState() => _NumberRushPreviewState();
}

class _NumberRushPreviewState extends State<_NumberRushPreview> {
  static const _frameCount = 40;
  static const _numbers = [
    12,
    3,
    19,
    7,
    24,
    15,
    1,
    21,
    9,
    5,
    18,
    11,
    25,
    2,
    14,
    6,
    23,
    10,
    17,
    4,
    20,
    8,
    16,
    22,
    13,
  ];

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _frame / _frameCount;
    var expected = 8;
    var elapsed = 28.80 + progress;
    var caption = '8을 찾으세요';
    var clearedNumbers = <int>{1, 2, 3, 4, 5, 6, 7};
    int? pressedNumber;
    int? wrongNumber;
    int? ignitionNumber;
    var replacementIndex = -1;
    int? replacementNumber;
    var replacementIsOn = false;
    var completed = false;

    switch (widget.mode) {
      case _NumberRushSceneMode.main:
        if (progress >= 0.36 && progress < 0.5) pressedNumber = 8;
        if (progress >= 0.5) {
          clearedNumbers.add(8);
          expected = 9;
          caption = '다음 숫자로!';
        }
        if (progress >= 0.62) {
          replacementIndex = _numbers.indexOf(7);
          replacementNumber = 26;
          ignitionNumber = 26;
          replacementIsOn = progress >= 0.78;
        }
      case _NumberRushSceneMode.sequence:
        elapsed = 3.10 + progress;
        clearedNumbers = {};
        expected = 1;
        caption = '1 → 2 → 3';
        if (progress >= 0.12 && progress < 0.23) pressedNumber = 1;
        if (progress >= 0.23) {
          clearedNumbers.add(1);
          expected = 2;
        }
        if (progress >= 0.38 && progress < 0.49) pressedNumber = 2;
        if (progress >= 0.49) {
          clearedNumbers.add(2);
          expected = 3;
        }
        if (progress >= 0.64 && progress < 0.75) pressedNumber = 3;
        if (progress >= 0.75) {
          clearedNumbers.add(3);
          expected = 4;
        }
      case _NumberRushSceneMode.next:
        caption = 'NEXT와 같은 숫자를 탭';
        if (progress >= 0.32 && progress < 0.48) pressedNumber = 8;
        if (progress >= 0.48) {
          clearedNumbers.add(8);
          expected = 9;
        }
      case _NumberRushSceneMode.refill:
        elapsed = 34.20 + progress;
        expected = 12;
        caption = progress < 0.48 ? '빈칸을 살펴보세요' : '0.5~2초 뒤 26 점화';
        clearedNumbers = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
        if (progress >= 0.38) {
          replacementIndex = _numbers.indexOf(1);
          replacementNumber = 26;
          ignitionNumber = 26;
          replacementIsOn = progress >= 0.68;
        }
      case _NumberRushSceneMode.mistake:
        elapsed = 28.80 + progress * 1.5;
        caption = '오답이어도 시간은 계속';
        if (progress >= 0.3 && progress < 0.56) wrongNumber = 18;
      case _NumberRushSceneMode.result:
        elapsed = 42.37;
        expected = 50;
        caption = progress < 0.48 ? '마지막 50을 탭' : '42.37초 · 기록 확정';
        clearedNumbers = {..._numbers}..remove(25);
        replacementIndex = _numbers.indexOf(25);
        replacementNumber = 50;
        replacementIsOn = true;
        if (progress >= 0.32 && progress < 0.48) pressedNumber = 50;
        completed = progress >= 0.48;
    }

    return DecoratedBox(
      key: widget.mode == _NumberRushSceneMode.main
          ? const Key('number-rush-home-animation')
          : null,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/number_rush/arcade_background.png'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF2071025),
            border: Border.all(color: const Color(0xFF7B2FB0), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAAFF3EBC), blurRadius: 8),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2,
                                ),
                            itemCount: _numbers.length,
                            itemBuilder: (context, index) {
                              final originalNumber = _numbers[index];
                              final number = index == replacementIndex
                                  ? replacementNumber!
                                  : originalNumber;
                              final isReplacement = index == replacementIndex;
                              final isCleared = isReplacement
                                  ? !replacementIsOn
                                  : clearedNumbers.contains(originalNumber);
                              final isPressed = pressedNumber == number;
                              final isWrong = wrongNumber == number;
                              return _NumberRushPreviewTile(
                                number: number,
                                cleared: isCleared,
                                pressed: isPressed,
                                wrong: isWrong,
                                igniting: ignitionNumber == number,
                                completed: completed && number == 50,
                                shakeRight: isWrong && (_frame ~/ 2).isEven,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _NumberRushPreviewHud(
                        elapsed: elapsed,
                        expected: expected,
                        caption: caption,
                        completed: completed,
                      ),
                    ),
                  ],
                ),
              ),
              if (completed)
                Center(
                  child: Container(
                    key: const Key('number-rush-clear-overlay'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    color: const Color(0xF2050A19),
                    child: const Text(
                      'CLEAR!',
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: Color(0xFFFFD84A),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberRushPreviewHud extends StatelessWidget {
  const _NumberRushPreviewHud({
    required this.elapsed,
    required this.expected,
    required this.caption,
    required this.completed,
  });

  final double elapsed;
  final int expected;
  final String caption;
  final bool completed;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const FittedBox(
        child: Text(
          'TAP 50',
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFF39F3FF),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: _NumberRushHudValue(
              label: 'TIME',
              value: elapsed.toStringAsFixed(2),
              color: const Color(0xFF39F3FF),
            ),
          ),
          Container(width: 1, height: 39, color: const Color(0xFF64268F)),
          Expanded(
            child: _NumberRushHudValue(
              key: const Key('number-rush-preview-next'),
              label: 'NEXT',
              value: completed ? 'CLEAR' : '$expected',
              color: completed
                  ? const Color(0xFFFFD84A)
                  : const Color(0xFFFF77CE),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF030713),
          border: Border.all(color: const Color(0xFF3C255D)),
        ),
        child: Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFFFD84A),
            fontSize: 9,
            height: 1.25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _NumberRushHudValue extends StatelessWidget {
  const _NumberRushHudValue({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      FittedBox(
        child: Text(
          value,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _NumberRushPreviewTile extends StatelessWidget {
  const _NumberRushPreviewTile({
    required this.number,
    required this.cleared,
    required this.pressed,
    required this.wrong,
    required this.igniting,
    required this.completed,
    required this.shakeRight,
  });

  final int number;
  final bool cleared;
  final bool pressed;
  final bool wrong;
  final bool igniting;
  final bool completed;
  final bool shakeRight;

  @override
  Widget build(BuildContext context) {
    final frame = completed
        ? 5
        : wrong
        ? 3
        : pressed
        ? 1
        : cleared
        ? 2
        : number == 50
        ? 4
        : 0;
    final numberColor = cleared
        ? const Color(0xFF183348)
        : number == 50
        ? const Color(0xFFFFD84A)
        : const Color(0xFF5DF5FF);

    return Transform.translate(
      offset: wrong ? Offset(shakeRight ? 2 : -2, 0) : Offset.zero,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          _NumberRushAtlasFrame(
            assetPath: 'assets/images/number_rush/number_button_states.png',
            columns: 3,
            rows: 2,
            frame: frame,
          ),
          Center(
            child: FittedBox(
              child: Text(
                '$number',
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: numberColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (pressed)
            const Positioned(
              right: -3,
              bottom: -3,
              child: Icon(
                Icons.touch_app_rounded,
                color: Color(0xFFFFD84A),
                size: 15,
                shadows: [Shadow(color: Color(0xFF030713), blurRadius: 3)],
              ),
            ),
          if (wrong || igniting || completed)
            Positioned.fill(
              child: Opacity(
                opacity: igniting && cleared ? 0.35 : 0.9,
                child: _NumberRushAtlasFrame(
                  assetPath: 'assets/images/number_rush/arcade_fx_sheet.png',
                  columns: 4,
                  rows: 2,
                  frame: wrong
                      ? 4
                      : completed
                      ? 6
                      : 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberRushAtlasFrame extends StatelessWidget {
  const _NumberRushAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AppleGamePreview extends StatelessWidget {
  const _AppleGamePreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/apple_game/apple_game_background.png',
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xDD24181B),
            border: Border.all(color: const Color(0xFFE6B94E), width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/apple_game/apple_faces_atlas.png',
              width: 116,
              height: 116,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppleGameV2Preview extends StatefulWidget {
  const _AppleGameV2Preview();

  @override
  State<_AppleGameV2Preview> createState() => _AppleGameV2PreviewState();
}

class _AppleGameV2PreviewState extends State<_AppleGameV2Preview> {
  static const _frameCount = 40;
  static const _cellSize = 42.0;
  static const _boardLeft = 12.0;
  static const _boardTop = 66.0;
  static const _firstTargetIndex = 17;
  static const _secondTargetIndex = 18;
  static const _values = [
    8, 2, 4, 3, 8, 6, 3, 5, //
    8, 6, 4, 7, 1, 1, 2, 3, //
    1, 4, 6, 5, 1, 3, 9, 6, //
    2, 8, 5, 7, 5, 9, 2, 4, //
    6, 7, 9, 7, 6, 6, 8, 3, //
    4, 1, 7, 1, 7, 9, 1, 5, //
    7, 9, 8, 4, 3, 7, 3, 4, //
    9, 1, 3, 4, 6, 6, 4, 7,
  ];

  Timer? _frameTimer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _frame >= 6 && _frame < 16;
    final reachedSecondApple = _frame >= 9;
    final firstAppleRemoved = _frame >= 16;
    final secondAppleRemoved = _frame >= 20;
    final firstPopFrame = _frame >= 16 && _frame < 20 ? _frame - 16 : null;
    final secondPopFrame = _frame >= 20 && _frame < 24 ? _frame - 20 : null;
    final score = _frame >= 24 ? 2 : 0;
    final sumLabel = switch (_frame) {
      >= 9 => '10 / 10',
      >= 6 => '4 / 10',
      _ => '합계 10 만들기',
    };
    final caption = switch (_frame) {
      >= 24 => '사과 2개 제거!',
      >= 16 => '펑!',
      >= 9 => '4 + 6 = 10',
      >= 6 => '4에서 6까지 드래그',
      _ => '드래그해서 10을 만드세요',
    };
    final dragProgress = ((_frame - 6) / 5).clamp(0.0, 1.0);
    final pointerLeft = 63.0 + 42.0 * dragProgress;

    return ClipRect(
      key: const Key('apple-game-v2-preview'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          key: const Key('apple-home-animation'),
          width: 360,
          height: 462,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/apple_game_v2/apple_game_background.png',
                  key: const Key('apple-home-background'),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.25),
                  filterQuality: FilterQuality.none,
                ),
              ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x26010B27)),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 10,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6011B19),
                    border: Border.all(
                      color: const Color(0xFFFFD24A),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AppleHomeHudValue(
                          key: const Key('apple-home-score'),
                          label: 'APPLES',
                          value: '$score',
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 28,
                        color: const Color(0xFF6B4E1E),
                      ),
                      Expanded(
                        child: _AppleHomeHudValue(
                          key: const Key('apple-home-sum'),
                          label: 'SUM',
                          value: sumLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (var index = 0; index < _values.length; index++)
                Positioned(
                  left: _boardLeft + (index % 8) * _cellSize,
                  top: _boardTop + (index ~/ 8) * _cellSize,
                  width: _cellSize,
                  height: _cellSize,
                  child: _AppleHomeTile(
                    value: _values[index],
                    removed:
                        index == _firstTargetIndex && firstAppleRemoved ||
                        index == _secondTargetIndex && secondAppleRemoved,
                    popFrame: index == _firstTargetIndex
                        ? firstPopFrame
                        : index == _secondTargetIndex
                        ? secondPopFrame
                        : null,
                    popKey: index == _firstTargetIndex
                        ? const Key('apple-home-pop-first')
                        : index == _secondTargetIndex
                        ? const Key('apple-home-pop-second')
                        : null,
                    showCombo:
                        index == _secondTargetIndex && secondPopFrame != null,
                  ),
                ),
              if (isDragging)
                Positioned(
                  key: const Key('apple-home-selection'),
                  left: _boardLeft + _cellSize,
                  top: _boardTop + _cellSize * 2,
                  width: reachedSecondApple ? _cellSize * 2 : _cellSize,
                  height: _cellSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x55FFF3C4),
                      border: Border.all(
                        color: const Color(0xFFFFD24A),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              if (isDragging)
                Positioned(
                  key: const Key('apple-home-drag-pointer'),
                  left: pointerLeft,
                  top: _boardTop + _cellSize * 2 + 22,
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: Color(0xFFFFF3C4),
                    size: 26,
                    shadows: [Shadow(color: Color(0xFF011B19), blurRadius: 4)],
                  ),
                ),
              if (score > 0)
                const Positioned(
                  key: Key('apple-home-score-burst'),
                  left: 88,
                  top: 132,
                  child: Text(
                    '+2',
                    style: TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFD24A),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Color(0xFF011B19), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 34,
                right: 34,
                bottom: 13,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6011B19),
                    border: Border.all(
                      color: score > 0
                          ? const Color(0xFFFFD24A)
                          : const Color(0xFF5C806A),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      caption,
                      key: const Key('apple-home-caption'),
                      style: TextStyle(
                        fontFamily: 'Galmuri',
                        color: score > 0
                            ? const Color(0xFFFFD24A)
                            : const Color(0xFFFFF3C4),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleHomeHudValue extends StatelessWidget {
  const _AppleHomeHudValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Galmuri',
          color: Color(0xFF91C9A9),
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      FittedBox(
        child: Text(
          value,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFFFFD24A),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _AppleHomeTile extends StatelessWidget {
  const _AppleHomeTile({
    required this.value,
    required this.removed,
    required this.popFrame,
    required this.popKey,
    required this.showCombo,
  });

  final int value;
  final bool removed;
  final int? popFrame;
  final Key? popKey;
  final bool showCombo;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      if (!removed)
        Positioned.fill(
          child: _AppleHomeAtlasFrame(
            assetPath: 'assets/images/apple_game_v2/apple_faces_atlas.png',
            columns: 3,
            rows: 3,
            frame: value - 1,
          ),
        ),
      if (!removed)
        Positioned.fill(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, 4),
              child: Text(
                '$value',
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFF3C4),
                  shadows: [
                    Shadow(color: Color(0xFF591F2C), offset: Offset(1, 0)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(-1, 0)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(0, 1)),
                    Shadow(color: Color(0xFF591F2C), offset: Offset(0, -1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (popFrame != null)
        Positioned(
          left: 1,
          top: 1,
          width: 40,
          height: 40,
          child: _AppleHomeAtlasFrame(
            key: popKey,
            assetPath: 'assets/images/apple_game_v2/apple_pop_sheet.png',
            columns: 4,
            rows: 1,
            frame: popFrame!,
          ),
        ),
      if (showCombo)
        Positioned(
          key: const Key('apple-home-combo'),
          left: -11,
          top: -11,
          width: 64,
          height: 64,
          child: _AppleHomeAtlasFrame(
            assetPath:
                'assets/images/apple_game_v2/apple_combo_burst_sheet.png',
            columns: 4,
            rows: 3,
            frame: popFrame!,
          ),
        ),
    ],
  );
}

class _AppleHomeAtlasFrame extends StatelessWidget {
  const _AppleHomeAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
    super.key,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _FailedBakeryPreview extends StatefulWidget {
  const _FailedBakeryPreview();

  @override
  State<_FailedBakeryPreview> createState() => _FailedBakeryPreviewState();
}

class _FailedBakeryPreviewState extends State<_FailedBakeryPreview> {
  late final Future<List<ui.Image>> _cakeImages;

  @override
  void initState() {
    super.initState();
    _cakeImages = Future.wait([
      _loadPreviewImage('assets/images/failed_bakery_25d/cake_top_atlas.png'),
      _loadPreviewImage(
        'assets/images/failed_bakery_25d/cake_side_face_atlas.png',
      ),
      _loadPreviewImage(
        'assets/images/failed_bakery_25d/cake_side_plain_atlas.png',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/failed_bakery_25d/bakery_background_3q.png',
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: FutureBuilder<List<ui.Image>>(
        future: _cakeImages,
        builder: (context, snapshot) => CustomPaint(
          painter: snapshot.hasData
              ? _FailedBakeryPreviewPainter(
                  topAtlas: snapshot.data![0],
                  faceSideAtlas: snapshot.data![1],
                  plainSideAtlas: snapshot.data![2],
                )
              : null,
        ),
      ),
    );
  }
}

Future<ui.Image> _loadPreviewImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

class _FailedBakeryPreviewPainter extends CustomPainter {
  const _FailedBakeryPreviewPainter({
    required this.topAtlas,
    required this.faceSideAtlas,
    required this.plainSideAtlas,
  });

  final ui.Image topAtlas;
  final ui.Image faceSideAtlas;
  final ui.Image plainSideAtlas;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.73);
    const skins = [0, 4, 1, 3, 2];
    for (var layer = 0; layer < skins.length; layer++) {
      final width = 82.0 - layer * 3;
      final halfWidth = width / 2;
      final halfHeight = width / 4;
      final y = center.dy - layer * 8;
      final back = Offset(center.dx, y - halfHeight);
      final right = Offset(center.dx + halfWidth, y);
      final front = Offset(center.dx, y + halfHeight);
      final left = Offset(center.dx - halfWidth, y);
      _drawPreviewCakeFace(
        canvas,
        origin: left,
        horizontal: front - left,
        skin: skins[layer],
        image: faceSideAtlas,
      );
      _drawPreviewCakeFace(
        canvas,
        origin: front,
        horizontal: right - front,
        skin: skins[layer],
        image: plainSideAtlas,
      );
      final topRow = skins[layer] ~/ 3;
      final topColumn = skins[layer] % 3;
      _drawPreviewImage(
        canvas,
        image: topAtlas,
        source: Rect.fromLTWH(topColumn * 40.0, topRow * 40.0, 40, 40),
        origin: back,
        horizontal: right - back,
        vertical: left - back,
      );
    }
  }

  void _drawPreviewCakeFace(
    Canvas canvas, {
    required Offset origin,
    required Offset horizontal,
    required int skin,
    required ui.Image image,
  }) {
    final row = skin ~/ 2;
    final column = skin % 2;
    _drawPreviewImage(
      canvas,
      image: image,
      source: Rect.fromLTWH(column * 40.0, row * 8.0, 40, 8),
      origin: origin,
      horizontal: horizontal,
      vertical: const Offset(0, 8),
    );
  }

  void _drawPreviewImage(
    Canvas canvas, {
    required ui.Image image,
    required Rect source,
    required Offset origin,
    required Offset horizontal,
    required Offset vertical,
  }) {
    final matrix = Float64List.fromList([
      horizontal.dx / source.width,
      horizontal.dy / source.width,
      0,
      0,
      vertical.dx / source.height,
      vertical.dy / source.height,
      0,
      0,
      0,
      0,
      1,
      0,
      origin.dx,
      origin.dy,
      0,
      1,
    ]);
    canvas
      ..save()
      ..transform(matrix)
      ..drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, source.width, source.height),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _FailedBakeryPreviewPainter oldDelegate) =>
      oldDelegate.topAtlas != topAtlas ||
      oldDelegate.faceSideAtlas != faceSideAtlas ||
      oldDelegate.plainSideAtlas != plainSideAtlas;
}

enum _GravityGuideMode { control, landing, obstacle, difficulty, collision }

class _GravityGuideAnimation extends StatefulWidget {
  const _GravityGuideAnimation({required this.mode, super.key});

  final _GravityGuideMode mode;

  @override
  State<_GravityGuideAnimation> createState() => _GravityGuideAnimationState();
}

class _GravityGuideAnimationState extends State<_GravityGuideAnimation> {
  @override
  Widget build(BuildContext context) => _GravityRuntimeGuide(mode: widget.mode);
}

class _GravityRuntimeGuide extends StatelessWidget {
  const _GravityRuntimeGuide({required this.mode});

  final _GravityGuideMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == _GravityGuideMode.difficulty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/gravity_switch_v2/gravity_runtime_hard.webp',
            key: const ValueKey('gravity-runtime-difficulty'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
          ),
          const Positioned(
            left: 10,
            top: 10,
            child: _VisualLabel(label: '후반 플레이', color: AppColors.danger),
          ),
        ],
      );
    }

    final assetPath = switch (mode) {
      _GravityGuideMode.control =>
        'assets/images/gravity_switch_v2/gravity_runtime_tap.webp',
      _GravityGuideMode.landing || _GravityGuideMode.obstacle =>
        'assets/images/gravity_switch_v2/gravity_runtime_control.webp',
      _GravityGuideMode.collision =>
        'assets/images/gravity_switch_v2/gravity_runtime_collision.webp',
      _GravityGuideMode.difficulty => throw StateError(
        'Difficulty uses a comparison.',
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          key: ValueKey('gravity-runtime-${mode.name}'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
        if (mode == _GravityGuideMode.control)
          const Positioned(
            left: 116,
            top: 112,
            child: _GravityTapCue(label: 'TAP ↑↓'),
          ),
        if (mode == _GravityGuideMode.landing)
          const Positioned(
            right: 10,
            top: 10,
            child: _VisualLabel(label: '착지 후 다시 탭', color: AppColors.reward),
          ),
        if (mode == _GravityGuideMode.obstacle)
          const Positioned(
            left: 10,
            top: 10,
            child: _VisualLabel(label: '안전한 쪽으로 이동 → 통과'),
          ),
      ],
    );
  }
}

class _GravityRuntimeComparisonHalf extends StatelessWidget {
  const _GravityRuntimeComparisonHalf({
    required this.label,
    required this.color,
    required this.assetPath,
  });

  final String label;
  final Color color;
  final String assetPath;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        assetPath,
        key: ValueKey(assetPath),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
      ),
      Positioned(
        left: 7,
        top: 7,
        child: _VisualLabel(label: label, color: color),
      ),
    ],
  );
}

class _GravityGuideCanvas extends StatelessWidget {
  const _GravityGuideCanvas({required this.mode, required this.frame});

  final _GravityGuideMode mode;
  final int frame;

  @override
  Widget build(BuildContext context) {
    if (mode == _GravityGuideMode.difficulty) {
      return _GravityDifficultyComparison(frame: frame);
    }

    final collision = mode == _GravityGuideMode.collision && frame >= 27;
    final tripFrame = frame % 60;
    final goingUp = tripFrame >= 9 && tripFrame < 25;
    final onCeiling = tripFrame >= 25 && tripFrame < 37;
    final goingDown = tripFrame >= 37 && tripFrame < 53;
    final progressUp = ((tripFrame - 9) / 16).clamp(0.0, 1.0);
    final progressDown = ((tripFrame - 37) / 16).clamp(0.0, 1.0);
    final playerY = collision
        ? 222.0
        : goingUp
        ? 222 - (116 * Curves.easeIn.transform(progressUp))
        : onCeiling
        ? 106.0
        : goingDown
        ? 106 + (116 * Curves.easeIn.transform(progressDown))
        : 222.0;
    final airborne = goingUp || goingDown;
    final double playerAngle = airborne
        ? (goingUp ? -1 : 1) * (airborne ? (tripFrame % 16) / 16 * pi * 2 : 0)
        : 0.0;
    final obstacleX = mode == _GravityGuideMode.collision
        ? max(112.0, 330 - frame * 8.1)
        : mode == _GravityGuideMode.obstacle
        ? max(178.0, 330 - frame * 3.0)
        : 260.0;
    final playerFrame = airborne ? 2 + ((frame ~/ 2) % 2) : (frame ~/ 2) % 2;

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: 360,
        height: 268,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(
              child: _GravitySceneBackground(
                assetPath:
                    'assets/images/gravity_switch_v2/current_runtime_guide.png',
              ),
            ),
            if (mode == _GravityGuideMode.obstacle ||
                mode == _GravityGuideMode.collision)
              Positioned(
                left: obstacleX,
                bottom: 38,
                width: 48,
                height: 144,
                child: const _GravityObstacleModule(),
              ),
            if (mode == _GravityGuideMode.obstacle)
              const Positioned(
                right: 10,
                top: 0,
                width: 48,
                height: 144,
                child: _GravityObstacleModule(ceiling: true),
              ),
            Positioned(
              key: ValueKey(
                collision
                    ? 'gravity-guide-ko-state'
                    : airborne
                    ? 'gravity-guide-flight-state'
                    : onCeiling
                    ? 'gravity-guide-ceiling-state'
                    : 'gravity-guide-floor-state',
              ),
              left: 70,
              top: playerY - 24,
              width: 48,
              height: 48,
              child: Transform.rotate(
                angle: playerAngle,
                child: _GravityPlayerFrame(
                  frame: playerFrame,
                  gameOver: collision,
                  key: collision ? const Key('gravity-guide-ko') : null,
                ),
              ),
            ),
            if (!collision &&
                (tripFrame == 25 ||
                    tripFrame == 26 ||
                    tripFrame == 53 ||
                    tripFrame == 54))
              Positioned(
                left: 70,
                top: tripFrame < 40 ? 81 : 190,
                width: 48,
                height: 48,
                child: _GravityLandingFrame(frame: frame % 4),
              ),
            if (mode == _GravityGuideMode.control &&
                (frame >= 6 && frame <= 12 || frame >= 34 && frame <= 40))
              const Positioned(
                left: 116,
                top: 112,
                child: _GravityTapCue(label: 'TAP'),
              ),
            if (mode == _GravityGuideMode.landing && frame >= 17 && frame <= 27)
              const Positioned(
                left: 132,
                top: 104,
                child: _GravityTapCue(label: '추가 탭', blocked: true),
              ),
            if (mode == _GravityGuideMode.landing && frame >= 28 && frame <= 39)
              const Positioned(
                left: 122,
                top: 86,
                child: _VisualLabel(
                  label: '착지 후 다시 탭',
                  color: AppColors.reward,
                ),
              ),
            if (mode == _GravityGuideMode.obstacle) ...[
              Positioned(
                left: 110,
                top: 74,
                width: max(42.0, obstacleX - 116),
                child: const Row(
                  children: [
                    Expanded(
                      child: Divider(color: AppColors.primary, thickness: 2),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 10,
                top: 10,
                child: _VisualLabel(label: '기둥 전에 위로'),
              ),
            ],
            if (mode == _GravityGuideMode.collision)
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: Text(
                  (12.34 + min(frame, 27) / 10).toStringAsFixed(2),
                  key: const Key('gravity-guide-collision-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Color(0xCC020617), offset: Offset(2, 2)),
                    ],
                  ),
                ),
              ),
            if (collision) ...[
              if (frame <= 29)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x55FF3565)),
                ),
              const Positioned(
                left: 0,
                right: 0,
                top: 62,
                child: Text(
                  'GAME OVER',
                  key: Key('gravity-guide-game-over'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Galmuri',
                    color: Color(0xFFFFD84A),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Color(0xFF6E123E), offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 17,
                child: Text(
                  '한 번 닿으면 즉시 종료',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GravityDifficultyComparison extends StatelessWidget {
  const _GravityDifficultyComparison({required this.frame});

  final int frame;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _GravityDifficultyHalf(
          label: '초반',
          color: AppColors.reward,
          offset: (frame * 1.4) % 48,
          hard: false,
        ),
      ),
      Container(width: 2, color: AppColors.border),
      Expanded(
        child: _GravityDifficultyHalf(
          label: '30초 이후',
          color: AppColors.danger,
          offset: (frame * 3.1) % 48,
          hard: true,
        ),
      ),
    ],
  );
}

class _GravityDifficultyHalf extends StatelessWidget {
  const _GravityDifficultyHalf({
    required this.label,
    required this.color,
    required this.offset,
    required this.hard,
  });

  final String label;
  final Color color;
  final double offset;
  final bool hard;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const _GravitySceneBackground(
          assetPath:
              'assets/images/gravity_switch_v2/current_runtime_guide.png',
        ),
        Positioned(
          left: hard ? 80 - offset : 132 - offset,
          top: 0,
          width: 48,
          height: hard ? 144 : 96,
          child: const _GravityObstacleModule(ceiling: true),
        ),
        Positioned(
          left: hard ? 112 + offset : 152 + offset,
          bottom: 38,
          width: 48,
          height: hard ? 144 : 96,
          child: const _GravityObstacleModule(),
        ),
        Positioned(
          left: 34,
          top: hard ? 84 : 190,
          width: 40,
          height: 40,
          child: _GravityPlayerFrame(frame: hard ? 2 : 0),
        ),
        Positioned(
          left: 7,
          top: 7,
          child: _VisualLabel(label: label, color: color),
        ),
        Positioned(
          right: 7,
          top: 10,
          child: Icon(
            Icons.fast_forward_rounded,
            color: color,
            size: hard ? 27 : 19,
          ),
        ),
      ],
    ),
  );
}

class _GravityTapCue extends StatelessWidget {
  const _GravityTapCue({required this.label, this.blocked = false});

  final String label;
  final bool blocked;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    color: const Color(0xDD020617),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          blocked ? Icons.block_rounded : Icons.touch_app_rounded,
          color: blocked ? AppColors.danger : AppColors.primary,
          size: 22,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: blocked ? AppColors.danger : AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _GravityGamePreview extends StatefulWidget {
  const _GravityGamePreview();

  @override
  State<_GravityGamePreview> createState() => _GravityGamePreviewState();
}

class _GravityGamePreviewState extends State<_GravityGamePreview> {
  static const _frameCount = 80;
  Timer? _timer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame >= 0) {
      return ClipRect(
        key: const Key('gravity-home-animation'),
        child: Image.asset(
          'assets/images/gravity_switch_v2/gravity_runtime_main.webp',
          key: const Key('gravity-home-runtime-capture'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
      );
    }
    final cycleFrame = _frame % _frameCount;
    final goingUp = cycleFrame >= 8 && cycleFrame < 24;
    final onCeiling = cycleFrame >= 24 && cycleFrame < 39;
    final goingDown = cycleFrame >= 39 && cycleFrame < 55;
    final progressUp = ((cycleFrame - 8) / 16).clamp(0.0, 1.0);
    final progressDown = ((cycleFrame - 39) / 16).clamp(0.0, 1.0);
    final playerY = goingUp
        ? 350 - 116 * Curves.easeIn.transform(progressUp)
        : onCeiling
        ? 234.0
        : goingDown
        ? 234 + 116 * Curves.easeIn.transform(progressDown)
        : 350.0;
    final airborne = goingUp || goingDown;
    final double playerAngle = airborne
        ? (goingUp ? -1 : 1) * (cycleFrame % 16) / 16 * pi * 2
        : 0.0;
    final playerFrame = airborne
        ? 2 + ((cycleFrame ~/ 2) % 2)
        : (cycleFrame ~/ 2) % 2;
    final timer = 8.80 + cycleFrame / 10;
    final floorObstacleX = 310 - cycleFrame * 4.2;
    final ceilingObstacleX = 500 - cycleFrame * 5.0;

    return ClipRect(
      key: const Key('gravity-home-animation'),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 360,
          height: 462,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const Positioned.fill(
                child: _GravitySceneBackground(
                  assetPath:
                      'assets/images/gravity_switch_v2/current_runtime_home.png',
                ),
              ),
              Positioned(
                left: floorObstacleX,
                bottom: 97,
                width: 48,
                height: 144,
                child: const _GravityObstacleModule(),
              ),
              Positioned(
                left: ceilingObstacleX,
                top: 76,
                width: 48,
                height: 144,
                child: const _GravityObstacleModule(ceiling: true),
              ),
              Positioned(
                left: 70,
                top: playerY - 24,
                width: 48,
                height: 48,
                child: Transform.rotate(
                  angle: playerAngle,
                  child: _GravityPlayerFrame(frame: playerFrame),
                ),
              ),
              if (cycleFrame == 24 ||
                  cycleFrame == 25 ||
                  cycleFrame == 55 ||
                  cycleFrame == 56)
                Positioned(
                  left: 70,
                  top: cycleFrame < 40 ? 210 : 320,
                  width: 48,
                  height: 48,
                  child: _GravityLandingFrame(frame: cycleFrame % 4),
                ),
              if (cycleFrame >= 5 && cycleFrame <= 11 ||
                  cycleFrame >= 36 && cycleFrame <= 42)
                const Positioned(
                  left: 124,
                  top: 205,
                  child: _GravityTapCue(label: 'TAP'),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 16,
                child: Text(
                  timer.toStringAsFixed(2),
                  key: const Key('gravity-home-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Color(0xCC020617), offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GravitySceneBackground extends StatelessWidget {
  const _GravitySceneBackground({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.none,
  );
}

class _GravityObstacleModule extends StatelessWidget {
  const _GravityObstacleModule({this.ceiling = false});

  final bool ceiling;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipY: ceiling,
    child: Image.asset(
      'assets/images/gravity_switch_v2/platform_modules_v4/'
      'scrap_basic_1x3_01.png',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    ),
  );
}

class _GravityPlayerFrame extends StatelessWidget {
  const _GravityPlayerFrame({
    required this.frame,
    this.gameOver = false,
    super.key,
  });

  final int frame;
  final bool gameOver;

  @override
  Widget build(BuildContext context) {
    if (gameOver) {
      return Image.asset(
        'assets/images/gravity_switch_v2/player_game_over.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      );
    }
    return _GravityAtlasFrame(
      assetPath:
          'assets/images/gravity_switch_v2/player_magnet_mite_sheet_v3.png',
      columns: 2,
      rows: 2,
      frame: frame,
    );
  }
}

class _GravityLandingFrame extends StatelessWidget {
  const _GravityLandingFrame({required this.frame});

  final int frame;

  @override
  Widget build(BuildContext context) => _GravityAtlasFrame(
    assetPath: 'assets/images/gravity_switch_v2/landing_impact_sheet.png',
    columns: 2,
    rows: 2,
    frame: frame,
  );
}

class _GravityAtlasFrame extends StatelessWidget {
  const _GravityAtlasFrame({
    required this.assetPath,
    required this.columns,
    required this.rows,
    required this.frame,
  });

  final String assetPath;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final column = frame % columns;
      final row = frame ~/ columns;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -column * width,
              top: -row * height,
              width: width * columns,
              height: height * rows,
              child: Image.asset(
                assetPath,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PixelStar extends StatelessWidget {
  const _PixelStar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.warning_amber_rounded,
      size: size,
      color: AppColors.danger,
    );
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta({required this.game});

  final TodayGame? game;

  @override
  Widget build(BuildContext context) {
    final durationLabel = _durationLabel(game);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MetaItem(icon: Icons.timer_outlined, label: durationLabel),
        const SizedBox(width: 24),
        const _MetaItem(icon: Icons.touch_app_outlined, label: '한 손'),
        const SizedBox(width: 24),
        const _MetaItem(icon: Icons.public, label: '전체 순위'),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.reward, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PixelGridBackground extends StatelessWidget {
  const _PixelGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.surface.withValues(alpha: 0.28);
    const gap = 24.0;

    for (var x = 0.0; x < size.width; x += gap) {
      for (var y = 0.0; y < size.height; y += gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
