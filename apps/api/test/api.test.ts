import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { before, describe, test } from "node:test";

process.env.AUTH_DEV_LOGIN = "1";
process.env.JWT_SECRET = "test-secret";
delete process.env.NODE_ENV;

const { createApp } = await import("../src/app.js");
const { PhygitalImageGenerator } = await import("../src/services/phygitalImageGenerator.js");
const { createImageGenerator } = await import("../src/services/imageGenerator.js");
const { runStoryPipeline } = await import("../src/services/storyPipeline.js");
const { createAuthService } = await import("../src/services/auth.js");
const { describeHero, wordsForMinutes, readingMinutes } = await import("../src/services/catalog.js");
const { createDb } = await import("../src/db/client.js");
const { MockImageGenerator } = await import("../src/services/imageGenerator.js");
const { LocalMediaStore } = await import("../src/services/mediaStore.js");
const { periodWindow, trialDaysFromEnv } = await import("../src/services/entitlements.js");
const { parseVerdict } = await import("../src/services/safetyChecker.js");
const { parseMediaMarkers } = await import("../src/services/mediaPrompts.js");

const RAW_STORY =
  "# Саша и дракончик\n\nЖил-был Саша.\n\n[IMAGE: boy and dragon]\n\nОни подружились.\n\n[IMAGE: stars]\n\nКонец.\n\n[MORAL: Дружба делает мир теплее.]\n[CLOSING: Спи сладко.]";

const profile = {
  name: "Саша",
  age: 5,
  language: "Русский",
  interests: ["динозавры"],
  worlds: ["forest"],
  favoriteCharacter: "Рекс"
};

const inlineBody = (format = "quick_story", extra: object = {}) => ({
  childProfile: { name: "Маша", age: 4, language: "Русский", interests: [], world: "море" },
  format,
  ...extra
});

// Knobs the tests flip to simulate model behaviour.
const behaviour = { textFails: false, verdicts: [] as Array<{ safe: boolean; reason?: string } | "throw"> };
let textCalls = 0;
let lastRequest: any;
const imagePrompts: string[] = [];

const textGenerator = {
  async generateStory(request: unknown) {
    textCalls++;
    lastRequest = request;
    if (behaviour.textFails) {
      throw new Error("anthropic down");
    }
    return { title: "Саша и дракончик", text: RAW_STORY, usage: { inputTokens: 10, outputTokens: 20, estimatedCostUsd: 0.001 } };
  }
};

const safetyChecker = {
  async check() {
    const next = behaviour.verdicts.shift() ?? { safe: true };
    if (next === "throw") {
      throw new Error("safety api down");
    }
    return next;
  }
};

const recordingImages = {
  provider: "mock",
  async generateImage(input: { prompt: string; quality: "standard" | "hd" }) {
    imagePrompts.push(input.prompt);
    return new MockImageGenerator().generateImage(input);
  }
};

let app: ReturnType<typeof createApp>;
let db: Awaited<ReturnType<typeof createDb>>;
let userCounter = 0;

before(async () => {
  db = await createDb({ dataDir: "memory://" });
  app = createApp({
    db,
    mediaStore: new LocalMediaStore(await mkdtemp(path.join(os.tmpdir(), "skazochnik-media-"))),
    imageGenerator: recordingImages,
    textGenerator,
    safetyChecker
  });
});

