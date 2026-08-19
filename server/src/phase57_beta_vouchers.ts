/**
 * Crownspire Vouchers — authenticated-account currency (wallet + spend)
 * plus entitlement-gated voucher CODE redemption / beta testing RPCs.
 *
 * DESIGN AUTHORITY: docs/CROWNSPIRE_SHOP_MONETIZATION_PRODUCTION_BIBLE.md
 * LIVE PRODUCT AUTHORITY: data/commerce_products.json + COMMERCE_PRODUCT_CATALOG
 *
 * Wallet visibility and voucher spend are available to any authenticated account.
 * `entitlement_beta_voucher_testing` gates ONLY:
 *   - crownspire_commerce_redeem_voucher_code
 *   - beta Top-Up RPCs
 * It does NOT gate owning, seeing, or spending Vouchers.
 *
 * Storage names still use `beta_*` until a later migration.
 * Wallet key remains `crownspire_commerce / beta_voucher_wallet`. Do not rename.
 *
 * Spend idempotency contract:
 *   Client sends opaque `idempotency_key` (UUID v4 recommended).
 *   Retries of the same logical purchase MUST reuse that key.
 *   A new user-initiated purchase MUST use a new key.
 *   Server identity is (account_id, product_id, idempotency_key) → one ledger tx.
 *   Duplicate key returns the existing DELIVERED result (no second spend/grant).
 *   Concurrent/rapid requests for the same product with a different key while a
 *   spend is in-flight or inside the short linger window return
 *   voucher_purchase_in_progress (no second charge).
 *   Do not use wall-clock seconds as the sole identity.
 *
 * - Zero cash value. Never revenue. Never GOOGLE_PLAY.
 * - BETA_VOUCHER rows live in a separate ledger, not crownspire_purchase_ledger.
 * - Production Top-Up is never advanced by voucher purchases.
 * - Proposed economy (Diamond ladder, Growth Fund, Monthly Card, 2k–1.5M ladder) is NOT live.
 */

const BETA_VOUCHER_WALLET_KEY = "beta_voucher_wallet";
const BETA_VOUCHER_LEDGER_COLLECTION = "crownspire_beta_voucher_ledger";
const BETA_VOUCHER_LEDGER_INDEX_KEY = "beta_voucher_ledger_index";
const BETA_VOUCHER_SPEND_INFLIGHT_KEY = "beta_voucher_spend_inflight";
const BETA_VOUCHER_CODE_COLLECTION = "crownspire_beta_voucher_codes";
const BETA_VOUCHER_REDEEM_COLLECTION = "crownspire_beta_voucher_redemptions";
const BETA_TOPUP_COLLECTION = "crownspire_beta_topup";
const PROD_TOPUP_COLLECTION = "crownspire_prod_topup";
const COMMERCE_AUDIT_COLLECTION = "crownspire_commerce_audit";
const ENTITLEMENT_BETA_VOUCHER_TESTING = "entitlement_beta_voucher_testing";
const VOUCHER_SPEND_INFLIGHT_TTL_SEC = 30;
const VOUCHER_SPEND_DOUBLE_TAP_LINGER_SEC = 5;

const BETA_TOPUP_TEST_ROUND_ID = "topup_beta_round_test_001";
const BETA_TOPUP_KIND = "BETA";
const PROD_TOPUP_KIND = "PRODUCTION";

interface BetaVoucherWalletRef {
  type: string;
  amount: number;
  ts: number;
  code_id?: string;
  product_id?: string;
  reason?: string;
}

interface BetaVoucherWalletRecord {
  account_id: string;
  balance: number;
  processed_refs: { [ref: string]: BetaVoucherWalletRef };
  updated_at: number;
}

interface BetaVoucherCodeDef {
  code_id: string;
  code_string: string;
  voucher_grant_amount: number;
  allocation_cohort: string;
  is_single_use: boolean;
  max_global_redemptions: number;
  per_account_limit: number;
  is_active: boolean;
  expires_at_utc: number;
  test_only: boolean;
}

interface BetaVoucherCodeStats {
  code_id: string;
  current_global_redemptions: number;
  updated_at: number;
}

interface BetaVoucherRedemptionRecord {
  account_id: string;
  code_id: string;
  code_string: string;
  count: number;
  last_amount: number;
  last_cohort: string;
  updated_at: number;
}

interface BetaVoucherLedgerRecord {
  account_id: string;
  purchase_source: string;
  product_id: string;
  platform: string;
  platform_transaction_id: string;
  voucher_cost: number;
  qualifying_topup_diamonds: number;
  delivery_status: string;
  delivery_transaction_id: string;
  rewards_granted: any[];
  created_at: number;
  updated_at: number;
}

interface VoucherSpendInflightLock {
  idempotency_key: string;
  tx_id: string;
  started_at: number;
  expires_at: number;
}

interface VoucherSpendInflightRecord {
  account_id: string;
  locks: { [productId: string]: VoucherSpendInflightLock };
  updated_at: number;
}

interface TopUpMilestoneDef {
  milestone_id: string;
  threshold: number;
  reward_diamonds: number;
  test_only: boolean;
}

interface TopUpRoundDef {
  round_id: string;
  kind: string;
  test_only: boolean;
  start_utc: number;
  end_utc: number;
  milestones: TopUpMilestoneDef[];
}

