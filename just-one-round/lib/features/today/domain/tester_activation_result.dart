enum TesterActivationStatus { activated, invalid, locked }

class TesterActivationResult {
  const TesterActivationResult({
    required this.status,
    this.attemptsRemaining,
    this.retryAfterSeconds,
  });

  factory TesterActivationResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'activated' => TesterActivationStatus.activated,
      'invalid' => TesterActivationStatus.invalid,
      'locked' => TesterActivationStatus.locked,
      _ => throw const FormatException('unknown tester activation status'),
    };
    return TesterActivationResult(
      status: status,
      attemptsRemaining: (json['attempts_remaining'] as num?)?.toInt(),
      retryAfterSeconds: (json['retry_after_seconds'] as num?)?.toInt(),
    );
  }

  final TesterActivationStatus status;
  final int? attemptsRemaining;
  final int? retryAfterSeconds;
}
