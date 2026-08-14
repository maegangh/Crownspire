/**
 * Crownspire hostile PvP + protection authority policy tests (no live Nakama).
 * Run: node server/scripts/hostile_pvp_validation_test.mjs
 *
 * Mirrors server/src/phase56_hostile_pvp.ts pure policy helpers.
 */

function protectionActive(expiresAt, now) {
  const exp = typeof expiresAt === "number" ? expiresAt : 0;
  return exp > now;
}

function evaluateHostileAction(action, attacker, target, now) {
  const act = String(action || "").trim().toLowerCase();
  if (act !== "attack" && act !== "scout") {
    return { ok: false, code: "invalid_action", reason: "Unsupported hostile action." };
  }
  if (!target || !target.user_id) {
    return { ok: false, code: "invalid_target", reason: "Target castle could not be resolved." };
  }
  if (attacker.user_id === target.user_id) {
    return { ok: false, code: "self", reason: "Cannot target your own city." };
  }
  const aAlliance = String(attacker.alliance_id || "").trim();
  const tAlliance = String(target.alliance_id || "").trim();
  if (aAlliance !== "" && tAlliance !== "" && aAlliance === tAlliance) {
    return {
      ok: false,
      code: "same_alliance",
      reason: act === "scout" ? "Cannot scout an alliance member." : "Cannot attack an alliance member.",
    };
  }
  const peace = protectionActive(target.peace_shield_expires_at, now);
  const beg =
    !Boolean(target.beginner_protection_cleared) &&
    protectionActive(target.beginner_protection_expires_at, now);
  const anti = protectionActive(target.anti_scout_expires_at, now);
  if (peace) {
    return { ok: false, code: "peace_shield", reason: "This city is protected by a Peace Shield." };
  }
  if (beg) {
    return { ok: false, code: "beginner_protection", reason: "This city is under Beginner Protection." };
  }
  if (act === "scout" && anti) {
    return { ok: false, code: "anti_scout", reason: "This city is protected by Anti-Scout." };
  }
  return { ok: true, code: "allowed", reason: "" };
}

const INV_AUTHORITY_REQUIRED =
  "Server inventory authority is required before this protection can be activated.";

function rejectClientProtectionActivation(kind, ctxUserId, payload) {
  const data = payload && typeof payload === "object" ? payload : {};
  const forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (forgedTarget !== "" && forgedTarget !== String(ctxUserId || "").trim()) {
    return {
      ok: false,
      code: "forbidden_target",
      reason: "Cannot modify another player's protection.",
    };
  }
  if (typeof data["duration_sec"] === "number" || typeof data["expires_at"] === "number") {
    return {
      ok: false,
      code: "arbitrary_duration_forbidden",
      reason: "Client-supplied protection duration/expiry is not allowed.",
    };
  }
  return {
    ok: false,
    code: "inventory_authority_required",
    reason: INV_AUTHORITY_REQUIRED,
  };
}

function planBeginnerProtectionClientMutation(ctxUserId, payload, profile, _now) {
  const data = payload && typeof payload === "object" ? payload : {};
  const forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (forgedTarget !== "" && forgedTarget !== String(ctxUserId || "").trim()) {
    return { ok: false, code: "forbidden_target", reason: "Cannot modify another player's protection." };
  }
  if (String(profile.user_id) !== String(ctxUserId)) {
    return { ok: false, code: "forbidden_target", reason: "Cannot modify another player's protection." };
  }
  if (data["clear"] === true) {
    return { ok: true, code: "clear_own", reason: "", clear: true, expires_at: 0 };
  }
  if (typeof data["expires_at"] === "number" || typeof data["duration_sec"] === "number") {
    return {
      ok: false,
      code: "beginner_grant_forbidden",
      reason: "Beginner Protection cannot be granted or extended by the client.",
    };
  }
  return {
    ok: false,
    code: "beginner_grant_forbidden",
    reason: "Beginner Protection cannot be granted or extended by the client.",
  };
}

/** Simulate clear-own: never increases expiry. */
function applyClearOwnBeginner(profile) {
  const before =
    typeof profile.beginner_protection_expires_at === "number"
      ? profile.beginner_protection_expires_at
      : 0;
  profile.beginner_protection_expires_at = 0;
  profile.beginner_protection_cleared = true;
  if (profile.beginner_protection_expires_at > before) {
    throw new Error("clear increased expiry");
  }
  return profile;
}

let failed = 0;
function ok(msg) {
  console.log(`[HOSTILE-PVP] OK: ${msg}`);
}
function fail(msg) {
  failed += 1;
  console.error(`[HOSTILE-PVP] FAIL: ${msg}`);
}

const now = 1_700_000_000;
const attacker = { user_id: "a1", alliance_id: "allyA" };
const enemy = {
  user_id: "b1",
  alliance_id: "allyB",
  peace_shield_expires_at: 0,
  anti_scout_expires_at: 0,
  beginner_protection_expires_at: 0,
  beginner_protection_cleared: false,
};

// --- Core hostile gate ---
if (!evaluateHostileAction("attack", attacker, enemy, now).ok) fail("enemy attack should allow");
else ok("enemy attack allowed");
if (!evaluateHostileAction("scout", attacker, enemy, now).ok) fail("enemy scout should allow");
else ok("enemy scout allowed");