interface TopUpProgressRecord {
  account_id: string;
  round_id: string;
  kind: string;
  progress: number;
  claimed: { [milestoneId: string]: { claimed_at: number; reward_diamonds: number; grant_ref: string } };
  applied_refs: { [ref: string]: { amount: number; ts: number; product_id: string } };
  history: any[];
  updated_at: number;
}

const TEST_ONLY_VOUCHER_CODES: BetaVoucherCodeDef[] = [
  {
    code_id: "code_test_voucher_5",
    code_string: "CROWNSPIRE-TEST-VOUCHER-5",
    voucher_grant_amount: 5,
    allocation_cohort: "TEST_ONLY_LOW",
    is_single_use: false,
    max_global_redemptions: 0,
    per_account_limit: 1,
    is_active: true,
    expires_at_utc: 0,
    test_only: true,
  },
  {
    code_id: "code_test_voucher_100",
    code_string: "CROWNSPIRE-TEST-VOUCHER-100",
    voucher_grant_amount: 100,
    allocation_cohort: "TEST_ONLY_MID",
    is_single_use: false,
    max_global_redemptions: 0,
    per_account_limit: 1,
    is_active: true,
    expires_at_utc: 0,
    test_only: true,
  },
  {
    code_id: "code_test_voucher_expired",
    code_string: "CROWNSPIRE-TEST-VOUCHER-EXPIRED",
    voucher_grant_amount: 5,
    allocation_cohort: "TEST_ONLY",
    is_single_use: false,
    max_global_redemptions: 0,
    per_account_limit: 1,
    is_active: true,
    expires_at_utc: 1,
    test_only: true,
  },
  {
    code_id: "code_test_voucher_inactive",
    code_string: "CROWNSPIRE-TEST-VOUCHER-INACTIVE",
    voucher_grant_amount: 5,
    allocation_cohort: "TEST_ONLY",
    is_single_use: false,
    max_global_redemptions: 0,
    per_account_limit: 1,
    is_active: false,
    expires_at_utc: 0,
    test_only: true,
  },
  {
    code_id: "code_test_voucher_cap1",
    code_string: "CROWNSPIRE-TEST-VOUCHER-CAP1",
    voucher_grant_amount: 5,
    allocation_cohort: "TEST_ONLY",
    is_single_use: false,
    max_global_redemptions: 1,
    per_account_limit: 1,
    is_active: true,
    expires_at_utc: 0,
    test_only: true,
  },
];

const TEST_ONLY_BETA_TOPUP_ROUNDS: { [id: string]: TopUpRoundDef } = {
  topup_beta_round_test_001: {
    round_id: "topup_beta_round_test_001",
    kind: BETA_TOPUP_KIND,
    test_only: true,
    start_utc: 0,
    end_utc: 4102444800,
    milestones: [
      { milestone_id: "beta_m_100", threshold: 100, reward_diamonds: 1, test_only: true },
      { milestone_id: "beta_m_500", threshold: 500, reward_diamonds: 2, test_only: true },
      { milestone_id: "beta_m_1000", threshold: 1000, reward_diamonds: 3, test_only: true },
    ],
  },
  topup_beta_round_test_002: {
    round_id: "topup_beta_round_test_002",
    kind: BETA_TOPUP_KIND,
    test_only: true,
    start_utc: 0,
    end_utc: 4102444800,
    milestones: [
      { milestone_id: "beta_m2_100", threshold: 100, reward_diamonds: 1, test_only: true },
    ],
  },
};

function normalizeVoucherCode(raw: string): string {
  return String(raw || "").trim().toUpperCase();
}

function runtimeContextName(env?: { [key: string]: string }): string {
  return String((env || {})["CROWNSPIRE_RUNTIME_CONTEXT"] || "").trim().toLowerCase();
}

function isExplicitLocalOrTestRuntime(env?: { [key: string]: string }): boolean {
  const ctx = runtimeContextName(env);
  return ctx === "local" || ctx === "test";
}

/** Local/headless only. Never sufficient on production Nakama. */
function isSafeDevVoucherBypass(env?: { [key: string]: string }): boolean {
  const e = env || {};
  if (String(e["CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC"] || "") !== "true") {
    return false;
  }
  return isExplicitLocalOrTestRuntime(e);
}

/** Hardcoded TEST_ONLY fixture codes. Off unless an explicit local/test code mode is set. */
function areFixtureTestCodesEnabled(env?: { [key: string]: string }): boolean {
  const e = env || {};
  if (String(e["CROWNSPIRE_ENABLE_BETA_VOUCHER_TEST_CODES"] || "") !== "true") {
    return false;
  }
  return isExplicitLocalOrTestRuntime(e);
}

function hasBetaVoucherTestingEntitlement(nk: nkruntime.Nakama, accountId: string): boolean {
  return StorageEntitlementProvider.isActive(nk, accountId, ENTITLEMENT_BETA_VOUCHER_TESTING);
}

function isBetaVoucherTestingEnabled(nk: nkruntime.Nakama, accountId: string, env?: { [key: string]: string }): boolean {
  if (hasBetaVoucherTestingEntitlement(nk, accountId)) {
    return true;
  }
  return isSafeDevVoucherBypass(env);
}

