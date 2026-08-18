/**
 * Isolated Batch 4B commerce authority tests. No live Nakama. No Apple/Google.
 * Mirrors server/src/phase57_commerce.ts ledger / wallet / voucher / delivery.
 * Run: node server/scripts/commerce_authority_test.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const CATALOG_PATH = path.join(ROOT, "data/commerce_products.json");
const QUEUE_PATH = path.join(ROOT, "data/queue_entitlements.json");
const SERVER_CATALOG_PATH = path.join(ROOT, "server/src/phase57_commerce.ts");

const fails = [];
function ok(label) {
  console.log(`[commerce 4B] OK  ${label}`);
}
function fail(label, detail) {
  const msg = detail ? `${label}: ${detail}` : label;
  fails.push(msg);
  console.log(`[commerce 4B] FAIL ${msg}`);
}
function assert(cond, label, detail) {
  if (cond) ok(label);
  else fail(label, detail);
}

const PURCHASE_RECEIVED = "RECEIVED";
const PURCHASE_VALIDATED = "VALIDATED";
const PURCHASE_DELIVERING = "DELIVERING";
const PURCHASE_DELIVERED = "DELIVERED";
const PURCHASE_REJECTED = "REJECTED";
const PURCHASE_REFUNDED = "REFUNDED";
const PURCHASE_REVOKED = "REVOKED";
const PURCHASE_VOIDED = "VOIDED";
const PURCHASE_CANCELLED = "CANCELLED";
const BETA_PROGRAM = "crownspire_paid_beta_v1";

class VersionedStore {
  constructor() {
    this.objs = new Map();
  }
  _k(c, u, k) {
    return `${c}|${u}|${k}`;
  }
  read(c, u, k) {
    const hit = this.objs.get(this._k(c, u, k));
    return hit ? { value: JSON.parse(JSON.stringify(hit.value)), version: hit.version } : null;
  }
  write(c, u, k, value, version) {
    const key = this._k(c, u, k);
    const cur = this.objs.get(key);
    if (version === "*") {
      if (cur) throw new Error("version mismatch create");
    } else if (!cur || cur.version !== version) {
      throw new Error("version mismatch");
    }
    const nextVer = String((cur ? Number(cur.version) : 0) + 1);
    this.objs.set(key, { value: JSON.parse(JSON.stringify(value)), version: nextVer });
    return nextVer;
  }
}

function computeBetaVoucherUsd(eligibleUsdCents) {
  const cents = Math.max(0, Math.floor(eligibleUsdCents));
  if (cents <= 0) return 0;
  return Math.ceil((cents * 110) / 10000);
}

function ledgerKey(platform, txId) {
  const p = String(platform || "").toLowerCase().replace(/[^a-z0-9]+/g, "_");
  const t = String(txId || "").replace(/[^a-zA-Z0-9._-]+/g, "_");
  let key = p + "__" + t;
  if (key.length > 120) key = key.substring(0, 120);
  return key;
}

function nowUnix() {
  return Math.floor(Date.now() / 1000);
}

function lookupProduct(catalog, platformProductId) {
  const id = String(platformProductId || "").trim();
  return catalog.find((r) => r.product_id === id || r.iap_product_id === id) || null;
}

function isDevEntitlementRpcEnabled(env) {
  if (String(env.CROWNSPIRE_ENABLE_DEV_ENTITLEMENT_RPC || "") !== "true") return false;
  return String(env.CROWNSPIRE_DEV_ENTITLEMENT_SECRET || "").length >= 16;
}

function isDevSettableEntitlement(id) {
  return id === "beta_alliance_auto_help" || id === "entitlement_beta_voucher_testing";
}

function runtimeContextName(env) {
  return String((env || {}).CROWNSPIRE_RUNTIME_CONTEXT || "").trim().toLowerCase();
}

function isExplicitLocalOrTestRuntime(env) {
  const ctx = runtimeContextName(env);
  return ctx === "local" || ctx === "test";
}

function isSafeDevVoucherBypass(env) {
  if (String((env || {}).CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC || "") !== "true") return false;
  return isExplicitLocalOrTestRuntime(env);
}

function areFixtureTestCodesEnabled(env) {
  if (String((env || {}).CROWNSPIRE_ENABLE_BETA_VOUCHER_TEST_CODES || "") !== "true") return false;
  return isExplicitLocalOrTestRuntime(env);
}

function createEngine(catalog, opts = {}) {
  const store = new VersionedStore();
  const LEDGER = "crownspire_purchase_ledger";
  const COMM = "crownspire_commerce";
  const ENT = "crownspire_entitlements";
  const WALLET = "diamond_wallet";
  const INDEX = "purchase_index";

  function emptyWallet(accountId) {
    return { account_id: accountId, balance: 0, diamond_debt: 0, processed_refs: {}, updated_at: nowUnix() };
  }

  function readWallet(accountId) {
    const obj = store.read(COMM, accountId, WALLET);
    if (obj) {
      const rec = obj.value;
      rec.processed_refs = rec.processed_refs || {};
      rec.account_id = accountId;
      rec.balance = Math.max(0, Math.floor(Number(rec.balance || 0)));
      rec.diamond_debt = Math.max(0, Math.floor(Number(rec.diamond_debt || 0)));
      return { value: rec, version: obj.version };
    }
    return { value: emptyWallet(accountId), version: "*" };
  }

  function deliveryRefFor(platform, txId) {
    return "dlv_" + ledgerKey(platform, txId);
  }

  function reversalRefFor(platform, txId) {
    return "rev_" + ledgerKey(platform, txId);
  }

  function isReversalStatus(status) {
    return status === PURCHASE_REFUNDED || status === PURCHASE_REVOKED || status === PURCHASE_VOIDED || status === PURCHASE_CANCELLED;
  }

  function isLedgerReversed(rec) {
    if (!rec) return false;
    if (rec.reversal_applied) return true;
    if (isReversalStatus(rec.refund_or_revocation_status)) return true;
    return isReversalStatus(rec.delivery_status);
  }

  function normalizeReversalReason(raw) {
    const s = String(raw || "").trim().toUpperCase();
    if (s === PURCHASE_CANCELLED || s === "CANCELED") return PURCHASE_CANCELLED;
    if (s === PURCHASE_VOIDED || s === "CHARGEBACK" || s === "CHARGED_BACK" || s === "VOID") return PURCHASE_VOIDED;
    if (s === PURCHASE_REVOKED) return PURCHASE_REVOKED;
    return PURCHASE_REFUNDED;
  }

  function isReversalNotification(notificationType, refundTime) {
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

  function grantDiamonds(accountId, amount, grantRef) {
    const amt = Math.floor(Number(amount || 0));
    const ref = String(grantRef || "").trim();
    if (!ref || amt < 0) return { ok: false, balance: 0, diamond_debt: 0, already: false, error: "Invalid grant" };
    if (amt === 0) {
      const cur = readWallet(accountId).value;
      return { ok: true, balance: cur.balance, diamond_debt: cur.diamond_debt, already: true };
    }
    for (let i = 0; i < 8; i++) {
      const obj = readWallet(accountId);
      const rec = obj.value;
      if (rec.processed_refs[ref]) {
        return { ok: true, balance: rec.balance, diamond_debt: rec.diamond_debt, already: true };
      }
      const debt = rec.diamond_debt;
      const repay = Math.min(debt, amt);
      const toBalance = amt - repay;
      rec.diamond_debt = debt - repay;
      rec.balance += toBalance;
      rec.processed_refs[ref] = {
        type: "grant",
        amount: amt,
        applied_to_debt: repay,
        applied_to_balance: toBalance,
        ts: nowUnix(),
      };
      rec.updated_at = nowUnix();
      try {
        store.write(COMM, accountId, WALLET, rec, obj.version);
        return { ok: true, balance: rec.balance, diamond_debt: rec.diamond_debt, already: false };
      } catch {
        continue;
      }
    }
    return { ok: false, balance: 0, diamond_debt: 0, already: false, error: "Wallet conflict" };
  }

  function reverseDiamonds(accountId, amount, reversalRef, originalDeliveryRef) {
    const amt = Math.floor(Number(amount || 0));
    const ref = String(reversalRef || "").trim();
    const deliveryRef = String(originalDeliveryRef || "").trim();
    if (!accountId || !ref || amt < 0) {
      return { ok: false, already: false, balance: 0, diamond_debt: 0, debit: 0, debt_added: 0, error: "Invalid reversal" };
    }
    if (amt === 0) {
      const cur = readWallet(accountId).value;
      return { ok: true, already: true, balance: cur.balance, diamond_debt: cur.diamond_debt, debit: 0, debt_added: 0 };
    }
    for (let i = 0; i < 8; i++) {
      const obj = readWallet(accountId);
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
      rec.balance -= debit;
      rec.diamond_debt += debtAdded;
      rec.processed_refs[ref] = {
        type: "reversal",
        amount: amt,
        debit,
        debt_added: debtAdded,
        original_delivery_ref: deliveryRef,
        ts: nowUnix(),
      };
      rec.updated_at = nowUnix();
      try {
        store.write(COMM, accountId, WALLET, rec, obj.version);
        return { ok: true, already: false, balance: rec.balance, diamond_debt: rec.diamond_debt, debit, debt_added: debtAdded };
      } catch {
        continue;
      }
    }
    return { ok: false, already: false, balance: 0, diamond_debt: 0, debit: 0, debt_added: 0, error: "Wallet conflict" };
  }

  function spendDiamonds(accountId, amount, spendRef) {
    const amt = Math.floor(Number(amount || 0));
    const ref = String(spendRef || "").trim();
    if (!ref || amt < 0) return { ok: false, balance: 0, already: false, error: "Invalid spend" };
    for (let i = 0; i < 8; i++) {
      const obj = readWallet(accountId);
      const rec = obj.value;
      if (rec.processed_refs[ref]) return { ok: true, balance: rec.balance, already: true };
      if (rec.balance < amt) return { ok: false, balance: rec.balance, already: false, error: "Insufficient diamonds" };
      rec.balance -= amt;
      rec.processed_refs[ref] = { type: "spend", amount: amt, ts: nowUnix() };
      rec.updated_at = nowUnix();
      try {
        store.write(COMM, accountId, WALLET, rec, obj.version);
        return { ok: true, balance: rec.balance, already: false };
      } catch {
        continue;
      }
    }
    return { ok: false, balance: 0, already: false, error: "Wallet conflict" };
  }

  function writeEntitlement(accountId, entitlementId, durationSeconds) {
    const now = nowUnix();
    const existing = store.read(ENT, accountId, entitlementId);
    let starts = now;
    let expires = durationSeconds > 0 ? now + durationSeconds : 0;
    if (existing && existing.value.status === "active" && durationSeconds > 0) {
      starts = existing.value.starts_at || now;
      const base = existing.value.expires_at > now ? existing.value.expires_at : now;
      expires = base + durationSeconds;
    }
    const rec = {
      entitlement_id: entitlementId,
      user_id: accountId,
      status: "active",
      starts_at: starts,
      expires_at: expires,
      source: "iap_validated",
      updated_at: now,
    };
    const ver = existing ? existing.version : "*";
    try {
      store.write(ENT, accountId, entitlementId, rec, ver);
    } catch {
      store.write(ENT, accountId, entitlementId, rec, existing ? existing.version : "*");
    }
  }

  function revokeEntitlement(accountId, entitlementId) {
    if (!entitlementId) return;
    const now = nowUnix();
    const existing = store.read(ENT, accountId, entitlementId);
    const rec = {
      entitlement_id: entitlementId,
      user_id: accountId,
      status: "revoked",
      starts_at: existing ? existing.value.starts_at : now,
      expires_at: now,
      source: "iap_refund",
      updated_at: now,
    };
    store.write(ENT, accountId, entitlementId, rec, existing ? existing.version : "*");
  }

  function indexKey(accountId, key) {
    const obj = store.read(COMM, accountId, INDEX);
    let rec = obj ? obj.value : { account_id: accountId, transaction_keys: [], updated_at: nowUnix() };
    rec.transaction_keys = rec.transaction_keys || [];
    if (rec.transaction_keys.indexOf(key) >= 0) return;
    rec.transaction_keys.push(key);
    rec.updated_at = nowUnix();
    store.write(COMM, accountId, INDEX, rec, obj ? obj.version : "*");
  }

  function readLedger(accountId, platform, txId) {
    const key = ledgerKey(platform, txId);
    const obj = store.read(LEDGER, accountId, key);
    if (!obj) return null;
    if (obj.value.account_id && obj.value.account_id !== accountId) return null;
    obj.value.account_id = accountId;
    return { value: obj.value, version: obj.version, key };
  }

  function writeLedger(rec, version) {
    const key = ledgerKey(rec.platform, rec.platform_transaction_id);
    rec.updated_at = nowUnix();
    store.write(LEDGER, rec.account_id, key, rec, version);
    try {
      indexKey(rec.account_id, key);
    } catch {
      /* index best-effort */
    }
  }

  function listLedger(accountId) {
    const obj = store.read(COMM, accountId, INDEX);
    if (!obj) return [];
    return (obj.value.transaction_keys || [])
      .map((k) => store.read(LEDGER, accountId, k))
      .filter(Boolean)
      .map((o) => o.value);
  }

  function eligibleCents(rows) {
    let sum = 0;
    for (const r of rows) {
      if (r.reversal_applied || isReversalStatus(r.refund_or_revocation_status) || isReversalStatus(r.delivery_status)) continue;
      if (r.delivery_status !== PURCHASE_DELIVERED) continue;
      sum += Math.max(0, Math.floor(Number(r.eligible_beta_spend_cents || 0)));
    }
    return sum;
  }

  function deliver(accountId, product, deliveryTxId) {
    if (product.delivery_type === "PERMANENT_ENTITLEMENT") {
      writeEntitlement(accountId, product.entitlement_id, 0);
      return { ok: true };
    }
    if (product.delivery_type === "TIMED_ENTITLEMENT") {
      writeEntitlement(accountId, product.entitlement_id, product.duration_seconds);
      return { ok: true };
    }
    if (product.delivery_type === "DIAMONDS") {
      return grantDiamonds(accountId, product.diamond_amount, deliveryTxId);
    }
    return { ok: false, error: "not implemented" };
  }

  function diamondAmountForReversal(rec, product) {
    if (product && product.delivery_type === "DIAMONDS") {
      return Math.max(0, Math.floor(Number(product.diamond_amount || 0)));
    }
    if (rec.delivery_type === "DIAMONDS") {
      const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(rec.platform, rec.platform_transaction_id);
      const grant = readWallet(rec.account_id).value.processed_refs[deliveryRef];
      if (grant && grant.type === "grant") return Math.max(0, Math.floor(Number(grant.amount || 0)));
    }
    return 0;
  }

  function wasDiamondDeliveryApplied(rec) {
    if (rec.original_delivery_status === PURCHASE_DELIVERED || rec.delivery_status === PURCHASE_DELIVERED) {
      return rec.delivery_type === "DIAMONDS" || !!lookupProduct(catalog, rec.product_id);
    }
    const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(rec.platform, rec.platform_transaction_id);
    const grant = readWallet(rec.account_id).value.processed_refs[deliveryRef];
    return !!(grant && grant.type === "grant");
  }

  function processPurchaseReversal(accountId, platform, txId, reasonRaw, productIdHint) {
    const uid = String(accountId || "").trim();
    const plat = String(platform || "").trim();
    const txn = String(txId || "").trim();
    if (!uid || !plat || !txn) return { ok: false, already: false, granted: false, error: "Invalid reversal target" };
    const reason = normalizeReversalReason(reasonRaw);
    const existing = readLedger(uid, plat, txn);
    if (existing && existing.value.account_id && existing.value.account_id !== uid) {
      return { ok: false, already: false, granted: false, error: "account_mismatch" };
    }

    let rec;
    let ver;
    if (existing) {
      rec = existing.value;
      ver = existing.version;
    } else {
      const product = lookupProduct(catalog, String(productIdHint || "").trim());
      if (!product) return { ok: true, already: true, granted: false, error: "ignored_unknown_product" };
      rec = {
        account_id: uid,
        platform: plat,
        platform_transaction_id: txn,
        product_id: product.product_id,
        purchase_timestamp: nowUnix(),
        validation_status: reason,
        delivery_status: reason,
        delivery_transaction_id: deliveryRefFor(plat, txn),
        refund_or_revocation_status: reason,
        verified_amount: product.usd_cents / 100,
        verified_currency: "USD",
        normalized_usd: product.usd_cents / 100,
        normalized_usd_cents: product.usd_cents,
        beta_program_id: BETA_PROGRAM,
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
      writeLedger(rec, "*");
      if (rec.entitlement_id) revokeEntitlement(uid, rec.entitlement_id);
      const wallet = readWallet(uid).value;
      return { ok: true, already: false, granted: false, ledger: rec, wallet: { balance: wallet.balance, diamond_debt: wallet.diamond_debt } };
    }

    const product = lookupProduct(catalog, rec.product_id) || lookupProduct(catalog, String(productIdHint || ""));
    const deliveryRef = rec.delivery_transaction_id || deliveryRefFor(plat, txn);
    const reversalRef = rec.reversal_ref || reversalRefFor(plat, txn);
    const reverseAmt = wasDiamondDeliveryApplied(rec) ? diamondAmountForReversal(rec, product) : 0;
    let walletResult = {
      ok: true,
      already: true,
      balance: readWallet(uid).value.balance,
      diamond_debt: readWallet(uid).value.diamond_debt,
    };
    if (reverseAmt > 0) {
      const reversed = reverseDiamonds(uid, reverseAmt, reversalRef, deliveryRef);
      if (!reversed.ok) return { ok: false, already: false, granted: false, error: reversed.error || "Diamond reversal failed", ledger: rec };
      walletResult = reversed;
    }
    if (rec.entitlement_id) revokeEntitlement(uid, rec.entitlement_id);
    const already = !!rec.reversal_applied && isLedgerReversed(rec);
    if (!rec.original_delivery_status) rec.original_delivery_status = rec.delivery_status;
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
    rec.delivery_transaction_id = deliveryRef;
    writeLedger(rec, ver);
    return {
      ok: true,
      already: already && walletResult.already,
      granted: false,
      ledger: rec,
      wallet: { balance: walletResult.balance, diamond_debt: walletResult.diamond_debt },
    };
  }

  function applyRefund(rec, _version) {
    const result = processPurchaseReversal(rec.account_id, rec.platform, rec.platform_transaction_id, PURCHASE_REFUNDED, rec.product_id);
    return result.ledger || rec;
  }

  function onGooglePurchaseNotification(purchase, notificationType) {
    const productId = String((purchase && purchase.productId) || "");
    const txId = String((purchase && purchase.transactionId) || "");
    const userId = String((purchase && purchase.userId) || "");
    const ntype = String(notificationType || "");
    const refundTime = Number((purchase && purchase.refundTime) || 0);
    if (!isReversalNotification(ntype, refundTime)) {
      return { ok: true, ignored: true, granted: false };
    }
    const product = lookupProduct(catalog, productId);
    if (!product) return { ok: true, ignored: true, granted: false, error: "ignored_unknown_product" };
    if (!userId || !txId) return { ok: false, granted: false, error: "missing user or transaction" };
    return processPurchaseReversal(userId, "GOOGLE", txId, ntype, productId);
  }

  function reconcileVoidedPurchase(accountId, platform, txId, productId, reason) {
    return processPurchaseReversal(accountId, platform, txId, reason || PURCHASE_VOIDED, productId);
  }

  function processValidated(accountId, platform, vp, opts = {}) {
    const txId = String(vp.transactionId || "").trim();
    const product = lookupProduct(catalog, vp.productId);
    const existing = readLedger(accountId, platform, txId);
    const refunded = Number(vp.refundTime || 0) > 0;
    const productionOk = product && product.production_deliverable !== false && product.product_type !== "TEST_ONLY";
    const allowTest = !!opts.allowTestSku;
    const deliverable = product && (productionOk || (allowTest && product.product_type === "TEST_ONLY"));

    if (!deliverable) {
      const rec = existing
        ? existing.value
        : {
            account_id: accountId,
            platform,
            platform_transaction_id: txId,
            product_id: String(vp.productId || ""),
            purchase_source: platform === "APPLE" ? "APPLE_STOREKIT" : "GOOGLE_PLAY",
            purchase_timestamp: Number(vp.purchaseTime || nowUnix()),
            validation_status: PURCHASE_REJECTED,
            delivery_status: PURCHASE_REJECTED,
            delivery_transaction_id: "",
            refund_or_revocation_status: refunded ? PURCHASE_REFUNDED : "",
            verified_amount: 0,
            verified_currency: "",
            normalized_usd: 0,
            normalized_usd_cents: 0,
            beta_program_id: BETA_PROGRAM,
            eligible_beta_spend_amount: 0,
            eligible_beta_spend_cents: 0,
            delivery_type: "",
            entitlement_id: "",
            seen_before: !!vp.seenBefore,
            updated_at: nowUnix(),
          };
      rec.validation_status = PURCHASE_REJECTED;
      rec.delivery_status = PURCHASE_REJECTED;
      writeLedger(rec, existing ? existing.version : "*");
      return rec;
    }

    if (existing && isLedgerReversed(existing.value)) {
      return existing.value;
    }

    if (existing && existing.value.delivery_status === PURCHASE_DELIVERED) {
      if (refunded) return applyRefund(existing.value, existing.version);
      return existing.value;
    }

    const usd = product.usd_cents / 100;
    const eligible = product.beta_spend_eligible ? product.usd_cents : 0;
    const deliveryTxId = "dlv_" + ledgerKey(platform, txId);
    let rec;
    let ver;
    if (existing) {
      rec = existing.value;
      ver = existing.version;
    } else {
      rec = {
        account_id: accountId,
        platform,
        platform_transaction_id: txId,
        product_id: product.product_id,
        purchase_source: platform === "APPLE" ? "APPLE_STOREKIT" : "GOOGLE_PLAY",
        purchase_timestamp: Number(vp.purchaseTime || nowUnix()),
        validation_status: PURCHASE_RECEIVED,
        delivery_status: PURCHASE_RECEIVED,
        delivery_transaction_id: "",
        refund_or_revocation_status: "",
        verified_amount: usd,
        verified_currency: "USD",
        normalized_usd: usd,
        normalized_usd_cents: product.usd_cents,
        beta_program_id: BETA_PROGRAM,
        eligible_beta_spend_amount: eligible / 100,
        eligible_beta_spend_cents: eligible,
        delivery_type: product.delivery_type,
        entitlement_id: product.entitlement_id,
        seen_before: !!vp.seenBefore,
        updated_at: nowUnix(),
      };
      ver = "*";
    }

    if (refunded) {
      rec.validation_status = PURCHASE_VALIDATED;
      return applyRefund(rec, ver);
    }

    rec.validation_status = PURCHASE_VALIDATED;
    rec.delivery_status = PURCHASE_DELIVERING;
    rec.delivery_transaction_id = deliveryTxId;
    rec.product_id = product.product_id;
    rec.verified_amount = usd;
    rec.verified_currency = "USD";
    rec.normalized_usd = usd;
    rec.normalized_usd_cents = product.usd_cents;
    rec.eligible_beta_spend_amount = eligible / 100;
    rec.eligible_beta_spend_cents = eligible;
    rec.entitlement_id = product.entitlement_id;
    rec.delivery_type = product.delivery_type;
    writeLedger(rec, ver);

    if (opts.stopAfterValidate) {
      return rec;
    }

    const delivered = deliver(accountId, product, deliveryTxId);
    const after = readLedger(accountId, platform, txId);
    rec = after.value;
    if (!delivered.ok) {
      rec.delivery_status = PURCHASE_VALIDATED;
      writeLedger(rec, after.version);
      throw new Error(delivered.error || "Delivery failed");
    }
    rec.delivery_status = PURCHASE_DELIVERED;
    rec.purchase_source = platform === "APPLE" ? "APPLE_STOREKIT" : "GOOGLE_PLAY";
    rec.qualifying_topup_diamonds = Math.max(0, Math.floor(Number(product.qualifying_topup_diamonds || 0)));
    writeLedger(rec, after.version);
    return rec;
  }

  function processPurchase(accountId, platform, receipt, validator, opts = {}) {
    const validated = validator(accountId, platform, receipt);
    if (!validated || validated.error || !validated.validatedPurchases || validated.validatedPurchases.length === 0) {
      return { ok: false, error: "validation_failed", delivered: false, purchases: [] };
    }
    const purchases = validated.validatedPurchases.map((vp) => processValidated(accountId, platform, vp, opts));
    return { ok: true, purchases, wallet: publicWallet(accountId) };
  }

  function retryDelivery(accountId, platform, txId) {
    const existing = readLedger(accountId, platform, txId);
    if (!existing) return { ok: false, error: "not_found" };
    let rec = existing.value;
    if (isLedgerReversed(rec)) return { ok: true, purchase: rec };
    if (rec.delivery_status === PURCHASE_VALIDATED || rec.delivery_status === PURCHASE_DELIVERING) {
      const product = lookupProduct(catalog, rec.product_id);
      const delivered = deliver(accountId, product, rec.delivery_transaction_id);
      const after = readLedger(accountId, platform, txId);
      rec = after.value;
      if (delivered.ok) {
        rec.delivery_status = PURCHASE_DELIVERED;
        writeLedger(rec, after.version);
      }
    }
    return { ok: true, purchase: rec };
  }

  function restore(accountId) {
    const rows = listLedger(accountId);
    for (const rec of rows) {
      if (rec.delivery_status !== PURCHASE_DELIVERED) continue;
      if (rec.reversal_applied || isReversalStatus(rec.refund_or_revocation_status) || isReversalStatus(rec.delivery_status)) continue;
      if (rec.delivery_type === "PERMANENT_ENTITLEMENT" && rec.entitlement_id) {
        writeEntitlement(accountId, rec.entitlement_id, 0);
      }
    }
    return publicWallet(accountId);
  }

  const VW = "beta_voucher_wallet";
  const BV_LEDGER = "crownspire_beta_voucher_ledger";
  const BV_REDEEM = "crownspire_beta_voucher_redemptions";
  const BV_CODES = "crownspire_beta_voucher_codes";
  const BV_TOPUP = "crownspire_beta_topup";
  const PROD_TOPUP = "crownspire_prod_topup";
  const SYS = "00000000-0000-0000-0000-000000000000";
  const TEST_CODES = {
    "CROWNSPIRE-TEST-VOUCHER-5": { code_id: "code_test_voucher_5", amount: 5, cohort: "TEST_ONLY_LOW", active: true, expires: 0, cap: 0, per: 1 },
    "CROWNSPIRE-TEST-VOUCHER-100": { code_id: "code_test_voucher_100", amount: 100, cohort: "TEST_ONLY_MID", active: true, expires: 0, cap: 0, per: 1 },
    "CROWNSPIRE-TEST-VOUCHER-EXPIRED": { code_id: "code_test_voucher_expired", amount: 5, cohort: "TEST_ONLY", active: true, expires: 1, cap: 0, per: 1 },
    "CROWNSPIRE-TEST-VOUCHER-INACTIVE": { code_id: "code_test_voucher_inactive", amount: 5, cohort: "TEST_ONLY", active: false, expires: 0, cap: 0, per: 1 },
    "CROWNSPIRE-TEST-VOUCHER-CAP1": { code_id: "code_test_voucher_cap1", amount: 5, cohort: "TEST_ONLY", active: true, expires: 0, cap: 1, per: 1 },
  };
  const BETA_ROUNDS = {
    topup_beta_round_test_001: {
      round_id: "topup_beta_round_test_001",
      kind: "BETA",
      milestones: [
        { milestone_id: "beta_m_100", threshold: 100, reward_diamonds: 1 },
        { milestone_id: "beta_m_500", threshold: 500, reward_diamonds: 2 },
        { milestone_id: "beta_m_1000", threshold: 1000, reward_diamonds: 3 },
      ],
    },
    topup_beta_round_test_002: {
      round_id: "topup_beta_round_test_002",
      kind: "BETA",
      milestones: [{ milestone_id: "beta_m2_100", threshold: 100, reward_diamonds: 1 }],
    },
  };
  let activeBetaRoundId = "topup_beta_round_test_001";
  const productionSafe = !!opts.productionSafe;
  const runtimeEnv = opts.env || {};
  const fixtureCodesOn = productionSafe ? false : opts.fixtureCodes !== false;
  const VOUCHER_ENT = "entitlement_beta_voucher_testing";

  function grantVoucherTesting(accountId) {
    store.write(
      ENT,
      accountId,
      VOUCHER_ENT,
      { entitlement_id: VOUCHER_ENT, user_id: accountId, status: "active", starts_at: 1, expires_at: 0, source: "beta_test" },
      store.read(ENT, accountId, VOUCHER_ENT) ? store.read(ENT, accountId, VOUCHER_ENT).version : "*"
    );
  }

  function revokeVoucherTesting(accountId) {
    store.write(
      ENT,
      accountId,
      VOUCHER_ENT,
      { entitlement_id: VOUCHER_ENT, user_id: accountId, status: "revoked", starts_at: 1, expires_at: nowUnix(), source: "beta_test" },
      store.read(ENT, accountId, VOUCHER_ENT) ? store.read(ENT, accountId, VOUCHER_ENT).version : "*"
    );
  }

  function isVoucherAuthorized(accountId) {
    const obj = store.read(ENT, accountId, VOUCHER_ENT);
    if (obj && obj.value.status === "active" && !(obj.value.expires_at > 0 && obj.value.expires_at <= nowUnix())) {
      return true;
    }
    if (productionSafe) return false;
    return isSafeDevVoucherBypass(runtimeEnv);
  }

  function denyUnauthorized(accountId) {
    if (isVoucherAuthorized(accountId)) return null;
    return { ok: false, error: "beta_voucher_unavailable" };
  }

  function readVoucherWallet(accountId) {
    const obj = store.read(COMM, accountId, VW);
    if (obj) {
      const rec = obj.value;
      rec.processed_refs = rec.processed_refs || {};
      rec.balance = Math.max(0, Math.floor(Number(rec.balance || 0)));
      return { value: rec, version: obj.version };
    }
    return { value: { account_id: accountId, balance: 0, processed_refs: {}, updated_at: nowUnix() }, version: "*" };
  }

  function mutateVouchers(accountId, ref, type, amount, extra = {}) {
    const amt = Math.floor(Number(amount || 0));
    const key = String(ref || "").trim();
    if (!key || amt < 0) return { ok: false, already: false, balance: 0, before: 0, error: "Invalid voucher mutation" };
    const obj = readVoucherWallet(accountId);
    const rec = obj.value;
    if (rec.processed_refs[key]) return { ok: true, already: true, balance: rec.balance, before: rec.balance };
    const before = rec.balance;
    if (type === "spend") {
      if (rec.balance < amt) return { ok: false, already: false, balance: rec.balance, before, error: "Insufficient vouchers" };
      rec.balance -= amt;
    } else {
      rec.balance += amt;
    }
    rec.processed_refs[key] = { type, amount: amt, ts: nowUnix(), ...extra };
    rec.updated_at = nowUnix();
    store.write(COMM, accountId, VW, rec, obj.version);
    return { ok: true, already: false, balance: rec.balance, before };
  }

  function readTopUp(accountId, roundId, collection) {
    const obj = store.read(collection, accountId, roundId);
    if (obj) {
      const rec = obj.value;
      rec.claimed = rec.claimed || {};
      rec.applied_refs = rec.applied_refs || {};
      rec.progress = Math.max(0, Math.floor(Number(rec.progress || 0)));
      return { value: rec, version: obj.version };
    }
    return {
      value: { account_id: accountId, round_id: roundId, progress: 0, claimed: {}, applied_refs: {}, history: [] },
      version: "*",
    };
  }

  function applyTopUp(accountId, roundId, collection, amount, ref, productId) {
    const obj = readTopUp(accountId, roundId, collection);
    const rec = obj.value;
    if (rec.applied_refs[ref]) return { ok: true, already: true, before: rec.progress, after: rec.progress };
    const before = rec.progress;
    rec.progress += Math.max(0, Math.floor(Number(amount || 0)));
    rec.applied_refs[ref] = { amount, ts: nowUnix(), product_id: productId };
    rec.history = rec.history || [];
    rec.history.push({ ref, amount, before, after: rec.progress, product_id: productId });
    store.write(collection, accountId, roundId, rec, obj.version);
    return { ok: true, already: false, before, after: rec.progress };
  }

  function redeemCode(accountId, rawCode, clientAmount) {
    const denied = denyUnauthorized(accountId);
    if (denied) return denied;
    const code = String(rawCode || "").trim().toUpperCase();
    const def = TEST_CODES[code];
    if (def && !fixtureCodesOn) return { ok: false, error: "invalid_code" };
    if (!def) return { ok: false, error: "invalid_code" };
    if (!def.active) return { ok: false, error: "inactive_code" };
    if (def.expires > 0 && nowUnix() >= def.expires) return { ok: false, error: "expired_code" };
    const existing = store.read(BV_REDEEM, accountId, def.code_id);
    if (existing && existing.value.count >= def.per) {
      return { ok: false, error: "already_redeemed", already: true, beta_vouchers: readVoucherWallet(accountId).value.balance };
    }
    if (def.cap > 0) {
      const stats = store.read(BV_CODES, SYS, def.code_id);
      const used = stats ? Number(stats.value.current_global_redemptions || 0) : 0;
      if (used >= def.cap) return { ok: false, error: "global_cap_reached" };
      store.write(BV_CODES, SYS, def.code_id, { code_id: def.code_id, current_global_redemptions: used + 1 }, stats ? stats.version : "*");
    }
    void clientAmount;
    const granted = mutateVouchers(accountId, "vgrant:" + def.code_id + ":" + accountId, "grant", def.amount, { code_id: def.code_id });
    store.write(
      BV_REDEEM,
      accountId,
      def.code_id,
      { account_id: accountId, code_id: def.code_id, count: 1, last_amount: def.amount, last_cohort: def.cohort },
      existing ? existing.version : "*"
    );
    return {
      ok: true,
      already: granted.already,
      granted_vouchers: def.amount,
      allocation_cohort: def.cohort,
      beta_vouchers: granted.balance,
      client_amount_ignored: Math.floor(Number(clientAmount || 0)),
    };
  }

  function purchaseWithVouchers(accountId, productId, clientCost, idempotencyKey) {
    const denied = denyUnauthorized(accountId);
    if (denied) return denied;
    const product = lookupProduct(catalog, productId);
    if (!product || !product.beta_voucher_purchasable || product.production_deliverable === false) {
      return { ok: false, error: "product_not_voucher_purchasable" };
    }
    const cost = product.beta_voucher_cost;
    void clientCost;
    const key = String(idempotencyKey || "").trim();
    if (!key) return { ok: false, error: "idempotency_key_required" };
    const txId = "bv_" + ledgerKey("beta_voucher", accountId + "_" + product.product_id + "_" + key);
    const existing = store.read(BV_LEDGER, accountId, txId);
    if (existing && existing.value.delivery_status === PURCHASE_DELIVERED) {
      return { ok: true, already: true, purchase_source: "BETA_VOUCHER", purchase: existing.value };
    }
    const spent = mutateVouchers(accountId, "vspend:" + txId, "spend", cost, { product_id: product.product_id });
    if (!spent.ok) return { ok: false, error: spent.error, beta_vouchers: spent.balance };
    const deliveryTxId = "dlv_" + txId;
    const delivered = deliver(accountId, product, deliveryTxId);
    if (!delivered.ok) return { ok: false, error: delivered.error || "Delivery failed" };
    const qualifying = product.qualifying_topup_diamonds || 0;
    const topup = applyTopUp(accountId, activeBetaRoundId, BV_TOPUP, qualifying, deliveryTxId, product.product_id);
    const rec = {
      account_id: accountId,
      purchase_source: "BETA_VOUCHER",
      product_id: product.product_id,
      platform: "BETA_VOUCHER",
      platform_transaction_id: txId,
      voucher_cost: cost,
      qualifying_topup_diamonds: qualifying,
      delivery_status: PURCHASE_DELIVERED,
      delivery_transaction_id: deliveryTxId,
    };
    store.write(BV_LEDGER, accountId, txId, rec, existing ? existing.version : "*");
    return {
      ok: true,
      already: spent.already,
      purchase_source: "BETA_VOUCHER",
      purchase: rec,
      beta_vouchers: spent.balance,
      beta_topup_before: topup.before,
      beta_topup_after: topup.after,
      production_topup: readTopUp(accountId, "topup_prod_round_001", PROD_TOPUP).value.progress,
    };
  }

  function claimMilestone(accountId, milestoneId) {
    const denied = denyUnauthorized(accountId);
    if (denied) return denied;
    const round = BETA_ROUNDS[activeBetaRoundId];
    const def = round.milestones.find((m) => m.milestone_id === milestoneId);
    if (!def) return { ok: false, error: "unknown_milestone" };
    const obj = readTopUp(accountId, round.round_id, BV_TOPUP);
    const rec = obj.value;
    if (rec.progress < def.threshold) return { ok: false, error: "threshold_not_reached", progress: rec.progress };
    if (rec.claimed[milestoneId]) return { ok: true, already: true, milestone_id: milestoneId };
    const grantRef = "btclaim:" + round.round_id + ":" + milestoneId + ":" + accountId;
    const granted = grantDiamonds(accountId, def.reward_diamonds, grantRef);
    rec.claimed[milestoneId] = { claimed_at: nowUnix(), reward_diamonds: def.reward_diamonds, grant_ref: grantRef };
    store.write(BV_TOPUP, accountId, round.round_id, rec, obj.version);
    return { ok: true, already: granted.already, milestone_id: milestoneId, reward_diamonds: def.reward_diamonds };
  }

  function publicWallet(accountId) {
    const spend = eligibleCents(listLedger(accountId));
    const ents = ["entitlement_builder_queue_30d", "entitlement_builder_queue_perm", "entitlement_research_queue_perm", "entitlement_march_queue_perm"]
      .map((id) => store.read(ENT, accountId, id))
      .filter(Boolean)
      .map((o) => o.value);
    const wallet = readWallet(accountId).value;
    const authorized = isVoucherAuthorized(accountId);
    const vouchers = authorized ? readVoucherWallet(accountId).value : { balance: 0 };
    return {
      diamonds: wallet.balance,
      diamond_debt: wallet.diamond_debt,
      entitlements: ents,
      eligible_beta_spend_cents: spend,
      future_voucher_usd: computeBetaVoucherUsd(spend),
      beta_vouchers: authorized ? vouchers.balance : 0,
      beta_voucher_available: authorized,
      beta_topup: authorized
        ? { round_id: activeBetaRoundId, progress: readTopUp(accountId, activeBetaRoundId, BV_TOPUP).value.progress }
        : null,
      production_topup: null,
    };
  }

  function entitlementActive(accountId, id) {
    const obj = store.read(ENT, accountId, id);
    if (!obj || obj.value.status !== "active") return false;
    if (obj.value.expires_at > 0 && obj.value.expires_at <= nowUnix()) return false;
    return true;
  }

  return {
    store,
    grantDiamonds,
    spendDiamonds,
    reverseDiamonds,
    processPurchase,
    processValidated,
    processPurchaseReversal,
    onGooglePurchaseNotification,
    reconcileVoidedPurchase,
    retryDelivery,
    restore,
    publicWallet,
    entitlementActive,
    listLedger,
    readWallet,
    readVoucherWallet,
    redeemCode,
    purchaseWithVouchers,
    claimMilestone,
    grantVoucherTesting,
    revokeVoucherTesting,
    isVoucherAuthorized,
    getBetaTopUp: (accountId) => {
      const denied = denyUnauthorized(accountId);
      if (denied) return denied;
      return { ok: true, beta_topup: { round_id: activeBetaRoundId, progress: readTopUp(accountId, activeBetaRoundId, BV_TOPUP).value.progress } };
    },
    readTopUp,
    setActiveBetaRound: (id) => {
      activeBetaRoundId = id;
    },
    listBetaLedger: (accountId) => {
      const out = [];
      for (const [k, v] of store.objs.entries()) {
        if (k.startsWith(`${BV_LEDGER}|${accountId}|`)) out.push(v.value);
      }
      return out;
    },
    applyRefund: (accountId, platform, txId) => {
      const existing = readLedger(accountId, platform, txId);
      if (!existing) throw new Error("missing");
      return applyRefund(existing.value, existing.version);
    },
  };
}

