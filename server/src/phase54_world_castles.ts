/**
 * Crownspire — Kingdom world castles (beta)
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Assigns stable world_x/world_y per profile and maintains a kingdom registry
 * so clients can spawn real player castles on the world map.
 */

const KINGDOM_CASTLE_COLLECTION = "crownspire_kingdom_castles";
const WORLD_MAP_SIZE = 8192;
const CASTLE_EDGE_MARGIN = 900;

function hashUserToUnit(userId: string): number {
  let h = 2166136261;
  const s = String(userId || "");
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0) / 4294967295;
}

function assignDeterministicCastleCoords(userId: string): { x: number; y: number } {
  const u1 = hashUserToUnit(userId + ":x");
  const u2 = hashUserToUnit(userId + ":y");
  const span = WORLD_MAP_SIZE - CASTLE_EDGE_MARGIN * 2;
  return {
    x: Math.floor(CASTLE_EDGE_MARGIN + u1 * span),
    y: Math.floor(CASTLE_EDGE_MARGIN + u2 * span),
  };
}

function ensureCastleCoords(nk: nkruntime.Nakama, profile: CrownspireProfile): CrownspireProfile {
  const hasX = typeof (profile as any).world_x === "number" && isFinite((profile as any).world_x);
  const hasY = typeof (profile as any).world_y === "number" && isFinite((profile as any).world_y);
  if (hasX && hasY) {
    return profile;
  }
  const coords = assignDeterministicCastleCoords(profile.user_id);
  (profile as any).world_x = coords.x;
  (profile as any).world_y = coords.y;
  profile.updated_at = nowUnix();
  writeProfile(nk, profile);
  return profile;
}

function readKingdomCastleRegistry(nk: nkruntime.Nakama, kingdomId: string): { castles: any[] } {
  const objects = nk.storageRead([
    { collection: KINGDOM_CASTLE_COLLECTION, key: kingdomId, userId: SYSTEM_USER },
  ]);
  if (objects && objects.length > 0 && objects[0].value) {
    const v = objects[0].value as any;
    return { castles: Array.isArray(v.castles) ? v.castles : [] };
  }
  return { castles: [] };
}

function writeKingdomCastleRegistry(nk: nkruntime.Nakama, kingdomId: string, castles: any[]): void {
  nk.storageWrite([
    {
      collection: KINGDOM_CASTLE_COLLECTION,
      key: kingdomId,
      userId: SYSTEM_USER,
      value: { kingdom_id: kingdomId, castles: castles, updated_at: nowUnix() },
      permissionRead: 2,
      permissionWrite: 0,
    },
  ]);
}

function upsertKingdomCastleEntry(nk: nkruntime.Nakama, profile: CrownspireProfile): void {
  const kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
  ensureCastleCoords(nk, profile);
  const reg = readKingdomCastleRegistry(nk, kingdomId);
  const entry = {
    user_id: profile.user_id,
    display_name: profile.display_name || "",
    alliance_tag: profile.alliance_tag || "",
    alliance_name: profile.alliance_name || "",
    avatar_id: profile.avatar_id || "avatar_01",
    world_x: Number((profile as any).world_x),
    world_y: Number((profile as any).world_y),
    citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
    power: typeof profile.power === "number" ? profile.power : 0,
    updated_at: nowUnix(),
  };
  let found = false;
  for (let i = 0; i < reg.castles.length; i++) {
    if (String(reg.castles[i].user_id) === profile.user_id) {
      reg.castles[i] = entry;
      found = true;
      break;
    }
  }
  if (!found) {
    reg.castles.push(entry);
  }
  // Soft cap for beta — keep most recently updated.
  if (reg.castles.length > 200) {
    reg.castles.sort(function (a, b) {
      return Number(b.updated_at || 0) - Number(a.updated_at || 0);
    });
    reg.castles = reg.castles.slice(0, 200);
  }
  writeKingdomCastleRegistry(nk, kingdomId, reg.castles);
}

function rpcListKingdomCastles(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  ensureCastleCoords(nk, profile);
  upsertKingdomCastleEntry(nk, profile);
  const kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
  const reg = readKingdomCastleRegistry(nk, kingdomId);
  return JSON.stringify({
    ok: true,
    kingdom_id: kingdomId,
    castles: reg.castles,
    self: {
      user_id: profile.user_id,
      world_x: Number((profile as any).world_x),
      world_y: Number((profile as any).world_y),
    },
  });
}
