/**
 * Crownspire — Hostile player-castle action validation + protection authority
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Public RPC surface (protection hardening):
 *  - crownspire_validate_hostile_action  (READ-ONLY gate)
 *  - crownspire_clear_own_beginner_protection (optional voluntary clear; cannot increase expiry)
 *
 * NOT registered for ordinary clients (no server item inventory for these yet):
 *  - Peace Shield activation / Anti-Scout activation / Beginner grant-extend
 * Internal trusted helpers are retained for future inventory/admin lifecycle only.
 *
 * PRODUCT — Peace Shield mid-flight:
 *  Shield blocks NEW hostile launches only. Already-dispatched marches continue.
 */

const PEACE_SHIELD_ITEM_ID = "boost_shield_peace_3d";
const ANTI_SCOUT_ITEM_ID = "boost_anti_scout_24h";
/** Design duration from Items.json — used only by trusted helpers, never by public RPC. */
const PEACE_SHIELD_DURATION_SEC = 3 * 24 * 60 * 60;
const ANTI_SCOUT_DURATION_SEC = 24 * 60 * 60;

const INV_AUTHORITY_REQUIRED =
  "Server inventory authority is required before this protection can be activated.";

function protectionActive(expiresAt: any, now: number): boolean {
  const exp = typeof expiresAt === "number" ? expiresAt : 0;
  return exp > now;
}

function hostileTargetSnapshot(profile: CrownspireProfile, now: number): any {
  const peaceExp = typeof (profile as any).peace_shield_expires_at === "number"
    ? (profile as any).peace_shield_expires_at
    : 0;
  const antiExp = typeof (profile as any).anti_scout_expires_at === "number"
    ? (profile as any).anti_scout_expires_at
    : 0;
  const begExp = typeof (profile as any).beginner_protection_expires_at === "number"
    ? (profile as any).beginner_protection_expires_at
    : 0;
  const begCleared = Boolean((profile as any).beginner_protection_cleared);
  return {
    user_id: profile.user_id,
    display_name: profile.display_name || "",
    kingdom_id: profile.kingdom_id || "",
    alliance_id: profile.alliance_id || "",
    alliance_tag: profile.alliance_tag || "",
    alliance_name: profile.alliance_name || "",
    world_x: typeof (profile as any).world_x === "number" ? (profile as any).world_x : 0,
    world_y: typeof (profile as any).world_y === "number" ? (profile as any).world_y : 0,
    citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
    power: typeof profile.power === "number" ? profile.power : 0,
    peace_shield_expires_at: peaceExp,
    anti_scout_expires_at: antiExp,
    beginner_protection_expires_at: begExp,
    beginner_protection_cleared: begCleared,
    peace_shield_active: protectionActive(peaceExp, now),
    anti_scout_active: protectionActive(antiExp, now),
    beginner_protection_active: !begCleared && protectionActive(begExp, now),
    resolved: true,
  };
}

function evaluateHostileAction(
  action: string,
  attacker: CrownspireProfile,
  target: CrownspireProfile,
  now: number
): { ok: boolean; code: string; reason: string } {
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
  const snap = hostileTargetSnapshot(target, now);
  if (snap.peace_shield_active) {
    return { ok: false, code: "peace_shield", reason: "This city is protected by a Peace Shield." };
  }
  if (snap.beginner_protection_active) {
    return { ok: false, code: "beginner_protection", reason: "This city is under Beginner Protection." };
  }
  if (act === "scout" && snap.anti_scout_active) {
    return { ok: false, code: "anti_scout", reason: "This city is protected by Anti-Scout." };
  }
  return { ok: true, code: "allowed", reason: "" };
}

/**
 * Pure policy: ordinary clients cannot grant Peace Shield / Anti-Scout.
 * Used by tests + deny stubs. Does not mutate storage.
 */
function rejectClientProtectionActivation(
  kind: string,
  ctxUserId: string,
  payload: any
): { ok: false; code: string; reason: string; error: string } {
  const data = payload && typeof payload === "object" ? payload : {};
  const forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (forgedTarget !== "" && forgedTarget !== String(ctxUserId || "").trim()) {
    return {
      ok: false,
      code: "forbidden_target",
      reason: "Cannot modify another player's protection.",
      error: "Cannot modify another player's protection.",
    };
  }
  if (typeof data["duration_sec"] === "number" || typeof data["expires_at"] === "number") {
    return {
      ok: false,
      code: "arbitrary_duration_forbidden",
      reason: "Client-supplied protection duration/expiry is not allowed.",
      error: "Client-supplied protection duration/expiry is not allowed.",
    };
  }
  const label = kind === "anti_scout" ? "Anti-Scout (" + ANTI_SCOUT_ITEM_ID + ")" : "Peace Shield (" + PEACE_SHIELD_ITEM_ID + ")";
  return {
    ok: false,
    code: "inventory_authority_required",
    reason: label + ": " + INV_AUTHORITY_REQUIRED,
    error: label + ": " + INV_AUTHORITY_REQUIRED,
  };
}

/**
 * Pure policy for beginner protection mutations from ordinary clients.
 * Only voluntary clear of OWN protection is allowed. Grants/extends/forged targets blocked.
 */
