/**
 * Crownspire Phase 5.7 — Server commerce authority spine
 * Concatenated into build/index.js via tsconfig files order.
 *
 * Production paid flow (CURRENT CANON / IMPLEMENTED AUTHORITY):
 *   Platform Store → receipt → Nakama server validation (persist=true)
 *   → purchase ledger → idempotent delivery → wallet/entitlement → client mirror
 *
 * A client platform callback is NEVER authority. No receipt = no paid delivery.
 * No validated server transaction = no paid delivery.
 *
 * Diamond wallet: ACCOUNT-WIDE server-only storage, permissionWrite: 0.
 * Why not Nakama wallet: nk.walletUpdate is unused in this repo; write-0 storage
 * plus OCC is the proven pattern (entitlements, teleport inventory).
 *
 * Price: nk ValidatedPurchase has no price/currency. Never trust client price.
 * USD is looked up from COMMERCE_PRODUCT_CATALOG only.
 *
 * First approved small consumable Diamond pack: com.crownspire.diamonds_500
 * (500 Diamonds, $4.99 / 499 cents). Consumable. production_deliverable.
 * TEST_ONLY fixture remains blocked on the production delivery path.
 *
 * Validation: nk.purchaseValidateApple / purchaseValidateGoogle with persist=true.
 * Do not use the Godot NakamaClient wrappers (they default persist=false).
 * No mocked validation in this production module.
 */

const COMMERCE_LEDGER_COLLECTION = "crownspire_purchase_ledger";
const COMMERCE_WALLET_COLLECTION = "crownspire_commerce";
const COMMERCE_WALLET_KEY = "diamond_wallet";
const COMMERCE_INDEX_KEY = "purchase_index";
const COMMERCE_BETA_PROGRAM_ID = "crownspire_paid_beta_v1";

const PURCHASE_RECEIVED = "RECEIVED";
const PURCHASE_VALIDATED = "VALIDATED";
const PURCHASE_DELIVERING = "DELIVERING";
const PURCHASE_DELIVERED = "DELIVERED";
const PURCHASE_REJECTED = "REJECTED";
const PURCHASE_REFUNDED = "REFUNDED";
const PURCHASE_REVOKED = "REVOKED";
const PURCHASE_VOIDED = "VOIDED";
const PURCHASE_CANCELLED = "CANCELLED";

const DELIVERY_DIAMONDS = "DIAMONDS";
const DELIVERY_PERMANENT_ENTITLEMENT = "PERMANENT_ENTITLEMENT";
const DELIVERY_TIMED_ENTITLEMENT = "TIMED_ENTITLEMENT";
const DELIVERY_ACCOUNT_COLLECTION = "ACCOUNT_COLLECTION";
const DELIVERY_CONSUMABLE_ITEM = "CONSUMABLE_ITEM";
const DELIVERY_SUBSCRIPTION = "SUBSCRIPTION";

const PAID_QUEUE_ENTITLEMENT_IDS: string[] = [
  "entitlement_builder_queue_30d",
  "entitlement_builder_queue_perm",
  "entitlement_research_queue_perm",
  "entitlement_march_queue_perm",
];

interface CommerceProductDef {
  product_id: string;
  iap_product_id: string;
  usd_cents: number;
  delivery_type: string;
  repeatability: string;
  duration_seconds: number;
  entitlement_id: string;
  diamond_amount: number;
  qualifying_topup_diamonds: number;
  beta_voucher_cost: number;
  beta_voucher_purchasable: boolean;
  beta_spend_eligible: boolean;
  production_deliverable: boolean;
  live_store: boolean;
}

const PURCHASE_SOURCE_GOOGLE_PLAY = "GOOGLE_PLAY";
const PURCHASE_SOURCE_APPLE_STOREKIT = "APPLE_STOREKIT";
const PURCHASE_SOURCE_BETA_VOUCHER = "BETA_VOUCHER";

function purchaseSourceForPlatform(platform: string): string {
  const p = String(platform || "").toUpperCase();
  if (p === "APPLE") {
    return PURCHASE_SOURCE_APPLE_STOREKIT;
  }
  return PURCHASE_SOURCE_GOOGLE_PLAY;
}

interface PurchaseLedgerRecord {
  account_id: string;
  platform: string;
  platform_transaction_id: string;
  product_id: string;
  purchase_source?: string;
  purchase_timestamp: number;
  validation_status: string;
  delivery_status: string;
  delivery_transaction_id: string;
  refund_or_revocation_status: string;
  verified_amount: number;
  verified_currency: string;
  normalized_usd: number;
  normalized_usd_cents: number;
  qualifying_topup_diamonds?: number;
  beta_program_id: string;
  eligible_beta_spend_amount: number;
  eligible_beta_spend_cents: number;
  delivery_type: string;
  entitlement_id: string;
  seen_before: boolean;
  updated_at: number;
  original_delivery_status?: string;
  refunded_at?: number;
  reversal_ref?: string;
  reversal_reason?: string;
  reversal_applied?: boolean;
}

interface DiamondWalletRef {
  type: string;
  amount: number;
  ts: number;
  applied_to_balance?: number;
  applied_to_debt?: number;
  original_delivery_ref?: string;
  debit?: number;
  debt_added?: number;
}

interface DiamondWalletRecord {
  account_id: string;
  balance: number;
  diamond_debt: number;
  processed_refs: { [ref: string]: DiamondWalletRef };
  updated_at: number;
}

interface PurchaseIndexRecord {
  account_id: string;
  transaction_keys: string[];
  updated_at: number;
}

