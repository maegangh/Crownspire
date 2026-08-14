/**
 * Crownspire — Hostile player-castle action validation + protection authority
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Public RPC surface (protection + secure consumables):
 *  - crownspire_validate_hostile_action  (READ-ONLY gate)
 *  - crownspire_use_peace_shield         (spend 1 authoritative Peace Shield → EXTEND expiry)
 *  - crownspire_use_anti_scout           (spend 1 authoritative Anti-Scout → EXTEND expiry)
 *  - crownspire_clear_own_beginner_protection (optional voluntary clear; cannot increase expiry)
 *
 * NOT registered for ordinary clients:
 *  - free activate_peace_shield / activate_anti_scout (no spend)
 *  - beginner grant/extend
 *  - any target_user_id mutation of self-protection
 *
 * PRODUCT — Peace Shield / Anti-Scout stacking (EXTEND):
 *  expires_at = max(now, current_expires_at) + item_duration
 *
 * PRODUCT — Peace Shield mid-flight:
 *  Shield blocks NEW hostile launches only. Already-dispatched marches continue.
 *
 * PRODUCT — Anti-Scout:
 *  Blocks Scout only; does not block Attack.
 */

const PEACE_SHIELD_ITEM_ID = "boost_shield_peace_3d";
const ANTI_SCOUT_ITEM_ID = "boost_anti_scout_24h";
/** Design duration from Items.json — used only by trusted helpers / use RPCs, never client-supplied. */
const PEACE_SHIELD_DURATION_SEC = 3 * 24 * 60 * 60;
const ANTI_SCOUT_DURATION_SEC = 24 * 60 * 60;

const INV_AUTHORITY_REQUIRED =
  "Server inventory authority is required before this protection can be activated.";

/**
 * Guard for free/arbitrary activate payloads (no inventory spend).
 * Legitimate activation is crownspire_use_peace_shield / crownspire_use_anti_scout only.
 */

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
 * PRODUCT stacking = EXTEND: expires = max(now, current) + duration.
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
 * PRODUCT stacking = EXTEND (same as Peace Shield).
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

function parseProtectionUsePayload(payload: string): any {
  try {
    return payload && payload.length > 0 ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid payload");
  }
}

function rejectForgedProtectionUseFields(
  ctxUserId: string,
  data: any
): { ok: false; code: string; reason: string; error: string } | null {
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
  return null;
}

/**
 * Spend 1 authoritative Peace Shield → EXTEND peace_shield_expires_at for ctx.userId only.
 */
function rpcUsePeaceShield(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parseProtectionUsePayload(payload);
  const forged = rejectForgedProtectionUseFields(ctx.userId, data);
  if (forged) return JSON.stringify(Object.assign({ authority_verified: true }, forged));

  const invProbe = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
  if (getSecureBalance(invProbe, PEACE_SHIELD_ITEM_ID) < 1) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "insufficient",
      reason: "No Peace Shields available.",
      error: "No Peace Shields available.",
    });
  }

  let remaining = 0;
  try {
    remaining = consumeSecureItemCAS(nk, ctx.userId, PEACE_SHIELD_ITEM_ID);
  } catch (e) {
    const msg = e instanceof Error ? String(e.message || e) : String(e);
    const code = msg.indexOf("No Peace Shields") >= 0 ? "insufficient" : "inventory_busy";
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: code,
      reason: msg.indexOf("No Peace Shields") >= 0 ? "No Peace Shields available." : "Unable to activate Peace Shield right now.",
      error: msg.indexOf("No Peace Shields") >= 0 ? "No Peace Shields available." : "Unable to activate Peace Shield right now.",
    });
  }

  try {
    const profile = ensureProfile(nk, logger, ctx.userId);
    const now = nowUnix();
    trustedApplyPeaceShield(profile, now, PEACE_SHIELD_DURATION_SEC);
    writeProfile(nk, profile);
    upsertKingdomCastleEntry(nk, profile);
    const expiresAt = Number((profile as any).peace_shield_expires_at || 0);
    logger.info(
      "Peace Shield used user=%s expires_at=%d remaining=%d",
      ctx.userId,
      expiresAt,
      remaining
    );
    return JSON.stringify({
      ok: true,
      authority_verified: true,
      code: "activated",
      item_id: PEACE_SHIELD_ITEM_ID,
      duration_sec: PEACE_SHIELD_DURATION_SEC,
      expires_at: expiresAt,
      remaining: remaining,
      balance: remaining,
      peace_shield_expires_at: expiresAt,
      peace_shield_active: expiresAt > now,
      profile: publicProfile(profile),
    });
  } catch (e) {
    try {
      refundSecureItemCAS(nk, ctx.userId, PEACE_SHIELD_ITEM_ID);
    } catch (refundErr) {
      logger.error("Peace Shield refund failed: %s", String(refundErr));
    }
    logger.error("Peace Shield activate failed: %s", String(e));
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "activate_failed",
      reason: "Unable to activate Peace Shield right now.",
      error: "Unable to activate Peace Shield right now.",
    });
  }
}