function lookupFixtureVoucherCode(code: string): BetaVoucherCodeDef | null {
  const norm = normalizeVoucherCode(code);
  for (let i = 0; i < TEST_ONLY_VOUCHER_CODES.length; i++) {
    if (normalizeVoucherCode(TEST_ONLY_VOUCHER_CODES[i].code_string) === norm) {
      return TEST_ONLY_VOUCHER_CODES[i];
    }
  }
  return null;
}

function lookupStoredVoucherCode(nk: nkruntime.Nakama, code: string): BetaVoucherCodeDef | null {
  const norm = normalizeVoucherCode(code);
  if (!norm) {
    return null;
  }
  const obj = storageReadOne(nk, BETA_VOUCHER_CODE_COLLECTION, norm, SYSTEM_USER);
  if (!obj || !obj.value) {
    return null;
  }
  const raw = obj.value as any;
  if (raw.test_only) {
    return null;
  }
  const amount = Math.floor(Number(raw.voucher_grant_amount || 0));
  if (amount <= 0 || !raw.code_string) {
    return null;
  }
  return {
    code_id: String(raw.code_id || norm),
    code_string: String(raw.code_string),
    voucher_grant_amount: amount,
    allocation_cohort: String(raw.allocation_cohort || ""),
    is_single_use: !!raw.is_single_use,
    max_global_redemptions: Math.max(0, Math.floor(Number(raw.max_global_redemptions || 0))),
    per_account_limit: Math.max(1, Math.floor(Number(raw.per_account_limit || 1))),
    is_active: raw.is_active !== false,
    expires_at_utc: Math.max(0, Math.floor(Number(raw.expires_at_utc || 0))),
    test_only: false,
  };
}

function lookupRedeemableVoucherCode(nk: nkruntime.Nakama, code: string, env?: { [key: string]: string }): BetaVoucherCodeDef | null {
  const stored = lookupStoredVoucherCode(nk, code);
  if (stored) {
    return stored;
  }
  if (!areFixtureTestCodesEnabled(env)) {
    return null;
  }
  return lookupFixtureVoucherCode(code);
}

function emptyVoucherWallet(accountId: string): BetaVoucherWalletRecord {
  return {
    account_id: accountId,
    balance: 0,
    processed_refs: {},
    updated_at: nowUnix(),
  };
}

function normalizeVoucherWallet(rec: BetaVoucherWalletRecord, accountId: string): BetaVoucherWalletRecord {
  if (!rec.processed_refs) {
    rec.processed_refs = {};
  }
  rec.account_id = accountId;
  rec.balance = Math.max(0, Math.floor(Number(rec.balance || 0)));
  return rec;
}

function readVoucherWalletObj(nk: nkruntime.Nakama, accountId: string): { value: BetaVoucherWalletRecord; version: string } {
  const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, BETA_VOUCHER_WALLET_KEY, accountId);
  if (obj && obj.value) {
    return { value: normalizeVoucherWallet(obj.value as BetaVoucherWalletRecord, accountId), version: obj.version };
  }
  return { value: emptyVoucherWallet(accountId), version: "*" };
}

function mutateVoucherWallet(
  nk: nkruntime.Nakama,
  accountId: string,
  ref: string,
  type: string,
  amount: number,
  extra: { code_id?: string; product_id?: string; reason?: string }
): { ok: boolean; already: boolean; balance: number; before: number; error?: string } {
  const amt = Math.floor(Number(amount || 0));
  const key = String(ref || "").trim();
  if (!accountId || !key || amt < 0) {
    return { ok: false, already: false, balance: 0, before: 0, error: "Invalid voucher mutation" };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readVoucherWalletObj(nk, accountId);
    const rec = obj.value;
    const prev = rec.processed_refs[key];
    if (prev) {
      return { ok: true, already: true, balance: rec.balance, before: rec.balance };
    }
    const before = rec.balance;
    if (type === "spend") {
      if (rec.balance < amt) {
        return { ok: false, already: false, balance: rec.balance, before: rec.balance, error: "Insufficient vouchers" };
      }
      rec.balance = rec.balance - amt;
    } else if (type === "grant" || type === "reversal") {
      rec.balance = rec.balance + amt;
    } else {
      return { ok: false, already: false, balance: rec.balance, before: rec.balance, error: "Unknown voucher mutation" };
    }
    rec.processed_refs[key] = {
      type: type,
      amount: amt,
      ts: nowUnix(),
      code_id: extra.code_id,
      product_id: extra.product_id,
      reason: extra.reason,
    };
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, BETA_VOUCHER_WALLET_KEY, accountId, rec, obj.version, 0);
      return { ok: true, already: false, balance: rec.balance, before: before };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, already: false, balance: 0, before: 0, error: "Voucher wallet conflict" };
}

function normalizeVoucherSpendIdempotencyKey(raw: string): { ok: boolean; key?: string; error?: string } {
  const key = String(raw || "").trim();
  if (!key) {
    return { ok: false, error: "idempotency_key_required" };
  }
  if (key.length > 128) {
    return { ok: false, error: "idempotency_key_invalid" };
  }
  if (!/^[A-Za-z0-9._-]+$/.test(key)) {
    return { ok: false, error: "idempotency_key_invalid" };
  }
  return { ok: true, key: key };
}