const COMMERCE_PRODUCT_CATALOG: CommerceProductDef[] = [
  {
    product_id: "com.crownspire.diamonds_500",
    iap_product_id: "com.crownspire.diamonds_500",
    usd_cents: 499,
    delivery_type: DELIVERY_DIAMONDS,
    repeatability: "consumable",
    duration_seconds: 0,
    entitlement_id: "",
    diamond_amount: 500,
    qualifying_topup_diamonds: 500,
    beta_voucher_cost: 5,
    beta_voucher_purchasable: true,
    beta_spend_eligible: true,
    production_deliverable: true,
    live_store: true,
  },
  {
    product_id: "entitlement_builder_queue_30d",
    iap_product_id: "com.crownspire.builder_queue_30d",
    usd_cents: 499,
    delivery_type: DELIVERY_TIMED_ENTITLEMENT,
    repeatability: "repeatable_distinct_transactions",
    duration_seconds: 2592000,
    entitlement_id: "entitlement_builder_queue_30d",
    diamond_amount: 0,
    qualifying_topup_diamonds: 0,
    beta_voucher_cost: 0,
    beta_voucher_purchasable: false,
    beta_spend_eligible: true,
    production_deliverable: true,
    live_store: false,
  },
  {
    product_id: "entitlement_builder_queue_perm",
    iap_product_id: "com.crownspire.builder_queue_perm",
    usd_cents: 999,
    delivery_type: DELIVERY_PERMANENT_ENTITLEMENT,
    repeatability: "non_consumable",
    duration_seconds: 0,
    entitlement_id: "entitlement_builder_queue_perm",
    diamond_amount: 0,
    qualifying_topup_diamonds: 0,
    beta_voucher_cost: 0,
    beta_voucher_purchasable: false,
    beta_spend_eligible: true,
    production_deliverable: true,
    live_store: false,
  },
  {
    product_id: "entitlement_research_queue_perm",
    iap_product_id: "com.crownspire.research_queue_perm",
    usd_cents: 999,
    delivery_type: DELIVERY_PERMANENT_ENTITLEMENT,
    repeatability: "non_consumable",
    duration_seconds: 0,
    entitlement_id: "entitlement_research_queue_perm",
    diamond_amount: 0,
    qualifying_topup_diamonds: 0,
    beta_voucher_cost: 0,
    beta_voucher_purchasable: false,
    beta_spend_eligible: true,
    production_deliverable: true,
    live_store: false,
  },
  {
    product_id: "entitlement_march_queue_perm",
    iap_product_id: "com.crownspire.march_queue_perm",
    usd_cents: 1999,
    delivery_type: DELIVERY_PERMANENT_ENTITLEMENT,
    repeatability: "non_consumable",
    duration_seconds: 0,
    entitlement_id: "entitlement_march_queue_perm",
    diamond_amount: 0,
    qualifying_topup_diamonds: 0,
    beta_voucher_cost: 0,
    beta_voucher_purchasable: false,
    beta_spend_eligible: true,
    production_deliverable: true,
    live_store: false,
  },
  {
    product_id: "com.crownspire.test.diamonds_internal_do_not_ship",
    iap_product_id: "com.crownspire.test.diamonds_internal_do_not_ship",
    usd_cents: 0,
    delivery_type: DELIVERY_DIAMONDS,
    repeatability: "consumable",
    duration_seconds: 0,
    entitlement_id: "",
    diamond_amount: 1,
    qualifying_topup_diamonds: 0,
    beta_voucher_cost: 0,
    beta_voucher_purchasable: false,
    beta_spend_eligible: false,
    production_deliverable: false,
    live_store: false,
  },
];

function lookupCommerceProduct(platformProductId: string): CommerceProductDef | null {
  const id = String(platformProductId || "").trim();
  if (!id) {
    return null;
  }
  for (let i = 0; i < COMMERCE_PRODUCT_CATALOG.length; i++) {
    const row = COMMERCE_PRODUCT_CATALOG[i];
    if (row.product_id === id || row.iap_product_id === id) {
      return row;
    }
  }
  return null;
}

/** Launch voucher dollars = ceil(eligible_usd * 1.10). Refunded rows must be excluded before calling. */
function computeBetaVoucherUsd(eligibleUsdCents: number): number {
  const cents = Math.max(0, Math.floor(eligibleUsdCents));
  if (cents <= 0) {
    return 0;
  }
  return Math.ceil((cents * 110) / 10000);
}

function ledgerStorageKey(platform: string, txId: string): string {
  const p = String(platform || "").toLowerCase().replace(/[^a-z0-9]+/g, "_");
  const t = String(txId || "").replace(/[^a-zA-Z0-9._-]+/g, "_");
  let key = p + "__" + t;
  if (key.length > 120) {
    key = key.substring(0, 120);
  }
  return key;
}

function emptyWallet(accountId: string): DiamondWalletRecord {
  return {
    account_id: accountId,
    balance: 0,
    diamond_debt: 0,
    processed_refs: {},
    updated_at: nowUnix(),
  };
}

function normalizeDiamondWallet(rec: DiamondWalletRecord, accountId: string): DiamondWalletRecord {
  if (!rec.processed_refs) {
    rec.processed_refs = {};
  }
  rec.account_id = accountId;
  rec.balance = Math.max(0, Math.floor(Number(rec.balance || 0)));
  rec.diamond_debt = Math.max(0, Math.floor(Number(rec.diamond_debt || 0)));
  return rec;
}

function readDiamondWalletObj(nk: nkruntime.Nakama, accountId: string): { value: DiamondWalletRecord; version: string } {
  const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_WALLET_KEY, accountId);
  if (obj && obj.value) {
    return { value: normalizeDiamondWallet(obj.value as DiamondWalletRecord, accountId), version: obj.version };
  }
  return { value: emptyWallet(accountId), version: "*" };
}

function deliveryRefFor(platform: string, txId: string): string {
  return "dlv_" + ledgerStorageKey(platform, txId);
}

function reversalRefFor(platform: string, txId: string): string {
  return "rev_" + ledgerStorageKey(platform, txId);
}