async function call(method: string, url: string, token?: string, body?: unknown) {
  const res = await app.request(url, {
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
  return { status: res.status, json, headers: res.headers };
}

async function newUser(tier?: "free" | "family" | "family_plus") {
  const { json } = await call("POST", "/v1/auth/dev", undefined, { name: `user${++userCounter}` });
  if (tier) {
    await call("PUT", "/v1/dev/subscription", json.token, { tier });
  }
  return json as { token: string; user: { id: string } };
}

function resetBehaviour() {
  behaviour.textFails = false;
  behaviour.verdicts = [];
}

describe("auth", () => {
  test("rejects missing and bad tokens", async () => {
    assert.equal((await call("GET", "/v1/profiles")).status, 401);
    assert.equal((await call("GET", "/v1/profiles", "garbage")).status, 401);
  });

  test("apple login without configuration is refused", async () => {
    assert.equal((await call("POST", "/v1/auth/apple", undefined, { identityToken: "x.y.z" })).status, 401);
    assert.equal((await call("POST", "/v1/auth/apple", undefined, {})).status, 400);
  });

  test("refresh gives a new working token for the same account and keeps its data", async () => {
    const guest = (await call("POST", "/v1/auth/anonymous")).json;
    await call("POST", "/v1/profiles", guest.token, profile);

    await new Promise((resolve) => setTimeout(resolve, 1100)); // the iat claim has one second resolution
    const refreshed = await call("POST", "/v1/auth/refresh", guest.token);
    assert.equal(refreshed.status, 200);
    assert.equal(refreshed.json.user.id, guest.user.id);
    assert.equal(refreshed.json.user.anonymous, true);
    assert.notEqual(refreshed.json.token, guest.token);

    assert.equal((await call("GET", "/v1/profiles", refreshed.json.token)).json.profiles.length, 1);
    assert.equal((await call("POST", "/v1/auth/refresh")).status, 401);
    assert.equal((await call("POST", "/v1/auth/refresh", "garbage")).status, 401);
  });

  test("tokens live for 90 days", async () => {
    const guest = (await call("POST", "/v1/auth/anonymous")).json;
    const payload = JSON.parse(Buffer.from(guest.token.split(".")[1], "base64url").toString());
    const days = (payload.exp - payload.iat) / 86400;
    assert.equal(days, 90);
  });

  test("dev login is stable per name", async () => {
    const a1 = (await call("POST", "/v1/auth/dev", undefined, { name: "stable" })).json;
    const a2 = (await call("POST", "/v1/auth/dev", undefined, { name: "stable" })).json;
    assert.equal(a1.user.id, a2.user.id);
  });
});

describe("profiles", () => {
  test("crud and isolation between users", async () => {
    const a = await newUser("family_plus");
    const b = await newUser();

    assert.equal((await call("POST", "/v1/profiles", a.token, { ...profile, age: 1 })).status, 400);

    const created = await call("POST", "/v1/profiles", a.token, profile);
    assert.equal(created.status, 201);
    const id = created.json.id;

    assert.equal((await call("GET", "/v1/profiles", a.token)).json.profiles.length, 1);
    assert.equal((await call("GET", `/v1/profiles/${id}`, b.token)).status, 404);
    assert.equal((await call("GET", "/v1/profiles/not-a-uuid", a.token)).status, 404);

    const updated = await call("PUT", `/v1/profiles/${id}`, a.token, { ...profile, name: "Саша2", favoriteCharacter: undefined });
    assert.equal(updated.json.name, "Саша2");
    assert.equal(updated.json.favoriteCharacter, undefined);

    assert.equal((await call("DELETE", `/v1/profiles/${id}`, a.token)).status, 204);
    assert.equal((await call("GET", `/v1/profiles/${id}`, a.token)).status, 404);
  });

  test("profile cap follows the tier and answers 402", async () => {
    const free = await newUser("free");
    assert.equal((await call("POST", "/v1/profiles", free.token, profile)).status, 201);
    const blocked = await call("POST", "/v1/profiles", free.token, profile);
    assert.equal(blocked.status, 402);
    assert.deepEqual(
      { code: blocked.json.error.code, feature: blocked.json.error.feature, tier: blocked.json.error.tier, limit: blocked.json.error.limit },
      { code: "limit_reached", feature: "profiles", tier: "free", limit: 1 }
    );

    const family = await newUser("family");
    for (let i = 0; i < 3; i++) {
      assert.equal((await call("POST", "/v1/profiles", family.token, profile)).status, 201);
    }
    assert.equal((await call("POST", "/v1/profiles", family.token, profile)).status, 402);

    const plus = await newUser("family_plus");
    for (let i = 0; i < 5; i++) {
      assert.equal((await call("POST", "/v1/profiles", plus.token, profile)).status, 201);
    }
    assert.equal((await call("POST", "/v1/profiles", plus.token, profile)).status, 402);
  });
});

describe("entitlements", () => {
  test("new users get a 7-day Family trial", async () => {
    const user = await newUser();
    const { json } = await call("GET", "/v1/entitlements", user.token);
    assert.equal(json.tier, "family");
    assert.equal(json.source, "trial");
    const days = (Date.parse(json.trialEndsAt) - Date.now()) / 86_400_000;
    assert.ok(days > 6.9 && days <= 7, `trial length ${days}`);
    assert.equal(json.limits.profiles.limit, 3);
  });

  test("snapshot reflects tier and usage", async () => {
    const user = await newUser("free");
    resetBehaviour();
    await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));

    const { json } = await call("GET", "/v1/entitlements", user.token);
    assert.equal(json.tier, "free");
    assert.equal(json.source, "free");
    assert.equal(json.limits.imageQuality, "standard");
    const quick = json.quotas.find((q: any) => q.feature === "quick_story");
    assert.deepEqual({ limit: quick.limit, used: quick.used, period: quick.period }, { limit: 3, used: 1, period: "week" });
  });

  test("TRIAL_DAYS: default 7, empty means unset, 0 starts on Free, ignored in production", () => {
    assert.equal(trialDaysFromEnv({}), 7);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "" }), 7);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "  " }), 7);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "0" }), 0);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "3" }), 3);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "abc" }), 7);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "-1" }), 7);
    assert.equal(trialDaysFromEnv({ TRIAL_DAYS: "0", NODE_ENV: "production" }), 7);
  });

  test("period windows are UTC day, Monday-based week and calendar month", () => {
    const wed = new Date("2026-10-28T15:30:00Z");
    assert.equal(periodWindow("day", wed).start.toISOString(), "2026-10-28T00:00:00.000Z");
    assert.equal(periodWindow("week", wed).start.toISOString(), "2026-10-26T00:00:00.000Z");
    assert.equal(periodWindow("week", wed).end.toISOString(), "2026-11-02T00:00:00.000Z");
    assert.equal(periodWindow("week", new Date("2026-11-01T23:59:00Z")).start.toISOString(), "2026-10-26T00:00:00.000Z");
    assert.equal(periodWindow("month", new Date("2026-12-31T23:00:00Z")).end.toISOString(), "2027-01-01T00:00:00.000Z");
  });
});