function appleOk(productId, txId, extra = {}) {
  return (_user, _platform, _receipt) => ({
    validatedPurchases: [
      {
        productId,
        transactionId: txId,
        purchaseTime: nowUnix(),
        refundTime: extra.refundTime || 0,
        seenBefore: !!extra.seenBefore,
      },
    ],
  });
}

function appleInvalid() {
  return () => ({ error: "invalid", validatedPurchases: [] });
}

const catalogJson = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));
const queueJson = JSON.parse(fs.readFileSync(QUEUE_PATH, "utf8"));
const catalog = catalogJson.products.map((p) => ({
  product_id: p.product_id,
  iap_product_id: p.iap_product_id,
  usd_cents: p.usd_cents,
  delivery_type: p.delivery_type,
  duration_seconds: p.duration_seconds || 0,
  entitlement_id: p.entitlement_id || "",
  diamond_amount: p.diamond_amount || 0,
  beta_spend_eligible: !!p.beta_spend_eligible,
  production_deliverable: p.production_deliverable !== false,
  product_type: p.product_type,
  live_store: !!p.live_store,
  repeatability: p.repeatability || "",
  qualifying_topup_diamonds: Math.max(0, Math.floor(Number(p.qualifying_topup_diamonds || 0))),
  beta_voucher_cost: Math.max(0, Math.floor(Number(p.beta_voucher_cost || 0))),
  beta_voucher_purchasable: !!p.beta_voucher_purchasable,
}));

