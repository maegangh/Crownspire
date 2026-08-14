/**
 * Crownspire — Hostile player-castle action validation (PvP foundation)
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Authoritative reject for scout/attack against:
 *  - self
 *  - same alliance
 *  - peace shield
 *  - beginner protection
 *  - missing/stale target profile
 *
 * PRODUCT — Peace Shield mid-flight:
 *  Shield blocks NEW hostile launches only. An attack/scout already validated
 *  and dispatched continues to resolve even if the defender activates a shield
 *  after launch.
 *
 * Does NOT run combat or marches. Client MarchState still owns travel/combat
 * until a future combat-authority phase. Realm Standing is intentionally omitted.
 */

const PEACE_SHIELD_DURATION_SEC = 3 * 24 * 60 * 60;
const ANTI_SCOUT_DURATION_SEC = 24 * 60 * 60;

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
      code: "invalid_target",
      reason: "Target castle could not be resolved.",
      error: "Target castle could not be resolved.",
    });
  }
  const attacker = ensureProfile(nk, logger, ctx.userId);
  let target: CrownspireProfile;
  try {
    target = ensureProfile(nk, logger, targetId);
  } catch (_e) {
    return JSON.stringify({
      ok: false,
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

/** Activate Peace Shield on the caller's city (item consumption is client-side for beta). */
function rpcActivatePeaceShield(
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
  const duration = typeof data["duration_sec"] === "number" && data["duration_sec"] > 0
    ? Math.floor(data["duration_sec"])
    : PEACE_SHIELD_DURATION_SEC;
  const profile = ensureProfile(nk, logger, ctx.userId);
  const now = nowUnix();
  const current = typeof (profile as any).peace_shield_expires_at === "number"
    ? (profile as any).peace_shield_expires_at
    : 0;
  const base = Math.max(now, current);
  (profile as any).peace_shield_expires_at = base + duration;
  profile.updated_at = now;
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({
    ok: true,
    expires_at: (profile as any).peace_shield_expires_at,
    duration_sec: duration,
    profile: publicProfile(profile),
  });
}

function rpcActivateAntiScout(
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
  const duration = typeof data["duration_sec"] === "number" && data["duration_sec"] > 0
    ? Math.floor(data["duration_sec"])
    : ANTI_SCOUT_DURATION_SEC;
  const profile = ensureProfile(nk, logger, ctx.userId);
  const now = nowUnix();
  const current = typeof (profile as any).anti_scout_expires_at === "number"
    ? (profile as any).anti_scout_expires_at
    : 0;
  const base = Math.max(now, current);
  (profile as any).anti_scout_expires_at = base + duration;
  profile.updated_at = now;
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({
    ok: true,
    expires_at: (profile as any).anti_scout_expires_at,
    duration_sec: duration,
    profile: publicProfile(profile),
  });
}

/**
 * Dev / future product hook for beginner protection.
 * Duration must be supplied — server refuses unexplained defaults.
 */
function rpcSetBeginnerProtection(
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
  const profile = ensureProfile(nk, logger, ctx.userId);
  const now = nowUnix();
  if (data["clear"] === true) {
    (profile as any).beginner_protection_expires_at = 0;
    (profile as any).beginner_protection_cleared = true;
  } else if (typeof data["expires_at"] === "number") {
    (profile as any).beginner_protection_expires_at = Math.floor(data["expires_at"]);
    (profile as any).beginner_protection_cleared = (profile as any).beginner_protection_expires_at <= now;
  } else if (typeof data["duration_sec"] === "number" && data["duration_sec"] > 0) {
    (profile as any).beginner_protection_expires_at = now + Math.floor(data["duration_sec"]);
    (profile as any).beginner_protection_cleared = false;
  } else {
    return JSON.stringify({
      ok: false,
      error: "beginner_protection requires expires_at or duration_sec (product value not locked).",
    });
  }
  profile.updated_at = now;
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({
    ok: true,
    beginner_protection_expires_at: (profile as any).beginner_protection_expires_at || 0,
    beginner_protection_cleared: Boolean((profile as any).beginner_protection_cleared),
    profile: publicProfile(profile),
  });
}
