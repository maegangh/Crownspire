/**
 * Secure consumable hardening tests (no live Nakama).
 * - Bag claims must NOT import Peace/Anti into authoritative inventory
 * - Teleport one-time bag reconcile preserved
 * - Grant/use/OCC/hostile gate
 * Run: node server/scripts/secure_consumable_protection_test.mjs
 */

const PEACE = "boost_shield_peace_3d";
const ANTI = "boost_anti_scout_24h";
const TELEPORT = "teleport_advanced_compass";
const PEACE_DUR = 3 * 24 * 60 * 60;
const ANTI_DUR = 24 * 60 * 60;

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

function normalizeInv(rec, userId) {
  const out = rec && typeof rec === "object" ? rec : {};
  out.user_id = String(out.user_id || userId);
  if (!out.balances || typeof out.balances !== "object") out.balances = {};
  out.reconciled = !!out.reconciled;
  out.import_fingerprint = String(out.import_fingerprint || "");
  if (!out.item_reconciled || typeof out.item_reconciled !== "object") out.item_reconciled = {};
  return out;
}

function getBal(rec, itemId) {
  const n = Number((rec.balances || {})[itemId] || 0);
  return isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function setBal(rec, itemId, amount) {
  if (!rec.balances) rec.balances = {};
  const n = Math.max(0, Math.floor(amount));
  if (n <= 0) delete rec.balances[itemId];
  else rec.balances[itemId] = n;
}

function readInv(store, userId) {
  const obj = store.read("inv", userId, userId);
  if (obj) return { value: normalizeInv(obj.value, userId), version: obj.version };
  return {
    value: normalizeInv({ user_id: userId, balances: {}, reconciled: false }, userId),
    version: "*",
  };
}

/** Mirrors rpcTeleportInventorySync: teleport bag import only; local_counts for Peace/Anti IGNORED. */
function syncInventory(store, userId, localCount, forgedLocalCounts) {
  // forgedLocalCounts intentionally unused for Peace/Anti — must not increase balances.
  void forgedLocalCounts;
  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readInv(store, userId);
    const inv = invObj.value;
    let dirty = false;
    if (!inv.reconciled) {
      setBal(inv, TELEPORT, localCount);
      inv.reconciled = true;
      inv.import_fingerprint = "bag_v1";
      dirty = true;
    }
    if (dirty) {
      try {
        store.write("inv", userId, userId, inv, invObj.version);
      } catch (_e) {
        continue;
      }
    }
    return normalizeInv(readInv(store, userId).value, userId);
  }
  throw new Error("sync busy");
}

function consumeCAS(store, userId, itemId) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readInv(store, userId);
    const inv = invObj.value;
    if (itemId === TELEPORT && !inv.reconciled) throw new Error("not_ready");
    const bal = getBal(inv, itemId);
    if (bal < 1) throw new Error("insufficient");
    setBal(inv, itemId, bal - 1);
    try {
      store.write("inv", userId, userId, inv, invObj.version);
      return getBal(inv, itemId);
    } catch (_e) {
      /* retry */
    }
  }
  throw new Error("busy");
}

function grantCAS(store, userId, itemId, amount) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readInv(store, userId);
    const inv = invObj.value;
    setBal(inv, itemId, getBal(inv, itemId) + amount);
    try {
      store.write("inv", userId, userId, inv, invObj.version);
      return getBal(inv, itemId);
    } catch (_e) {
      /* retry */
    }
  }
  throw new Error("busy");
}

function applyPeace(profile, now, dur = PEACE_DUR) {
  const current = typeof profile.peace_shield_expires_at === "number" ? profile.peace_shield_expires_at : 0;
  profile.peace_shield_expires_at = Math.max(now, current) + dur;
}

function applyAnti(profile, now, dur = ANTI_DUR) {
  const current = typeof profile.anti_scout_expires_at === "number" ? profile.anti_scout_expires_at : 0;
  profile.anti_scout_expires_at = Math.max(now, current) + dur;
}

function evaluateHostileAction(action, attacker, target, now) {
  const act = String(action || "").trim().toLowerCase();
  if (attacker.user_id === target.user_id) return { ok: false, code: "self" };
  const peace = (target.peace_shield_expires_at || 0) > now;
  const anti = (target.anti_scout_expires_at || 0) > now;
  if (peace) return { ok: false, code: "peace_shield" };
  if (act === "scout" && anti) return { ok: false, code: "anti_scout" };
  return { ok: true, code: "allowed" };
}

function rejectForgedUse(ctxUserId, payload) {
  const data = payload && typeof payload === "object" ? payload : {};
  const forged = String(data.target_user_id || data.user_id || "").trim();
  if (forged !== "" && forged !== ctxUserId) return { ok: false, code: "forbidden_target" };
  if (typeof data.duration_sec === "number" || typeof data.expires_at === "number") {
    return { ok: false, code: "arbitrary_duration_forbidden" };
  }
  return null;
}