describe("story generation", () => {
  test("saves the story, strips markers and serves the library", async () => {
    resetBehaviour();
    const user = await newUser("family");
    const created = (await call("POST", "/v1/profiles", user.token, profile)).json;

    const gen = await call("POST", "/v1/stories/generate", user.token, {
      profileIds: [created.id],
      format: "quick_story",
      mediaOptions: { requestedTypes: ["image"], imageQuality: "hd" }
    });
    assert.equal(gen.status, 200);
    assert.equal(gen.json.media.length, 2);
    assert.equal(gen.json.media[0].variant, "hd");
    assert.deepEqual(
      gen.json.steps.map((s: any) => `${s.name}:${s.status}`),
      ["generate_text:succeeded", "safety_check:succeeded", "parse_media_prompts:succeeded", "generate_images:succeeded"]
    );

    const list = (await call("GET", "/v1/stories", user.token)).json.stories;
    assert.equal(list.length, 1);
    assert.ok(list[0].coverImageUrl.startsWith("/v1/media/"));
    assert.equal((await call("GET", `/v1/stories?profileId=${created.id}`, user.token)).json.stories.length, 1);
    assert.equal(gen.json.story.moral, "Дружба делает мир теплее.");
    assert.ok(gen.json.story.readingMinutes >= 1);
    assert.equal((await call("GET", "/v1/stories?profileId=abc", user.token)).status, 400);

    const full = (await call("GET", `/v1/stories/${gen.json.storyId}`, user.token)).json;
    assert.equal(full.parts[0].media.length, 2);
    assert.ok(!full.parts[0].text.includes("[IMAGE"));
    assert.ok(!full.parts[0].text.includes("# "), "the heading is not part of the body");
    assert.equal(full.title, "Саша и дракончик");
    assert.equal(full.moral, "Дружба делает мир теплее.");
    assert.equal(full.closing, "Спи сладко.");
    assert.equal(full.world, "forest");
    assert.deepEqual(full.heroIds, [created.id]);
    assert.equal(full.favorite, false);
    assert.equal(full.readProgress, 0);
    assert.deepEqual(gen.json.media.map((m: any) => m.afterParagraph), [1, 2]);

    const media = await call("GET", full.parts[0].media[0].url);
    assert.equal(media.status, 200);
    assert.equal(media.headers.get("content-type"), "image/svg+xml");
    assert.equal((await call("GET", "/v1/media/..%2F..%2Fpackage.json")).status, 404);

    const other = await newUser();
    assert.equal((await call("GET", `/v1/stories/${gen.json.storyId}`, other.token)).status, 404);

    assert.equal((await call("DELETE", `/v1/stories/${gen.json.storyId}`, user.token)).status, 204);
    assert.equal((await call("GET", `/v1/stories/${gen.json.storyId}`, user.token)).status, 404);
  });

  test("validates the body and foreign or malformed profile ids", async () => {
    const a = await newUser();
    const b = await newUser();
    const created = (await call("POST", "/v1/profiles", a.token, profile)).json;

    assert.equal((await call("POST", "/v1/stories/generate", a.token, { format: "quick_story" })).status, 400);
    assert.equal((await call("POST", "/v1/stories/generate", b.token, { profileIds: [created.id], format: "quick_story" })).status, 404);
    assert.equal((await call("POST", "/v1/stories/generate", a.token, { profileIds: ["abc"], format: "quick_story" })).status, 404);
    assert.equal((await call("POST", "/v1/stories/generate", a.token, { profileIds: [], format: "quick_story" })).status, 400);
  });

  test("free tier gets standard images even when hd is requested", async () => {
    resetBehaviour();
    const user = await newUser("free");
    const gen = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story", { mediaOptions: { requestedTypes: ["image"], imageQuality: "hd" } }));
    assert.equal(gen.status, 200);
    assert.equal(gen.json.media[0].variant, "standard");
  });
});