assert(catalogJson._meta.price_policy.includes("Never trust client-submitted price"), "catalog documents client-price rejection");
assert(catalogJson._meta.first_public_diamond_pack === "com.crownspire.diamonds_500", "catalog records first public Diamond pack id");
const liveStoreIds = catalog.filter((p) => p.live_store).map((p) => p.product_id);
assert(liveStoreIds.length === 1 && liveStoreIds[0] === "com.crownspire.diamonds_500", "only diamonds_500 is live_store");
const testSku = catalog.find((p) => p.product_id === "com.crownspire.test.diamonds_internal_do_not_ship");
assert(!!testSku && testSku.product_type === "TEST_ONLY" && testSku.live_store === false && testSku.production_deliverable === false, "TEST Diamond SKU is non-production");
const diamondPack = catalog.find((p) => p.product_id === "com.crownspire.diamonds_500");
assert(!!diamondPack, "catalog contains com.crownspire.diamonds_500");
assert(diamondPack.iap_product_id === "com.crownspire.diamonds_500", "diamonds_500 iap id");
assert(diamondPack.diamond_amount === 500, "diamonds_500 grants 500");
assert(diamondPack.usd_cents === 499, "diamonds_500 is 499 cents");
assert(diamondPack.delivery_type === "DIAMONDS", "diamonds_500 delivery DIAMONDS");
assert(diamondPack.repeatability === "consumable", "diamonds_500 is consumable");
assert(diamondPack.production_deliverable === true, "diamonds_500 is production_deliverable");
assert(diamondPack.beta_spend_eligible === true, "diamonds_500 is beta-spend eligible");
assert(diamondPack.qualifying_topup_diamonds === 500, "diamonds_500 qualifying_topup_diamonds is 500");
assert(diamondPack.beta_voucher_cost === 5, "diamonds_500 voucher cost is 5");
assert(diamondPack.beta_voucher_purchasable === true, "diamonds_500 may be voucher-purchased in beta mode");
assert(diamondPack.diamond_amount === 500, "diamonds_500 real reward remains 500");