function isReversalStatus(status: string): boolean {
  return (
    status === PURCHASE_REFUNDED ||
    status === PURCHASE_REVOKED ||
    status === PURCHASE_VOIDED ||
    status === PURCHASE_CANCELLED
  );
}

function isLedgerReversed(rec: PurchaseLedgerRecord): boolean {
  if (rec.reversal_applied) {
    return true;
  }
  if (isReversalStatus(rec.refund_or_revocation_status)) {
    return true;
  }
  return isReversalStatus(rec.delivery_status);
}

function normalizeReversalReason(raw: string): string {
  const s = String(raw || "").trim().toUpperCase();
  if (s === PURCHASE_CANCELLED || s === "CANCELED") {
    return PURCHASE_CANCELLED;
  }
  if (s === PURCHASE_VOIDED || s === "CHARGEBACK" || s === "CHARGED_BACK" || s === "VOID") {
    return PURCHASE_VOIDED;
  }
  if (s === PURCHASE_REVOKED) {
    return PURCHASE_REVOKED;
  }
  return PURCHASE_REFUNDED;
}

function isReversalNotification(notificationType: string, refundTime: number): boolean {
  const t = String(notificationType || "").trim().toUpperCase();
  if (
    t === "REFUNDED" ||
    t === "CANCELLED" ||
    t === "CANCELED" ||
    t === "VOIDED" ||
    t === "VOID" ||
    t === "CHARGEBACK" ||
    t === "CHARGED_BACK" ||
    t === "REVOKED"
  ) {
    return true;
  }
  return Number(refundTime || 0) > 0;
}

function grantDiamondsIdempotent(
  nk: nkruntime.Nakama,
  accountId: string,
  amount: number,
  grantRef: string
): { ok: boolean; balance: number; diamond_debt: number; already: boolean; error?: string } {
  const amt = Math.floor(Number(amount || 0));
  const ref = String(grantRef || "").trim();
  if (!ref || amt < 0) {
    return { ok: false, balance: 0, diamond_debt: 0, already: false, error: "Invalid grant" };
  }
  if (amt === 0) {
    const cur = readDiamondWalletObj(nk, accountId);
    return { ok: true, balance: cur.value.balance, diamond_debt: cur.value.diamond_debt, already: true };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readDiamondWalletObj(nk, accountId);
    const rec = obj.value;
    const prev = rec.processed_refs[ref];
    if (prev) {
      return { ok: true, balance: rec.balance, diamond_debt: rec.diamond_debt, already: true };
    }
    // Paid Diamond grants repay diamond_debt first. Remainder becomes spendable balance.
    const debt = rec.diamond_debt;
    const repay = Math.min(debt, amt);
    const toBalance = amt - repay;
    rec.diamond_debt = debt - repay;
    rec.balance = rec.balance + toBalance;
    rec.processed_refs[ref] = {
      type: "grant",
      amount: amt,
      applied_to_debt: repay,
      applied_to_balance: toBalance,
      ts: nowUnix(),
    };
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_WALLET_KEY, accountId, rec, obj.version, 0);
      return { ok: true, balance: rec.balance, diamond_debt: rec.diamond_debt, already: false };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, balance: 0, diamond_debt: 0, already: false, error: "Wallet conflict" };
}

function spendDiamondsIdempotent(
  nk: nkruntime.Nakama,
  accountId: string,
  amount: number,
  spendRef: string
): { ok: boolean; balance: number; already: boolean; error?: string } {
  const amt = Math.floor(Number(amount || 0));
  const ref = String(spendRef || "").trim();
  if (!ref || amt < 0) {
    return { ok: false, balance: 0, already: false, error: "Invalid spend" };
  }
  if (amt === 0) {
    const cur = readDiamondWalletObj(nk, accountId);
    return { ok: true, balance: cur.value.balance, already: true };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readDiamondWalletObj(nk, accountId);
    const rec = obj.value;
    const prev = rec.processed_refs[ref];
    if (prev) {
      return { ok: true, balance: rec.balance, already: true };
    }
    if (rec.balance < amt) {
      return { ok: false, balance: rec.balance, already: false, error: "Insufficient diamonds" };
    }
    rec.balance = rec.balance - amt;
    rec.processed_refs[ref] = { type: "spend", amount: amt, ts: nowUnix() };
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_WALLET_KEY, accountId, rec, obj.version, 0);
      return { ok: true, balance: rec.balance, already: false };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, balance: 0, already: false, error: "Wallet conflict" };
}

function reverseDiamondsIdempotent(
  nk: nkruntime.Nakama,
  userId: string,
  amount: number,
  reversalRef: string,
  originalDeliveryRef: string
): {
  ok: boolean;
  already: boolean;
  balance: number;
  diamond_debt: number;
  debit: number;
  debt_added: number;
  error?: string;
} {
  const amt = Math.floor(Number(amount || 0));
  const ref = String(reversalRef || "").trim();
  const deliveryRef = String(originalDeliveryRef || "").trim();
  if (!userId || !ref || amt < 0) {
    return { ok: false, already: false, balance: 0, diamond_debt: 0, debit: 0, debt_added: 0, error: "Invalid reversal" };
  }
  if (amt === 0) {
    const cur = readDiamondWalletObj(nk, userId);
    return {
      ok: true,
      already: true,
      balance: cur.value.balance,
      diamond_debt: cur.value.diamond_debt,
      debit: 0,
      debt_added: 0,
    };
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readDiamondWalletObj(nk, userId);
    const rec = obj.value;
    const prev = rec.processed_refs[ref];
    if (prev) {
      return {
        ok: true,
        already: true,
        balance: rec.balance,
        diamond_debt: rec.diamond_debt,
        debit: Math.max(0, Math.floor(Number(prev.debit || 0))),
        debt_added: Math.max(0, Math.floor(Number(prev.debt_added || 0))),
      };
    }
    const debit = Math.min(rec.balance, amt);
    const debtAdded = amt - debit;
    rec.balance = rec.balance - debit;
    rec.diamond_debt = rec.diamond_debt + debtAdded;
    rec.processed_refs[ref] = {
      type: "reversal",
      amount: amt,
      debit: debit,
      debt_added: debtAdded,
      original_delivery_ref: deliveryRef,
      ts: nowUnix(),
    };
    rec.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_WALLET_KEY, userId, rec, obj.version, 0);
      return {
        ok: true,
        already: false,
        balance: rec.balance,
        diamond_debt: rec.diamond_debt,
        debit: debit,
        debt_added: debtAdded,
      };
    } catch (_e) {
      continue;
    }
  }
  return { ok: false, already: false, balance: 0, diamond_debt: 0, debit: 0, debt_added: 0, error: "Wallet conflict" };
}

