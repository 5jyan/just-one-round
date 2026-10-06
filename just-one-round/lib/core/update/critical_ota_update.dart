import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _previewCriticalOtaPrompt = bool.fromEnvironment(
  'PREVIEW_CRITICAL_OTA_PROMPT',
  defaultValue: false,
);

const defaultCriticalOtaMessage = '중요한 업데이트가 준비됐어요.';

final criticalOtaUpdateServiceProvider = Provider<CriticalOtaUpdateService>(
  (_) => const InactiveCriticalOtaUpdateService(),
);

abstract interface class CriticalOtaUpdateService {
  Future<CriticalOtaUpdateResult> prepareUpdate();
}

class CriticalOtaUpdateResult {
  const CriticalOtaUpdateResult._({
    required this.shouldPromptRestart,
    this.message,
  });

  const CriticalOtaUpdateResult.inactive() : this._(shouldPromptRestart: false);

  const CriticalOtaUpdateResult.restartRequired(String message)
    : this._(shouldPromptRestart: true, message: message);

  final bool shouldPromptRestart;
  final String? message;
}

class InactiveCriticalOtaUpdateService implements CriticalOtaUpdateService {
  const InactiveCriticalOtaUpdateService();

  @override
  Future<CriticalOtaUpdateResult> prepareUpdate() async =>
      const CriticalOtaUpdateResult.inactive();
}

class PreviewCriticalOtaUpdateService implements CriticalOtaUpdateService {
  const PreviewCriticalOtaUpdateService({
    this.message = defaultCriticalOtaMessage,
  });

  final String message;

  @override
  Future<CriticalOtaUpdateResult> prepareUpdate() async =>
      CriticalOtaUpdateResult.restartRequired(message);
}

class ShorebirdCriticalOtaUpdateService implements CriticalOtaUpdateService {
  ShorebirdCriticalOtaUpdateService(
    this._client, {
    ShorebirdUpdater? updater,
    this._directiveTimeout = const Duration(seconds: 2),
    this._updateTimeout = const Duration(seconds: 30),
  }) : _updater = updater ?? ShorebirdUpdater();

  final SupabaseClient _client;
  final ShorebirdUpdater _updater;
  final Duration _directiveTimeout;
  final Duration _updateTimeout;

  @override
  Future<CriticalOtaUpdateResult> prepareUpdate() async {
    if (_previewCriticalOtaPrompt) {
      return const CriticalOtaUpdateResult.restartRequired(
        defaultCriticalOtaMessage,
      );
    }

    try {
      final directive = await _fetchDirective().timeout(_directiveTimeout);
      if (!directive.enabled || !_updater.isAvailable) {
        return const CriticalOtaUpdateResult.inactive();
      }

      final initialStatus = await _updater.checkForUpdate();
      if (initialStatus == UpdateStatus.restartRequired) {
        return CriticalOtaUpdateResult.restartRequired(directive.message);
      }
      if (initialStatus != UpdateStatus.outdated) {
        return const CriticalOtaUpdateResult.inactive();
      }

      await _updater.update().timeout(_updateTimeout);
      if (await _waitUntilPatchIsReady()) {
        return CriticalOtaUpdateResult.restartRequired(directive.message);
      }
    } catch (error, stackTrace) {
      debugPrint('[CriticalOTA] Update preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // A failed or slow OTA check must never prevent the app from opening.
    return const CriticalOtaUpdateResult.inactive();
  }

  Future<bool> _waitUntilPatchIsReady() async {
    final deadline = DateTime.now().add(_updateTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.restartRequired) return true;
      if (status != UpdateStatus.outdated) return false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<_CriticalOtaDirective> _fetchDirective() async {
    final response = await _client.rpc('get_critical_ota_directive');
    return _CriticalOtaDirective.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}

class _CriticalOtaDirective {
  const _CriticalOtaDirective({required this.enabled, required this.message});

  factory _CriticalOtaDirective.fromJson(Map<String, dynamic> json) {
    final rawMessage = (json['message'] as String?)?.trim();
    return _CriticalOtaDirective(
      enabled: json['enabled'] as bool? ?? false,
      message: rawMessage == null || rawMessage.isEmpty
          ? defaultCriticalOtaMessage
          : rawMessage,
    );
  }

  final bool enabled;
  final String message;
}