const selfGate = evaluateHostileAction("attack", attacker, { ...enemy, user_id: "a1" }, now);
if (selfGate.ok || selfGate.code !== "self") fail("self must block");
else ok("self blocked");

const allyGate = evaluateHostileAction("attack", attacker, { ...enemy, alliance_id: "allyA" }, now);
if (allyGate.ok || allyGate.code !== "same_alliance") fail("alliance must block");
else ok("alliance blocked");

const shieldGate = evaluateHostileAction(
  "scout",
  attacker,
  { ...enemy, peace_shield_expires_at: now + 100 },
  now
);
if (shieldGate.ok || !String(shieldGate.reason).includes("Peace Shield")) fail("shield reason");
else ok("peace shield blocked");

const begGate = evaluateHostileAction(
  "attack",
  attacker,
  { ...enemy, beginner_protection_expires_at: now + 100 },
  now
);
if (begGate.ok || !String(begGate.reason).includes("Beginner Protection")) fail("beginner reason");
else ok("beginner blocked");

const stale = evaluateHostileAction("attack", attacker, { user_id: "" }, now);
if (stale.ok) fail("empty target must fail");
else ok("invalid target rejected");

// J. Legitimate protection still readable by validate
const legitShield = evaluateHostileAction(
  "attack",
  attacker,
  { ...enemy, peace_shield_expires_at: now + 999 },
  now
);
if (legitShield.ok || legitShield.code !== "peace_shield") fail("J: legitimate shield not read");
else ok("J: hostile validation reads legitimate protection state");

// A. Free shield activation without inventory entitlement → BLOCKED
const freeShield = rejectClientProtectionActivation("peace_shield", "a1", {});
if (freeShield.ok || freeShield.code !== "inventory_authority_required") fail("A: free shield");
else ok("A: free shield activation blocked");

// B. Arbitrary shield duration → BLOCKED
const arbDur = rejectClientProtectionActivation("peace_shield", "a1", { duration_sec: 999999 });
if (arbDur.ok || arbDur.code !== "arbitrary_duration_forbidden") fail("B: arbitrary duration");
else ok("B: arbitrary shield duration blocked");

// C. Shield mutation targeting another user → BLOCKED
const forgedShield = rejectClientProtectionActivation("peace_shield", "a1", {
  target_user_id: "victim",
});
if (forgedShield.ok || forgedShield.code !== "forbidden_target") fail("C: forged target");
else ok("C: shield forged target blocked");

// D. Free Anti-Scout → BLOCKED
const freeAnti = rejectClientProtectionActivation("anti_scout", "a1", {});
if (freeAnti.ok || freeAnti.code !== "inventory_authority_required") fail("D: free anti-scout");
else ok("D: free Anti-Scout blocked");

// E. Arbitrary Anti-Scout duration → BLOCKED
const antiDur = rejectClientProtectionActivation("anti_scout", "a1", { expires_at: now + 99999 });
if (antiDur.ok || antiDur.code !== "arbitrary_duration_forbidden") fail("E: anti duration");
else ok("E: arbitrary Anti-Scout duration blocked");

// F. Normal client grants itself Beginner Protection → BLOCKED
const selfGrant = planBeginnerProtectionClientMutation(
  "a1",
  { duration_sec: 86400 },
  { user_id: "a1", beginner_protection_expires_at: 0 },
  now
);
if (selfGrant.ok || selfGrant.code !== "beginner_grant_forbidden") fail("F: self grant");
else ok("F: client beginner grant blocked");

// G. Normal client extends Beginner Protection → BLOCKED
const extend = planBeginnerProtectionClientMutation(
  "a1",
  { expires_at: now + 999999 },
  { user_id: "a1", beginner_protection_expires_at: now + 100 },
  now
);
if (extend.ok || extend.code !== "beginner_grant_forbidden") fail("G: extend");
else ok("G: client beginner extend blocked");

// H. Normal client modifies another player's Beginner Protection → BLOCKED
const otherBeg = planBeginnerProtectionClientMutation(
  "a1",
  { clear: true, target_user_id: "b1" },
  { user_id: "a1" },
  now
);
if (otherBeg.ok || otherBeg.code !== "forbidden_target") fail("H: other player");
else ok("H: forged beginner target blocked");

// Also profile.user_id mismatch
const mismatch = planBeginnerProtectionClientMutation(
  "a1",
  { clear: true },
  { user_id: "b1" },
  now
);
if (mismatch.ok || mismatch.code !== "forbidden_target") fail("H2: profile mismatch");
else ok("H2: beginner profile binding enforced");

// I. Allowed clear cannot increase expiry
const clearPlan = planBeginnerProtectionClientMutation(
  "a1",
  { clear: true },
  { user_id: "a1", beginner_protection_expires_at: now + 5000 },
  now
);
if (!clearPlan.ok || !clearPlan.clear) fail("I: clear plan");
else {
  const p = applyClearOwnBeginner({
    user_id: "a1",
    beginner_protection_expires_at: now + 5000,
    beginner_protection_cleared: false,
  });
  if (p.beginner_protection_expires_at !== 0 || !p.beginner_protection_cleared) fail("I: clear apply");
  else ok("I: clear-own cannot increase expiry");
}

if (failed === 0) {
  console.log("[HOSTILE-PVP] PASS");
  process.exit(0);
}
console.log(`[HOSTILE-PVP] FAILED count=${failed}`);
process.exit(1);