function readLedger(
  nk: nkruntime.Nakama,
  accountId: string,
  platform: string,
  txId: string
): { value: PurchaseLedgerRecord; version: string } | null {
  const key = ledgerStorageKey(platform, txId);
  const obj = storageReadOne(nk, COMMERCE_LEDGER_COLLECTION, key, accountId);
  if (!obj || !obj.value) {
    return null;
  }
  const rec = obj.value as PurchaseLedgerRecord;
  if (rec.account_id && rec.account_id !== accountId) {
    return null;
  }
  rec.account_id = accountId;
  return { value: rec, version: obj.version };
}

function writeLedger(
  nk: nkruntime.Nakama,
  rec: PurchaseLedgerRecord,
  version: string
): void {
  const key = ledgerStorageKey(rec.platform, rec.platform_transaction_id);
  rec.updated_at = nowUnix();
  storageWriteVersioned(nk, COMMERCE_LEDGER_COLLECTION, key, rec.account_id, rec, version, 0);
  indexPurchaseKey(nk, rec.account_id, key);
}

function indexPurchaseKey(nk: nkruntime.Nakama, accountId: string, key: string): void {
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_INDEX_KEY, accountId);
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
      storageWriteVersioned(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_INDEX_KEY, accountId, rec, ver, 0);
      return;
    } catch (_e) {
      continue;
    }
  }
}

function listLedgerRecords(nk: nkruntime.Nakama, accountId: string): PurchaseLedgerRecord[] {
  const obj = storageReadOne(nk, COMMERCE_WALLET_COLLECTION, COMMERCE_INDEX_KEY, accountId);
  const out: PurchaseLedgerRecord[] = [];
  if (!obj || !obj.value) {
    return out;
  }
  const idx = obj.value as PurchaseIndexRecord;
  const keys = idx.transaction_keys || [];
  for (let i = 0; i < keys.length; i++) {
    const row = storageReadOne(nk, COMMERCE_LEDGER_COLLECTION, keys[i], accountId);
    if (row && row.value) {
      out.push(row.value as PurchaseLedgerRecord);
    }
  }
  return out;
}

function eligibleBetaSpendCents(rows: PurchaseLedgerRecord[]): number {
  let sum = 0;
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    if (r.reversal_applied || isReversalStatus(r.refund_or_revocation_status) || isReversalStatus(r.delivery_status)) {
      continue;
    }
    if (r.delivery_status !== PURCHASE_DELIVERED) {
      continue;
    }
    sum += Math.max(0, Math.floor(Number(r.eligible_beta_spend_cents || 0)));
  }
  return sum;
}

function writePaidQueueEntitlement(
  nk: nkruntime.Nakama,
  accountId: string,
  entitlementId: string,
  durationSeconds: number,
  source: string
): void {
  const now = nowUnix();
  const existing = StorageEntitlementProvider.getRecord(nk, accountId, entitlementId);
  let starts = now;
  let expires = durationSeconds > 0 ? now + durationSeconds : 0;
  if (existing && existing.status === "active" && durationSeconds > 0) {
    starts = existing.starts_at > 0 ? existing.starts_at : now;
    const base = existing.expires_at > now ? existing.expires_at : now;
    expires = base + durationSeconds;
  } else if (existing && existing.status === "active" && durationSeconds <= 0) {
    starts = existing.starts_at > 0 ? existing.starts_at : now;
    expires = 0;
  }
  const rec: EntitlementRecord = {
    entitlement_id: entitlementId,
    user_id: accountId,
    status: "active",
    starts_at: starts,
    expires_at: expires,
    source: source,
    updated_at: now,
  };
  nk.storageWrite([
    {
      collection: ENTITLEMENT_COLLECTION,
      key: entitlementId,
      userId: accountId,
      value: rec,
      permissionRead: 1,
      permissionWrite: 0,
    },
  ]);
}

function revokePaidQueueEntitlement(nk: nkruntime.Nakama, accountId: string, entitlementId: string): void {
  if (!entitlementId) {
    return;
  }
  const now = nowUnix();
  const existing = StorageEntitlementProvider.getRecord(nk, accountId, entitlementId);
  const rec: EntitlementRecord = {
    entitlement_id: entitlementId,
    user_id: accountId,
    status: "revoked",
    starts_at: existing ? existing.starts_at : now,
    expires_at: now,
    source: existing ? existing.source : "iap_refund",
    updated_at: now,
  };
  nk.storageWrite([
    {
      collection: ENTITLEMENT_COLLECTION,
      key: entitlementId,
      userId: accountId,
      value: rec,
      permissionRead: 1,
      permissionWrite: 0,
    },
  ]);
}

function listPaidQueueEntitlements(nk: nkruntime.Nakama, accountId: string): EntitlementRecord[] {
  const out: EntitlementRecord[] = [];
  for (let i = 0; i < PAID_QUEUE_ENTITLEMENT_IDS.length; i++) {
    const rec = StorageEntitlementProvider.getRecord(nk, accountId, PAID_QUEUE_ENTITLEMENT_IDS[i]);
    if (rec) {
      out.push(rec);
    }
  }
  return out;
}

