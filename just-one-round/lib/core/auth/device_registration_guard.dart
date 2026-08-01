class DeviceRegistrationGuard {
  factory DeviceRegistrationGuard({
    required String? Function() currentUserId,
    required Future<String> Function() readDeviceHash,
    required Future<void> Function(String deviceHash) registerDevice,
  }) =>
      DeviceRegistrationGuard._(currentUserId, readDeviceHash, registerDevice);

  DeviceRegistrationGuard._(
    this._currentUserId,
    this._readDeviceHash,
    this._registerDevice,
  );

  final String? Function() _currentUserId;
  final Future<String> Function() _readDeviceHash;
  final Future<void> Function(String deviceHash) _registerDevice;
  String? _registeredUserId;
  Future<void>? _pendingRegistration;

  Future<void> ensureRegistered() async {
    final userId = _currentUserId();
    if (userId == null) throw StateError('authentication required');
    if (_registeredUserId == userId) return;

    final pending = _pendingRegistration;
    if (pending != null) {
      await pending;
      if (_registeredUserId == userId) return;
    }

    final registration = _register(userId);
    _pendingRegistration = registration;
    try {
      await registration;
    } finally {
      if (identical(_pendingRegistration, registration)) {
        _pendingRegistration = null;
      }
    }
  }

  Future<void> registerAgain() async {
    _registeredUserId = null;
    await ensureRegistered();
  }

  Future<void> _register(String userId) async {
    final deviceHash = await _readDeviceHash();
    await _registerDevice(deviceHash);
    if (_currentUserId() == userId) {
      _registeredUserId = userId;
    }
  }
}
