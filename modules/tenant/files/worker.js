// Generic assets worker — serves objects from a private OCI Object Storage
// bucket over Cloudflare, signed with AWS SigV4 against the OCI S3-compatible
// endpoint.
//
// Request:  GET /{key}
// Upstream: GET https://{namespace}.compat.objectstorage.{region}.oraclecloud.com/{bucket}/{key}
//
// Deployed by the tenant module (cloudflare_workers_script). Secrets
// (OCI_S3_ACCESS_KEY, OCI_S3_SECRET_KEY) are injected as secret_text_bindings;
// namespace/region/bucket as plain_text_bindings.

const EMPTY_SHA256 =
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
const SERVICE = "s3";

addEventListener("fetch", (event) => {
  event.respondWith(handle(event));
});

async function handle(event) {
  const request = event.request;
  const url = new URL(request.url);
  const key = url.pathname.replace(/^\/+/, "");
  if (!key) {
    return new Response("Not Found", { status: 404 });
  }

  const cache = caches.default;
  const cached = await cache.match(request);
  if (cached) {
    return cached;
  }

  const encodedKey = key.split("/").map(encodeURIComponent).join("/");
  const objectUrl =
    `https://${env("OCI_NAMESPACE")}.compat.objectstorage.` +
    `${env("OCI_REGION")}.oraclecloud.com/${env("OCI_BUCKET")}/${encodedKey}`;

  const signed = await signGet(
    objectUrl,
    env("OCI_S3_ACCESS_KEY"),
    env("OCI_S3_SECRET_KEY"),
    env("OCI_REGION")
  );

  const upstream = await fetch(signed);
  if (!upstream.ok) {
    return new Response(`Upstream error ${upstream.status}`, {
      status: upstream.status,
    });
  }

  const headers = new Headers();
  headers.set("Content-Type", upstream.headers.get("Content-Type") || "application/octet-stream");
  headers.set("Cache-Control", "public, max-age=31536000, immutable");

  const response = new Response(upstream.body, { headers });
  event.waitUntil(cache.put(request, response.clone()));
  return response;
}

function env(name) {
  return globalThis[name];
}

// ── AWS SigV4 (header-based) ──────────────────────────────
async function signGet(url, accessKey, secretKey, region) {
  const u = new URL(url);
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const method = "GET";

  const host = u.host;
  const canonicalUri = u.pathname;
  const canonicalQuery = u.search ? u.search.slice(1) : "";
  const canonicalHeaders =
    `host:${host}\n` +
    `x-amz-content-sha256:${EMPTY_SHA256}\n` +
    `x-amz-date:${amzDate}\n`;
  const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    EMPTY_SHA256,
  ].join("\n");

  const algorithm = "AWS4-HMAC-SHA256";
  const scope = `${dateStamp}/${region}/${SERVICE}/aws4_request`;
  const stringToSign = [
    algorithm,
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const kDate = await hmac("AWS4" + secretKey, dateStamp);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, SERVICE);
  const kSigning = await hmac(kService, "aws4_request");
  const signature = toHex(await hmac(kSigning, stringToSign));

  const authorization =
    `${algorithm} Credential=${accessKey}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const headers = new Headers();
  headers.set("x-amz-content-sha256", EMPTY_SHA256);
  headers.set("x-amz-date", amzDate);
  headers.set("Authorization", authorization);
  return new Request(url, { method: "GET", headers });
}

// ── Crypto helpers ────────────────────────────────────────
const enc = new TextEncoder();

async function sha256Hex(data) {
  const digest = await crypto.subtle.digest("SHA-256", typeof data === "string" ? enc.encode(data) : data);
  return toHex(new Uint8Array(digest));
}

async function hmac(key, msg) {
  const keyData = typeof key === "string" ? enc.encode(key) : key;
  const msgData = typeof msg === "string" ? enc.encode(msg) : msg;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  return new Uint8Array(signature);
}

function toHex(bytes) {
  let out = "";
  for (const b of bytes) out += b.toString(16).padStart(2, "0");
  return out;
}