function voucherSpendTxId(accountId: string, productId: string, idempotencyKey: string): string {
  return "bv_" + ledgerStorageKey("beta_voucher", accountId + "_" + productId + "_" + idempotencyKey);
}

function listVoucherPurchasableOffers(): any[] {
  const offers: any[] = [];
  for (let i = 0; i < COMMERCE_PRODUCT_CATALOG.length; i++) {
    const p = COMMERCE_PRODUCT_CATALOG[i];
    if (!p.beta_voucher_purchasable || !p.production_deliverable) {
      continue;
    }
    if (productGrantsVouchers(p)) {
      continue;
    }
    offers.push({
      product_id: p.product_id,
      iap_product_id: p.iap_product_id,
      voucher_cost: Math.max(0, Math.floor(Number(p.beta_voucher_cost || 0))),
      diamond_amount: p.diamond_amount,
      qualifying_topup_diamonds: Math.max(0, Math.floor(Number(p.qualifying_topup_diamonds || 0))),
    });
  }
  return offers;
}

function readVoucherSpendInflightObj(
  nk: nkruntime.Nakama,
  accountId: string
): { value: VoucherSpendInflightRecord; version: string } {
  const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, BETA_VOUCHER_SPEND_INFLIGHT_KEY, accountId);
  if (obj && obj.value) {
    const rec = obj.value as VoucherSpendInflightRecord;
    if (!rec.locks) {
      rec.locks = {};
    }
    rec.account_id = accountId;
    return { value: rec, version: obj.version };
  }
  return {
    value: { account_id: accountId, locks: {}, updated_at: nowUnix() },
    version: "*",
  };
}

function acquireVoucherSpendInflight(
  nk: nkruntime.Nakama,
  accountId: string,
  productId: string,
  idempotencyKey: string,
  txId: string
): { ok: boolean; error?: string } {
  for (let attempt = 0; attempt < 8; attempt++) {
    const now = nowUnix();
    const obj = readVoucherSpendInflightObj(nk, accountId);
    const rec = obj.value;
    const existing = rec.locks[productId];
    if (existing && existing.expires_at > now && existing.idempotency_key !== idempotencyKey) {
      return { ok: false, error: "voucher_purchase_in_progress" };
    }
    rec.locks[productId] = {
      idempotency_key: idempotencyKey,
      tx_id: txId,
      started_at: existing && existing.idempotency_key === idempotencyKey ? existing.started_at : now,
      expires_at: now + VOUCHER_SPEND_INFLIGHT_TTL_SEC,
    };
    rec.updated_at = now;
    try {
      storageWriteVersioned(
        nk,
        COMMERCE_WALLET_COLLECTION,
        BETA_VOUCHER_SPEND_INFLIGHT_KEY,
        accountId,
        rec,
        obj.version,
        0
      );
      return { ok: true };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, error: "voucher_purchase_in_progress" };
}

function lingerVoucherSpendInflight(
  nk: nkruntime.Nakama,
  accountId: string,
  productId: string,
  idempotencyKey: string,
  txId: string
): void {
  for (let attempt = 0; attempt < 8; attempt++) {
    const now = nowUnix();
    const obj = readVoucherSpendInflightObj(nk, accountId);
    const rec = obj.value;
    rec.locks[productId] = {
      idempotency_key: idempotencyKey,
      tx_id: txId,
      started_at: now,
      expires_at: now + VOUCHER_SPEND_DOUBLE_TAP_LINGER_SEC,
    };
    rec.updated_at = now;
    try {
      storageWriteVersioned(
        nk,
        COMMERCE_WALLET_COLLECTION,
        BETA_VOUCHER_SPEND_INFLIGHT_KEY,
        accountId,
        rec,
        obj.version,
        0
      );
      return;
    } catch (_e) {
      continue;
    }
  }
}

function releaseVoucherSpendInflight(nk: nkruntime.Nakama, accountId: string, productId: string): void {
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readVoucherSpendInflightObj(nk, accountId);
    const rec = obj.value;
    if (!rec.locks[productId]) {
      return;
    }
    delete rec.locks[productId];
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(
        nk,
        COMMERCE_WALLET_COLLECTION,
        BETA_VOUCHER_SPEND_INFLIGHT_KEY,
        accountId,
        rec,
        obj.version,
        0
      );
      return;
    } catch (_e) {
      continue;
    }
  }
}

function writeCommerceAudit(nk: nkruntime.Nakama, accountId: string, audit: any): void {
  const id = String(audit.idempotency_key || audit.transaction_id || ("aud_" + nowUnix() + "_" + Math.floor(Math.random() * 10000)));
  let key = id.replace(/[^a-zA-Z0-9._-]+/g, "_");
  if (key.length > 120) {
    key = key.substring(0, 120);
  }
  audit.account_id = accountId;
  audit.server_timestamp_utc = nowUnix();
  try {
    storageWriteVersioned(nk, COMMERCE_AUDIT_COLLECTION, key, accountId, audit, "*", 0);
  } catch (_e) {
    /* audit is best-effort; commerce mutation already committed */
  }
}

function activeBetaTopUpRound(): TopUpRoundDef {
  return TEST_ONLY_BETA_TOPUP_ROUNDS[BETA_TOPUP_TEST_ROUND_ID];
}

