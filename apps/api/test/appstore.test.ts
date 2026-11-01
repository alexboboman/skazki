import assert from "node:assert/strict";
import { createSign } from "node:crypto";
import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { before, describe, test } from "node:test";

process.env.AUTH_DEV_LOGIN = "1";
process.env.JWT_SECRET = "test-secret";
delete process.env.NODE_ENV;
delete process.env.APPLE_BUNDLE_ID;

const { createApp } = await import("../src/app.js");
const { createDb } = await import("../src/db/client.js");
const { createAppStoreVerifier } = await import("../src/services/appStore.js");
const { statusFromNotification, statusFromTransaction } = await import("../src/services/subscriptionService.js");
const { MockImageGenerator } = await import("../src/services/imageGenerator.js");
const { LocalMediaStore } = await import("../src/services/mediaStore.js");

const BUNDLE_ID = "com.example.skazochnik";
const DAY = 24 * 3600 * 1000;
const fixtures = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures", "appstore");
const pem = (name: string) => readFile(path.join(fixtures, name), "utf8");

const [rootPem, interPem, leafPem, leafKey, devLeafPem, devLeafKey] = await Promise.all([
  pem("root.pem"),
  pem("inter.pem"),
  pem("leaf.pem"),
  pem("leaf.key"),
  pem("devleaf.pem"),
  pem("devleaf.key")
]);

const der = (certPem: string) => certPem.replace(/-----[A-Z ]+-----|\s/g, "");
const b64url = (value: object | Buffer) => Buffer.from(value instanceof Buffer ? value : JSON.stringify(value)).toString("base64url");

/** Signs like the App Store does: ES256 with the leaf key, certificate chain in x5c. */
function signJws(payload: object, opts: { developerCert?: boolean; alg?: string } = {}) {
  const leaf = opts.developerCert ? devLeafPem : leafPem;
  const key = opts.developerCert ? devLeafKey : leafKey;
  const header = { alg: opts.alg ?? "ES256", x5c: [der(leaf), der(interPem), der(rootPem)] };
  const input = `${b64url(header)}.${b64url(payload)}`;
  const signature = createSign("sha256").update(input).sign({ key, dsaEncoding: "ieee-p1363" });
  return `${input}.${b64url(signature)}`;
}

const verifier = createAppStoreVerifier({ rootCertificates: [rootPem] });

let clock = Date.now();
const tx = (over: Record<string, unknown> = {}) => ({
  transactionId: "2000000000001",
  originalTransactionId: "1000000000001",
  bundleId: BUNDLE_ID,
  productId: "family_monthly",
  type: "Auto-Renewable Subscription",
  purchaseDate: Date.now(),
  expiresDate: Date.now() + 30 * DAY,
  environment: "Sandbox",
  signedDate: ++clock,
  ...over
});

const notification = (type: string, transaction: object, extra: { subtype?: string; renewal?: object; signedDate?: number } = {}) =>
  signJws({
    notificationType: type,
    subtype: extra.subtype,
    notificationUUID: `${type}-${++clock}`,
    signedDate: extra.signedDate ?? ++clock,
    data: {
      environment: "Sandbox",
      bundleId: BUNDLE_ID,
      signedTransactionInfo: signJws(transaction),
      ...(extra.renewal ? { signedRenewalInfo: signJws(extra.renewal) } : {})
    }
  });

describe("App Store signature check", () => {
  test("accepts a payload signed through the trusted chain", () => {
    const payload = verifier.verify<{ hello: string }>(signJws({ hello: "world", signedDate: Date.now() }));
    assert.equal(payload.hello, "world");
  });

  test("rejects a tampered payload", () => {
    const [header, , signature] = signJws({ productId: "family_monthly" }).split(".");
    assert.throws(() => verifier.verify(`${header}.${b64url({ productId: "family_plus_yearly" })}.${signature}`), /signature/i);
  });

  test("rejects a chain that does not end in a trusted root", () => {
    assert.throws(() => createAppStoreVerifier().verify(signJws({ a: 1 })), /root/i);
  });

  test("rejects a certificate without Apple's App Store marker, even from the same root", () => {
    assert.throws(() => verifier.verify(signJws({ a: 1 }, { developerCert: true })), /App Store/);
  });

  test("rejects other algorithms and malformed input", () => {
    assert.throws(() => verifier.verify(signJws({ a: 1 }, { alg: "none" })));
    assert.throws(() => verifier.verify("not-a-jws"));
    assert.throws(() => verifier.verify("a.b.c"));
  });

  test("checks certificate validity at the signing time", () => {
    const farFuture = Date.UTC(2200, 0, 1);
    assert.throws(() => verifier.verify(signJws({ a: 1, signedDate: farFuture })), /valid/i);
  });
});