describe("quotas and paywall", () => {
  test("free: 3 quick stories per week, then 402 with reset time", async () => {
    resetBehaviour();
    const user = await newUser("free");
    for (let i = 0; i < 3; i++) {
      assert.equal((await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"))).status, 200);
    }
    const blocked = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));
    assert.equal(blocked.status, 402);
    assert.equal(blocked.json.error.code, "limit_reached");
    assert.equal(blocked.json.error.feature, "quick_story");
    assert.equal(blocked.json.error.limit, 3);
    assert.ok(Date.parse(blocked.json.error.resetsAt) > Date.now());

    // Reading is never blocked by the paywall.
    assert.equal((await call("GET", "/v1/stories", user.token)).json.stories.length, 3);
  });

  test("free: 1 classic story per day", async () => {
    resetBehaviour();
    const user = await newUser("free");
    assert.equal((await call("POST", "/v1/stories/generate", user.token, inlineBody("classic_story"))).status, 200);
    const blocked = await call("POST", "/v1/stories/generate", user.token, inlineBody("classic_story"));
    assert.equal(blocked.status, 402);
    assert.equal(blocked.json.error.feature, "classic_story");
  });

  test("story arcs need a paid tier", async () => {
    resetBehaviour();
    const free = await newUser("free");
    const blocked = await call("POST", "/v1/stories/generate", free.token, inlineBody("story_arc_part"));
    assert.equal(blocked.status, 402);
    assert.equal(blocked.json.error.code, "upgrade_required");
    assert.equal(blocked.json.error.feature, "story_arc");

    const family = await newUser("family");
    assert.equal((await call("POST", "/v1/stories/generate", family.token, inlineBody("story_arc_part"))).status, 200);
  });

  test("parallel requests cannot exceed the limit", async () => {
    resetBehaviour();
    const user = await newUser("free");
    const results = await Promise.all(
      Array.from({ length: 6 }, () => call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story")))
    );
    assert.equal(results.filter((r) => r.status === 200).length, 3);
    assert.equal(results.filter((r) => r.status === 402).length, 3);
  });

  test("a failed generation gives the quota back", async () => {
    const user = await newUser("free");
    const used = async () =>
      (await call("GET", "/v1/entitlements", user.token)).json.quotas.find((q: any) => q.feature === "quick_story").used;

    behaviour.textFails = true;
    const failed = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));
    assert.equal(failed.status, 502);
    assert.equal(await used(), 0);

    resetBehaviour();
    assert.equal((await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"))).status, 200);
    assert.equal(await used(), 1);
  });
});

describe("safety check", () => {
  test("an unsafe story is regenerated once and then served", async () => {
    resetBehaviour();
    behaviour.verdicts = [{ safe: false, reason: "страшная сцена" }];
    textCalls = 0;

    const user = await newUser("family");
    const gen = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));
    assert.equal(gen.status, 200);
    assert.equal(textCalls, 2);
    assert.deepEqual(
      gen.json.steps.map((s: any) => `${s.name}:${s.status}`).slice(0, 4),
      ["generate_text:succeeded", "safety_check:failed", "generate_text:succeeded", "safety_check:succeeded"]
    );
    assert.equal(gen.json.usage.inputTokens, 20);
  });

  test("two unsafe drafts in a row are rejected and the quota is refunded", async () => {
    resetBehaviour();
    behaviour.verdicts = [{ safe: false, reason: "a" }, { safe: false, reason: "b" }];

    const user = await newUser("free");
    const gen = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));
    assert.equal(gen.status, 422);
    assert.equal(gen.json.error.code, "story_rejected");

    const quota = (await call("GET", "/v1/entitlements", user.token)).json.quotas.find((q: any) => q.feature === "quick_story");
    assert.equal(quota.used, 0);
    assert.equal((await call("GET", "/v1/stories", user.token)).json.stories.length, 0);
  });

  test("a safety service outage fails closed", async () => {
    resetBehaviour();
    behaviour.verdicts = ["throw"];
    const user = await newUser("family");
    const gen = await call("POST", "/v1/stories/generate", user.token, inlineBody("quick_story"));
    assert.equal(gen.status, 502);
    assert.equal((await call("GET", "/v1/stories", user.token)).json.stories.length, 0);
  });

  test("verdict parsing fails closed", () => {
    assert.deepEqual(parseVerdict('{"safe": true}'), { safe: true });
    assert.deepEqual(parseVerdict('Вот ответ: {"safe": true, "reason": ""} спасибо'), { safe: true });
    assert.equal(parseVerdict('{"safe": false, "reason": "кровь"}').safe, false);
    assert.equal(parseVerdict('{"safe": "yes"}').safe, false);
    assert.equal(parseVerdict("не знаю").safe, false);
    assert.equal(parseVerdict("{broken").safe, false);
  });
});