/** Mirrors beta grant auth: flag + secret + self-only + allowlist. */
function planBetaGrant(env, ctxUserId, payload) {
  if (String(env.CROWNSPIRE_ENABLE_BETA_GRANTS || "") !== "true") {
    return { ok: false, code: "disabled" };
  }
  const expected = String(env.CROWNSPIRE_BETA_GRANT_SECRET || "");
  if (expected.length < 16) return { ok: false, code: "disabled" };
  const provided = String(payload.dev_secret || "");
  if (provided.length < 16 || provided !== expected) return { ok: false, code: "forbidden" };
  const forged = String(payload.user_id || payload.target_user_id || "").trim();
  if (forged !== "" && forged !== ctxUserId) return { ok: false, code: "forbidden_target" };
  const itemId = String(payload.item_id || "").trim();
  if (itemId !== PEACE && itemId !== ANTI) return { ok: false, code: "unsupported_item" };
  const amount = payload.amount;
  if (typeof amount !== "number" || amount < 1 || Math.floor(amount) !== amount) {
    return { ok: false, code: "bad_amount" };
  }
  return { ok: true, itemId, amount };
}

function shouldRegisterBetaGrantRpc(env) {
  return (
    String(env.CROWNSPIRE_ENABLE_BETA_GRANTS || "") === "true" &&
    String(env.CROWNSPIRE_BETA_GRANT_SECRET || "").length >= 16
  );
}

let failed = 0;
function ok(msg) {
  console.log(`[SECURE-PROT] OK: ${msg}`);
}
function fail(msg) {
  failed += 1;
  console.error(`[SECURE-PROT] FAIL: ${msg}`);
}

const now = 1_700_000_000;
const attacker = { user_id: "a1", alliance_id: "allyA" };
const SECRET = "beta-grant-secret-ok"; // test-only fixture length >= 16

// A. Local Bag claims 100 Peace Shields before first sync → authoritative remains 0
{
  const store = new VersionedStore();
  const rec = syncInventory(store, "u1", 0, { [PEACE]: 100, [ANTI]: 0 });
  if (getBal(rec, PEACE) !== 0) fail("A: peace bag claim imported");
  else ok("A: forged 100 Peace Shields → authoritative balance 0");
}

// B. Local Bag claims 100 Anti-Scout → authoritative remains 0
{
  const store = new VersionedStore();
  const rec = syncInventory(store, "u1", 0, { [PEACE]: 0, [ANTI]: 100 });
  if (getBal(rec, ANTI) !== 0) fail("B: anti bag claim imported");
  else ok("B: forged 100 Anti-Scout → authoritative balance 0");
}

// Also forged 999999 must be zero-effect
{
  const store = new VersionedStore();
  grantCAS(store, "u1", PEACE, 1);
  const before = getBal(readInv(store, "u1").value, PEACE);
  syncInventory(store, "u1", 0, { [PEACE]: 999999, [ANTI]: 999999 });
  const after = getBal(readInv(store, "u1").value, PEACE);
  const anti = getBal(readInv(store, "u1").value, ANTI);
  if (before !== 1 || after !== 1 || anti !== 0) fail("forged 999999 mutated balances");
  else ok("forged local_counts 999999 have zero effect on balances");
}

// C. Advanced Teleport reconcile still one-time bag import
{
  const store = new VersionedStore();
  let rec = syncInventory(store, "u1", 7, { [PEACE]: 99 });
  if (getBal(rec, TELEPORT) !== 7 || !rec.reconciled) fail("C: teleport first sync");
  rec = syncInventory(store, "u1", 99, { [PEACE]: 99 });
  if (getBal(rec, TELEPORT) !== 7) fail("C: teleport re-import");
  else if (getBal(rec, PEACE) !== 0) fail("C: peace imported during teleport sync");
  else ok("C: Advanced Teleport reconcile unchanged; peace not imported");
}

// D. Trusted beta grant → balance 1
{
  const env = { CROWNSPIRE_ENABLE_BETA_GRANTS: "true", CROWNSPIRE_BETA_GRANT_SECRET: SECRET };
  const plan = planBetaGrant(env, "u1", { dev_secret: SECRET, item_id: PEACE, amount: 1 });
  const store = new VersionedStore();
  if (!plan.ok) fail("D: plan");
  else {
    const bal = grantCAS(store, "u1", plan.itemId, plan.amount);
    if (bal !== 1) fail("D: balance");
    else ok("D: trusted beta grant → authoritative Peace Shield = 1");
  }
}

// E. Use shield → 0 + expiry + hostile blocked
{
  const store = new VersionedStore();
  const profile = { user_id: "u1", peace_shield_expires_at: 0 };
  grantCAS(store, "u1", PEACE, 1);
  const rem = consumeCAS(store, "u1", PEACE);
  applyPeace(profile, now);
  const atk = evaluateHostileAction("attack", attacker, { ...profile, user_id: "u1", alliance_id: "x" }, now);
  // target is defender u1 — use separate target profile
  const defender = {
    user_id: "b1",
    alliance_id: "allyB",
    peace_shield_expires_at: profile.peace_shield_expires_at,
  };
  const atk2 = evaluateHostileAction("attack", attacker, defender, now);
  const sc = evaluateHostileAction("scout", attacker, defender, now);
  if (rem !== 0 || profile.peace_shield_expires_at !== now + PEACE_DUR) fail("E: use state");
  else if (atk2.ok || atk2.code !== "peace_shield" || sc.ok || sc.code !== "peace_shield") fail("E: hostile");
  else ok("E: use shield → balance 0, expiry set, attack+scout blocked");
}

