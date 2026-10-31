import { and, eq, gt, inArray, or, sql } from "drizzle-orm";
import type {
  EntitlementsResponse,
  QuotaFeature,
  QuotaPeriod,
  QuotaStatus,
  StoryFormat,
  Tier
} from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { childProfiles, stories, storyArcs, subscriptions, usageCounters, users } from "../db/schema.js";

/** Length of the Family trial for new accounts. `TRIAL_DAYS=0` (dev) makes new accounts start on Free to try the limits. */
export const TRIAL_DAYS = trialDaysFromEnv(process.env);

export function trialDaysFromEnv(env: NodeJS.ProcessEnv): number {
  const raw = env.TRIAL_DAYS?.trim();
  const value = Number(raw);
  // An empty value (as in .env.example) means "not set", not zero days.
  return env.NODE_ENV !== "production" && raw && Number.isFinite(value) && value >= 0 ? value : 7;
}

interface Quota {
  limit: number;
  period: QuotaPeriod;
}

interface TierConfig {
  profiles: number;
  activeArcs: number;
  imageQuality: "standard" | "hd";
  /** Neural narration voice (the system voice on the device is free for everyone). */
  premiumVoice: boolean;
  quotas: Record<QuotaFeature, Quota>;
}

/**
 * Entitlement matrix from the PRD (section 4.2). "Unlimited, fair use" becomes a generous
 * monthly cap. Lives in code for now; moves to remote config so limits change without a release.
 */
export const TIERS: Record<Tier, TierConfig> = {
  free: {
    profiles: 1,
    activeArcs: 0,
    imageQuality: "standard",
    premiumVoice: false,
    quotas: { classic_story: { limit: 1, period: "day" }, quick_story: { limit: 3, period: "week" } }
  },
  family: {
    profiles: 3,
    activeArcs: 1,
    imageQuality: "hd",
    premiumVoice: false,
    quotas: { classic_story: { limit: 100, period: "month" }, quick_story: { limit: 100, period: "month" } }
  },
  family_plus: {
    profiles: 5,
    activeArcs: 3,
    imageQuality: "hd",
    premiumVoice: true,
    quotas: { classic_story: { limit: 100, period: "month" }, quick_story: { limit: 100, period: "month" } }
  }
};

const TIER_RANK: Record<Tier, number> = { free: 0, family: 1, family_plus: 2 };
const ACTIVE_STATUSES = ["active", "grace_period", "billing_retry"];

/** Series parts have no quota of their own: the tier gates them, and `activeArcs` caps unfinished series. */
const FORMAT_FEATURE: Partial<Record<StoryFormat, QuotaFeature>> = {
  classic_story: "classic_story",
  quick_story: "quick_story"
};

export type ReserveResult =
  | { ok: true; feature?: QuotaFeature; periodStart?: Date }
  | { ok: false; reason: "upgrade_required" | "limit_reached"; feature: string; tier: Tier; limit?: number; resetsAt?: Date };

export interface ResolvedTier {
  tier: Tier;
  source: "subscription" | "trial" | "free";
  trialEndsAt?: Date;
}

export class EntitlementService {
  constructor(private readonly db: Db) {}

  async resolveTier(userId: string, now = new Date()): Promise<ResolvedTier> {
    const subs = await this.db
      .select({ tier: subscriptions.tier })
      .from(subscriptions)
      .where(
        and(
          eq(subscriptions.userId, userId),
          inArray(subscriptions.status, ACTIVE_STATUSES),
          or(gt(subscriptions.expiresAt, now), gt(subscriptions.gracePeriodExpiresAt, now))
        )
      );

    const best = subs
      .map((row) => row.tier as Tier)
      .filter((tier) => tier in TIERS)
      .sort((a, b) => TIER_RANK[b] - TIER_RANK[a])[0];

    if (best) {
      return { tier: best, source: "subscription" };
    }

    const [user] = await this.db.select({ trialEndsAt: users.trialEndsAt }).from(users).where(eq(users.id, userId)).limit(1);

    if (user?.trialEndsAt && user.trialEndsAt > now) {
      return { tier: "family", source: "trial", trialEndsAt: user.trialEndsAt };
    }

    return { tier: "free", source: "free" };
  }

  async snapshot(userId: string, now = new Date()): Promise<EntitlementsResponse> {
    const resolved = await this.resolveTier(userId, now);
    const config = TIERS[resolved.tier];

    const [{ used: profilesUsed }] = await this.db
      .select({ used: sql<number>`count(*)::int` })
      .from(childProfiles)
      .where(eq(childProfiles.userId, userId));

    const [{ activeArcs }] = await this.db
      .select({ activeArcs: sql<number>`count(*)::int` })
      .from(storyArcs)
      .innerJoin(stories, eq(stories.id, storyArcs.storyId))
      .where(and(eq(stories.userId, userId), eq(storyArcs.status, "active")));

    const quotas: QuotaStatus[] = [];

    for (const feature of Object.keys(config.quotas) as QuotaFeature[]) {
      const quota = config.quotas[feature];
      const window = periodWindow(quota.period, now);
      const [row] = await this.db
        .select({ count: usageCounters.count })
        .from(usageCounters)
        .where(
          and(
            eq(usageCounters.userId, userId),
            eq(usageCounters.featureKey, feature),
            eq(usageCounters.periodStart, window.start)
          )
        )
        .limit(1);

      quotas.push({
        feature,
        period: quota.period,
        limit: quota.limit,
        used: row?.count ?? 0,
        resetsAt: window.end.toISOString()
      });
    }

    return {
      tier: resolved.tier,
      source: resolved.source,
      trialEndsAt: resolved.trialEndsAt?.toISOString(),
      limits: {
        profiles: { limit: config.profiles, used: profilesUsed },
        activeArcs: config.activeArcs,
        activeArcsUsed: activeArcs,
        imageQuality: config.imageQuality,
        premiumVoice: config.premiumVoice
      },
      quotas
    };
  }