describe("media markers", () => {
  test("splits title, body, moral, closing and cues", () => {
    const parsed = parseMediaMarkers(
      "# Title\n\nOne.\n\n[IMAGE: a]\n\nTwo.\n[AUDIO_CUE: calm]\n[ILLUSTRATION: b]\n\nEnd.\n\n[MORAL: Be kind.]\n[CLOSING: Sleep well.]"
    );
    assert.equal(parsed.title, "Title");
    assert.equal(parsed.text, "One.\n\nTwo.\n\nEnd.");
    assert.deepEqual(parsed.images, [
      { prompt: "a", afterParagraph: 1 },
      { prompt: "b", afterParagraph: 2 }
    ]);
    assert.deepEqual(parsed.audioCues, ["calm"]);
    assert.equal(parsed.moral, "Be kind.");
    assert.equal(parsed.closing, "Sleep well.");
  });

  test("text without heading or moral still parses", () => {
    const parsed = parseMediaMarkers("Once.\n\nTwice.");
    assert.equal(parsed.title, undefined);
    assert.equal(parsed.text, "Once.\n\nTwice.");
    assert.equal(parsed.moral, undefined);
  });
});

describe("anonymous accounts", () => {
  test("guest onboarding works without signing in and keeps the trial", async () => {
    resetBehaviour();
    const { status, json } = await call("POST", "/v1/auth/anonymous");
    assert.equal(status, 201);
    assert.equal(json.user.anonymous, true);

    const ent = (await call("GET", "/v1/entitlements", json.token)).json;
    assert.equal(ent.tier, "family");
    assert.equal(ent.source, "trial");

    const created = await call("POST", "/v1/profiles", json.token, profile);
    assert.equal(created.status, 201);
    const gen = await call("POST", "/v1/stories/generate", json.token, { profileIds: [created.json.id], format: "quick_story" });
    assert.equal(gen.status, 200);
  });

  test("linking Apple keeps the guest data, trial and id", async () => {
    resetBehaviour();
    const guest = (await call("POST", "/v1/auth/anonymous")).json;
    const created = (await call("POST", "/v1/profiles", guest.token, profile)).json;
    const auth = createAuthService(db);

    const linked = await auth.completeAppleLogin("apple-sub-link-1", "mama@example.com", guest.user.id);
    assert.equal(linked.user.id, guest.user.id);
    assert.equal(linked.user.anonymous, false);
    assert.equal(linked.user.email, "mama@example.com");

    // The old guest token still works, and so does signing in with Apple alone later.
    assert.equal((await call("GET", `/v1/profiles/${created.id}`, guest.token)).status, 200);
    const again = await auth.completeAppleLogin("apple-sub-link-1", undefined);
    assert.equal(again.user.id, guest.user.id);
  });

  test("an Apple ID that already has an account signs into it without merging the guest", async () => {
    const first = await createAuthService(db).completeAppleLogin("apple-sub-existing", undefined);
    const guest = (await call("POST", "/v1/auth/anonymous")).json;

    const result = await createAuthService(db).completeAppleLogin("apple-sub-existing", undefined, guest.user.id);
    assert.equal(result.user.id, first.user.id);
    assert.notEqual(result.user.id, guest.user.id);
  });

  test("a non-guest account cannot be re-linked to another Apple ID", async () => {
    const a = await createAuthService(db).completeAppleLogin("apple-sub-a", undefined);
    const b = await createAuthService(db).completeAppleLogin("apple-sub-b", undefined, a.user.id);
    assert.notEqual(b.user.id, a.user.id);
  });
});

