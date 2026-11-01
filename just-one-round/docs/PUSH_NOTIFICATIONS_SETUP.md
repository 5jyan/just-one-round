# Social push notification setup

> 일반 원칙은 [한국어 푸시 알림 일반 가이드](PUSH_NOTIFICATIONS_GUIDE.md)를
> 먼저 읽는다.

The app and database already create durable social notifications, register FCM
device tokens, and queue every poke, boast, and gift in
`push_notification_outbox`. Complete these one-time external steps before a
release build can display lock-screen notifications.

Social actions are limited server-side to three pokes and three boasts per
Seoul calendar day. The app may disable or explain the action locally for a
better experience, but it must not be the only enforcement layer. There is no
per-recipient six-hour poke cooldown.

## Current project status

The external wiring for `just-one-round` has been checked and is currently in
place: Firebase Cloud Messaging API (HTTP v1) is enabled, both Firebase apps
use the `com.justoneround.app` identifiers, Apple Developer has Push
Notifications enabled for that App ID, and the development/App Store profiles
exist. Firebase's iOS app configuration contains the APNs key for the
`K82D26JQH7` team in both development and production entries. Do not replace
or revoke the existing key, and do not reuse Shook's bundle ID or signing
assets. The physical receive smoke test is complete on the connected Android
and iPhone. Keep the receive-and-tap check in the release checklist whenever
the signing profile, Firebase/APNs credentials, or tap flow changes.

1. Create Android and iOS apps in one Firebase project, then run
   `flutterfire configure`. Keep `GoogleService-Info.plist` in `ios/Runner` and
   `google-services.json` in `android/app`. These client configuration files
   are ignored by Git and must be injected into local/release build machines.
   The current FlutterFire iOS SDK requires iOS 15.0 or newer; the project
   deployment target is configured accordingly.
2. In Xcode, enable **Push Notifications** and **Background Modes > Remote
   notifications**. Upload the Apple APNs `.p8` key in Firebase Cloud Messaging.
   For App Store/TestFlight builds, the Apple Developer account must also have
   the `JustOneRound App Store` profile for the explicit App ID
   `com.justoneround.app`; install the downloaded profile in Xcode's local
   provisioning-profile directory. This is separate from the `Shook` bundle
   ID and its signing credentials.
3. Apply the database migrations before deploying the worker. The claim lease
   migration is what prevents a webhook and the periodic retry from sending
   the same outbox row concurrently:

   ```sh
   npx supabase link --project-ref <project-ref>
   npx supabase db push
   ```

4. Configure Supabase secrets (never commit the values):

   ```sh
   npx supabase secrets set \
     FIREBASE_SERVICE_ACCOUNT_JSON='<service-account-json>' \
     PUSH_WORKER_SECRET='<long-random-secret>'
   npx supabase functions deploy send-social-push --no-verify-jwt
   ```

5. Configure the delivery trigger as an external one-time wiring step. Create
   a Supabase Database Webhook for inserts on
   `public.push_notification_outbox`, point it to
   `https://<project-ref>.supabase.co/functions/v1/send-social-push`, and add the
   header `x-push-worker-secret: <same-secret>`. A one-minute cron invocation is
   also recommended to retry transient failures. The current repository
   migrations and local database do not create this webhook, a `pg_cron` job, or
   a Vault secret automatically; configure those separately in the deployed
   Supabase project or an external scheduler. The migrations provide the
   outbox and claim function that the external wiring invokes. Social-action
   and gift RPCs reject test-account senders before changing inventory or
   creating an in-app notification. The shared enqueue path also filters test
   senders and recipients, and the claim path suppresses any stale test-account
   row before a worker can deliver it. Marking an account as a test account
   revokes an already-held push lease as well.
