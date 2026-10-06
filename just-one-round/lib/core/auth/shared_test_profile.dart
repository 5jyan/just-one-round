import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class SharedTestProfileConfig {
  const SharedTestProfileConfig({
    required this.enabled,
    required this.email,
    required this.password,
  });

  const SharedTestProfileConfig.fromEnvironment()
    : enabled = const bool.fromEnvironment(
        'USE_SHARED_TEST_PROFILE',
        defaultValue: false,
      ),
      email = const String.fromEnvironment('SHARED_TEST_PROFILE_EMAIL'),
      password = const String.fromEnvironment('SHARED_TEST_PROFILE_PASSWORD');

  final bool enabled;
  final String email;
  final String password;

  void validate() {
    if (!enabled) return;
    if (email.isEmpty || password.isEmpty) {
      throw StateError(
        'USE_SHARED_TEST_PROFILE requires email and password dart-defines.',
      );
    }
  }
}

Future<void> signInSharedTestProfile(
  SupabaseClient client,
  SharedTestProfileConfig config,
) async {
  config.validate();
  if (!config.enabled) return;

  if (client.auth.currentUser?.email == config.email) {
    await client.auth.getUser();
    return;
  }
  await client.auth.signInWithPassword(
    email: config.email,
    password: config.password,
  );
}