function lookupBetaTopUpRound(roundId: string): TopUpRoundDef | null {
  const id = String(roundId || "").trim();
  if (TEST_ONLY_BETA_TOPUP_ROUNDS[id]) {
    return TEST_ONLY_BETA_TOPUP_ROUNDS[id];
  }
  return null;
}

function emptyTopUpProgress(accountId: string, round: TopUpRoundDef): TopUpProgressRecord {
  return {
    account_id: accountId,
    round_id: round.round_id,
    kind: round.kind,
    progress: 0,
    claimed: {},
    applied_refs: {},
    history: [],
    updated_at: nowUnix(),
  };
}

function readTopUpProgress(
  nk: nkruntime.Nakama,
  collection: string,
  accountId: string,
  round: TopUpRoundDef
): { value: TopUpProgressRecord; version: string } {
  const obj = storageReadOne(nk, collection, round.round_id, accountId);
  if (obj && obj.value) {
    const rec = obj.value as TopUpProgressRecord;
    rec.claimed = rec.claimed || {};
    rec.applied_refs = rec.applied_refs || {};
    rec.history = rec.history || [];
    rec.progress = Math.max(0, Math.floor(Number(rec.progress || 0)));
    rec.account_id = accountId;
    rec.round_id = round.round_id;
    rec.kind = round.kind;
    return { value: rec, version: obj.version };
  }
  return { value: emptyTopUpProgress(accountId, round), version: "*" };
}

function applyTopUpProgressIdempotent(
  nk: nkruntime.Nakama,
  collection: string,
  accountId: string,
  round: TopUpRoundDef,
  amount: number,
  applyRef: string,
  productId: string
): { ok: boolean; already: boolean; before: number; after: number; error?: string } {
  const amt = Math.max(0, Math.floor(Number(amount || 0)));
  const ref = String(applyRef || "").trim();
  if (!accountId || !ref) {
    return { ok: false, already: false, before: 0, after: 0, error: "Invalid top-up apply" };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readTopUpProgress(nk, collection, accountId, round);
    const rec = obj.value;
    if (rec.applied_refs[ref]) {
      return { ok: true, already: true, before: rec.progress, after: rec.progress };
    }
    const before = rec.progress;
    rec.progress = rec.progress + amt;
    rec.applied_refs[ref] = { amount: amt, ts: nowUnix(), product_id: productId };
    rec.history.push({
      ref: ref,
      product_id: productId,
      amount: amt,
      before: before,
      after: rec.progress,
      ts: nowUnix(),
    });
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, collection, round.round_id, accountId, rec, obj.version, 0);
      return { ok: true, already: false, before: before, after: rec.progress };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, already: false, before: 0, after: 0, error: "Top-up conflict" };
}

function publicTopUpState(nk: nkruntime.Nakama, accountId: string, round: TopUpRoundDef, collection: string): any {
  const rec = readTopUpProgress(nk, collection, accountId, round).value;
  const now = nowUnix();
  const milestones: any[] = [];
  for (let i = 0; i < round.milestones.length; i++) {
    const m = round.milestones[i];
    const claimed = !!rec.claimed[m.milestone_id];
    milestones.push({
      milestone_id: m.milestone_id,
      threshold: m.threshold,
      reward_diamonds: m.reward_diamonds,
      test_only: !!m.test_only,
      reached: rec.progress >= m.threshold,
      claimed: claimed,
      claimable: rec.progress >= m.threshold && !claimed && now >= round.start_utc && (round.end_utc <= 0 || now <= round.end_utc),
    });
  }
  return {
    round_id: round.round_id,
    kind: round.kind,
    test_only: !!round.test_only,
    start_utc: round.start_utc,
    end_utc: round.end_utc,
    progress: rec.progress,
    milestones: milestones,
  };
}

function applyProductionQualifyingTopUp(
  nk: nkruntime.Nakama,
  accountId: string,
  rec: PurchaseLedgerRecord,
  product: CommerceProductDef
): void {
  if (!rec || rec.purchase_source === PURCHASE_SOURCE_BETA_VOUCHER) {
    return;
  }
  if (rec.purchase_source !== PURCHASE_SOURCE_GOOGLE_PLAY && rec.purchase_source !== PURCHASE_SOURCE_APPLE_STOREKIT) {
    return;
  }
  if (rec.delivery_status !== PURCHASE_DELIVERED) {
    return;
  }
  // No production Top-Up round is active in Phase 1. Do not invent one.
  const activeProd = lookupActiveProductionTopUpRound();
  if (!activeProd) {
    return;
  }
  const amount = Math.max(0, Math.floor(Number(product.qualifying_topup_diamonds || 0)));
  if (amount <= 0) {
    return;
  }
  const ref = rec.delivery_transaction_id || deliveryRefFor(rec.platform, rec.platform_transaction_id);
  applyTopUpProgressIdempotent(nk, PROD_TOPUP_COLLECTION, accountId, activeProd, amount, ref, product.product_id);
}

function lookupActiveProductionTopUpRound(): TopUpRoundDef | null {
  return null;
}