describe("profile look and worlds", () => {
  const look = { skin: 1, hair: 3, hairStyle: "long", outfit: 0 };

  test("stores gender and appearance and normalises 'none'", async () => {
    const user = await newUser("family");
    const created = await call("POST", "/v1/profiles", user.token, { ...profile, gender: "girl", appearance: look });
    assert.equal(created.status, 201);
    assert.equal(created.json.gender, "girl");
    assert.deepEqual(created.json.appearance, look);

    const none = await call("POST", "/v1/profiles", user.token, { ...profile, gender: "none" });
    assert.equal(none.json.gender, undefined);
    assert.equal(none.json.appearance, undefined);
  });

  test("rejects unknown worlds and out-of-range looks", async () => {
    const user = await newUser("family");
    assert.equal((await call("POST", "/v1/profiles", user.token, { ...profile, worlds: ["волшебный лес"] })).status, 400);
    assert.equal((await call("POST", "/v1/profiles", user.token, { ...profile, gender: "robot" })).status, 400);
    assert.equal((await call("POST", "/v1/profiles", user.token, { ...profile, appearance: { ...look, skin: 9 } })).status, 400);
    assert.equal((await call("POST", "/v1/profiles", user.token, { ...profile, appearance: { ...look, hairStyle: "bald" } })).status, 400);
  });

  test("the hero's look is written into every illustration prompt", async () => {
    resetBehaviour();
    imagePrompts.length = 0;
    const user = await newUser("family");
    const hero = (await call("POST", "/v1/profiles", user.token, { ...profile, name: "Аня", gender: "girl", appearance: look })).json;

    await call("POST", "/v1/stories/generate", user.token, {
      profileIds: [hero.id],
      format: "quick_story",
      mediaOptions: { requestedTypes: ["image"] }
    });

    assert.equal(imagePrompts.length, 2);
    for (const prompt of imagePrompts) {
      assert.ok(prompt.includes("Аня, a 5-year-old girl with light skin, long blond hair, wearing a purple outfit"), prompt);
    }
  });

  test("describeHero without a look still names the hero", () => {
    assert.equal(describeHero({ name: "Миша", age: 3, language: "Русский", interests: [], world: "x" }), "Миша, a 3-year-old child");
  });
});

describe("story creation options", () => {
  test("topic, length, world override and several heroes reach the text generator", async () => {
    resetBehaviour();
    const user = await newUser("family_plus");
    const anya = (await call("POST", "/v1/profiles", user.token, { ...profile, name: "Аня", age: 5, worlds: ["ocean"] })).json;
    const misha = (await call("POST", "/v1/profiles", user.token, { ...profile, name: "Миша", age: 3, worlds: ["space"] })).json;

    const gen = await call("POST", "/v1/stories/generate", user.token, {
      profileIds: [anya.id, misha.id],
      format: "quick_story",
      topic: "Не страшно в темноте",
      lengthMinutes: 7,
      world: "castle"
    });
    assert.equal(gen.status, 200);
    assert.equal(lastRequest.wordCount, wordsForMinutes(7));
    assert.equal(lastRequest.topic, "Не страшно в темноте");
    assert.equal(lastRequest.childProfile.name, "Аня");
    assert.deepEqual(lastRequest.companions.map((c: any) => c.name), ["Миша"]);
    assert.ok(lastRequest.childProfile.world.includes("замк"));

    const story = (await call("GET", `/v1/stories/${gen.json.storyId}`, user.token)).json;
    assert.deepEqual(story.heroIds, [anya.id, misha.id]);
    assert.equal(story.world, "castle");

    // The story shows up in each hero's library.
    for (const hero of [anya, misha]) {
      assert.equal((await call("GET", `/v1/stories?profileId=${hero.id}`, user.token)).json.stories.length, 1);
    }
  });

  test("an explicit wordCount beats lengthMinutes, a profile's own world is the default", async () => {
    resetBehaviour();
    const user = await newUser("family");
    const hero = (await call("POST", "/v1/profiles", user.token, { ...profile, worlds: ["jungle"] })).json;
    await call("POST", "/v1/stories/generate", user.token, { profileIds: [hero.id], format: "quick_story", wordCount: 300, lengthMinutes: 12 });
    assert.equal(lastRequest.wordCount, 300);
    assert.ok(lastRequest.childProfile.world.includes("джунгли"));
  });

  test("validates the new options", async () => {
    const user = await newUser("family");
    const hero = (await call("POST", "/v1/profiles", user.token, profile)).json;
    const gen = (extra: object) => call("POST", "/v1/stories/generate", user.token, { profileIds: [hero.id], format: "quick_story", ...extra });

    assert.equal((await gen({ lengthMinutes: 5 })).status, 400);
    assert.equal((await gen({ world: "moon" })).status, 400);
    assert.equal((await gen({ topic: "x".repeat(301) })).status, 400);
    assert.equal((await call("POST", "/v1/stories/generate", user.token, { profileIds: [hero.id, hero.id], format: "quick_story" })).status, 400);
    assert.equal((await call("POST", "/v1/stories/generate", user.token, { profileIds: [hero.id, hero.id, hero.id, hero.id], format: "quick_story" })).status, 400);
  });

  test("lengths map to word counts and reading time", () => {
    assert.deepEqual([4, 7, 12].map((m) => wordsForMinutes(m as 4 | 7 | 12)), [450, 780, 1200]);
    assert.equal(readingMinutes("слово ".repeat(550)), 5);
    assert.equal(readingMinutes("слово"), 1);
  });
});

