import { createClient } from "jsr:@supabase/supabase-js@2";

const ADMOB_KEYS_URL =
  "https://www.gstatic.com/admob/reward/verifier-keys.json";

type AdMobKey = {
  keyId: number;
  pem?: string;
  base64?: string;
};

function response(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(
    normalized.length + ((4 - normalized.length % 4) % 4),
    "=",
  );
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function decodePublicKey(key: AdMobKey): Uint8Array {
  if (key.base64) return decodeBase64Url(key.base64);
  if (!key.pem) throw new Error("AdMob public key has no key material");
  return decodeBase64Url(
    key.pem
      .replace("-----BEGIN PUBLIC KEY-----", "")
      .replace("-----END PUBLIC KEY-----", "")
      .replaceAll(/\s/g, ""),
  );
}

function asArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

// Web Crypto uses the IEEE P1363 r||s form while AdMob sends ASN.1 DER.
function derEcdsaSignatureToRaw(signature: Uint8Array): Uint8Array {
  if (signature.length === 64 && signature[0] !== 0x30) return signature;
  let offset = 0;

  function readByte(): number {
    if (offset >= signature.length) throw new Error("Malformed signature");
    return signature[offset++];
  }

  function readLength(): number {
    const first = readByte();
    if ((first & 0x80) === 0) return first;
    const byteCount = first & 0x7f;
    if (byteCount === 0 || byteCount > 2) {
      throw new Error("Malformed signature length");
    }
    let length = 0;
    for (let index = 0; index < byteCount; index++) {
      length = (length << 8) | readByte();
    }
    return length;
  }

  if (readByte() !== 0x30) throw new Error("Expected DER sequence");
  readLength();

  function readInteger(): Uint8Array {
    if (readByte() !== 0x02) throw new Error("Expected DER integer");
    const length = readLength();
    const integer = signature.slice(offset, offset + length);
    offset += length;
    const unsigned = integer[0] === 0 ? integer.slice(1) : integer;
    if (unsigned.length > 32) throw new Error("Oversized ECDSA integer");
    const padded = new Uint8Array(32);
    padded.set(unsigned, 32 - unsigned.length);
    return padded;
  }

  const raw = new Uint8Array(64);
  raw.set(readInteger(), 0);
  raw.set(readInteger(), 32);
  return raw;
}

async function verifySignature(
  signedContent: string,
  encodedSignature: string,
  keyId: number,
): Promise<boolean> {
  const keysResponse = await fetch(ADMOB_KEYS_URL, {
    headers: { accept: "application/json" },
  });
  if (!keysResponse.ok) throw new Error("Unable to fetch AdMob keys");
  const payload = await keysResponse.json() as { keys: AdMobKey[] };
  const matchingKey = payload.keys.find((key) => key.keyId === keyId);
  if (!matchingKey) throw new Error("Unknown AdMob key id");

  const publicKey = await crypto.subtle.importKey(
    "spki",
    asArrayBuffer(decodePublicKey(matchingKey)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    asArrayBuffer(
      derEcdsaSignatureToRaw(decodeBase64Url(encodedSignature)),
    ),
    new TextEncoder().encode(signedContent),
  );
}

function isAllowedAdUnit(adUnit: string): boolean {
  // Temporarily accept AdMob's URL-verification test unit.
  if (Deno.env.get("ADMOB_ALLOW_URL_VERIFICATION") === "true") return true;
  const configured = Deno.env.get("ADMOB_REWARDED_AD_UNIT_IDS") ?? "";
  const allowed = configured
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return allowed.some((value) =>
    value === adUnit || value.endsWith(`/${adUnit}`)
  );
}

Deno.serve(async (request) => {
  if (request.method !== "GET") return response("Method not allowed", 405);

  try {
    const url = new URL(request.url);
    const rawQuery = url.search.slice(1);
    const signatureMarker = "&signature=";
    const signatureOffset = rawQuery.indexOf(signatureMarker);
    if (signatureOffset < 0) return response("Missing signature", 400);

    const params = url.searchParams;
    const signature = params.get("signature");
    const keyId = Number(params.get("key_id"));
    const sessionId = params.get("custom_data");
    const userId = params.get("user_id");
    const transactionId = params.get("transaction_id");
    const adUnit = params.get("ad_unit");
    const rewardAmount = Number(params.get("reward_amount"));
    const rewardItem = params.get("reward_item") ?? "";

    if (
      !signature || !Number.isInteger(keyId) || !sessionId || !userId ||
      !transactionId || !adUnit || !Number.isSafeInteger(rewardAmount)
    ) {
      return response("Missing callback parameters", 400);
    }
    if (!isAllowedAdUnit(adUnit)) {
      return response("Ad unit is not allowed", 403);
    }

    const verified = await verifySignature(
      rawQuery.slice(0, signatureOffset),
      signature,
      keyId,
    );
    if (!verified) return response("Invalid signature", 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return response("Server is not configured", 503);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await supabase.rpc("verify_rewarded_ad_grant", {
      reward_session_id: sessionId,
      reward_user_id: userId,
      transaction_id: transactionId,
      verified_ad_unit_id: adUnit,
      verified_reward_amount: rewardAmount,
      verified_reward_item: rewardItem,
    });
    if (error) {
      console.error("Failed to verify rewarded ad grant", error);
      return response("Reward could not be recorded", 409);
    }
    return response("OK");
  } catch (error) {
    console.error("AdMob SSV callback failed", error);
    return response("Verification failed", 500);
  }
});