function attachBetaCommercePublicFields(
  nk: nkruntime.Nakama,
  accountId: string,
  payload: any,
  env?: { [key: string]: string }
): any {
  const available = isBetaVoucherTestingEnabled(nk, accountId, env);
  payload.beta_voucher_available = available;
  payload.beta_voucher_cash_value = 0;
  payload.production_topup = null;
  const vouchers = readVoucherWalletObj(nk, accountId).value;
  const balance = vouchers.balance;
  payload.vouchers = balance;
  payload.beta_vouchers = balance;
  const offers = listVoucherPurchasableOffers();
  payload.voucher_offers = offers;
  payload.beta_voucher_offers = offers;
  if (available) {
    payload.beta_topup = publicTopUpState(nk, accountId, activeBetaTopUpRound(), BETA_TOPUP_COLLECTION);
  } else {
    payload.beta_topup = null;
  }
  return payload;
}

function redeemVoucherCodeForAccount(
  nk: nkruntime.Nakama,
  accountId: string,
  rawCode: string,
  clientAmount: number,
  clientCohort: string,
  idempotencyKey: string,
  env?: { [key: string]: string }
): any {
  const code = normalizeVoucherCode(rawCode);
  if (!code) {
    return { ok: false, error: "invalid_code" };
  }
  const def = lookupRedeemableVoucherCode(nk, code, env);
  if (!def) {
    return { ok: false, error: "invalid_code" };
  }
  if (!def.is_active) {
    return { ok: false, error: "inactive_code" };
  }
  if (def.expires_at_utc > 0 && nowUnix() >= def.expires_at_utc) {
    return { ok: false, error: "expired_code" };
  }
  const grantAmount = Math.max(0, Math.floor(Number(def.voucher_grant_amount || 0)));
  const cohort = def.allocation_cohort;
  void clientAmount;
  void clientCohort;
  const redeemKey = def.code_id;
  const existing = storageReadOne(nk, BETA_VOUCHER_REDEEM_COLLECTION, redeemKey, accountId);
  if (existing && existing.value) {
    const prev = existing.value as BetaVoucherRedemptionRecord;
    if (prev.count >= def.per_account_limit) {
      const wallet = readVoucherWalletObj(nk, accountId).value;
      return {
        ok: false,
        error: "already_redeemed",
        already: true,
        beta_vouchers: wallet.balance,
        wallet: publicWallet(nk, accountId),
      };
    }
  }
  if (def.max_global_redemptions > 0) {
    const statsObj = storageReadOne(nk, BETA_VOUCHER_CODE_COLLECTION, def.code_id, SYSTEM_USER);
    const stats: BetaVoucherCodeStats = statsObj && statsObj.value
      ? (statsObj.value as BetaVoucherCodeStats)
      : { code_id: def.code_id, current_global_redemptions: 0, updated_at: nowUnix() };
    if (stats.current_global_redemptions >= def.max_global_redemptions) {
      return { ok: false, error: "global_cap_reached" };
    }
    stats.current_global_redemptions += 1;
    stats.updated_at = nowUnix();
    try {
      storageWriteVersioned(
        nk,
        BETA_VOUCHER_CODE_COLLECTION,
        def.code_id,
        SYSTEM_USER,
        stats,
        statsObj ? statsObj.version : "*",
        0
      );
    } catch (_e) {
      return { ok: false, error: "global_cap_conflict" };
    }
  }
  const grantRef = "vgrant:" + def.code_id + ":" + accountId;
  const before = readVoucherWalletObj(nk, accountId).value.balance;
  const granted = mutateVoucherWallet(nk, accountId, grantRef, "grant", grantAmount, {
    code_id: def.code_id,
    reason: "code_redemption",
  });
  if (!granted.ok) {
    return { ok: false, error: granted.error || "grant_failed" };
  }
  const redemption: BetaVoucherRedemptionRecord = {
    account_id: accountId,
    code_id: def.code_id,
    code_string: def.code_string,
    count: existing && existing.value ? Math.floor(Number((existing.value as BetaVoucherRedemptionRecord).count || 0)) + (granted.already ? 0 : 1) : 1,
    last_amount: grantAmount,
    last_cohort: cohort,
    updated_at: nowUnix(),
  };
  try {
    storageWriteVersioned(
      nk,
      BETA_VOUCHER_REDEEM_COLLECTION,
      redeemKey,
      accountId,
      redemption,
      existing ? existing.version : "*",
      0
    );
  } catch (_e) {
    /* wallet grant already idempotent */
  }
  writeCommerceAudit(nk, accountId, {
    transaction_id: grantRef,
    purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
    event: "voucher_code_redeem",
    code_id: def.code_id,
    tester_cohort: cohort,
    voucher_grant_amount: grantAmount,
    voucher_balance_before: granted.already ? before : granted.before,
    voucher_balance_after: granted.balance,
    idempotency_key: String(idempotencyKey || grantRef),
    client_amount_ignored: Math.floor(Number(clientAmount || 0)),
  });
  return {
    ok: true,
    already: granted.already,
    granted_vouchers: grantAmount,
    allocation_cohort: cohort,
    beta_vouchers: granted.balance,
    wallet: publicWallet(nk, accountId),
  };
}