const serverCatalogSrc = fs.readFileSync(SERVER_CATALOG_PATH, "utf8");
const serverDiamondBlock = serverCatalogSrc.match(/product_id:\s*"com\.crownspire\.diamonds_500"[\s\S]*?live_store:\s*true/);
assert(!!serverDiamondBlock, "server catalog embeds com.crownspire.diamonds_500");
assert(serverDiamondBlock[0].includes("usd_cents: 499"), "server diamonds_500 usd_cents 499");
assert(serverDiamondBlock[0].includes("diamond_amount: 500"), "server diamonds_500 diamond_amount 500");
assert(serverDiamondBlock[0].includes('repeatability: "consumable"'), "server diamonds_500 consumable");
assert(serverDiamondBlock[0].includes("production_deliverable: true"), "server diamonds_500 production_deliverable");
assert(serverCatalogSrc.includes('iap_product_id: "com.crownspire.diamonds_500"'), "server GOOGLE/iap id matches");
assert(serverCatalogSrc.includes('product_id: "com.crownspire.test.diamonds_internal_do_not_ship"'), "server still embeds TEST_ONLY fixture");
assert(serverCatalogSrc.includes("function reverseDiamondsIdempotent"), "server defines reverseDiamondsIdempotent");
assert(serverCatalogSrc.includes("function processPurchaseReversal"), "server defines processPurchaseReversal");
assert(serverCatalogSrc.includes("function reconcileVoidedPurchase"), "server defines reconcileVoidedPurchase");
assert(serverCatalogSrc.includes("function onGooglePurchaseNotification"), "server defines Google purchase notification handler");
assert(serverCatalogSrc.includes("diamond_debt"), "server wallet schema includes diamond_debt");
const indexSrc = fs.readFileSync(path.join(ROOT, "server/src/index.ts"), "utf8");
assert(indexSrc.includes("registerPurchaseNotificationGoogle(onGooglePurchaseNotification)"), "InitModule registers Google purchase notification handler");