function planBeginnerProtectionClientMutation(
  ctxUserId: string,
  payload: any,
  profile: { user_id: string; beginner_protection_expires_at?: number; beginner_protection_cleared?: boolean },
  now: number
): { ok: boolean; code: string; reason: string; clear?: boolean; expires_at?: number } {
  const data = payload && typeof payload === "object" ? payload : {};
  const forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (forgedTarget !== "" && forgedTarget !== String(ctxUserId || "").trim()) {
    return {
      ok: false,
      code: "forbidden_target",
      reason: "Cannot modify another player's protection.",
    };
  }
  if (String(profile.user_id) !== String(ctxUserId)) {
    return {
      ok: false,
      code: "forbidden_target",
      reason: "Cannot modify another player's protection.",
    };
  }
  if (data["clear"] === true) {
    return {
      ok: true,
      code: "clear_own",
      reason: "",
      clear: true,
      expires_at: 0,
    };
  }
  // Any grant / extend / restore path is forbidden for ordinary clients.
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

function rpcValidateHostileAction(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  let data: any = {};
  try {
    data = payload ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid payload");
  }
  const action = String(data["action"] || "").trim().toLowerCase();
  const targetId = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (!targetId) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "invalid_target",
      reason: "Target castle could not be resolved.",
      error: "Target castle could not be resolved.",
    });
  }
  // READ-ONLY: load profiles, evaluate, return. Never write protection / inventory / alliance.
  const attacker = ensureProfile(nk, logger, ctx.userId);
  let target: CrownspireProfile;
  try {
    target = ensureProfile(nk, logger, targetId);
  } catch (_e) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "stale_target",
      reason: "Target castle is no longer available.",
      error: "Target castle is no longer available.",
    });
  }
  const now = nowUnix();
  const gate = evaluateHostileAction(action, attacker, target, now);
  const snap = hostileTargetSnapshot(target, now);
  if (!gate.ok) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: gate.code,
      reason: gate.reason,
      error: gate.reason,
      action: action,
      target: snap,
    });
  }
  return JSON.stringify({
    ok: true,
    authority_verified: true,
    code: "allowed",
    reason: "",
    action: action,
    target: snap,
  });
}

/**
 * Public voluntary clear of the caller's own Beginner Protection.
 * Never increases expiry. Identity from ctx.userId only.
 */
function rpcClearOwnBeginnerProtection(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  let data: any = {};
  try {
    data = payload ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid payload");
  }
  // Force clear-only semantics regardless of client payload extras.
  const clearPayload = { clear: true };
  const forged = String(data["target_user_id"] || data["user_id"] || "").trim();
  if (forged !== "" && forged !== ctx.userId) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "forbidden_target",
      reason: "Cannot modify another player's protection.",
      error: "Cannot modify another player's protection.",
    });
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  const now = nowUnix();
  const plan = planBeginnerProtectionClientMutation(ctx.userId, clearPayload, profile as any, now);
  if (!plan.ok || !plan.clear) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: plan.code,
      reason: plan.reason,
      error: plan.reason,
    });
  }
  const before = typeof (profile as any).beginner_protection_expires_at === "number"
    ? (profile as any).beginner_protection_expires_at
    : 0;
  (profile as any).beginner_protection_expires_at = 0;
  (profile as any).beginner_protection_cleared = true;
  // Invariant: clear must never increase expiry.
  if ((profile as any).beginner_protection_expires_at > before) {
    throw Err("Beginner clear integrity failure");
  }
  profile.updated_at = now;
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({
    ok: true,
    authority_verified: true,
    code: "cleared",
    beginner_protection_expires_at: 0,
    beginner_protection_cleared: true,
    profile: publicProfile(profile),
  });
}

/**
 * TRUSTED INTERNAL ONLY — never register as a public client RPC.
 * Requires future server inventory spend for Peace Shield item.
 */
function trustedApplyPeaceShield(profile: CrownspireProfile, now: number, durationSec: number): void {
  const dur = durationSec > 0 ? Math.floor(durationSec) : PEACE_SHIELD_DURATION_SEC;
  const current = typeof (profile as any).peace_shield_expires_at === "number"
    ? (profile as any).peace_shield_expires_at
    : 0;
  const base = Math.max(now, current);
  (profile as any).peace_shield_expires_at = base + dur;
  profile.updated_at = now;
}

/**
 * TRUSTED INTERNAL ONLY — never register as a public client RPC.
 */
function trustedApplyAntiScout(profile: CrownspireProfile, now: number, durationSec: number): void {
  const dur = durationSec > 0 ? Math.floor(durationSec) : ANTI_SCOUT_DURATION_SEC;
  const current = typeof (profile as any).anti_scout_expires_at === "number"
    ? (profile as any).anti_scout_expires_at
    : 0;
  const base = Math.max(now, current);
  (profile as any).anti_scout_expires_at = base + dur;
  profile.updated_at = now;
}

/**
 * TRUSTED INTERNAL ONLY — account lifecycle / admin tooling.
 * Ordinary clients must use clear-own RPC only.
 */
function trustedSetBeginnerProtection(
  profile: CrownspireProfile,
  now: number,
  opts: { expires_at?: number; duration_sec?: number; clear?: boolean }
): void {
  if (opts.clear === true) {
    (profile as any).beginner_protection_expires_at = 0;
    (profile as any).beginner_protection_cleared = true;
  } else if (typeof opts.expires_at === "number") {
    (profile as any).beginner_protection_expires_at = Math.floor(opts.expires_at);
    (profile as any).beginner_protection_cleared =
      (profile as any).beginner_protection_expires_at <= now;
  } else if (typeof opts.duration_sec === "number" && opts.duration_sec > 0) {
    (profile as any).beginner_protection_expires_at = now + Math.floor(opts.duration_sec);
    (profile as any).beginner_protection_cleared = false;
  }
  profile.updated_at = now;
}