/**
 * Spend 1 authoritative Anti-Scout → EXTEND anti_scout_expires_at for ctx.userId only.
 */
function rpcUseAntiScout(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parseProtectionUsePayload(payload);
  const forged = rejectForgedProtectionUseFields(ctx.userId, data);
  if (forged) return JSON.stringify(Object.assign({ authority_verified: true }, forged));

  const invProbe = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
  if (getSecureBalance(invProbe, ANTI_SCOUT_ITEM_ID) < 1) {
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "insufficient",
      reason: "No Anti-Scout items available.",
      error: "No Anti-Scout items available.",
    });
  }

  let remaining = 0;
  try {
    remaining = consumeSecureItemCAS(nk, ctx.userId, ANTI_SCOUT_ITEM_ID);
  } catch (e) {
    const msg = e instanceof Error ? String(e.message || e) : String(e);
    const insufficient = msg.indexOf("No Anti-Scout") >= 0;
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: insufficient ? "insufficient" : "inventory_busy",
      reason: insufficient ? "No Anti-Scout items available." : "Unable to activate Anti-Scout right now.",
      error: insufficient ? "No Anti-Scout items available." : "Unable to activate Anti-Scout right now.",
    });
  }

  try {
    const profile = ensureProfile(nk, logger, ctx.userId);
    const now = nowUnix();
    trustedApplyAntiScout(profile, now, ANTI_SCOUT_DURATION_SEC);
    writeProfile(nk, profile);
    upsertKingdomCastleEntry(nk, profile);
    const expiresAt = Number((profile as any).anti_scout_expires_at || 0);
    logger.info(
      "Anti-Scout used user=%s expires_at=%d remaining=%d",
      ctx.userId,
      expiresAt,
      remaining
    );
    return JSON.stringify({
      ok: true,
      authority_verified: true,
      code: "activated",
      item_id: ANTI_SCOUT_ITEM_ID,
      duration_sec: ANTI_SCOUT_DURATION_SEC,
      expires_at: expiresAt,
      remaining: remaining,
      balance: remaining,
      anti_scout_expires_at: expiresAt,
      anti_scout_active: expiresAt > now,
      profile: publicProfile(profile),
    });
  } catch (e) {
    try {
      refundSecureItemCAS(nk, ctx.userId, ANTI_SCOUT_ITEM_ID);
    } catch (refundErr) {
      logger.error("Anti-Scout refund failed: %s", String(refundErr));
    }
    logger.error("Anti-Scout activate failed: %s", String(e));
    return JSON.stringify({
      ok: false,
      authority_verified: true,
      code: "activate_failed",
      reason: "Unable to activate Anti-Scout right now.",
      error: "Unable to activate Anti-Scout right now.",
    });
  }
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