  async profileLimit(userId: string): Promise<{ tier: Tier; limit: number }> {
    const { tier } = await this.resolveTier(userId);
    return { tier, limit: TIERS[tier].profiles };
  }

  async maxImageQuality(userId: string): Promise<"standard" | "hd"> {
    const { tier } = await this.resolveTier(userId);
    return TIERS[tier].imageQuality;
  }

  /**
   * Checks the tier allows this format and atomically takes one unit of its quota.
   * Call `refund` if the generation then fails, so errors do not eat the user's quota.
   */
  async reserve(userId: string, format: StoryFormat, now = new Date()): Promise<ReserveResult> {
    const { tier } = await this.resolveTier(userId, now);
    const config = TIERS[tier];

    if (format === "story_arc_part") {
      return config.activeArcs > 0
        ? { ok: true }
        : { ok: false, reason: "upgrade_required", feature: "story_arc", tier };
    }

    const feature = FORMAT_FEATURE[format] as QuotaFeature;
    const quota = config.quotas[feature];
    const window = periodWindow(quota.period, now);

    const rows = await this.db
      .insert(usageCounters)
      .values({
        userId,
        featureKey: feature,
        periodStart: window.start,
        periodEnd: window.end,
        count: 1,
        limitValue: quota.limit
      })
      .onConflictDoUpdate({
        target: [usageCounters.userId, usageCounters.featureKey, usageCounters.periodStart],
        set: { count: sql`${usageCounters.count} + 1`, limitValue: quota.limit },
        setWhere: sql`${usageCounters.count} < ${quota.limit}`
      })
      .returning({ id: usageCounters.id });

    if (rows.length === 0) {
      return { ok: false, reason: "limit_reached", feature, tier, limit: quota.limit, resetsAt: window.end };
    }

    return { ok: true, feature, periodStart: window.start };
  }

  /** Whether the user may start one more series: the tier must allow series and fewer than `activeArcs` may be unfinished. */
  async canStartArc(userId: string, activeArcs: number, now = new Date()): Promise<ReserveResult> {
    const { tier } = await this.resolveTier(userId, now);
    const limit = TIERS[tier].activeArcs;

    if (limit === 0) {
      return { ok: false, reason: "upgrade_required", feature: "story_arc", tier };
    }

    return activeArcs >= limit ? { ok: false, reason: "limit_reached", feature: "story_arc", tier, limit } : { ok: true };
  }

  /** Premium narration is a Family+ feature. */
  async canUsePremiumVoice(userId: string, now = new Date()): Promise<ReserveResult> {
    const { tier } = await this.resolveTier(userId, now);
    return TIERS[tier].premiumVoice ? { ok: true } : { ok: false, reason: "upgrade_required", feature: "premium_voice", tier };
  }

  async refund(userId: string, reservation: { feature?: QuotaFeature; periodStart?: Date }): Promise<void> {
    if (!reservation.feature || !reservation.periodStart) {
      return;
    }

    await this.db
      .update(usageCounters)
      .set({ count: sql`greatest(${usageCounters.count} - 1, 0)` })
      .where(
        and(
          eq(usageCounters.userId, userId),
          eq(usageCounters.featureKey, reservation.feature),
          eq(usageCounters.periodStart, reservation.periodStart)
        )
      );
  }

  /** Dev only: replaces the user's subscription with `tier` and ends the trial. `free` just removes both. */
  async devSetTier(userId: string, tier: Tier): Promise<void> {
    await this.db.delete(subscriptions).where(eq(subscriptions.userId, userId));
    await this.db.update(users).set({ trialEndsAt: null, updatedAt: new Date() }).where(eq(users.id, userId));

    if (tier !== "free") {
      await this.db.insert(subscriptions).values({
        userId,
        productId: `dev.${tier}`,
        tier,
        status: "active",
        expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000)
      });
    }
  }
}

/** UTC windows: day, ISO week (Monday start) and calendar month. */
export function periodWindow(period: QuotaPeriod, now: Date): { start: Date; end: Date } {
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth();
  const d = now.getUTCDate();

  if (period === "day") {
    return { start: new Date(Date.UTC(y, m, d)), end: new Date(Date.UTC(y, m, d + 1)) };
  }

  if (period === "week") {
    const sinceMonday = (now.getUTCDay() + 6) % 7;
    return { start: new Date(Date.UTC(y, m, d - sinceMonday)), end: new Date(Date.UTC(y, m, d - sinceMonday + 7)) };
  }

  return { start: new Date(Date.UTC(y, m, 1)), end: new Date(Date.UTC(y, m + 1, 1)) };
}
