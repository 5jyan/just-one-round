import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type PushJob = {
  id: string;
  recipient_id: string;
  title: string;
  body: string;
  payload: Record<string, unknown> | null;
  attempt_count: number;
  lease_token: string;
};

type PushDevice = {
  id: string;
  user_id: string;
  token: string;
};

type ClaimedJobRef = Pick<PushJob, "id" | "lease_token">;

const fcmRequestTimeoutMs = 15_000;

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function parseServiceAccount(raw: string): ServiceAccount {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("Firebase service account is not valid JSON");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Firebase service account must be a JSON object");
  }

  const candidate = parsed as Record<string, unknown>;
  if (
    !isNonEmptyString(candidate.project_id) ||
    !isNonEmptyString(candidate.client_email) ||
    !isNonEmptyString(candidate.private_key)
  ) {
    throw new Error("Firebase service account is missing required fields");
  }
  return {
    project_id: candidate.project_id.trim(),
    client_email: candidate.client_email.trim(),
    private_key: candidate.private_key,
  };
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function firebaseAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    signal: AbortSignal.timeout(fcmRequestTimeoutMs),
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new Error("FCM authorization returned invalid JSON");
  }
  const payloadRecord =
    payload !== null && typeof payload === "object"
      ? (payload as Record<string, unknown>)
      : null;
  const accessToken = payloadRecord?.access_token;
  if (!response.ok || !isNonEmptyString(accessToken)) {
    throw new Error(`FCM authorization failed: ${response.status}`);
  }
  return accessToken;
}

async function releaseClaimedJobs(
  admin: ReturnType<typeof createClient>,
  jobs: ReadonlyArray<ClaimedJobRef>,
  lastError: string,
): Promise<boolean> {
  if (!jobs.length) return true;

  for (const job of jobs) {
    try {
      const { error } = await admin
        .from("push_notification_outbox")
        .update({ processing_until: null, lease_token: null, last_error: lastError })
        .eq("id", job.id)
        .eq("lease_token", job.lease_token)
        .is("sent_at", null)
        .is("suppressed_at", null);
      if (error) {
        console.error("[Push] Failed to release push job lease");
        return false;
      }
    } catch {
      console.error("[Push] Failed to release push job lease");
      return false;
    }
  }
  return true;
}

async function responseAfterClaimFailure(
  admin: ReturnType<typeof createClient>,
  jobs: ReadonlyArray<ClaimedJobRef>,
  status: number,
  message: string,
): Promise<Response> {
  const released = await releaseClaimedJobs(admin, jobs, message);
  return json(
    {
      error: released ? message : "Unable to release push job leases",
    },
    released ? status : 500,
  );
}

async function isSocialPushEnabled(
  admin: ReturnType<typeof createClient>,
  recipientId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("profiles")
    .select("social_notifications_enabled")
    .eq("id", recipientId)
    .maybeSingle();
  if (error) throw new Error("Unable to load push preference");
  return data?.social_notifications_enabled === true;
}

async function suppressClaimedJob(
  admin: ReturnType<typeof createClient>,
  job: ClaimedJobRef,
): Promise<boolean> {
  try {
    const { error } = await admin
      .from("push_notification_outbox")
      .update({
        suppressed_at: new Date().toISOString(),
        processing_until: null,
        lease_token: null,
        last_error: "suppressed by user preference",
      })
      .eq("id", job.id)
      .eq("lease_token", job.lease_token)
      .is("sent_at", null)
      .is("suppressed_at", null);
    if (error) {
      console.error("[Push] Failed to suppress push job");
      return false;
    }
    return true;
  } catch {
    console.error("[Push] Failed to suppress push job");
    return false;
  }
}

async function isClaimedJobSendable(
  admin: ReturnType<typeof createClient>,
  job: ClaimedJobRef,
): Promise<boolean> {
  const { data, error } = await admin
    .from("push_notification_outbox")
    .select("id")
    .eq("id", job.id)
    .eq("lease_token", job.lease_token)
    .is("sent_at", null)
    .is("suppressed_at", null)
    .gt("processing_until", new Date().toISOString())
    .maybeSingle();
  if (error) throw new Error("Unable to verify push job lease");
  return data !== null;
}