function indexBetaVoucherLedger(nk: nkruntime.Nakama, accountId: string, key: string): void {
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, BETA_VOUCHER_LEDGER_INDEX_KEY, accountId);
    let rec: PurchaseIndexRecord;
    let ver = "*";
    if (obj && obj.value) {
      rec = obj.value as PurchaseIndexRecord;
      ver = obj.version;
      if (!rec.transaction_keys) {
        rec.transaction_keys = [];
      }
    } else {
      rec = { account_id: accountId, transaction_keys: [], updated_at: nowUnix() };
    }
    if (rec.transaction_keys.indexOf(key) >= 0) {
      return;
    }
    rec.transaction_keys.push(key);
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, BETA_VOUCHER_LEDGER_INDEX_KEY, accountId, rec, ver, 0);
      return;
    } catch (_e) {
      continue;
    }
  }
}

function purchasePackageWithVouchers(
  nk: nkruntime.Nakama,
  accountId: string,
  productId: string,
  clientCost: number,
  clientQualifying: number,
  idempotencyKey: string
): any {
  void clientCost;
  void clientQualifying;
  const product = lookupCommerceProduct(productId);
  if (!product || !product.production_deliverable || !product.beta_voucher_purchasable) {
    return { ok: false, error: "product_not_voucher_purchasable" };
  }
  if (productGrantsVouchers(product)) {
    return { ok: false, error: "voucher_pack_not_voucher_purchasable" };
  }
  const cost = Math.max(0, Math.floor(Number(product.beta_voucher_cost || 0)));
  if (cost <= 0) {
    return { ok: false, error: "invalid_voucher_cost" };
  }
  const keyNorm = normalizeVoucherSpendIdempotencyKey(idempotencyKey);
  if (!keyNorm.ok || !keyNorm.key) {
    return { ok: false, error: keyNorm.error || "idempotency_key_required" };
  }
  const keyRaw = keyNorm.key;
  const txId = voucherSpendTxId(accountId, product.product_id, keyRaw);
  const existing = storageReadOne(nk, BETA_VOUCHER_LEDGER_COLLECTION, txId, accountId);
  if (existing && existing.value && (existing.value as BetaVoucherLedgerRecord).delivery_status === PURCHASE_DELIVERED) {
    return {
      ok: true,
      already: true,
      purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
      purchase: existing.value,
      wallet: publicWallet(nk, accountId),
    };
  }
  const locked = acquireVoucherSpendInflight(nk, accountId, product.product_id, keyRaw, txId);
  if (!locked.ok) {
    return { ok: false, error: locked.error || "voucher_purchase_in_progress" };
  }
  const spendRef = "vspend:" + txId;
  const spent = mutateVoucherWallet(nk, accountId, spendRef, "spend", cost, {
    product_id: product.product_id,
    reason: "simulated_purchase",
  });
  if (!spent.ok) {
    releaseVoucherSpendInflight(nk, accountId, product.product_id);
    return { ok: false, error: spent.error || "Insufficient vouchers", beta_vouchers: spent.balance };
  }
  const deliveryTxId = "dlv_" + txId;
  const delivered = deliverCatalogProduct(nk, accountId, product, deliveryTxId);
  if (!delivered.ok) {
    mutateVoucherWallet(nk, accountId, "vrev:" + txId, "reversal", cost, {
      product_id: product.product_id,
      reason: "delivery_failed_reversal",
    });
    releaseVoucherSpendInflight(nk, accountId, product.product_id);
    return { ok: false, error: delivered.error || "Delivery failed" };
  }
  const qualifying = Math.max(0, Math.floor(Number(product.qualifying_topup_diamonds || 0)));
  const betaRound = activeBetaTopUpRound();
  const topup = applyTopUpProgressIdempotent(
    nk,
    BETA_TOPUP_COLLECTION,
    accountId,
    betaRound,
    qualifying,
    deliveryTxId,
    product.product_id
  );
  const rewards: any[] = [];
  if (product.delivery_type === DELIVERY_DIAMONDS) {
    rewards.push({ type: "wallet_currency", target_id: "diamonds", amount: product.diamond_amount });
  } else if (product.entitlement_id) {
    rewards.push({ type: "entitlement", target_id: product.entitlement_id, amount: 1 });
  }
  const rec: BetaVoucherLedgerRecord = {
    account_id: accountId,
    purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
    product_id: product.product_id,
    platform: "BETA_VOUCHER",
    platform_transaction_id: txId,
    voucher_cost: cost,
    qualifying_topup_diamonds: qualifying,
    delivery_status: PURCHASE_DELIVERED,
    delivery_transaction_id: deliveryTxId,
    rewards_granted: rewards,
    created_at: nowUnix(),
    updated_at: nowUnix(),
  };
  try {
    storageWriteVersioned(nk, BETA_VOUCHER_LEDGER_COLLECTION, txId, accountId, rec, existing ? existing.version : "*", 0);
    indexBetaVoucherLedger(nk, accountId, txId);
  } catch (_e) {
    /* replay-safe */
  }
  lingerVoucherSpendInflight(nk, accountId, product.product_id, keyRaw, txId);
  writeCommerceAudit(nk, accountId, {
    transaction_id: txId,
    purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
    event: "voucher_simulated_purchase",
    product_id: product.product_id,
    voucher_cost: cost,
    qualifying_topup_diamonds: qualifying,
    topup_event_id: betaRound.round_id,
    topup_progress_before: topup.before,
    topup_progress_after: topup.after,
    rewards_granted: rewards,
    voucher_balance_before: spent.before,
    voucher_balance_after: spent.balance,
    production_revenue: 0,
    production_topup: 0,
    idempotency_key: keyRaw,
  });
  return {
    ok: true,
    already: spent.already,
    purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
    purchase: rec,
    beta_vouchers: spent.balance,
    beta_topup: publicTopUpState(nk, accountId, betaRound, BETA_TOPUP_COLLECTION),
    production_topup: 0,
    wallet: publicWallet(nk, accountId),
  };
}

