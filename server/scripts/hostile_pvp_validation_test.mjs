/**
 * Local Node smoke for phase56 hostile evaluation helpers.
 * Run: node server/scripts/hostile_pvp_validation_test.mjs
 *
 * Does NOT require a live Nakama process — mirrors gate rules in isolation.
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

if (failed === 0) {
  console.log("[HOSTILE-PVP] PASS");
  process.exit(0);
}
console.log(`[HOSTILE-PVP] FAILED count=${failed}`);
process.exit(1);