function isUnregisteredFcmResponse(responseBody: string): boolean {
  let parsed: unknown;
  try {
    parsed = JSON.parse(responseBody);
  } catch {
    return false;
  }
  if (parsed === null || typeof parsed !== "object") return false;
  const error = (parsed as Record<string, unknown>).error;
  if (error === null || typeof error !== "object") return false;
  const details = (error as Record<string, unknown>).details;
  if (!Array.isArray(details)) return false;
  return details.some((detail) => {
    if (detail === null || typeof detail !== "object") return false;
    const code = (detail as Record<string, unknown>).errorCode;
    if (typeof code !== "string") return false;
    const normalized = code.trim().toUpperCase();
    return normalized === "UNREGISTERED" ||
      normalized === "REGISTRATION_TOKEN_NOT_REGISTERED";
  });
}

async function disableInvalidDeviceToken(
  admin: ReturnType<typeof createClient>,
  device: PushDevice,
): Promise<boolean> {
  const { error } = await admin
    .from("push_device_tokens")
    .update({ enabled: false })
    .eq("id", device.id)
    .eq("user_id", device.user_id)
    .eq("token", device.token)
    .eq("enabled", true);
  return error === null;
}

async function isActivePushDevice(
  admin: ReturnType<typeof createClient>,
  device: PushDevice,
): Promise<boolean> {
  const { data, error } = await admin
    .from("push_device_tokens")
    .select("id")
    .eq("id", device.id)
    .eq("user_id", device.user_id)
    .eq("token", device.token)
    .eq("enabled", true)
    .maybeSingle();
  if (error) throw new Error("Unable to verify push device");
  return data !== null;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const workerSecret = Deno.env.get("PUSH_WORKER_SECRET");
  if (!workerSecret || request.headers.get("x-push-worker-secret") !== workerSecret) {
    return json({ error: "Unauthorized" }, 401);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const accountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (
    !isNonEmptyString(supabaseUrl) ||
    !isNonEmptyString(serviceKey) ||
    !isNonEmptyString(accountJson)
  ) {
    return json({ error: "Push secrets are not configured" }, 503);
  }

  let account: ServiceAccount;
  try {
    account = parseServiceAccount(accountJson);
  } catch {
    console.error("[Push] Invalid Firebase service account configuration");
    return json({ error: "Invalid Firebase service account configuration" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (new URL(request.url).searchParams.get("health") === "1") {
    try {
      await firebaseAccessToken(account);
      return json({ status: "ok" });
    } catch {
      return json({ error: "FCM authorization failed" }, 503);
    }
  }

  let rawJobs: unknown = null;
  let jobsError: unknown = null;
  try {
    const result = await admin.rpc("claim_push_notification_jobs", {
      batch_limit: 50,
    });
    rawJobs = result.data;
    jobsError = result.error;
  } catch (error) {
    jobsError = error;
  }
  if (jobsError) return json({ error: "Unable to claim push jobs" }, 500);
  if (!Array.isArray(rawJobs)) {
    return json({ error: "Unable to claim push jobs" }, 500);
  }

  const jobs = rawJobs as PushJob[];
  if (!jobs.length) {
    console.info('[Push] queue empty');
    return json({ processed: 0, sent: 0 });
  }

  let accessToken: string;
  try {
    accessToken = await firebaseAccessToken(account);
  } catch {
    return responseAfterClaimFailure(
      admin,
      jobs,
      503,
      "FCM authorization failed",
    );
  }

  const recipientIds = [...new Set(jobs.map((job) => job.recipient_id))];
  let rawDevices: unknown = null;
  let devicesError: unknown = null;
  try {
    const result = await admin
      .from("push_device_tokens")
      .select("id,user_id,token")
      .in("user_id", recipientIds)
      .eq("enabled", true);
    rawDevices = result.data;
    devicesError = result.error;
  } catch (error) {
    devicesError = error;
  }
  if (devicesError) {
    return responseAfterClaimFailure(
      admin,
      jobs,
      500,
      "Unable to load push devices",
    );
  }

  const devices = (Array.isArray(rawDevices) ? rawDevices : []) as PushDevice[];

  let sent = 0;
  for (let jobIndex = 0; jobIndex < jobs.length; jobIndex++) {
    const job = jobs[jobIndex];
    const targets = devices?.filter((device) => device.user_id === job.recipient_id) ?? [];

    let pushEnabled: boolean;
    try {
      pushEnabled = await isSocialPushEnabled(admin, job.recipient_id);
    } catch {
      return responseAfterClaimFailure(
        admin,
        jobs.slice(jobIndex),
        500,
        "Unable to load push preference",
      );
    }
    if (!pushEnabled) {
      if (!(await suppressClaimedJob(admin, job))) {
        return responseAfterClaimFailure(
          admin,
          jobs.slice(jobIndex),
          500,
          "Unable to suppress push job",
        );
      }
      continue;
    }

    let delivered = false;
    let lastError = targets.length ? "FCM delivery failed" : "No registered device";
    let staleClaim = false;
    let suppressed = false;
    for (const device of targets) {
      let sendable: boolean;
      try {
        sendable = await isClaimedJobSendable(admin, job);
      } catch {
        return responseAfterClaimFailure(
          admin,
          jobs.slice(jobIndex),
          500,
          "Unable to verify push job lease",
        );
      }
      if (!sendable) {
        staleClaim = true;
        break;
      }

      let activeDevice: boolean;
      try {
        activeDevice = await isActivePushDevice(admin, device);
      } catch {
        return responseAfterClaimFailure(
          admin,
          jobs.slice(jobIndex),
          500,
          "Unable to verify push device",
        );
      }
      if (!activeDevice) {
        lastError = "No registered device";
        continue;
      }

      try {
        pushEnabled = await isSocialPushEnabled(admin, job.recipient_id);
      } catch {
        return responseAfterClaimFailure(
          admin,
          jobs.slice(jobIndex),
          500,
          "Unable to load push preference",
        );
      }
      if (!pushEnabled) {
        if (!(await suppressClaimedJob(admin, job))) {
          return responseAfterClaimFailure(
            admin,
            jobs.slice(jobIndex),
            500,
            "Unable to suppress push job",
          );
        }
        suppressed = true;
        break;
      }

      let response: Response;
      try {
        response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${accessToken}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: device.token,
                notification: { title: job.title, body: job.body },
                data: Object.fromEntries(
                  Object.entries(job.payload ?? {}).map(([key, value]) => [key, String(value)]),
                ),
                android: {
                  priority: "high",
                  notification: {
                    channel_id: "social_notifications",
                    tag: job.id,
                  },
                },
                apns: {
                  headers: {
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                    "apns-collapse-id": job.id,
                  },
                  payload: { aps: { sound: "default" } },
                },
              },
            }),
            signal: AbortSignal.timeout(fcmRequestTimeoutMs),
          },
        );
      } catch {
        lastError = "FCM network error";
        continue;
      }

      if (response.ok) {
        delivered = true;
      } else {
        let responseBody = "";
        try {
          responseBody = await response.text();
        } catch {
          responseBody = "";
        }
        lastError = `FCM ${response.status}`;
        if (isUnregisteredFcmResponse(responseBody)) {
          try {
            if (!(await disableInvalidDeviceToken(admin, device))) {
              lastError = "Failed to disable invalid device token";
            }
          } catch {
            lastError = "Failed to disable invalid device token";
          }
        }
      }
    }

    if (staleClaim || suppressed) continue;

    let updateError: unknown = null;
    let completionApplied = false;
    try {
      const result = await admin
        .from("push_notification_outbox")
        .update({
          sent_at: delivered ? new Date().toISOString() : null,
          attempt_count: job.attempt_count + 1,
          last_error: delivered ? null : lastError,
          processing_until: null,
          lease_token: null,
        })
        .eq("id", job.id)
        .eq("lease_token", job.lease_token)
        .is("sent_at", null)
        .is("suppressed_at", null)
        .select("id");
      updateError = result.error;
      completionApplied = (result.data?.length ?? 0) > 0;
    } catch (error) {
      updateError = error;
    }
    if (updateError) {
      await releaseClaimedJobs(
        admin,
        jobs.slice(jobIndex),
        "Push job update failed",
      );
      return json({ error: "Unable to update push job" }, 500);
    }
    if (delivered && completionApplied) {
      sent++;
    } else if (!delivered) {
      console.warn(`[Push] delivery failed: ${lastError}`);
    }
  }
  console.info(`[Push] batch processed=${jobs.length} sent=${sent}`);
  return json({ processed: jobs.length, sent });
});
