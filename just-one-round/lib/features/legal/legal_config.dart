class LegalConfig {
  const LegalConfig._();

  static const termsVersion = '2026-07-26-v1';
  static const privacyVersion = '2026-07-26-v1';

  static const baseUrl = String.fromEnvironment(
    'LEGAL_BASE_URL',
    defaultValue: 'https://legal.shook.work',
  );

  static Uri get termsUri => Uri.parse('$baseUrl/terms');
  static Uri get privacyUri => Uri.parse('$baseUrl/privacy');
  static Uri get communityUri => Uri.parse('$baseUrl/community-guidelines');
  static Uri get deletionUri => Uri.parse('$baseUrl/account-deletion');
}