describe("subscription status rules", () => {
  const now = new Date();

  test("a transaction is active until it expires and revoked when refunded", () => {
    assert.equal(statusFromTransaction(tx() as any, now), "active");
    assert.equal(statusFromTransaction(tx({ expiresDate: now.getTime() - 1 }) as any, now), "expired");
    assert.equal(statusFromTransaction(tx({ revocationDate: now.getTime() }) as any, now), "revoked");
  });

  test("failed renewals depend on the grace period", () => {
    assert.equal(statusFromNotification("DID_FAIL_TO_RENEW", "GRACE_PERIOD", tx() as any, now), "grace_period");
    assert.equal(statusFromNotification("DID_FAIL_TO_RENEW", undefined, tx() as any, now), "billing_retry");
    assert.equal(statusFromNotification("GRACE_PERIOD_EXPIRED", undefined, tx() as any, now), "expired");
    assert.equal(statusFromNotification("DID_RENEW", undefined, tx() as any, now), "active");
    assert.equal(statusFromNotification("REFUND", undefined, tx() as any, now), "revoked");
  });
});

let app: ReturnType<typeof createApp>;
let userCounter = 0;

before(async () => {
  const db = await createDb({ dataDir: "memory://" });
  const deps = {
    db,
    mediaStore: new LocalMediaStore(await mkdtemp(path.join(os.tmpdir(), "skazochnik-media-"))),
    imageGenerator: new MockImageGenerator(),
    appStoreVerifier: verifier
  };
  app = createApp({ ...deps, appleBundleId: BUNDLE_ID });
  unconfigured = createApp(deps);
});

let unconfigured: ReturnType<typeof createApp>;