describe("library: favorites and reading progress", () => {
  test("favorite and progress can be updated and filtered", async () => {
    resetBehaviour();
    const user = await newUser("family");
    const a = (await call("POST", "/v1/stories/generate", user.token, inlineBody())).json.storyId;
    const b = (await call("POST", "/v1/stories/generate", user.token, inlineBody())).json.storyId;

    const patched = await call("PATCH", `/v1/stories/${a}`, user.token, { favorite: true, readProgress: 0.62 });
    assert.equal(patched.status, 200);
    assert.equal(patched.json.favorite, true);
    assert.equal(patched.json.readProgress, 0.62);

    const favorites = (await call("GET", "/v1/stories?favorite=true", user.token)).json.stories;
    assert.deepEqual(favorites.map((s: any) => s.id), [a]);
    assert.deepEqual((await call("GET", "/v1/stories?favorite=false", user.token)).json.stories.map((s: any) => s.id), [b]);

    assert.equal((await call("PATCH", `/v1/stories/${a}`, user.token, { readProgress: 1.5 })).status, 400);
    assert.equal((await call("PATCH", `/v1/stories/${a}`, user.token, { favorite: "yes" })).status, 400);
    assert.equal((await call("PATCH", `/v1/stories/${a}`, user.token, {})).status, 400);
    assert.equal((await call("GET", "/v1/stories?favorite=maybe", user.token)).status, 400);

    const stranger = await newUser();
    assert.equal((await call("PATCH", `/v1/stories/${a}`, stranger.token, { favorite: false })).status, 404);
    assert.equal((await call("PATCH", "/v1/stories/not-a-uuid", user.token, { favorite: false })).status, 404);
  });
});