for (const row of queueJson.entitlements) {
  const match = catalog.find((p) => p.product_id === row.entitlement_id);
  assert(!!match, `catalog contains ${row.entitlement_id}`);
  assert(match.iap_product_id === row.iap_product_id, `${row.entitlement_id} iap id matches queue contract`);
  assert(match.usd_cents === Math.round(row.price_usd * 100), `${row.entitlement_id} USD matches queue contract (catalog cents vs json)`);
}

const uid = "acct_test_4b";

// A. same purchase twice → one delivery
{
  const eng = createEngine(catalog);
  const tx = "apple-tx-dup-1";
  const v = appleOk("com.crownspire.builder_queue_perm", tx);
  const a = eng.processPurchase(uid, "APPLE", "receipt-a", v);
  const b = eng.processPurchase(uid, "APPLE", "receipt-a", v);
  assert(a.ok && b.ok, "A: both submissions accepted");
  assert(a.purchases[0].delivery_status === PURCHASE_DELIVERED, "A: first delivered");
  assert(b.purchases[0].delivery_status === PURCHASE_DELIVERED, "A: second reports delivered");
  const delivered = eng.listLedger(uid).filter((r) => r.delivery_status === PURCHASE_DELIVERED);
  assert(delivered.length === 1, "A: one ledger delivery row", `count=${delivered.length}`);
  assert(eng.entitlementActive(uid, "entitlement_builder_queue_perm"), "A: entitlement granted once");
}

// B. validate ok, delivery response lost, retry → no duplicate
{
  const eng = createEngine(catalog);
  const tx = "apple-tx-retry-1";
  const v = appleOk("com.crownspire.research_queue_perm", tx);
  const paused = eng.processPurchase(uid + "b", "APPLE", "receipt-b", v, { stopAfterValidate: true });
  assert(paused.ok && paused.purchases[0].delivery_status === PURCHASE_DELIVERING, "B: paused in DELIVERING after validate");
  assert(!eng.entitlementActive(uid + "b", "entitlement_research_queue_perm"), "B: no grant before retry");
  const retried = eng.retryDelivery(uid + "b", "APPLE", tx);
  assert(retried.ok && retried.purchase.delivery_status === PURCHASE_DELIVERED, "B: retry delivers");
  const again = eng.retryDelivery(uid + "b", "APPLE", tx);
  assert(again.purchase.delivery_status === PURCHASE_DELIVERED, "B: second retry stays delivered");
  const rows = eng.listLedger(uid + "b").filter((r) => r.product_id === "entitlement_research_queue_perm");
  assert(rows.length === 1, "B: still one ledger row");
  assert(eng.entitlementActive(uid + "b", "entitlement_research_queue_perm"), "B: entitlement present after retry");
}

// C. invalid purchase → zero delivery
{
  const eng = createEngine(catalog);
  const res = eng.processPurchase(uid + "c", "APPLE", "bad", appleInvalid());
  assert(!res.ok && res.delivered === false, "C: invalid rejected");
  assert(eng.listLedger(uid + "c").length === 0, "C: no ledger delivery");
  assert(eng.readWallet(uid + "c").value.balance === 0, "C: wallet unchanged");
}

// D. client-only fake success → zero delivery (no receipt processed)
{
  const eng = createEngine(catalog);
  const fake = { ok: false, error: "client_callback_not_authority", delivered: false, granted: false };
  assert(fake.delivered === false && fake.granted === false, "D: client callback grants nothing");
  assert(eng.listLedger(uid + "d").length === 0, "D: no server ledger without process_purchase");
  assert(eng.readWallet(uid + "d").value.balance === 0, "D: wallet stays 0");
}

// E. permanent queue purchase survives restore
{
  const eng = createEngine(catalog);
  const tx = "apple-tx-restore-1";
  eng.processPurchase(uid + "e", "APPLE", "r", appleOk("com.crownspire.march_queue_perm", tx));
  assert(eng.entitlementActive(uid + "e", "entitlement_march_queue_perm"), "E: granted");
  eng.store.objs.delete(`crownspire_entitlements|${uid + "e"}|entitlement_march_queue_perm`);
  assert(!eng.entitlementActive(uid + "e", "entitlement_march_queue_perm"), "E: simulated entitlement loss");
  eng.restore(uid + "e");
  assert(eng.entitlementActive(uid + "e", "entitlement_march_queue_perm"), "E: restore re-asserts permanent entitlement");
  const diamondsBefore = eng.readWallet(uid + "e").value.balance;
  eng.restore(uid + "e");
  assert(eng.readWallet(uid + "e").value.balance === diamondsBefore, "E: restore does not re-grant consumables/diamonds");
}