function publicWallet(nk: nkruntime.Nakama, accountId: string, env?: { [key: string]: string }): any {
  const wallet = readDiamondWalletObj(nk, accountId).value;
  const rows = listLedgerRecords(nk, accountId);
  const spendCents = eligibleBetaSpendCents(rows);
  const payload: any = {
    account_id: accountId,
    diamonds: wallet.balance,
    diamond_debt: wallet.diamond_debt,
    scope: "ACCOUNT",
    beta_program_id: COMMERCE_BETA_PROGRAM_ID,
    eligible_beta_spend_usd: spendCents / 100,
    eligible_beta_spend_cents: spendCents,
    future_voucher_usd: computeBetaVoucherUsd(spendCents),
    entitlements: listPaidQueueEntitlements(nk, accountId),
  };
  return attachBetaCommercePublicFields(nk, accountId, payload, env);
}

function deliverCatalogProduct(
  nk: nkruntime.Nakama,
  accountId: string,
  product: CommerceProductDef,
  deliveryTxId: string
): { ok: boolean; error?: string } {
  if (product.delivery_type === DELIVERY_PERMANENT_ENTITLEMENT) {
    writePaidQueueEntitlement(nk, accountId, product.entitlement_id, 0, "iap_validated");
    return { ok: true };
  }
  if (product.delivery_type === DELIVERY_TIMED_ENTITLEMENT) {
    writePaidQueueEntitlement(nk, accountId, product.entitlement_id, product.duration_seconds, "iap_validated");
    return { ok: true };
  }
  if (product.delivery_type === DELIVERY_DIAMONDS) {
    const g = grantDiamondsIdempotent(nk, accountId, product.diamond_amount, deliveryTxId);
    if (!g.ok) {
      return { ok: false, error: g.error || "Diamond grant failed" };
    }
    return { ok: true };
  }
  if (
    product.delivery_type === DELIVERY_ACCOUNT_COLLECTION ||
    product.delivery_type === DELIVERY_CONSUMABLE_ITEM ||
    product.delivery_type === DELIVERY_SUBSCRIPTION
  ) {
    return { ok: false, error: "Delivery type not implemented in Batch 4B" };
  }
  return { ok: false, error: "Unknown delivery type" };
}

interface PurchaseReversalResult {
  ok: boolean;
  already: boolean;
  granted: boolean;
  error?: string;
  ledger?: PurchaseLedgerRecord;
  wallet?: { balance: number; diamond_debt: number };
}

function diamondAmountForReversal(
  nk: nkruntime.Nakama,
  rec: PurchaseLedgerRecord,
  product: CommerceProductDef | null
): number {
  if (product && product.delivery_type === DELIVERY_DIAMONDS) {
    return Math.max(0, Math.floor(Number(product.diamond_amount || 0)));
  }
  if (rec.delivery_type === DELIVERY_DIAMONDS) {
    const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(rec.platform, rec.platform_transaction_id);
    const wallet = readDiamondWalletObj(nk, rec.account_id).value;
    const grant = wallet.processed_refs[deliveryRef];
    if (grant && grant.type === "grant") {
      return Math.max(0, Math.floor(Number(grant.amount || 0)));
    }
  }
  return 0;
}

function wasDiamondDeliveryApplied(nk: nkruntime.Nakama, rec: PurchaseLedgerRecord): boolean {
  if (rec.original_delivery_status === PURCHASE_DELIVERED || rec.delivery_status === PURCHASE_DELIVERED) {
    return rec.delivery_type === DELIVERY_DIAMONDS || !!lookupCommerceProduct(rec.product_id);
  }
  const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(rec.platform, rec.platform_transaction_id);
  if (!deliveryRef) {
    return false;
  }
  const grant = readDiamondWalletObj(nk, rec.account_id).value.processed_refs[deliveryRef];
  return !!(grant && grant.type === "grant");
}

