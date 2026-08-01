class AnonymousSessionGuard {
  factory AnonymousSessionGuard({
    required bool Function() hasSession,
    required Future<void> Function() signInAnonymously,
  }) => AnonymousSessionGuard._(hasSession, signInAnonymously);

  AnonymousSessionGuard._(this._hasSession, this._signInAnonymously);

  final bool Function() _hasSession;
  final Future<void> Function() _signInAnonymously;
  Future<void>? _pendingSignIn;

  Future<void> ensureSignedIn() {
    if (_hasSession()) return Future.value();

    final pending = _pendingSignIn;
    if (pending != null) return pending;

    final signIn = _signInIfStillNeeded();
    _pendingSignIn = signIn;
    return signIn.whenComplete(() {
      if (identical(_pendingSignIn, signIn)) {
        _pendingSignIn = null;
      }
    });
  }

  Future<void> _signInIfStillNeeded() async {
    if (_hasSession()) return;
    await _signInAnonymously();
  }
}