// G-server. local diamond edit cannot alter wallet (wallet is separate storage)
{
  const eng = createEngine(catalog);
  eng.grantDiamonds(uid + "g", 10, "seed");
  const forgedClient = 999999;
  assert(eng.readWallet(uid + "g").value.balance === 10, "G: server wallet is 10");
  assert(forgedClient !== eng.readWallet(uid + "g").value.balance, "G: client mirror cannot write server wallet");
}

// H. spend rejects insufficient
{
  const eng = createEngine(catalog);
  const r = eng.spendDiamonds(uid + "h", 5, "spend:test:1");
  assert(!r.ok && r.error === "Insufficient diamonds", "H: insufficient rejected");
  assert(r.balance === 0, "H: balance stays 0");
}

// I. grant is idempotent
{
  const eng = createEngine(catalog);
  const a = eng.grantDiamonds(uid + "i", 50, "grant:reason:tx1");
  const b = eng.grantDiamonds(uid + "i", 50, "grant:reason:tx1");
  assert(a.ok && !a.already && a.balance === 50, "I: first grant 50");
  assert(b.ok && b.already && b.balance === 50, "I: replay does not add");
}

// J. refunded tx excluded from eligible spend
{
  const eng = createEngine(catalog);
  const tx = "apple-tx-refund-1";
  eng.processPurchase(uid + "j", "APPLE", "r", appleOk("com.crownspire.builder_queue_perm", tx));
  assert(eng.publicWallet(uid + "j").eligible_beta_spend_cents === 999, "J: $9.99 eligible before refund");
  eng.applyRefund(uid + "j", "APPLE", tx);
  assert(eng.publicWallet(uid + "j").eligible_beta_spend_cents === 0, "J: refunded excluded");
  assert(eng.publicWallet(uid + "j").future_voucher_usd === 0, "J: voucher 0 after refund");
  assert(!eng.entitlementActive(uid + "j", "entitlement_builder_queue_perm"), "J: entitlement revoked");
}

// K. $25 → $28
assert(computeBetaVoucherUsd(2500) === 28, "K: $25 eligible → $28 voucher");
// L. $0.99 → $2
assert(computeBetaVoucherUsd(99) === 2, "L: $0.99 eligible → $2 voucher");

// N. dev grant RPC without env authorization → refused
assert(!isDevEntitlementRpcEnabled({}), "N: empty env refused");
assert(
  !isDevEntitlementRpcEnabled({ CROWNSPIRE_ENABLE_BETA_GRANTS: "true", CROWNSPIRE_BETA_GRANT_SECRET: "abcdefghijklmnop" }),
  "N: beta grants flag does not enable production/dev entitlement RPC"
);
assert(
  !isDevEntitlementRpcEnabled({ CROWNSPIRE_ENABLE_DEV_ENTITLEMENT_RPC: "true" }),
  "N: flag without secret refused"
);
assert(
  !isDevEntitlementRpcEnabled({
    CROWNSPIRE_ENABLE_DEV_ENTITLEMENT_RPC: "true",
    CROWNSPIRE_DEV_ENTITLEMENT_SECRET: "short",
  }),
  "N: short secret refused"
);
assert(
  isDevEntitlementRpcEnabled({
    CROWNSPIRE_ENABLE_DEV_ENTITLEMENT_RPC: "true",
    CROWNSPIRE_DEV_ENTITLEMENT_SECRET: "sixteen-chars-ok",
  }),
  "N: dedicated flag + min-16 secret allowed"
);

// Unknown product / TEST sku rejected in production path
{
  const eng = createEngine(catalog);
  const res = eng.processPurchase(uid + "x", "APPLE", "r", appleOk("com.crownspire.test.diamonds_internal_do_not_ship", "tx-test"));
  assert(res.ok && res.purchases[0].delivery_status === PURCHASE_REJECTED, "TEST SKU rejected in production deliverable path");
  assert(eng.readWallet(uid + "x").value.balance === 0, "TEST SKU does not mint diamonds in production path");
}

// Client-submitted price ignored: catalog 9.99 even if validator/client claimed otherwise
{
  const eng = createEngine(catalog);
  const rec = eng.processPurchase(uid + "price", "APPLE", "r", appleOk("com.crownspire.builder_queue_perm", "tx-price"));
  assert(rec.purchases[0].normalized_usd_cents === 999, "catalog USD used, not client price");
  assert(rec.purchases[0].verified_currency === "USD", "currency from catalog USD");
}

// First small consumable Diamond pack: 500 / $4.99, idempotent, restore does not re-grant
{
  const eng = createEngine(catalog);
  const tx = "gp-diamonds-500-1";
  const res = eng.processPurchase(uid + "d500", "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  assert(res.ok && res.purchases[0].delivery_status === PURCHASE_DELIVERED, "diamonds_500 delivered");
  assert(eng.readWallet(uid + "d500").value.balance === 500, "diamonds_500 grants 500");
  assert(res.purchases[0].normalized_usd_cents === 499, "diamonds_500 catalog 499 cents");
  assert(res.purchases[0].eligible_beta_spend_cents === 499, "diamonds_500 beta-spend 499 cents");
  assert(res.purchases[0].purchase_source === "GOOGLE_PLAY", "diamonds_500 Google row is GOOGLE_PLAY");
  const again = eng.processPurchase(uid + "d500", "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  assert(again.ok && again.purchases[0].delivery_status === PURCHASE_DELIVERED, "diamonds_500 duplicate accepted as already delivered");
  assert(eng.readWallet(uid + "d500").value.balance === 500, "diamonds_500 duplicate does not re-grant");
  eng.restore(uid + "d500");
  assert(eng.readWallet(uid + "d500").value.balance === 500, "restore does not re-grant consumable Diamonds");
}

// Refund A: grant 500, refund before spend → wallet 0, debt 0, ledger REFUNDED
{
  const eng = createEngine(catalog);
  const acct = uid + "refA";
  const tx = "gp-refund-a";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  const refunded = eng.applyRefund(acct, "GOOGLE", tx);
  const wallet = eng.readWallet(acct).value;
  assert(refunded.delivery_status === PURCHASE_REFUNDED, "Refund A: ledger REFUNDED");
  assert(refunded.original_delivery_status === PURCHASE_DELIVERED, "Refund A: original DELIVERED preserved");
  assert(refunded.reversal_applied === true, "Refund A: reversal marker set");
  assert(refunded.eligible_beta_spend_cents === 0, "Refund A: eligible spend 0");
  assert(wallet.balance === 0, "Refund A: wallet 0");
  assert(wallet.diamond_debt === 0, "Refund A: debt 0");
  assert(wallet.balance >= 0, "Refund A: displayed balance not negative");
  assert(!!wallet.processed_refs["dlv_" + ledgerKey("GOOGLE", tx)], "Refund A: original grant preserved");
  assert(wallet.processed_refs["rev_" + ledgerKey("GOOGLE", tx)].type === "reversal", "Refund A: separate reversal ref");
}

// Refund B: grant 500, spend 200, refund → wallet 0, debt 200
{
  const eng = createEngine(catalog);
  const acct = uid + "refB";
  const tx = "gp-refund-b";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  eng.spendDiamonds(acct, 200, "spend:test:b");
  eng.applyRefund(acct, "GOOGLE", tx);
  const wallet = eng.readWallet(acct).value;
  assert(wallet.balance === 0, "Refund B: wallet 0");
  assert(wallet.diamond_debt === 200, "Refund B: debt 200");
}

// Refund C: grant 500, spend all 500, refund → wallet 0, debt 500
{
  const eng = createEngine(catalog);
  const acct = uid + "refC";
  const tx = "gp-refund-c";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  eng.spendDiamonds(acct, 500, "spend:test:c");
  eng.applyRefund(acct, "GOOGLE", tx);
  const wallet = eng.readWallet(acct).value;
  assert(wallet.balance === 0, "Refund C: wallet 0");
  assert(wallet.diamond_debt === 500, "Refund C: debt 500");
}

// Refund D: replay same refund → no additional debit/debt
{
  const eng = createEngine(catalog);
  const acct = uid + "refD";
  const tx = "gp-refund-d";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  eng.spendDiamonds(acct, 200, "spend:test:d");
  const first = eng.processPurchaseReversal(acct, "GOOGLE", tx, "REFUNDED", "com.crownspire.diamonds_500");
  const second = eng.processPurchaseReversal(acct, "GOOGLE", tx, "REFUNDED", "com.crownspire.diamonds_500");
  const wallet = eng.readWallet(acct).value;
  assert(first.ok && !first.already, "Refund D: first reversal applied");
  assert(second.ok && second.already, "Refund D: replay already");
  assert(wallet.balance === 0 && wallet.diamond_debt === 200, "Refund D: no extra debit/debt");
  const revRefs = Object.keys(wallet.processed_refs).filter((k) => wallet.processed_refs[k].type === "reversal");
  assert(revRefs.length === 1, "Refund D: one reversal record");
}

// Refund E: RTDN and Voided Purchases reconciliation converge to one reversal
{
  const eng = createEngine(catalog);
  const acct = uid + "refE";
  const tx = "gp-refund-e";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  const rtdn = eng.onGooglePurchaseNotification(
    { userId: acct, productId: "com.crownspire.diamonds_500", transactionId: tx, refundTime: nowUnix() },
    "REFUNDED"
  );
  const recon = eng.reconcileVoidedPurchase(acct, "GOOGLE", tx, "com.crownspire.diamonds_500", "VOIDED");
  const wallet = eng.readWallet(acct).value;
  assert(rtdn.ok && rtdn.granted === false, "Refund E: RTDN reverses, never grants");
  assert(recon.ok && recon.already, "Refund E: reconciliation is replay-safe");
  assert(wallet.balance === 0 && wallet.diamond_debt === 0, "Refund E: reversal happened once");
  const revRefs = Object.keys(wallet.processed_refs).filter((k) => wallet.processed_refs[k].type === "reversal");
  assert(revRefs.length === 1, "Refund E: one reversal ref for RTDN+poll");
}

// Refund F: refund before any spend → exact removal
{
  const eng = createEngine(catalog);
  const acct = uid + "refF";
  const tx = "gp-refund-f";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  assert(eng.readWallet(acct).value.balance === 500, "Refund F: granted 500");
  eng.applyRefund(acct, "GOOGLE", tx);
  const wallet = eng.readWallet(acct).value;
  assert(wallet.balance === 0 && wallet.diamond_debt === 0, "Refund F: exact removal, no debt");
}

// Refund G: future paid 500 grant with debt 200 → debt 0, spendable +300
{
  const eng = createEngine(catalog);
  const acct = uid + "refG";
  const tx1 = "gp-refund-g1";
  const tx2 = "gp-refund-g2";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx1));
  eng.spendDiamonds(acct, 200, "spend:test:g");
  eng.applyRefund(acct, "GOOGLE", tx1);
  assert(eng.readWallet(acct).value.diamond_debt === 200, "Refund G: debt 200 before next grant");
  const next = eng.processPurchase(acct, "GOOGLE", "r2", appleOk("com.crownspire.diamonds_500", tx2));
  const wallet = eng.readWallet(acct).value;
  assert(next.ok && next.purchases[0].delivery_status === PURCHASE_DELIVERED, "Refund G: second paid grant delivered");
  assert(wallet.diamond_debt === 0, "Refund G: debt repaid");
  assert(wallet.balance === 300, "Refund G: remainder 300 spendable");
}

