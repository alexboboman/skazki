import { eq } from "drizzle-orm";
import { SUBSCRIPTION_PRODUCT_TIERS } from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { subscriptions, users } from "../db/schema.js";
import type { AppStoreVerifier, NotificationPayload, RenewalInfo, TransactionInfo } from "./appStore.js";

export type SubscriptionStatus = "active" | "grace_period" | "billing_retry" | "expired" | "revoked";

export class PurchasesUnavailableError extends Error {
  constructor() {
    super("APPLE_BUNDLE_ID is not configured.");
  }
}

const dateOrNull = (ms: number | undefined) => (typeof ms === "number" ? new Date(ms) : null);

const isUuid = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

/** Status of a subscription judged by its transaction alone. */
export function statusFromTransaction(tx: TransactionInfo, now: Date): SubscriptionStatus {
  if (tx.revocationDate) {
    return "revoked";
  }

  return tx.expiresDate && tx.expiresDate > now.getTime() ? "active" : "expired";
}

/**
 * Status after a Server Notification v2. Failed renewals keep access only while Apple's grace period runs;
 * after that (billing retry) the subscription counts as lapsed, as in the App Store.
 */
export function statusFromNotification(
  type: string,
  subtype: string | undefined,
  tx: TransactionInfo,
  now: Date
): SubscriptionStatus {
  switch (type) {
    case "REVOKE":
    case "REFUND":
      return "revoked";
    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      return "expired";
    case "DID_FAIL_TO_RENEW":
      return subtype === "GRACE_PERIOD" ? "grace_period" : "billing_retry";
    default:
      return statusFromTransaction(tx, now);
  }
}

export class SubscriptionService {
  /** `bundleId` is the app's bundle id (APPLE_BUNDLE_ID): a transaction of another app is never accepted. */
  constructor(
    private readonly db: Db,
    private readonly verifier: AppStoreVerifier,
    private readonly bundleId: string | undefined
  ) {}

  get available(): boolean {
    return Boolean(this.bundleId);
  }

  private verifyTransaction(jws: string): TransactionInfo {
    const tx = this.verifier.verify<TransactionInfo>(jws);

    if (tx.bundleId !== this.bundleId) {
      throw new Error("Transaction belongs to another app.");
    }

    if (tx.type !== undefined && tx.type !== "Auto-Renewable Subscription") {
      throw new Error("Not a subscription.");
    }

    if (!tx.originalTransactionId || !(tx.productId in SUBSCRIPTION_PRODUCT_TIERS)) {
      throw new Error("Unknown product.");
    }

    return tx;
  }

  /**
   * Binds the subscriptions in `transactions` (signed by Apple, sent by the app after a purchase or on restore)
   * to the user. A signed transaction can only come from a device signed in to the Apple ID that owns it, so it
   * is moved to the caller even when another account (a lost guest account) held it before.
   * Returns how many of the transactions were valid.
   */
  async sync(userId: string, transactions: string[], now = new Date()): Promise<number> {
    if (!this.bundleId) {
      throw new PurchasesUnavailableError();
    }

    let applied = 0;

    for (const jws of transactions) {
      let tx: TransactionInfo;

      try {
        tx = this.verifyTransaction(jws);
      } catch {
        continue;
      }

      applied++;
      await this.apply(tx, statusFromTransaction(tx, now), { userId, graceUntil: null, now });
    }

    return applied;
  }

  /** Handles one App Store Server Notification v2 (`signedPayload` from Apple's POST). */
  async handleNotification(signedPayload: string, now = new Date()): Promise<void> {
    if (!this.bundleId) {
      throw new PurchasesUnavailableError();
    }

    const notification = this.verifier.verify<NotificationPayload>(signedPayload);
    const signedTransaction = notification.data?.signedTransactionInfo;

    // TEST and notifications without a transaction (e.g. CONSUMPTION_REQUEST for other products) carry nothing to apply.
    if (!signedTransaction) {
      return;
    }

    const tx = this.verifyTransaction(signedTransaction);
    const renewal = notification.data?.signedRenewalInfo
      ? this.verifier.verify<RenewalInfo>(notification.data.signedRenewalInfo)
      : undefined;
    const status = statusFromNotification(notification.notificationType, notification.subtype, tx, now);

    await this.apply(tx, status, {
      graceUntil: status === "grace_period" ? dateOrNull(renewal?.gracePeriodExpiresDate) : null,
      signedAt: notification.signedDate ?? tx.signedDate,
      now
    });
  }

  private async apply(
    tx: TransactionInfo,
    status: SubscriptionStatus,
    opts: { userId?: string; graceUntil: Date | null; signedAt?: number; now: Date }
  ): Promise<void> {
    const [existing] = await this.db
      .select()
      .from(subscriptions)
      .where(eq(subscriptions.originalTransactionId, tx.originalTransactionId))
      .limit(1);

    const signedAt = dateOrNull(opts.signedAt ?? tx.signedDate);

    // A late, older event must not undo a newer one.
    if (existing?.lastSignedAt && signedAt && signedAt < existing.lastSignedAt) {
      if (opts.userId && existing.userId !== opts.userId) {
        await this.db.update(subscriptions).set({ userId: opts.userId, updatedAt: opts.now }).where(eq(subscriptions.id, existing.id));
      }
      return;
    }

    const tier = SUBSCRIPTION_PRODUCT_TIERS[tx.productId as keyof typeof SUBSCRIPTION_PRODUCT_TIERS];
    const values = {
      productId: tx.productId,
      tier,
      status,
      expiresAt: dateOrNull(tx.expiresDate),
      gracePeriodExpiresAt: opts.graceUntil,
      environment: tx.environment ?? null,
      lastSignedAt: signedAt,
      updatedAt: opts.now
    };

    if (existing) {
      await this.db
        .update(subscriptions)
        .set({ ...values, ...(opts.userId ? { userId: opts.userId } : {}) })
        .where(eq(subscriptions.id, existing.id));
      return;
    }

    // First time we hear of this subscription: the account is the caller, or the one named by appAccountToken.
    const userId = opts.userId ?? (await this.userForAccountToken(tx.appAccountToken));

    if (!userId) {
      console.warn(`Subscription ${tx.originalTransactionId} has no known account yet; the app will claim it on sync.`);
      return;
    }

    await this.db
      .insert(subscriptions)
      .values({ ...values, userId, originalTransactionId: tx.originalTransactionId })
      .onConflictDoNothing({ target: subscriptions.originalTransactionId });
  }

  /** The app passes the user's id as `appAccountToken` when buying, so Apple's notifications can be matched to the account. */
  private async userForAccountToken(token: string | undefined): Promise<string | undefined> {
    if (!isUuid(token)) {
      return undefined;
    }

    const [user] = await this.db.select({ id: users.id }).from(users).where(eq(users.id, token.toLowerCase())).limit(1);
    return user?.id;
  }
}
