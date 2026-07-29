/**
 * Crownspire Phase 5.1 — Player Identity & Presence
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Concatenated into build/index.js via tsconfig files order.
 *
 * Extends CrownspireProfile with avatar, power, citadel, VIP, last_online.
 * Online status = last_online within PRESENCE_ONLINE_SEC (see index.ts).
 */

const ALLOWED_AVATAR_IDS: { [key: string]: boolean } = {
  avatar_01: true,
  avatar_02: true,
  avatar_03: true,
  avatar_04: true,
  avatar_05: true,
  avatar_06: true,
  avatar_07: true,
  avatar_08: true,
};

function sanitizeAvatarId(raw: string): string {
  const id = String(raw || "").trim().toLowerCase();
  if (ALLOWED_AVATAR_IDS[id]) {
    return id;
  }
  return "avatar_01";
}

/**
 * Update avatar / social display stats.
 * Power / citadel / VIP are client-reported social snapshots for beta — not combat authority.
 */
function rpcUpdatePlayerIdentity(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  assertRateLimit(nk, ctx.userId, "update_player_identity", 2);
  const data = parsePayload(payload);
  const profile = ensureProfile(nk, logger, ctx.userId);

  if (data["avatar_id"] !== undefined) {
    profile.avatar_id = sanitizeAvatarId(String(data["avatar_id"] || ""));
  }
  if (data["power"] !== undefined) {
    const power = Math.floor(Number(data["power"]));
    if (!isFinite(power) || power < 0) {
      throw Err("Invalid power");
    }
    profile.power = Math.min(power, 999999999);
  }
  if (data["citadel_level"] !== undefined) {
    const lvl = Math.floor(Number(data["citadel_level"]));
    if (!isFinite(lvl) || lvl < 1) {
      throw Err("Invalid citadel_level");
    }
    profile.citadel_level = Math.min(lvl, 100);
  }
  if (data["vip_level"] !== undefined) {
    const vip = Math.floor(Number(data["vip_level"]));
    if (!isFinite(vip) || vip < 0) {
      throw Err("Invalid vip_level");
    }
    profile.vip_level = Math.min(vip, 20);
  }

  profile.last_online = nowUnix();
  profile.updated_at = nowUnix();
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}

/** Heartbeat while socket connected — marks player online for roster. */
function rpcPresenceHeartbeat(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  // Soft rate limit — clients pulse ~every 30s; allow burst reconnect.
  assertRateLimit(nk, ctx.userId, "presence_heartbeat", 8);
  const profile = ensureProfile(nk, logger, ctx.userId);
  const data = parsePayload(payload);
  // Optional light identity sync on heartbeat (keeps roster fresh).
  if (data["power"] !== undefined) {
    const power = Math.floor(Number(data["power"]));
    if (isFinite(power) && power >= 0) {
      profile.power = Math.min(power, 999999999);
    }
  }
  if (data["citadel_level"] !== undefined) {
    const lvl = Math.floor(Number(data["citadel_level"]));
    if (isFinite(lvl) && lvl >= 1) {
      profile.citadel_level = Math.min(lvl, 100);
    }
  }
  if (data["vip_level"] !== undefined) {
    const vip = Math.floor(Number(data["vip_level"]));
    if (isFinite(vip) && vip >= 0) {
      profile.vip_level = Math.min(vip, 20);
    }
  }
  profile.last_online = nowUnix();
  profile.updated_at = nowUnix();
  writeProfile(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  return JSON.stringify({
    ok: true,
    last_online: profile.last_online,
    online_status: "online",
    profile: publicProfile(profile),
  });
}