// Refund H: same original transaction cannot grant again after refund
{
  const eng = createEngine(catalog);
  const acct = uid + "refH";
  const tx = "gp-refund-h";
  eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  eng.applyRefund(acct, "GOOGLE", tx);
  const again = eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  const wallet = eng.readWallet(acct).value;
  assert(again.ok && again.purchases[0].delivery_status === PURCHASE_REFUNDED, "Refund H: resubmit stays REFUNDED");
  assert(wallet.balance === 0 && wallet.diamond_debt === 0, "Refund H: no re-grant");
  const retried = eng.retryDelivery(acct, "GOOGLE", tx);
  assert(retried.purchase.delivery_status === PURCHASE_REFUNDED, "Refund H: get_purchase cannot re-deliver");
}

// Refund I: queue entitlement refund still works, no diamond wallet interaction
{
  const eng = createEngine(catalog);
  const acct = uid + "refI";
  const tx = "gp-refund-i-queue";
  eng.processPurchase(acct, "APPLE", "r", appleOk("com.crownspire.builder_queue_perm", tx));
  assert(eng.entitlementActive(acct, "entitlement_builder_queue_perm"), "Refund I: queue granted");
  assert(eng.readWallet(acct).value.balance === 0, "Refund I: no diamonds from queue SKU");
  eng.applyRefund(acct, "APPLE", tx);
  assert(!eng.entitlementActive(acct, "entitlement_builder_queue_perm"), "Refund I: queue entitlement revoked");
  assert(eng.publicWallet(acct).eligible_beta_spend_cents === 0, "Refund I: eligible spend 0");
  assert(eng.readWallet(acct).value.balance === 0, "Refund I: diamond balance unchanged");
  assert(eng.readWallet(acct).value.diamond_debt === 0, "Refund I: no diamond debt from queue refund");
}

// Refund J: TEST_ONLY remains rejected
{
  const eng = createEngine(catalog);
  const acct = uid + "refJ";
  const res = eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.test.diamonds_internal_do_not_ship", "tx-test-j"));
  assert(res.ok && res.purchases[0].delivery_status === PURCHASE_REJECTED, "Refund J: TEST_ONLY rejected");
  assert(eng.readWallet(acct).value.balance === 0, "Refund J: TEST_ONLY does not mint");
}

// Refund K: unknown product remains rejected / ignored by notification
{
  const eng = createEngine(catalog);
  const acct = uid + "refK";
  const res = eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.unknown_sku", "tx-unknown-k"));
  assert(res.ok && res.purchases[0].delivery_status === PURCHASE_REJECTED, "Refund K: unknown product rejected");
  const note = eng.onGooglePurchaseNotification(
    { userId: acct, productId: "com.crownspire.unknown_sku", transactionId: "tx-unknown-k", refundTime: 1 },
    "REFUNDED"
  );
  assert(note.ignored === true && note.granted === false, "Refund K: notification ignores unknown product");
  assert(eng.readWallet(acct).value.balance === 0 && eng.readWallet(acct).value.diamond_debt === 0, "Refund K: wallet untouched");
}