function processPurchaseReversal(
  nk: nkruntime.Nakama,
  accountId: string,
  platform: string,
  txId: string,
  reasonRaw: string,
  productIdHint?: string
): PurchaseReversalResult {
  const uid = String(accountId || "").trim();
  const plat = String(platform || "").trim();
  const txn = String(txId || "").trim();
  if (!uid || !plat || !txn) {
    return { ok: false, already: false, granted: false, error: "Invalid reversal target" };
  }
  const reason = normalizeReversalReason(reasonRaw);
  const existing = readLedger(nk, uid, plat, txn);
  if (existing && existing.value.account_id && existing.value.account_id !== uid) {
    return { ok: false, already: false, granted: false, error: "account_mismatch" };
  }

  let rec: PurchaseLedgerRecord;
  let ver: string;
  if (existing) {
    rec = existing.value;
    ver = existing.version;
  } else {
    const hint = String(productIdHint || "").trim();
    const product = lookupCommerceProduct(hint);
    if (!product) {
      return { ok: true, already: true, granted: false, error: "ignored_unknown_product" };
    }
    rec = {
      account_id: uid,
      platform: plat,
      platform_transaction_id: txn,
      product_id: product.product_id,
      purchase_source: purchaseSourceForPlatform(plat),
      purchase_timestamp: nowUnix(),
      validation_status: reason,
      delivery_status: reason,
      delivery_transaction_id: deliveryRefFor(plat, txn),
      refund_or_revocation_status: reason,
      verified_amount: product.usd_cents / 100,
      verified_currency: "USD",
      normalized_usd: product.usd_cents / 100,
      normalized_usd_cents: product.usd_cents,
      beta_program_id: COMMERCE_BETA_PROGRAM_ID,
      eligible_beta_spend_amount: 0,
      eligible_beta_spend_cents: 0,
      delivery_type: product.delivery_type,
      entitlement_id: product.entitlement_id,
      seen_before: false,
      updated_at: nowUnix(),
      original_delivery_status: PURCHASE_RECEIVED,
      refunded_at: nowUnix(),
      reversal_ref: reversalRefFor(plat, txn),
      reversal_reason: reason,
      reversal_applied: true,
    };
    writeLedger(nk, rec, "*");
    if (rec.entitlement_id) {
      revokePaidQueueEntitlement(nk, uid, rec.entitlement_id);
    }
    const wallet = readDiamondWalletObj(nk, uid).value;
    return {
      ok: true,
      already: false,
      granted: false,
      ledger: rec,
      wallet: { balance: wallet.balance, diamond_debt: wallet.diamond_debt },
    };
  }

  const product = lookupCommerceProduct(rec.product_id) || lookupCommerceProduct(String(productIdHint || ""));
  const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(plat, txn);
  const reversalRef = rec.reversal_ref || reversalRefFor(plat, txn);
  const deliveredDiamonds = wasDiamondDeliveryApplied(nk, rec);
  const reverseAmt = deliveredDiamonds ? diamondAmountForReversal(nk, rec, product) : 0;

  let walletResult = {
    ok: true,
    already: true,
    balance: readDiamondWalletObj(nk, uid).value.balance,
    diamond_debt: readDiamondWalletObj(nk, uid).value.diamond_debt,
    debit: 0,
    debt_added: 0,
  };
  if (reverseAmt > 0) {
    const reversed = reverseDiamondsIdempotent(nk, uid, reverseAmt, reversalRef, deliveryRef);
    if (!reversed.ok) {
      return { ok: false, already: false, granted: false, error: reversed.error || "Diamond reversal failed", ledger: rec };
    }
    walletResult = reversed;
  }

  if (rec.entitlement_id) {
    revokePaidQueueEntitlement(nk, uid, rec.entitlement_id);
  }

  const already = !!rec.reversal_applied && isLedgerReversed(rec);
  if (!rec.original_delivery_status) {
    rec.original_delivery_status = rec.delivery_status;
  }
  rec.delivery_status = reason;
  rec.refund_or_revocation_status = reason;
  rec.validation_status = reason;
  rec.eligible_beta_spend_amount = 0;
  rec.eligible_beta_spend_cents = 0;
  rec.refunded_at = rec.refunded_at || nowUnix();
  rec.reversal_ref = reversalRef;
  rec.reversal_reason = reason;
  rec.reversal_applied = true;
  rec.account_id = uid;
  rec.platform_transaction_id = rec.platform_transaction_id || txn;
  rec.delivery_transaction_id = deliveryRef;
  writeLedger(nk, rec, ver);

  return {
    ok: true,
    already: already && walletResult.already,
    granted: false,
    ledger: rec,
    wallet: { balance: walletResult.balance, diamond_debt: walletResult.diamond_debt },
  };
}

function applyRefundToLedger(
  nk: nkruntime.Nakama,
  rec: PurchaseLedgerRecord,
  _version: string
): PurchaseLedgerRecord {
  const result = processPurchaseReversal(
    nk,
    rec.account_id,
    rec.platform,
    rec.platform_transaction_id,
    PURCHASE_REFUNDED,
    rec.product_id
  );
  return result.ledger || rec;
}

function reconcileVoidedPurchase(
  nk: nkruntime.Nakama,
  accountId: string,
  platform: string,
  txId: string,
  productId: string,
  reason: string
): PurchaseReversalResult {
  return processPurchaseReversal(nk, accountId, platform, txId, reason || PURCHASE_VOIDED, productId);
}

function validatePlatformPurchase(
  nk: nkruntime.Nakama,
  userId: string,
  platform: string,
  receipt: string
): nkruntime.ValidatePurchaseResponse {
  const p = String(platform || "").toUpperCase();
  // persist=true is mandatory. Godot wrappers default persist=false and must not be used.
  if (p === "APPLE") {
    return nk.purchaseValidateApple(userId, receipt, true);
  }
  if (p === "GOOGLE") {
    return nk.purchaseValidateGoogle(userId, receipt, true);
  }
  throw Err("Unsupported platform");
}