6. To run the worker against the local Supabase stack, create the ignored
   `.env.push-worker.local` file outside version control with these four
   non-empty entries (use real values only in your local secret store or shell):

   ```dotenv
   SUPABASE_URL=<local-supabase-url>
   SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key>
   PUSH_WORKER_SECRET=<local-worker-secret>
   FIREBASE_SERVICE_ACCOUNT_JSON=<service-account-json>
   ```

   Start the worker with:

   ```sh
   ./tool/serve_push_worker_local.sh
   ```

   The script checks only that the env file exists and those four assignments
   are non-empty; it never prints their values. Use
   `PUSH_WORKER_ENV_FILE=/absolute/path/to/file` for another ignored local env
   file. The Docker network defaults to
   `supabase_network_just-one-round`; set `SUPABASE_NETWORK_ID` when the local
   stack uses a different network.

   With `PUSH_WORKER_SECRET` injected into the current shell by a secret
   manager, check the local endpoint without printing the secret or response
   body:

   ```sh
   ./tool/check_push_worker.sh
   PUSH_WORKER_URL=http://127.0.0.1:54321/functions/v1/send-social-push \
     ./tool/check_push_worker.sh
   ```

   The check validates Firebase OAuth credentials through the non-claiming
   `?health=1` endpoint and checks HTTP 200 with `{"status":"ok"}`. It makes
   one health request only; it never calls the dispatch endpoint and therefore
   cannot claim or send queued notifications. Never commit the local env file,
   service account JSON, service-role key, worker secret, or device tokens. For
   production, inject the same values through the Supabase secret manager or a
   CI secret store rather than repository files or logs.
7. Release/profile builds enable Firebase push by default. The app observes
   existing OS permission on startup and shows a one-time in-app confirmation
   for each store build. Users with an undecided permission are sent to the
   system prompt, while users who previously denied it are sent to device
   settings. The normal social notification setting remains available for
   later changes. For an explicit
   value, use `--dart-define=ENABLE_FIREBASE_PUSH=true`; local debug/test builds
   can opt in with the same flag. The Android Gradle plugin is applied only
   when `android/app/google-services.json` exists, so credential-free local
   builds remain usable. Release builds fail early when the Android JSON or
   iOS `GoogleService-Info.plist` is missing instead of silently shipping
   without push.

   The checked-in App Store export mapping keeps manual signing deterministic:

   ```sh
   flutter build ipa --release \
     --export-options-plist=ios/ExportOptions-AppStore.plist \
     --dart-define=ENABLE_FIREBASE_PUSH=true
   ```

After deployment, inject `PUSH_WORKER_SECRET` from the secret manager and use
the same response-safe check script against the external endpoint:

```sh
npx supabase functions list
PUSH_WORKER_URL='https://<project-ref>.supabase.co/functions/v1/send-social-push' \
  ./tool/check_push_worker.sh
```

The health check should return HTTP 200 with `{"status":"ok"}`. To dispatch
queued notifications, use the configured webhook or scheduler directly; do
not use the health check as a dispatch probe.
For a real device smoke test, sign in on iOS and Android, confirm both rows are
enabled in `push_device_tokens`, then send one poke and verify one outbox row
becomes `sent_at` non-null and the device receives the notification. A tap
first opens the safe daily-game home and then opens the matching in-app social
dialog; the user confirms the dialog before the notification is acknowledged.

The Edge Function uses FCM HTTP v1, disables only structurally confirmed
unregistered device tokens, protects outbox updates with a per-claim lease
token, releases leases when Firebase authorization or device lookup fails,
times out outbound requests, and retries each queued notification at most five
times. Turning off `social_notifications_enabled` suppresses unsent outbox rows
and the worker rechecks the preference before each device send; turning it back
on does not resurrect suppressed rows. On iOS, the app routes cold-start
notification taps independently of APNs token readiness, then waits for APNs
before requesting the FCM token. A notification tap opens the daily-game home
and then shows the matching in-app social dialog; the user must confirm the
dialog and press the start button before a server-issued attempt is consumed.
The in-app inbox remains the fallback when the user denies OS notification
permission.

### Google Play automated test devices

Android reads Firebase Test Lab's `firebase.test.lab` system setting when it
reports app build information. When the value is exactly `true`, the client
keeps gameplay available but skips social-action and shop-gift requests, so an
automated crawler cannot create notifications for real users. The server-side
test-account and outbox filters remain the independent safety boundary. Builds
that predate this native flag, or platforms without the channel, default to
normal social behavior; the native guard takes effect with the next Android
build that includes `MainActivity.kt`.