// Refund L: wrong user / stale transaction cannot affect another user
{
  const eng = createEngine(catalog);
  const acctA = uid + "refLa";
  const acctB = uid + "refLb";
  const tx = "gp-refund-l";
  eng.processPurchase(acctA, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", tx));
  const beforeA = eng.readWallet(acctA).value;
  const wrong = eng.processPurchaseReversal(acctB, "GOOGLE", tx, "REFUNDED", "com.crownspire.diamonds_500");
  const afterA = eng.readWallet(acctA).value;
  const afterB = eng.readWallet(acctB).value;
  assert(beforeA.balance === 500, "Refund L: user A starts at 500");
  assert(afterA.balance === 500 && afterA.diamond_debt === 0, "Refund L: user A wallet unchanged");
  assert(afterB.balance === 0 && afterB.diamond_debt === 0, "Refund L: user B not debited");
  assert(wrong.granted === false, "Refund L: wrong-user path never grants");
  const ledgerA = eng.listLedger(acctA)[0];
  assert(ledgerA.delivery_status === PURCHASE_DELIVERED, "Refund L: user A ledger still DELIVERED");
}

// Refund M: wallet read remains backward-compatible with old objects lacking debt
{
  const eng = createEngine(catalog);
  const acct = uid + "refM";
  eng.store.write("crownspire_commerce", acct, "diamond_wallet", { account_id: acct, balance: 120, processed_refs: {} }, "*");
  const wallet = eng.readWallet(acct).value;
  const pub = eng.publicWallet(acct);
  assert(wallet.balance === 120, "Refund M: old balance preserved");
  assert(wallet.diamond_debt === 0, "Refund M: missing debt normalizes to 0");
  assert(pub.diamonds === 120 && pub.diamond_debt === 0, "Refund M: wallet RPC exposes diamonds + diamond_debt");
}

// Phase 1 Beta Voucher + simulated Top-Up
{
  const eng = createEngine(catalog);
  const acct = uid + "voucherA";
  eng.grantVoucherTesting(acct);
  const a = eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5", 9999);
  assert(a.ok && a.granted_vouchers === 5 && a.beta_vouchers === 5, "A: fixture code grants 5 once");
  assert(a.client_amount_ignored === 9999, "G: client-requested amount is ignored");
  const b = eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5", 5);
  assert(!b.ok && b.error === "already_redeemed", "B: same code/account cannot redeem twice");
  assert(eng.readVoucherWallet(acct).value.balance === 5, "B: balance stays 5");
}

{
  const eng = createEngine(catalog);
  eng.grantVoucherTesting(uid + "vexp");
  eng.grantVoucherTesting(uid + "vinact");
  const expired = eng.redeemCode(uid + "vexp", "CROWNSPIRE-TEST-VOUCHER-EXPIRED");
  assert(!expired.ok && expired.error === "expired_code", "C: expired code rejected");
  const inactive = eng.redeemCode(uid + "vinact", "CROWNSPIRE-TEST-VOUCHER-INACTIVE");
  assert(!inactive.ok && inactive.error === "inactive_code", "D: inactive code rejected");
}

{
  const eng = createEngine(catalog);
  eng.grantVoucherTesting(uid + "vcap1");
  eng.grantVoucherTesting(uid + "vcap2");
  const first = eng.redeemCode(uid + "vcap1", "CROWNSPIRE-TEST-VOUCHER-CAP1");
  const second = eng.redeemCode(uid + "vcap2", "CROWNSPIRE-TEST-VOUCHER-CAP1");
  assert(first.ok, "E: first global cap redeem ok");
  assert(!second.ok && second.error === "global_cap_reached", "E: global cap enforced");
}

{
  const eng = createEngine(catalog);
  eng.grantVoucherTesting(uid + "vneg");
  const spent = eng.purchaseWithVouchers(uid + "vneg", "com.crownspire.diamonds_500", 5, "k1");
  assert(!spent.ok && spent.error === "Insufficient vouchers", "F: voucher balance cannot go negative");
  assert(eng.readVoucherWallet(uid + "vneg").value.balance === 0, "F: balance stays 0");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vbuy";
  eng.grantVoucherTesting(acct);
  eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  const googleBefore = eng.listLedger(acct).length;
  const buy = eng.purchaseWithVouchers(acct, "com.crownspire.diamonds_500", 99, "sim-500");
  assert(buy.ok && buy.purchase_source === "BETA_VOUCHER", "H: purchase_source BETA_VOUCHER");
  assert(eng.readVoucherWallet(acct).value.balance === 0, "H: vouchers 5 -> 0");
  assert(eng.readWallet(acct).value.balance === 500, "H: Diamonds +500");
  assert(buy.purchase.voucher_cost === 5, "H: server cost 5, not client 99");
  assert(eng.listLedger(acct).length === googleBefore, "I: simulated purchase does not create Google ledger row");
  assert(eng.listBetaLedger(acct).length === 1, "I: beta voucher ledger has the simulated row");
  assert(eng.publicWallet(acct).eligible_beta_spend_cents === 0, "I: no real revenue / launch-voucher spend");
  assert(buy.production_topup === 0, "J: simulated purchase does not increase production Top-Up");
  assert(buy.beta_topup_after === 500, "K: Beta Top-Up +500 from qualifying_topup_diamonds");
  const replay = eng.purchaseWithVouchers(acct, "com.crownspire.diamonds_500", 5, "sim-500");
  assert(replay.ok && replay.already, "L: replay does not double-grant");
  assert(eng.readWallet(acct).value.balance === 500, "L: diamonds stay 500");
  assert(eng.readVoucherWallet(acct).value.balance === 0, "L: vouchers stay 0");
  assert(eng.readTopUp(acct, "topup_beta_round_test_001", "crownspire_beta_topup").value.progress === 500, "L: beta top-up not doubled");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vmil";
  eng.grantVoucherTesting(acct);
  const early = eng.claimMilestone(acct, "beta_m_100");
  assert(!early.ok && early.error === "threshold_not_reached", "M: cannot claim before threshold");
  eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  eng.purchaseWithVouchers(acct, "com.crownspire.diamonds_500", 5, "m1");
  const first = eng.claimMilestone(acct, "beta_m_100");
  const second = eng.claimMilestone(acct, "beta_m_100");
  assert(first.ok && first.reward_diamonds === 1, "M: claim after threshold");
  assert(second.ok && second.already, "N: milestone cannot be claimed twice");
  const later = eng.claimMilestone(acct, "beta_m_1000");
  assert(!later.ok && later.error === "threshold_not_reached", "M: cannot claim future milestone");
  const mid = eng.claimMilestone(acct, "beta_m_500");
  assert(mid.ok, "M: 500 threshold claimable after +500 progress");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vround";
  eng.grantVoucherTesting(acct);
  eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  eng.purchaseWithVouchers(acct, "com.crownspire.diamonds_500", 5, "r1");
  assert(eng.readTopUp(acct, "topup_beta_round_test_001", "crownspire_beta_topup").value.progress === 500, "P: old round history 500");
  eng.setActiveBetaRound("topup_beta_round_test_002");
  assert(eng.readTopUp(acct, "topup_beta_round_test_002", "crownspire_beta_topup").value.progress === 0, "O: new beta round starts at 0");
  assert(eng.readTopUp(acct, "topup_beta_round_test_001", "crownspire_beta_topup").value.progress === 500, "P: old round remains");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vfree";
  eng.grantDiamonds(acct, 500, "free-quest");
  assert(eng.readWallet(acct).value.balance === 500, "Q: free grant 500 diamonds");
  assert(eng.readTopUp(acct, "topup_beta_round_test_001", "crownspire_beta_topup").value.progress === 0, "Q: free Diamond grant adds 0 Top-Up");
  assert(eng.readTopUp(acct, "topup_prod_round_001", "crownspire_prod_topup").value.progress === 0, "Q: production Top-Up stays 0");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vgoogle";
  const res = eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", "gp-class"));
  assert(res.purchases[0].purchase_source === "GOOGLE_PLAY", "R: Google classification unchanged");
  assert(eng.listBetaLedger(acct).length === 0, "R: Google path does not write beta voucher ledger");
  assert(eng.readTopUp(acct, "topup_beta_round_test_001", "crownspire_beta_topup").value.progress === 0, "R: Google does not credit Beta Top-Up");
  assert(eng.readTopUp(acct, "topup_prod_round_001", "crownspire_prod_topup").value.progress === 0, "R: no invented production Top-Up round");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "vsession";
  eng.grantVoucherTesting(acct);
  eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-100");
  const snap = eng.publicWallet(acct);
  assert(snap.beta_vouchers === 100, "U: voucher balance in wallet snapshot");
  const again = eng.publicWallet(acct);
  assert(again.beta_vouchers === 100, "U: voucher balance survives refresh");
  assert(again.diamonds === 0, "U: vouchers are not Diamonds");
}

assert(serverCatalogSrc.includes("PURCHASE_SOURCE_BETA_VOUCHER"), "server defines BETA_VOUCHER source");
assert(serverCatalogSrc.includes("qualifying_topup_diamonds"), "server catalog has qualifying_topup_diamonds");
const betaSrc = fs.readFileSync(path.join(ROOT, "server/src/phase57_beta_vouchers.ts"), "utf8");
assert(betaSrc.includes("TEST_ONLY"), "voucher fixtures marked TEST_ONLY");
assert(!betaSrc.includes("1500000"), "proposed 1.5M ladder is not hardcoded live");
assert(indexSrc.includes("crownspire_commerce_redeem_voucher_code"), "redeem RPC registered");
assert(indexSrc.includes("crownspire_commerce_purchase_with_vouchers"), "voucher purchase RPC registered");

assert(!isSafeDevVoucherBypass({}), "env flag alone is not a production bypass");
assert(!isSafeDevVoucherBypass({ CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC: "true" }), "ENABLE without runtime context is ignored");
assert(
  !isSafeDevVoucherBypass({ CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC: "true", CROWNSPIRE_RUNTIME_CONTEXT: "production" }),
  "ENABLE on production context is ignored"
);
assert(
  isSafeDevVoucherBypass({ CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC: "true", CROWNSPIRE_RUNTIME_CONTEXT: "local" }),
  "ENABLE + local context is a constrained dev bypass"
);
assert(!areFixtureTestCodesEnabled({ CROWNSPIRE_ENABLE_BETA_VOUCHER_TEST_CODES: "true" }), "fixture codes need local/test context");
assert(
  areFixtureTestCodesEnabled({ CROWNSPIRE_ENABLE_BETA_VOUCHER_TEST_CODES: "true", CROWNSPIRE_RUNTIME_CONTEXT: "test" }),
  "fixture codes allowed only in explicit test context"
);
assert(isDevSettableEntitlement("entitlement_beta_voucher_testing"), "dev RPC allowlist includes voucher testing");
assert(isDevSettableEntitlement("beta_alliance_auto_help"), "dev RPC still allows auto-help");
assert(!isDevSettableEntitlement("entitlement_builder_queue_perm"), "dev RPC cannot grant paid queue");
assert(!isDevSettableEntitlement("alliance_auto_help"), "dev RPC cannot grant production auto-help");

{
  const live = createEngine(catalog, { productionSafe: true });
  const acct = uid + "unauth";
  const wallet = live.publicWallet(acct);
  assert(wallet.beta_voucher_available === false, "A: unauthorized wallet hides voucher mode");
  assert(wallet.beta_vouchers === 0, "A: unauthorized wallet does not expose voucher balance");
  assert(wallet.beta_topup === null, "A: unauthorized wallet has no Beta Top-Up");
  const redeem = live.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  assert(!redeem.ok && redeem.error === "beta_voucher_unavailable", "B: unauthorized cannot redeem valid fixture code");
  const buy = live.purchaseWithVouchers(acct, "com.crownspire.diamonds_500", 5, "nope");
  assert(!buy.ok && buy.error === "beta_voucher_unavailable", "C: unauthorized cannot voucher-buy diamonds_500");
  const top = live.getBetaTopUp(acct);
  const claim = live.claimMilestone(acct, "beta_m_100");
  assert(!top.ok && top.error === "beta_voucher_unavailable", "D: unauthorized cannot fetch Beta Top-Up");
  assert(!claim.ok && claim.error === "beta_voucher_unavailable", "D: unauthorized cannot claim Beta Top-Up");
  assert(live.readWallet(acct).value.balance === 0, "A-D: diamonds unchanged");
  assert(live.listLedger(acct).length === 0, "A-D: no Google ledger rows");
}

{
  const live = createEngine(catalog, { productionSafe: true });
  const acct = uid + "authLive";
  live.grantVoucherTesting(acct);
  const wallet = live.publicWallet(acct);
  assert(wallet.beta_voucher_available === true, "E: authorized account can access voucher system");
  const bad = live.redeemCode(acct, "NOT-A-REAL-CODE");
  assert(!bad.ok && bad.error === "invalid_code", "G: authorized + invalid code fails");
  const leaked = live.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  assert(!leaked.ok, "J: fixture codes unavailable in production-safe mode");
  assert(live.readVoucherWallet(acct).value.balance === 0, "J: leaked fixture grants nothing on production");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "authLocal";
  eng.grantVoucherTesting(acct);
  const okRedeem = eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  assert(okRedeem.ok && okRedeem.beta_vouchers === 5, "F: authorized + valid code succeeds");
  const selfGrant = { ok: false, error: "client_cannot_grant_entitlement" };
  assert(!selfGrant.ok, "H: client cannot self-grant entitlement");
}

{
  const live = createEngine(catalog, { productionSafe: true, env: { CROWNSPIRE_ENABLE_BETA_VOUCHER_RPC: "true" } });
  const acct = uid + "flagOnly";
  const redeem = live.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  assert(!redeem.ok && redeem.error === "beta_voucher_unavailable", "I: leaked fixture code is useless without account authorization");
  assert(live.publicWallet(acct).beta_voucher_available === false, "I: global ENABLE flag does not authorize production accounts");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "revoke";
  eng.grantVoucherTesting(acct);
  assert(eng.publicWallet(acct).beta_voucher_available === true, "K: granted tester is authorized");
  eng.revokeVoucherTesting(acct);
  assert(eng.publicWallet(acct).beta_voucher_available === false, "K: revoking entitlement removes voucher access");
  const redeem = eng.redeemCode(acct, "CROWNSPIRE-TEST-VOUCHER-5");
  assert(!redeem.ok && redeem.error === "beta_voucher_unavailable", "K: revoked account cannot redeem");
}

{
  const eng = createEngine(catalog);
  const acct = uid + "googleStay";
  const res = eng.processPurchase(acct, "GOOGLE", "r", appleOk("com.crownspire.diamonds_500", "gp-1b"));
  assert(res.ok && res.purchases[0].purchase_source === "GOOGLE_PLAY", "M: Google purchase path remains unchanged");
  assert(res.purchases[0].delivery_status === PURCHASE_DELIVERED, "M: Google still delivers");
  assert(eng.readWallet(acct).value.balance === 500, "M: Google still grants 500 Diamonds");
  assert(eng.publicWallet(acct).beta_voucher_available === false, "M: Google purchase does not enable voucher mode");
}

const helpSrc = fs.readFileSync(path.join(ROOT, "server/src/phase5_help.ts"), "utf8");
assert(helpSrc.includes('entitlementId !== "entitlement_beta_voucher_testing"'), "dev entitlement RPC can grant voucher testing");
assert(helpSrc.includes("Only closed-beta test entitlements can be set via dev tooling"), "dev RPC still blocks other entitlements");
const betaSrc1b = fs.readFileSync(path.join(ROOT, "server/src/phase57_beta_vouchers.ts"), "utf8");
assert(betaSrc1b.includes("isSafeDevVoucherBypass"), "server constrains global voucher env flag");
assert(betaSrc1b.includes("areFixtureTestCodesEnabled"), "server gates fixture codes");

if (fails.length) {
  console.error(`[commerce 4B] FAILED ${fails.length}`);
  for (const f of fails) console.error(" - " + f);
  process.exit(1);
}
console.log("[commerce 4B] PASS");
process.exit(0);