function processValidatedPurchase(
  nk: nkruntime.Nakama,
  accountId: string,
  platform: string,
  vp: nkruntime.ValidatedPurchase
): PurchaseLedgerRecord {
  const txId = String(vp.transactionId || "").trim();
  if (!txId) {
    throw Err("Validated purchase missing transactionId");
  }
  const product = lookupCommerceProduct(String(vp.productId || ""));
  const existing = readLedger(nk, accountId, platform, txId);
  const refunded = Number(vp.refundTime || 0) > 0;

  if (!product || !product.production_deliverable) {
    const rec: PurchaseLedgerRecord = existing
      ? existing.value
      : {
          account_id: accountId,
          platform: platform,
          platform_transaction_id: txId,
          product_id: String(vp.productId || ""),
          purchase_source: purchaseSourceForPlatform(platform),
          purchase_timestamp: Number(vp.purchaseTime || nowUnix()),
          validation_status: PURCHASE_REJECTED,
          delivery_status: PURCHASE_REJECTED,
          delivery_transaction_id: "",
          refund_or_revocation_status: refunded ? PURCHASE_REFUNDED : "",
          verified_amount: 0,
          verified_currency: "",
          normalized_usd: 0,
          normalized_usd_cents: 0,
          beta_program_id: COMMERCE_BETA_PROGRAM_ID,
          eligible_beta_spend_amount: 0,
          eligible_beta_spend_cents: 0,
          delivery_type: "",
          entitlement_id: "",
          seen_before: !!vp.seenBefore,
          updated_at: nowUnix(),
        };
    rec.validation_status = PURCHASE_REJECTED;
    rec.delivery_status = PURCHASE_REJECTED;
    writeLedger(nk, rec, existing ? existing.version : "*");
    return rec;
  }

  if (existing && isLedgerReversed(existing.value)) {
    return existing.value;
  }

  if (existing && existing.value.delivery_status === PURCHASE_DELIVERED) {
    if (refunded) {
      return applyRefundToLedger(nk, existing.value, existing.version);
    }
    return existing.value;
  }

  const usd = product.usd_cents / 100;
  const eligibleCents = product.beta_spend_eligible ? product.usd_cents : 0;
  const deliveryTxId = "dlv_" + ledgerStorageKey(platform, txId);
  let rec: PurchaseLedgerRecord;
  let ver: string;
  if (existing) {
    rec = existing.value;
    ver = existing.version;
  } else {
    rec = {
      account_id: accountId,
      platform: platform,
      platform_transaction_id: txId,
      product_id: product.product_id,
      purchase_source: purchaseSourceForPlatform(platform),
      purchase_timestamp: Number(vp.purchaseTime || nowUnix()),
      validation_status: PURCHASE_RECEIVED,
      delivery_status: PURCHASE_RECEIVED,
      delivery_transaction_id: "",
      refund_or_revocation_status: "",
      verified_amount: usd,
      verified_currency: "USD",
      normalized_usd: usd,
      normalized_usd_cents: product.usd_cents,
      beta_program_id: COMMERCE_BETA_PROGRAM_ID,
      eligible_beta_spend_amount: eligibleCents / 100,
      eligible_beta_spend_cents: eligibleCents,
      delivery_type: product.delivery_type,
      entitlement_id: product.entitlement_id,
      seen_before: !!vp.seenBefore,
      updated_at: nowUnix(),
    };
    ver = "*";
  }

  rec.product_id = product.product_id;
  rec.purchase_source = purchaseSourceForPlatform(platform);
  rec.verified_amount = usd;
  rec.verified_currency = "USD";
  rec.normalized_usd = usd;
  rec.normalized_usd_cents = product.usd_cents;
  rec.qualifying_topup_diamonds = Math.max(0, Math.floor(Number(product.qualifying_topup_diamonds || 0)));
  rec.delivery_type = product.delivery_type;
  rec.entitlement_id = product.entitlement_id;
  rec.seen_before = !!vp.seenBefore;

  if (refunded) {
    rec.validation_status = PURCHASE_VALIDATED;
    return applyRefundToLedger(nk, rec, ver);
  }

  rec.validation_status = PURCHASE_VALIDATED;
  rec.delivery_status = PURCHASE_DELIVERING;
  rec.delivery_transaction_id = deliveryTxId;
  rec.eligible_beta_spend_amount = eligibleCents / 100;
  rec.eligible_beta_spend_cents = eligibleCents;
  rec.refund_or_revocation_status = "";
  writeLedger(nk, rec, ver);

  const delivered = deliverCatalogProduct(nk, accountId, product, deliveryTxId);
  const after = readLedger(nk, accountId, platform, txId);
  const afterVer = after ? after.version : "*";
  rec = after ? after.value : rec;
  if (!delivered.ok) {
    rec.delivery_status = PURCHASE_VALIDATED;
    writeLedger(nk, rec, afterVer);
    throw Err(delivered.error || "Delivery failed");
  }
  rec.delivery_status = PURCHASE_DELIVERED;
  rec.validation_status = PURCHASE_VALIDATED;
  writeLedger(nk, rec, afterVer);
  applyProductionQualifyingTopUp(nk, accountId, rec, product);
  return rec;
}

function restoreAccountPurchases(nk: nkruntime.Nakama, accountId: string): any {
  const rows = listLedgerRecords(nk, accountId);
  for (let i = 0; i < rows.length; i++) {
    const rec = rows[i];
    if (rec.delivery_status !== PURCHASE_DELIVERED) {
      continue;
    }
    if (rec.reversal_applied || isReversalStatus(rec.refund_or_revocation_status) || isReversalStatus(rec.delivery_status)) {
      continue;
    }
    if (rec.delivery_type === DELIVERY_PERMANENT_ENTITLEMENT && rec.entitlement_id) {
      writePaidQueueEntitlement(nk, accountId, rec.entitlement_id, 0, "iap_restore");
    }
    if (rec.delivery_type === DELIVERY_TIMED_ENTITLEMENT && rec.entitlement_id) {
      const still = StorageEntitlementProvider.getRecord(nk, accountId, rec.entitlement_id);
      if (still && still.status === "active") {
        continue;
      }
      // Timed restore re-asserts remaining expiry from ledger timestamp + duration; does not re-grant diamonds.
      const product = lookupCommerceProduct(rec.product_id);
      if (product && product.duration_seconds > 0) {
        const ends = rec.purchase_timestamp + product.duration_seconds;
        if (ends > nowUnix()) {
          writePaidQueueEntitlement(nk, accountId, rec.entitlement_id, ends - nowUnix(), "iap_restore");
        }
      }
    }
    // DIAMONDS / other consumables are NOT re-delivered on restore.
  }
  return publicWallet(nk, accountId);
}

function rpcCommerceGetWallet(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, _payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  return JSON.stringify({ ok: true, wallet: publicWallet(nk, ctx.userId, ctx.env) });
}

function rpcCommerceSpendDiamonds(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  const amount = Math.floor(Number(data["amount"] || 0));
  const reason = String(data["reason"] || "").trim();
  const clientRef = String(data["idempotency_key"] || data["spend_ref"] || "").trim();
  if (amount <= 0) {
    throw Err("Invalid amount");
  }
  if (!reason || !clientRef) {
    throw Err("reason and idempotency_key required");
  }
  const spendRef = "spend:" + reason + ":" + clientRef;
  const result = spendDiamondsIdempotent(nk, ctx.userId, amount, spendRef);
  if (!result.ok) {
    return JSON.stringify({ ok: false, error: result.error || "Spend failed", balance: result.balance });
  }
  return JSON.stringify({ ok: true, balance: result.balance, already: result.already, wallet: publicWallet(nk, ctx.userId, ctx.env) });
}