async function call(target: typeof app, method: string, url: string, token?: string, body?: unknown) {
  const res = await target.request(url, {
    method,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await res.text();
  let json: any;
  try {
    json = JSON.parse(text);
  } catch {
    json = undefined;
  }
  return { status: res.status, json };
}

/** A user on Free: the trial is ended, so the tier comes from purchases only. */
async function freeUser() {
  const { json } = await call(app, "POST", "/v1/auth/dev", undefined, { name: `buyer${++userCounter}` });
  await call(app, "PUT", "/v1/dev/subscription", json.token, { tier: "free" });
  return json as { token: string; user: { id: string } };
}

const sync = (token: string, ...transactions: string[]) => call(app, "POST", "/v1/subscription/sync", token, { transactions });
const tierOf = async (token: string) => (await call(app, "GET", "/v1/entitlements", token)).json;

let originalCounter = 5000;
const freshOriginal = () => String(++originalCounter);

describe("POST /v1/subscription/sync", () => {
  test("a purchase unlocks the tier of its product", async () => {
    const { token } = await freeUser();
    assert.equal((await tierOf(token)).tier, "free");

    const res = await sync(token, signJws(tx({ originalTransactionId: freshOriginal(), productId: "family_plus_yearly" })));
    assert.equal(res.status, 200);
    assert.equal(res.json.tier, "family_plus");
    assert.equal(res.json.source, "subscription");
    assert.equal(res.json.limits.premiumVoice, true);
  });

  test("requires a signed-in user", async () => {
    assert.equal((await call(app, "POST", "/v1/subscription/sync", undefined, { transactions: [] })).status, 401);
  });

  test("an empty list just returns the current entitlements", async () => {
    const { token } = await freeUser();
    const res = await sync(token);
    assert.equal(res.status, 200);
    assert.equal(res.json.tier, "free");
  });

  test("rejects forged, foreign and unknown transactions", async () => {
    const { token } = await freeUser();
    const forged = signJws(tx({ originalTransactionId: freshOriginal() }), { developerCert: true });
    const foreignApp = signJws(tx({ originalTransactionId: freshOriginal(), bundleId: "com.someone.else" }));
    const unknownProduct = signJws(tx({ originalTransactionId: freshOriginal(), productId: "gems_100" }));
    const consumable = signJws(tx({ originalTransactionId: freshOriginal(), type: "Consumable" }));

    for (const jws of [forged, foreignApp, unknownProduct, consumable, "garbage"]) {
      assert.equal((await sync(token, jws)).status, 400);
    }
    assert.equal((await tierOf(token)).tier, "free");
  });

  test("valid transactions count even when another one in the list is bad", async () => {
    const { token } = await freeUser();
    const res = await sync(token, "garbage", signJws(tx({ originalTransactionId: freshOriginal() })));
    assert.equal(res.status, 200);
    assert.equal(res.json.tier, "family");
  });

  test("validates the body", async () => {
    const { token } = await freeUser();
    assert.equal((await call(app, "POST", "/v1/subscription/sync", token, { transactions: "x" })).status, 400);
    assert.equal((await call(app, "POST", "/v1/subscription/sync", token, { transactions: [1] })).status, 400);
    assert.equal((await call(app, "POST", "/v1/subscription/sync", token, {})).status, 400);
  });

  test("an expired subscription gives nothing", async () => {
    const { token } = await freeUser();
    const res = await sync(token, signJws(tx({ originalTransactionId: freshOriginal(), expiresDate: Date.now() - DAY })));
    assert.equal(res.json.tier, "free");
  });

  test("restoring on a new account moves the subscription to it", async () => {
    const original = freshOriginal();
    const first = await freeUser();
    const second = await freeUser();
    await sync(first.token, signJws(tx({ originalTransactionId: original })));
    assert.equal((await tierOf(first.token)).tier, "family");

    await sync(second.token, signJws(tx({ originalTransactionId: original })));
    assert.equal((await tierOf(second.token)).tier, "family");
    assert.equal((await tierOf(first.token)).tier, "free");
  });

  test("answers 503 when the server does not know the bundle id", async () => {
    const { json } = await call(unconfigured, "POST", "/v1/auth/dev", undefined, { name: "nobundle" });
    const res = await call(unconfigured, "POST", "/v1/subscription/sync", json.token, { transactions: [] });
    assert.equal(res.status, 503);
    assert.equal(res.json.error.code, "purchases_unavailable");
  });
});

describe("POST /v1/webhooks/apple", () => {
  const hook = (signedPayload: string) => call(app, "POST", "/v1/webhooks/apple", undefined, { signedPayload });

  test("a renewal extends the subscription", async () => {
    const { token } = await freeUser();
    const original = freshOriginal();
    await sync(token, signJws(tx({ originalTransactionId: original, expiresDate: Date.now() + 1000 })));

    const renewed = await hook(notification("DID_RENEW", tx({ originalTransactionId: original, expiresDate: Date.now() + 30 * DAY })));
    assert.equal(renewed.status, 200);
    assert.equal((await tierOf(token)).tier, "family");
  });

  test("an upgrade changes the tier", async () => {
    const { token } = await freeUser();
    const original = freshOriginal();
    await sync(token, signJws(tx({ originalTransactionId: original })));

    await hook(notification("DID_CHANGE_RENEWAL_PREF", tx({ originalTransactionId: original, productId: "family_plus_monthly" }), { subtype: "UPGRADE" }));
    assert.equal((await tierOf(token)).tier, "family_plus");
  });

  test("expiry, refund and revocation take access away", async () => {
    for (const type of ["EXPIRED", "REFUND", "REVOKE"]) {
      const { token } = await freeUser();
      const original = freshOriginal();
      await sync(token, signJws(tx({ originalTransactionId: original })));
      assert.equal((await tierOf(token)).tier, "family");

      await hook(notification(type, tx({ originalTransactionId: original })));
      assert.equal((await tierOf(token)).tier, "free", type);
    }
  });

  test("a failed renewal keeps access only during the grace period", async () => {
    const { token } = await freeUser();
    const original = freshOriginal();
    const lapsed = tx({ originalTransactionId: original, expiresDate: Date.now() - DAY });
    await sync(token, signJws(tx({ originalTransactionId: original })));

    await hook(
      notification("DID_FAIL_TO_RENEW", lapsed, { subtype: "GRACE_PERIOD", renewal: { gracePeriodExpiresDate: Date.now() + 5 * DAY } })
    );
    assert.equal((await tierOf(token)).tier, "family");

    await hook(notification("GRACE_PERIOD_EXPIRED", lapsed));
    assert.equal((await tierOf(token)).tier, "free");

    const retrying = await freeUser();
    const other = freshOriginal();
    await sync(retrying.token, signJws(tx({ originalTransactionId: other })));
    await hook(notification("DID_FAIL_TO_RENEW", tx({ originalTransactionId: other, expiresDate: Date.now() - DAY })));
    assert.equal((await tierOf(retrying.token)).tier, "free");
  });

  test("an older notification arriving late does not undo a newer one", async () => {
    const { token } = await freeUser();
    const original = freshOriginal();
    await sync(token, signJws(tx({ originalTransactionId: original })));

    const stale = notification("EXPIRED", tx({ originalTransactionId: original }), { signedDate: Date.now() - 10 * DAY });
    await hook(stale);
    assert.equal((await tierOf(token)).tier, "family");
  });

  test("a purchase made on another device is matched by appAccountToken", async () => {
    const { token, user } = await freeUser();
    const original = freshOriginal();
    const res = await hook(notification("SUBSCRIBED", tx({ originalTransactionId: original, appAccountToken: user.id }), { subtype: "INITIAL_BUY" }));
    assert.equal(res.status, 200);
    assert.equal((await tierOf(token)).tier, "family");
  });

  test("a subscription of an unknown account is acknowledged and waits for the app to claim it", async () => {
    const original = freshOriginal();
    const res = await hook(notification("SUBSCRIBED", tx({ originalTransactionId: original })));
    assert.equal(res.status, 200);

    const { token } = await freeUser();
    await sync(token, signJws(tx({ originalTransactionId: original })));
    assert.equal((await tierOf(token)).tier, "family");
  });

  test("notifications without a transaction (TEST) are acknowledged", async () => {
    const res = await hook(signJws({ notificationType: "TEST", signedDate: Date.now() }));
    assert.equal(res.status, 200);
  });

  test("a forged or malformed notification is refused", async () => {
    const forged = signJws({ notificationType: "SUBSCRIBED", data: {} }, { developerCert: true });
    assert.equal((await hook(forged)).status, 400);
    assert.equal((await hook("garbage")).status, 400);
    assert.equal((await call(app, "POST", "/v1/webhooks/apple", undefined, {})).status, 400);
  });
});
