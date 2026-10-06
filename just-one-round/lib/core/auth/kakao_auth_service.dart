import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:supabase_flutter/supabase_flutter.dart';

const kakaoNativeAppKey = String.fromEnvironment(
  'KAKAO_NATIVE_APP_KEY',
  defaultValue: '8f22d14ad0934753e6de50e73edaee82',
);
const kakaoCustomScheme = String.fromEnvironment(
  'KAKAO_CUSTOM_SCHEME',
  defaultValue: 'kakao8f22d14ad0934753e6de50e73edaee82',
);

bool get kakaoLoginConfigured => kakaoNativeAppKey.trim().isNotEmpty;

Future<void> initializeKakaoSdk() async {
  if (!kakaoLoginConfigured) return;

  await kakao.KakaoSdk.init(
    nativeAppKey: kakaoNativeAppKey,
    customScheme: kakaoCustomScheme.trim().isEmpty
        ? null
        : kakaoCustomScheme.trim(),
    loggingEnabled: kDebugMode,
  );
}

abstract interface class KakaoAuthService {
  bool get isConfigured;

  bool get isLinked;

  Future<KakaoAccountLinkResult> linkAccount();
}

enum KakaoAccountLinkResult { linked, alreadyLinked, signedIntoExistingAccount }

final kakaoAuthServiceProvider = Provider<KakaoAuthService>(
  (ref) => const DisabledKakaoAuthService(),
);

class DisabledKakaoAuthService implements KakaoAuthService {
  const DisabledKakaoAuthService();

  @override
  bool get isConfigured => false;

  @override
  bool get isLinked => false;

  @override
  Future<KakaoAccountLinkResult> linkAccount() async {
    throw const KakaoLoginException('카카오 로그인을 사용할 수 없어요. 앱 키 설정이 필요합니다.');
  }
}

class SupabaseKakaoAuthService implements KakaoAuthService {
  SupabaseKakaoAuthService(this._client, {bool? configured})
    : _configured = configured ?? kakaoLoginConfigured;

  final SupabaseClient _client;
  final bool _configured;

  @override
  bool get isConfigured => _configured;

  @override
  bool get isLinked =>
      _client.auth.currentUser?.identities?.any(
        (identity) => identity.provider == 'kakao',
      ) ??
      false;

  @override
  Future<KakaoAccountLinkResult> linkAccount() async {
    if (!isConfigured) {
      throw const KakaoLoginException('카카오 로그인을 사용할 수 없어요. 앱 키 설정이 필요합니다.');
    }
    if (_client.auth.currentSession == null) {
      throw const KakaoLoginException('현재 로그인 세션을 찾을 수 없어요. 다시 시도해 주세요.');
    }
    if (isLinked) return KakaoAccountLinkResult.alreadyLinked;

    try {
      return await _linkWithKakaoIdToken();
    } catch (error) {
      if (_isCancelled(error)) {
        throw const KakaoLoginException('', cancelled: true);
      }
      if (error is KakaoLoginException) rethrow;
      if (error is AuthException) {
        debugPrint(
          '[Kakao] Supabase OAuth failed: code=${error.code ?? ''} '
          'message=${error.message}',
        );
        throw KakaoLoginException(
          error.message.isEmpty ? '카카오 로그인에 실패했어요.' : error.message,
        );
      }
      if (error is kakao.KakaoClientException) {
        debugPrint('[Kakao] SDK login failed: reason=${error.reason.name}');
        throw KakaoLoginException(
          error.msg.isEmpty ? '카카오 로그인에 실패했어요.' : error.msg,
        );
      }
      if (error is kakao.KakaoAuthException) {
        final description = error.errorDescription ?? '';
        debugPrint(
          '[Kakao] OAuth authorization failed: '
          'cause=${error.error.name} message=$description',
        );
        if (error.error == kakao.AuthErrorCause.accessDenied) {
          throw const KakaoLoginException('', cancelled: true);
        }
        if (error.error == kakao.AuthErrorCause.misconfigured) {
          throw const KakaoLoginException(
            '카카오 Android 키 해시가 개발자 콘솔에 등록되지 않았어요.',
          );
        }
        throw KakaoLoginException(
          description.isEmpty ? '카카오 로그인에 실패했어요.' : description,
        );
      }
      if (error is PlatformException) {
        debugPrint(
          '[Kakao] OAuth browser failed: code=${error.code} '
          'message=${error.message ?? ''}',
        );
        throw KakaoLoginException(_platformErrorMessage(error));
      }
      debugPrint('[Kakao] OAuth link failed: ${error.runtimeType}');
      throw const KakaoLoginException(
        '카카오 로그인 화면에서 앱으로 돌아오지 못했어요. 다시 시도해 주세요.',
      );
    }
  }

  Future<KakaoAccountLinkResult> _linkWithKakaoIdToken() async {
    final token = await kakao.UserApi.instance.loginWithKakaoAccount();
    final idToken = token.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const KakaoLoginException(
        '카카오 OpenID 토큰을 받지 못했어요. 카카오 로그인 설정을 확인해 주세요.',
      );
    }

    try {
      await _client.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.kakao,
        idToken: idToken,
        accessToken: token.accessToken,
      );
      await _client.auth.getUser();
      return KakaoAccountLinkResult.linked;
    } on AuthException catch (error) {
      // A Kakao identity that is already attached to another Supabase user
      // cannot be merged into the anonymous session. Preserve the previous
      // behavior by signing into that existing account instead.
      if (!_isIdentityConflict(error)) rethrow;
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.kakao,
        idToken: idToken,
        accessToken: token.accessToken,
      );
      await _client.auth.getUser();
      return KakaoAccountLinkResult.signedIntoExistingAccount;
    }
  }

  String _platformErrorMessage(PlatformException error) {
    switch (error.code) {
      case 'channel-error':
        return '카카오 로그인 모듈을 불러오지 못했어요. 앱을 완전히 종료한 뒤 다시 시도해 주세요.';
      case 'INVALID_URL':
      case 'OPEN_URL_ERROR':
        return '카카오 로그인 화면을 열지 못했어요. 잠시 후 다시 시도해 주세요.';
      case 'CANCELED':
        return '';
      default:
        return '카카오 로그인에 실패했어요. 잠시 후 다시 시도해 주세요. (${error.code})';
    }
  }

  bool _isCancelled(Object error) {
    if (error is kakao.KakaoClientException) {
      return error.reason == kakao.ClientErrorCause.cancelled;
    }
    if (error is PlatformException) {
      return error.code == 'CANCELED';
    }
    if (error is AuthException) {
      final code = error.code?.toLowerCase() ?? '';
      final message = error.message.toLowerCase();
      return code == 'access_denied' ||
          message.contains('access denied') ||
          message.contains('user cancelled');
    }
    return false;
  }

  bool _isIdentityConflict(AuthException error) {
    final code = error.code?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();
    return (code.contains('identity') &&
            (code.contains('already') || code.contains('exist'))) ||
        (message.contains('identity') &&
            (message.contains('already') || message.contains('exist')));
  }
}

class KakaoLoginException implements Exception {
  const KakaoLoginException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => 'KakaoLoginException: $message';
}