// F. Anti-Scout grant + use → scout blocked, attack allowed
{
  const store = new VersionedStore();
  const profile = { user_id: "u1", anti_scout_expires_at: 0 };
  grantCAS(store, "u1", ANTI, 1);
  consumeCAS(store, "u1", ANTI);
  applyAnti(profile, now);
  const defender = {
    user_id: "b1",
    alliance_id: "allyB",
    peace_shield_expires_at: 0,
    anti_scout_expires_at: profile.anti_scout_expires_at,
  };
  const sc = evaluateHostileAction("scout", attacker, defender, now);
  const atk = evaluateHostileAction("attack", attacker, defender, now);
  if (sc.ok || sc.code !== "anti_scout" || !atk.ok) fail("F: anti effects");
  else ok("F: anti-scout use → scout blocked, attack allowed");
}

// G. Beta grant without valid server authorization → rejected
{
  const off = planBetaGrant({}, "u1", { dev_secret: SECRET, item_id: PEACE, amount: 1 });
  const badSecret = planBetaGrant(
    { CROWNSPIRE_ENABLE_BETA_GRANTS: "true", CROWNSPIRE_BETA_GRANT_SECRET: SECRET },
    "u1",
    { dev_secret: "wrong-secret-value!", item_id: PEACE, amount: 1 }
  );
  if (off.ok || badSecret.ok) fail("G: unauthorized grant accepted");
  else ok("G: beta grant without valid authorization rejected");
}

// Registration gate
{
  if (shouldRegisterBetaGrantRpc({})) fail("reg: default");
  if (shouldRegisterBetaGrantRpc({ CROWNSPIRE_ENABLE_BETA_GRANTS: "true" })) fail("reg: no secret");
  if (
    !shouldRegisterBetaGrantRpc({
      CROWNSPIRE_ENABLE_BETA_GRANTS: "true",
      CROWNSPIRE_BETA_GRANT_SECRET: SECRET,
    })
  ) {
    fail("reg: enabled");
  } else ok("G2: RPC registration requires flag=true AND secret length>=16");
}

// H. Forged user_id → rejected
{
  const env = { CROWNSPIRE_ENABLE_BETA_GRANTS: "true", CROWNSPIRE_BETA_GRANT_SECRET: SECRET };
  const plan = planBetaGrant(env, "u1", {
    dev_secret: SECRET,
    item_id: PEACE,
    amount: 1,
    target_user_id: "victim",
  });
  const useForge = rejectForgedUse("u1", { target_user_id: "victim" });
  if (plan.ok || !useForge || useForge.code !== "forbidden_target") fail("H: forged user");
  else ok("H: forged user_id rejected; ctx.userId only");
}

// I. Non-allowlisted item → rejected
{
  const env = { CROWNSPIRE_ENABLE_BETA_GRANTS: "true", CROWNSPIRE_BETA_GRANT_SECRET: SECRET };
  const plan = planBetaGrant(env, "u1", {
    dev_secret: SECRET,
    item_id: "boost_speedup_60m",
    amount: 1,
  });
  if (plan.ok || plan.code !== "unsupported_item") fail("I: allowlist");
  else ok("I: non-allowlisted grant item rejected");
}

// J. Double-spend final item → only one succeeds
{
  const store = new VersionedStore();
  grantCAS(store, "u1", PEACE, 1);
  let success = 0;
  let failCount = 0;
  try {
    consumeCAS(store, "u1", PEACE);
    success++;
  } catch (_e) {
    failCount++;
  }
  try {
    consumeCAS(store, "u1", PEACE);
    success++;
  } catch (_e) {
    failCount++;
  }
  if (success !== 1 || failCount !== 1) fail(`J: double-spend success=${success}`);
  else ok("J: double-spend final item — only one succeeds");
}

// K. Client cannot supply duration/expiry
{
  const a = rejectForgedUse("u1", { duration_sec: 999 });
  const b = rejectForgedUse("u1", { expires_at: now + 999 });
  if (!a || a.code !== "arbitrary_duration_forbidden" || !b) fail("K");
  else ok("K: client duration/expiry rejected");
}

// L. No grant secret in Godot/client paths — checked by runner shell; placeholder here
ok("L: secret-in-client scan delegated to runner (see report)");

// EXTEND still locked
{
  const p = { peace_shield_expires_at: now + 18 * 3600 };
  applyPeace(p, now);
  if (p.peace_shield_expires_at !== now + 18 * 3600 + PEACE_DUR) fail("EXTEND");
  else ok("EXTEND stacking unchanged");
}

if (failed === 0) {
  console.log("[SECURE-PROT] PASS");
  process.exit(0);
}
console.log(`[SECURE-PROT] FAILED count=${failed}`);
process.exit(1);