describe("Phygital+ image provider", () => {
  const png = Buffer.from("89504e470d0a1a0a", "hex");

  function fakeFetch(script: Array<(url: string, init?: RequestInit) => Response>) {
    const calls: Array<{ url: string; init?: RequestInit }> = [];
    const fetchImpl = async (url: string, init?: RequestInit) => {
      calls.push({ url, init });
      const next = script.shift();
      assert.ok(next, `unexpected request: ${url}`);
      return next(url, init);
    };
    return { fetchImpl, calls };
  }

  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

  const make = (script: Array<(url: string, init?: RequestInit) => Response>, extra: object = {}) => {
    const { fetchImpl, calls } = fakeFetch(script);
    const generator = new PhygitalImageGenerator({ apiKey: "test-key", pollIntervalMs: 1, timeoutMs: 200, fetch: fetchImpl, ...extra });
    return { generator, calls };
  };

  test("creates a task, polls until done and downloads the image", async () => {
    const { generator, calls } = make([
      () => json(200, { task_id: 7, status_url: "/api/tasks/7" }),
      () => json(200, { task_id: 7, status: "running", outputs: null }),
      () => json(200, { task_id: 7, status: "done", outputs: [{ name: "image", links: ["https://files.example/i.png?sig=1"] }] }),
      () => new Response(png, { status: 200, headers: { "content-type": "image/png" } })
    ]);

    const image = await generator.generateImage({ prompt: "a fox", quality: "standard" });

    assert.deepEqual(image.bytes, png);
    assert.equal(image.contentType, "image/png");
    assert.equal(calls[0].url, "https://dev.phygital.plus/api/models/gemini-image");
    const headers = calls[0].init?.headers as Record<string, string>;
    assert.equal(headers["x-api-key"], "test-key");
    const body = JSON.parse(String(calls[0].init?.body));
    assert.equal(body.inputs.text_prompt, "a fox");
    assert.equal(body.params.model_name, "v3_1_lite");
    assert.equal(calls[1].url, "https://dev.phygital.plus/api/tasks/7");
    assert.equal(calls[3].url, "https://files.example/i.png?sig=1");
  });

  test("hd quality asks for the Pro model version", async () => {
    const { generator, calls } = make([
      () => json(200, { task_id: 8 }),
      () => json(200, { status: "done", outputs: [{ links: ["https://files.example/i.png"] }] }),
      () => new Response(png, { headers: { "content-type": "image/png" } })
    ]);
    await generator.generateImage({ prompt: "x", quality: "hd" });
    assert.equal(JSON.parse(String(calls[0].init?.body)).params.model_name, "v3");
  });

  test("failed tasks, rejected requests, empty results and timeouts become errors", async () => {
    await assert.rejects(
      make([() => json(200, { task_id: 1 }), () => json(200, { status: "failed", error_message: "content policy" })]).generator.generateImage({ prompt: "x", quality: "standard" }),
      /failed: content policy/
    );
    await assert.rejects(
      make([() => json(401, { detail: "bad key" })]).generator.generateImage({ prompt: "x", quality: "standard" }),
      /rejected the task \(HTTP 401\)/
    );
    await assert.rejects(
      make([() => json(200, { task_id: 2 }), () => json(200, { status: "done", outputs: [] })]).generator.generateImage({ prompt: "x", quality: "standard" }),
      /without an image/
    );
    const stuck = make([() => json(200, { task_id: 3 }), ...Array.from({ length: 500 }, () => () => json(200, { status: "running" }))], { timeoutMs: 30 });
    await assert.rejects(stuck.generator.generateImage({ prompt: "x", quality: "standard" }), /did not finish/);
  });

  test("a failed download is an error", async () => {
    await assert.rejects(
      make([
        () => json(200, { task_id: 4 }),
        () => json(200, { status: "done", outputs: [{ links: ["https://files.example/x.png"] }] }),
        () => new Response("nope", { status: 403 })
      ]).generator.generateImage({ prompt: "x", quality: "standard" }),
      /download failed with HTTP 403/
    );
  });

  test("the factory prefers Phygital+ when its key is set and honours IMAGE_PROVIDER", () => {
    assert.equal(createImageGenerator({ PHYGITAL_API_KEY: "k" }).provider, "phygital");
    assert.equal(createImageGenerator({ OPENAI_API_KEY: "k" }).provider, "openai");
    assert.equal(createImageGenerator({}).provider, "mock");
    assert.equal(createImageGenerator({ PHYGITAL_API_KEY: "k", IMAGE_PROVIDER: "mock" }).provider, "mock");
    assert.equal(createImageGenerator({ PHYGITAL_API_KEY: "k", IMAGE_PROVIDER: "" }).provider, "phygital");
    assert.throws(() => createImageGenerator({ IMAGE_PROVIDER: "phygital" }), /requires PHYGITAL_API_KEY/);
    assert.throws(() => createImageGenerator({ IMAGE_PROVIDER: "nope" }), /Unknown IMAGE_PROVIDER/);
  });
});

describe("pipeline images run side by side", () => {
  const request = {
    childProfile: { name: "Маша", age: 4, language: "Русский", interests: [], world: "лес" },
    format: "quick_story" as const,
    mediaOptions: { requestedTypes: ["image" as const] }
  };
  const store = { save: async () => ({ id: crypto.randomUUID(), url: "/v1/media/x.png" }), read: async () => undefined };

  test("pictures overlap in time and keep the order of their markers", async () => {
    let running = 0;
    let peak = 0;
    const generator = {
      provider: "slow",
      async generateImage(input: { prompt: string }) {
        running++;
        peak = Math.max(peak, running);
        await new Promise((resolve) => setTimeout(resolve, input.prompt.includes("boy and dragon") ? 60 : 10));
        running--;
        return { bytes: Buffer.from("x"), contentType: "image/png", estimatedCostUsd: 0.5 };
      }
    };

    const result = await runStoryPipeline(request, { textGenerator, safetyChecker, imageGenerator: generator, mediaStore: store });
    assert.equal(peak, 2);
    assert.deepEqual(result.media.map((m) => m.afterParagraph), [1, 2]);
    assert.ok(result.media[0].prompt.includes("boy and dragon"), "the slow first picture still comes first");
    assert.equal(result.usage.estimatedCostUsd, 0.001 + 1);
  });

  test("one failed picture does not drop the others", async () => {
    const generator = {
      provider: "flaky",
      async generateImage(input: { prompt: string }) {
        if (input.prompt.includes("stars")) throw new Error("provider hiccup");
        return { bytes: Buffer.from("x"), contentType: "image/png", estimatedCostUsd: 0 };
      }
    };
    const result = await runStoryPipeline(request, { textGenerator, safetyChecker, imageGenerator: generator, mediaStore: store });
    assert.equal(result.media.length, 1);
    const step = result.steps.find((s) => s.name === "generate_images");
    assert.equal(step?.status, "failed");
    assert.match(step?.error ?? "", /provider hiccup/);
  });
});