function claimBetaTopUpMilestone(nk: nkruntime.Nakama, accountId: string, milestoneId: string, idempotencyKey: string): any {
  const mid = String(milestoneId || "").trim();
  if (!mid) {
    return { ok: false, error: "milestone_required" };
  }
  const round = activeBetaTopUpRound();
  const now = nowUnix();
  if (now < round.start_utc || (round.end_utc > 0 && now > round.end_utc)) {
    return { ok: false, error: "round_inactive" };
  }
  let def: TopUpMilestoneDef | null = null;
  for (let i = 0; i < round.milestones.length; i++) {
    if (round.milestones[i].milestone_id === mid) {
      def = round.milestones[i];
      break;
    }
  }
  if (!def) {
    return { ok: false, error: "unknown_milestone" };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readTopUpProgress(nk, BETA_TOPUP_COLLECTION, accountId, round);
    const rec = obj.value;
    if (rec.progress < def.threshold) {
      return { ok: false, error: "threshold_not_reached", progress: rec.progress, threshold: def.threshold };
    }
    if (rec.claimed[mid]) {
      return {
        ok: true,
        already: true,
        milestone_id: mid,
        wallet: publicWallet(nk, accountId),
        beta_topup: publicTopUpState(nk, accountId, round, BETA_TOPUP_COLLECTION),
      };
    }
    const grantRef = "btclaim:" + round.round_id + ":" + mid + ":" + accountId;
    const granted = grantDiamondsIdempotent(nk, accountId, def.reward_diamonds, grantRef);
    if (!granted.ok) {
      return { ok: false, error: granted.error || "reward_failed" };
    }
    rec.claimed[mid] = {
      claimed_at: nowUnix(),
      reward_diamonds: def.reward_diamonds,
      grant_ref: grantRef,
    };
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, BETA_TOPUP_COLLECTION, round.round_id, accountId, rec, obj.version, 0);
      writeCommerceAudit(nk, accountId, {
        transaction_id: grantRef,
        purchase_source: PURCHASE_SOURCE_BETA_VOUCHER,
        event: "beta_topup_milestone_claim",
        milestone_id: mid,
        threshold: def.threshold,
        reward_diamonds: def.reward_diamonds,
        topup_event_id: round.round_id,
        idempotency_key: String(idempotencyKey || grantRef),
      });
      return {
        ok: true,
        already: granted.already,
        milestone_id: mid,
        reward_diamonds: def.reward_diamonds,
        wallet: publicWallet(nk, accountId),
        beta_topup: publicTopUpState(nk, accountId, round, BETA_TOPUP_COLLECTION),
      };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, error: "claim_conflict" };
}

function rpcCommerceRedeemVoucherCode(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  if (!isBetaVoucherTestingEnabled(nk, ctx.userId, ctx.env)) {
    return JSON.stringify({ ok: false, error: "beta_voucher_unavailable" });
  }
  const data = parsePayload(payload);
  return JSON.stringify(
    redeemVoucherCodeForAccount(
      nk,
      ctx.userId,
      String(data["code"] || ""),
      Number(data["amount"] || data["voucher_grant_amount"] || 0),
      String(data["allocation_cohort"] || data["cohort"] || ""),
      String(data["idempotency_key"] || ""),
      ctx.env
    )
  );
}

function rpcCommercePurchaseWithVouchers(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  void data["diamond_amount"];
  void data["amount"];
  return JSON.stringify(
    purchasePackageWithVouchers(
      nk,
      ctx.userId,
      String(data["product_id"] || ""),
      Number(data["voucher_cost"] || data["amount"] || 0),
      Number(data["qualifying_topup_diamonds"] || 0),
      String(data["idempotency_key"] || "")
    )
  );
}

function rpcCommerceGetBetaTopUp(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, _payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  if (!isBetaVoucherTestingEnabled(nk, ctx.userId, ctx.env)) {
    return JSON.stringify({ ok: false, error: "beta_voucher_unavailable" });
  }
  return JSON.stringify({
    ok: true,
    beta_topup: publicTopUpState(nk, ctx.userId, activeBetaTopUpRound(), BETA_TOPUP_COLLECTION),
    production_topup: null,
    wallet: publicWallet(nk, ctx.userId, ctx.env),
  });
}

function rpcCommerceClaimBetaTopUpMilestone(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  if (!isBetaVoucherTestingEnabled(nk, ctx.userId, ctx.env)) {
    return JSON.stringify({ ok: false, error: "beta_voucher_unavailable" });
  }
  const data = parsePayload(payload);
  return JSON.stringify(
    claimBetaTopUpMilestone(nk, ctx.userId, String(data["milestone_id"] || ""), String(data["idempotency_key"] || ""))
  );
}