function rpcCommerceProcessPurchase(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  const platform = String(data["platform"] || "").toUpperCase();
  const receipt = String(data["receipt"] || data["purchase"] || "").trim();
  if (!receipt) {
    throw Err("receipt required");
  }
  if (platform !== "APPLE" && platform !== "GOOGLE") {
    throw Err("platform must be APPLE or GOOGLE");
  }
  // Client-submitted product_id / price / usd are ignored. Catalog lookup after validation is authority.
  let validated: nkruntime.ValidatePurchaseResponse;
  try {
    validated = validatePlatformPurchase(nk, ctx.userId, platform, receipt);
  } catch (e) {
    logger.error("IAP validation failed user=%s platform=%s", ctx.userId, platform);
    return JSON.stringify({
      ok: false,
      error: "validation_failed",
      delivered: false,
    });
  }
  const purchases = validated && validated.validatedPurchases ? validated.validatedPurchases : [];
  if (purchases.length === 0) {
    return JSON.stringify({ ok: false, error: "validation_failed", delivered: false, purchases: [] });
  }
  const results: PurchaseLedgerRecord[] = [];
  for (let i = 0; i < purchases.length; i++) {
    results.push(processValidatedPurchase(nk, ctx.userId, platform, purchases[i]));
  }
  return JSON.stringify({
    ok: true,
    purchases: results,
    wallet: publicWallet(nk, ctx.userId, ctx.env),
  });
}

function rpcCommerceGetPurchase(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  const platform = String(data["platform"] || "").toUpperCase();
  const txId = String(data["platform_transaction_id"] || "").trim();
  if (!platform || !txId) {
    throw Err("platform and platform_transaction_id required");
  }
  const existing = readLedger(nk, ctx.userId, platform, txId);
  if (!existing) {
    return JSON.stringify({ ok: false, error: "not_found" });
  }
  let rec = existing.value;
  if (isLedgerReversed(rec)) {
    return JSON.stringify({ ok: true, purchase: rec, wallet: publicWallet(nk, ctx.userId, ctx.env) });
  }
  if (rec.delivery_status === PURCHASE_VALIDATED || rec.delivery_status === PURCHASE_DELIVERING) {
    const product = lookupCommerceProduct(rec.product_id);
    if (product && product.production_deliverable) {
      const delivered = deliverCatalogProduct(nk, ctx.userId, product, rec.delivery_transaction_id || ("dlv_" + ledgerStorageKey(platform, txId)));
      const after = readLedger(nk, ctx.userId, platform, txId);
      rec = after ? after.value : rec;
      if (delivered.ok) {
        rec.delivery_status = PURCHASE_DELIVERED;
        writeLedger(nk, rec, after ? after.version : "*");
        applyProductionQualifyingTopUp(nk, ctx.userId, rec, product);
      }
    }
  }
  return JSON.stringify({ ok: true, purchase: rec, wallet: publicWallet(nk, ctx.userId, ctx.env) });
}

function rpcCommerceRestore(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, _payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const wallet = restoreAccountPurchases(nk, ctx.userId);
  return JSON.stringify({ ok: true, wallet: wallet, restored: true });
}

function rpcCommerceGetCatalog(ctx: nkruntime.Context, _logger: nkruntime.Logger, _nk: nkruntime.Nakama, _payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const live: any[] = [];
  for (let i = 0; i < COMMERCE_PRODUCT_CATALOG.length; i++) {
    const p = COMMERCE_PRODUCT_CATALOG[i];
    if (!p.production_deliverable) {
      continue;
    }
    live.push({
      product_id: p.product_id,
      iap_product_id: p.iap_product_id,
      usd_cents: p.usd_cents,
      delivery_type: p.delivery_type,
      repeatability: p.repeatability,
      diamond_amount: p.diamond_amount,
      qualifying_topup_diamonds: Math.max(0, Math.floor(Number(p.qualifying_topup_diamonds || 0))),
      beta_voucher_cost: Math.max(0, Math.floor(Number(p.beta_voucher_cost || 0))),
      beta_voucher_purchasable: !!p.beta_voucher_purchasable,
      duration_seconds: p.duration_seconds,
      entitlement_id: p.entitlement_id,
      beta_spend_eligible: p.beta_spend_eligible,
      live_store: !!p.live_store,
    });
  }
  return JSON.stringify({ ok: true, products: live });
}

function onGooglePurchaseNotification(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  purchase: nkruntime.ValidatedPurchase,
  _providerPayload: string,
  notificationType: nkruntime.IAPNotificationType
): void {
  const productId = String((purchase && purchase.productId) || "");
  const txId = String((purchase && purchase.transactionId) || "");
  const userId = String((purchase && purchase.userId) || (ctx && ctx.userId) || "");
  const ntype = String(notificationType || "");
  const refundTime = Number((purchase && purchase.refundTime) || 0);
  if (!isReversalNotification(ntype, refundTime)) {
    logger.info("Google purchase notification ignored type=%s product=%s", ntype, productId);
    return;
  }
  const product = lookupCommerceProduct(productId);
  if (!product) {
    logger.info("Google purchase notification ignored unknown product=%s", productId);
    return;
  }
  if (!userId || !txId) {
    logger.error("Google purchase notification missing user or transaction product=%s", productId);
    return;
  }
  const result = processPurchaseReversal(nk, userId, "GOOGLE", txId, ntype, productId);
  logger.info(
    "Google purchase reversal product=%s ok=%s already=%s reason=%s",
    productId,
    String(result.ok),
    String(result.already),
    normalizeReversalReason(ntype)
  );
}
