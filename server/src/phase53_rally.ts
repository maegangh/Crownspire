/**
 * Crownspire Phase 5.3 — Alliance Rallies (Wildling Lair battles)
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Concatenated into build/index.js via tsconfig files order.
 */

const RALLY_COLLECTION = "crownspire_rallies";
const RALLY_INDEX_COLLECTION = "crownspire_alliance_rally_index";
const RALLY_NOTIF_CODE = 5002;
const RALLY_SCHEMA_VERSION = 1;

const RALLY_STATUS_FORMING = "FORMING";
const RALLY_STATUS_LAUNCHED = "LAUNCHED";
const RALLY_STATUS_COMPLETED = "COMPLETED";
const RALLY_STATUS_CANCELLED = "CANCELLED";

const RALLY_ALLOWED_COUNTDOWNS: { [key: number]: boolean } = {
  60: true,
  300: true,
  600: true,
};
const RALLY_DEFAULT_COUNTDOWN = 60;
const RALLY_MAX_PARTICIPANTS = 10;

interface RallyParticipant {
  user_id: string;
  display_name: string;
  hero_ids: string[];
  troop_counts: { [key: string]: number };
  troop_tiers: any;
  power: number;
  joined_at: number;
}

interface RallyRecord {
  rally_id: string;
  alliance_id: string;
  leader_user_id: string;
  leader_display_name: string;
  lair_id: string;
  lair_level: number;
  lair_catalog_id: string;
  species: string;
  visual_variant: string;
  world_x: number;
  world_y: number;
  recommended_power: number;
  countdown_seconds: number;
  created_at: number;
  launch_at: number;
  launched_at: number;
  completed_at: number;
  status: string;
  participants: RallyParticipant[];
  max_participants: number;
  total_power: number;
  total_troops: number;
  result: any;
  schema_version: number;
  updated_at: number;
}

function rpcRallyCreate(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  assertRateLimit(nk, ctx.userId, "rally_create", 3);
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Join an Alliance to create a Rally.");

  // One active rally per player.
  const existing = findActiveRallyForUser(nk, profile.alliance_id, ctx.userId);
  if (existing) throw Err("You already have an active Rally.");

  const data = parsePayload(payload);
  const countdown = sanitizeCountdown(Number(data["countdown_seconds"]));
  const lairId = String(data["lair_id"] || "").trim();
  if (!lairId) throw Err("lair_id required");
  // Reject obviously fake / empty targets. Full kingdom lair registry is client+kingdom seeded in Phase 5.4.
  if (lairId.length < 6 || lairId.length > 96) throw Err("Invalid Alliance Lair target.");
  if (lairId.indexOf(" ") >= 0) throw Err("Invalid Alliance Lair target.");
  const lower = lairId.toLowerCase();
  if (lower === "fake" || lower === "null" || lower === "undefined" || lower.indexOf("fake_") === 0) {
    throw Err("Fake Alliance Lair target rejected.");
  }

  const heroIds = sanitizeStringArray(data["hero_ids"], 3);
  const troopCounts = sanitizeTroopCounts(data["troop_counts"] || data["troops"] || {});
  const troopTiers = data["troop_tiers"] || {};
  const power = Math.max(0, Math.floor(Number(data["power"] || 0)));
  const totalTroops = troopTotal(troopCounts);
  if (totalTroops <= 0) throw Err("Rally requires troops.");

  const now = nowUnix();
  const rallyId = nk.uuidv4();
  const participant: RallyParticipant = {
    user_id: ctx.userId,
    display_name: profile.display_name || "Leader",
    hero_ids: heroIds,
    troop_counts: troopCounts,
    troop_tiers: troopTiers,
    power: power,
    joined_at: now,
  };

  const rally: RallyRecord = {
    rally_id: rallyId,
    alliance_id: profile.alliance_id,
    leader_user_id: ctx.userId,
    leader_display_name: profile.display_name || "Leader",
    lair_id: lairId,
    lair_level: Math.max(1, Math.floor(Number(data["lair_level"] || 1))),
    lair_catalog_id: String(data["lair_catalog_id"] || ""),
    species: String(data["species"] || "").substring(0, 64),
    visual_variant: String(data["visual_variant"] || "").substring(0, 64),
    world_x: Number(data["world_x"] != null ? data["world_x"] : (data["world_position"] || {})["x"] || 0),
    world_y: Number(data["world_y"] != null ? data["world_y"] : (data["world_position"] || {})["y"] || 0),
    recommended_power: Math.max(0, Math.floor(Number(data["recommended_power"] || 0))),
    countdown_seconds: countdown,
    created_at: now,
    launch_at: now + countdown,
    launched_at: 0,
    completed_at: 0,
    status: RALLY_STATUS_FORMING,
    participants: [participant],
    max_participants: RALLY_MAX_PARTICIPANTS,
    total_power: power,
    total_troops: totalTroops,
    result: null,
    schema_version: RALLY_SCHEMA_VERSION,
    updated_at: now,
  };

  writeRally(nk, rally);
  indexAllianceRally(nk, profile.alliance_id, rallyId, true);
  sendAllianceSystemMessage(
    nk,
    logger,
    profile.alliance_id,
    (profile.display_name || "A player") + " started a Rally on Lair Lv." + rally.lair_level + ".",
    "rally_started"
  );
  sendRallyChatCard(nk, logger, rally);
  notifyAllianceRally(nk, logger, rally, "rally_created");

  logger.info("Rally created id=%s alliance=%s leader=%s", rallyId, profile.alliance_id, ctx.userId);
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyJoin(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  assertRateLimit(nk, ctx.userId, "rally_join", 2);
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");

  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  if (!rallyId) throw Err("rally_id required");
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  rally = refreshRallyStatus(nk, rally);
  if (rally.alliance_id !== profile.alliance_id) throw Err("Rally belongs to another Alliance");
  if (rally.status !== RALLY_STATUS_FORMING) throw Err("Rally is not open to join");
  if (rally.participants.length >= rally.max_participants) throw Err("Rally is full");
  if (findParticipant(rally, ctx.userId)) throw Err("Already joined this Rally");
  if (findActiveRallyForUser(nk, profile.alliance_id, ctx.userId)) throw Err("You already have an active Rally");

  const troopCounts = sanitizeTroopCounts(data["troop_counts"] || data["troops"] || {});
  const totalTroops = troopTotal(troopCounts);
  if (totalTroops <= 0) throw Err("Join requires troops.");
  const power = Math.max(0, Math.floor(Number(data["power"] || 0)));
  const now = nowUnix();
  rally.participants.push({
    user_id: ctx.userId,
    display_name: profile.display_name || "Player",
    hero_ids: sanitizeStringArray(data["hero_ids"], 3),
    troop_counts: troopCounts,
    troop_tiers: data["troop_tiers"] || {},
    power: power,
    joined_at: now,
  });
  recomputeTotals(rally);
  rally.updated_at = now;
  writeRally(nk, rally);

  sendAllianceSystemMessage(
    nk,
    logger,
    profile.alliance_id,
    (profile.display_name || "A player") + " joined the Rally.",
    "rally_joined"
  );
  notifyAllianceRally(nk, logger, rally, "rally_joined");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyLeave(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  rally = refreshRallyStatus(nk, rally);
  if (rally.status !== RALLY_STATUS_FORMING) throw Err("Cannot leave after launch");
  if (rally.leader_user_id === ctx.userId) throw Err("Leader must cancel the Rally instead of leaving");
  const before = rally.participants.length;
  rally.participants = rally.participants.filter(function (p) {
    return p.user_id !== ctx.userId;
  });
  if (rally.participants.length === before) throw Err("Not in this Rally");
  recomputeTotals(rally);
  rally.updated_at = nowUnix();
  writeRally(nk, rally);
  notifyAllianceRally(nk, logger, rally, "rally_left");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyCancel(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  if (rally.leader_user_id !== ctx.userId) throw Err("Only the Rally leader can cancel");
  if (rally.status === RALLY_STATUS_COMPLETED || rally.status === RALLY_STATUS_CANCELLED) {
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
  }
  rally.status = RALLY_STATUS_CANCELLED;
  rally.updated_at = nowUnix();
  writeRally(nk, rally);
  indexAllianceRally(nk, rally.alliance_id, rally.rally_id, false);
  sendAllianceSystemMessage(nk, logger, rally.alliance_id, "Rally cancelled.", "rally_cancelled");
  notifyAllianceRally(nk, logger, rally, "rally_cancelled");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyLaunch(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  rally = refreshRallyStatus(nk, rally);
  if (rally.status === RALLY_STATUS_LAUNCHED) {
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
  }
  if (rally.status !== RALLY_STATUS_FORMING) throw Err("Rally cannot launch");
  const auto = !!data["auto"];
  if (!auto && rally.leader_user_id !== ctx.userId) throw Err("Only the leader can Launch Now");
  if (auto && ctx.userId !== rally.leader_user_id && !findParticipant(rally, ctx.userId)) {
    throw Err("Not in this Rally");
  }
  // Auto-launch only when timer elapsed.
  if (auto && nowUnix() < rally.launch_at) throw Err("Rally timer has not finished");

  rally.status = RALLY_STATUS_LAUNCHED;
  rally.launched_at = nowUnix();
  rally.updated_at = nowUnix();
  writeRally(nk, rally);
  sendAllianceSystemMessage(nk, logger, rally.alliance_id, "Rally launched!", "rally_launched");
  notifyAllianceRally(nk, logger, rally, "rally_launched");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyGet(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  rally = refreshRallyStatus(nk, rally);
  if (profile.alliance_id && rally.alliance_id !== profile.alliance_id) throw Err("Rally belongs to another Alliance");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

function rpcRallyListActive(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    return JSON.stringify({ ok: true, rallies: [], connected: true, in_alliance: false });
  }
  const ids = listAllianceRallyIds(nk, profile.alliance_id);
  const out: any[] = [];
  for (let i = 0; i < ids.length; i++) {
    let rally = readRally(nk, ids[i]);
    if (!rally) continue;
    rally = refreshRallyStatus(nk, rally);
    if (rally.status === RALLY_STATUS_FORMING || rally.status === RALLY_STATUS_LAUNCHED) {
      out.push(publicRally(rally));
    }
  }
  return JSON.stringify({ ok: true, rallies: out, connected: true, in_alliance: true });
}

function rpcRallyComplete(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const rallyId = String(data["rally_id"] || "").trim();
  let rally = readRally(nk, rallyId);
  if (!rally) throw Err("Rally not found");
  if (rally.leader_user_id !== ctx.userId) throw Err("Only the Rally leader can submit battle results");
  if (rally.status === RALLY_STATUS_COMPLETED) {
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
  }
  if (rally.status !== RALLY_STATUS_LAUNCHED && rally.status !== RALLY_STATUS_FORMING) {
    throw Err("Rally is not active");
  }
  const result = data["result"] || {};
  const victory = !!result["victory"];
  rally.status = RALLY_STATUS_COMPLETED;
  rally.completed_at = nowUnix();
  rally.result = {
    victory: victory,
    summary: String(result["summary"] || (victory ? "Victory" : "Defeat")),
    damage_dealt: Math.max(0, Math.floor(Number(result["damage_dealt"] || 0))),
    remaining_hp: Math.max(0, Math.floor(Number(result["remaining_hp"] || 0))),
    rewards: result["rewards"] || {},
    rounds: Math.max(0, Math.floor(Number(result["rounds"] || 0))),
    casualty_ratio: Math.max(0, Number(result["casualty_ratio"] || 0)),
    participant_results: result["participant_results"] || [],
  };
  rally.updated_at = nowUnix();
  writeRally(nk, rally);
  indexAllianceRally(nk, rally.alliance_id, rally.rally_id, false);
  sendAllianceSystemMessage(
    nk,
    logger,
    rally.alliance_id,
    victory ? "Rally Victory!" : "Rally Defeat.",
    victory ? "rally_victory" : "rally_defeat"
  );
  notifyAllianceRally(nk, logger, rally, victory ? "rally_victory" : "rally_defeat");
  return JSON.stringify({ ok: true, rally: publicRally(rally) });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sanitizeCountdown(raw: number): number {
  const n = Math.floor(Number(raw));
  if (RALLY_ALLOWED_COUNTDOWNS[n]) return n;
  return RALLY_DEFAULT_COUNTDOWN;
}

function sanitizeTroopCounts(raw: any): { [key: string]: number } {
  const src = raw || {};
  return {
    infantry: Math.max(0, Math.floor(Number(src["infantry"] != null ? src["infantry"] : src["Infantry"] || 0))),
    marksmen: Math.max(0, Math.floor(Number(src["marksmen"] != null ? src["marksmen"] : src["Marksmen"] || 0))),
    cavalry: Math.max(0, Math.floor(Number(src["cavalry"] != null ? src["cavalry"] : src["Cavalry"] || 0))),
  };
}

function troopTotal(counts: { [key: string]: number }): number {
  return (counts.infantry || 0) + (counts.marksmen || 0) + (counts.cavalry || 0);
}

function sanitizeStringArray(raw: any, maxLen: number): string[] {
  const out: string[] = [];
  if (!raw || !(raw instanceof Array)) return out;
  for (let i = 0; i < raw.length && out.length < maxLen; i++) {
    const s = String(raw[i] || "").trim();
    if (s) out.push(s.substring(0, 64));
  }
  return out;
}

function recomputeTotals(rally: RallyRecord): void {
  let power = 0;
  let troops = 0;
  for (let i = 0; i < rally.participants.length; i++) {
    power += rally.participants[i].power || 0;
    troops += troopTotal(rally.participants[i].troop_counts || {});
  }
  rally.total_power = power;
  rally.total_troops = troops;
}

function findParticipant(rally: RallyRecord, userId: string): RallyParticipant | null {
  for (let i = 0; i < rally.participants.length; i++) {
    if (rally.participants[i].user_id === userId) return rally.participants[i];
  }
  return null;
}

function refreshRallyStatus(nk: nkruntime.Nakama, rally: RallyRecord): RallyRecord {
  if (rally.status === RALLY_STATUS_FORMING && nowUnix() >= rally.launch_at) {
    // Timer elapsed — leave FORMING until a client calls launch(auto=true).
    // Clients poll remaining_seconds; launch RPC finalizes.
  }
  return rally;
}

function publicRally(rally: RallyRecord): any {
  const now = nowUnix();
  return {
    rally_id: rally.rally_id,
    alliance_id: rally.alliance_id,
    leader_user_id: rally.leader_user_id,
    leader_display_name: rally.leader_display_name,
    lair_id: rally.lair_id,
    lair_level: rally.lair_level,
    lair_catalog_id: rally.lair_catalog_id,
    species: rally.species,
    visual_variant: rally.visual_variant,
    world_x: rally.world_x,
    world_y: rally.world_y,
    recommended_power: rally.recommended_power,
    countdown_seconds: rally.countdown_seconds,
    created_at: rally.created_at,
    launch_at: rally.launch_at,
    launched_at: rally.launched_at,
    completed_at: rally.completed_at,
    status: rally.status,
    remaining_seconds: rally.status === RALLY_STATUS_FORMING ? Math.max(0, rally.launch_at - now) : 0,
    participants: rally.participants,
    participant_count: rally.participants.length,
    max_participants: rally.max_participants,
    total_power: rally.total_power,
    total_troops: rally.total_troops,
    result: rally.result,
    schema_version: rally.schema_version,
    updated_at: rally.updated_at,
  };
}

function writeRally(nk: nkruntime.Nakama, rally: RallyRecord): void {
  nk.storageWrite([
    {
      collection: RALLY_COLLECTION,
      key: rally.rally_id,
      userId: SYSTEM_USER,
      value: rally,
      permissionRead: 1,
      permissionWrite: 0,
    },
  ]);
}

function readRally(nk: nkruntime.Nakama, rallyId: string): RallyRecord | null {
  const objects = nk.storageRead([{ collection: RALLY_COLLECTION, key: rallyId, userId: SYSTEM_USER }]);
  if (!objects || objects.length === 0 || !objects[0].value) return null;
  return objects[0].value as RallyRecord;
}

function indexAllianceRally(nk: nkruntime.Nakama, allianceId: string, rallyId: string, active: boolean): void {
  const objects = nk.storageRead([{ collection: RALLY_INDEX_COLLECTION, key: allianceId, userId: SYSTEM_USER }]);
  let ids: string[] = [];
  if (objects && objects.length > 0 && objects[0].value) {
    ids = ((objects[0].value as any).rally_ids || []) as string[];
  }
  ids = ids.filter(function (id) {
    return id !== rallyId;
  });
  if (active) ids.unshift(rallyId);
  if (ids.length > 40) ids = ids.slice(0, 40);
  nk.storageWrite([
    {
      collection: RALLY_INDEX_COLLECTION,
      key: allianceId,
      userId: SYSTEM_USER,
      value: { alliance_id: allianceId, rally_ids: ids, updated_at: nowUnix() },
      permissionRead: 1,
      permissionWrite: 0,
    },
  ]);
}

function listAllianceRallyIds(nk: nkruntime.Nakama, allianceId: string): string[] {
  const objects = nk.storageRead([{ collection: RALLY_INDEX_COLLECTION, key: allianceId, userId: SYSTEM_USER }]);
  if (!objects || objects.length === 0 || !objects[0].value) return [];
  return ((objects[0].value as any).rally_ids || []) as string[];
}

function findActiveRallyForUser(nk: nkruntime.Nakama, allianceId: string, userId: string): RallyRecord | null {
  const ids = listAllianceRallyIds(nk, allianceId);
  for (let i = 0; i < ids.length; i++) {
    const rally = readRally(nk, ids[i]);
    if (!rally) continue;
    if (rally.status !== RALLY_STATUS_FORMING && rally.status !== RALLY_STATUS_LAUNCHED) continue;
    if (findParticipant(rally, userId)) return rally;
  }
  return null;
}

function notifyAllianceRally(nk: nkruntime.Nakama, logger: nkruntime.Logger, rally: RallyRecord, eventType: string): void {
  try {
    const users = nk.groupUsersList(rally.alliance_id, 100);
    const list = users.groupUsers || [];
    const ids: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const gu = list[i];
      const state = Number(gu.state);
      if ((state === 0 || state === 1 || state === 2) && gu.user) {
        const uid = String(gu.user.userId || (gu.user as any).id || "");
        if (uid) ids.push(uid);
      }
    }
    if (ids.length === 0) return;
    nk.notificationsSend(
      ids.map(function (uid) {
        return {
          code: RALLY_NOTIF_CODE,
          content: { event: eventType, rally_id: rally.rally_id, rally: publicRally(rally) },
          persistent: false,
          senderId: rally.leader_user_id,
          subject: "Alliance Rally",
          userId: uid,
        };
      })
    );
  } catch (e) {
    logger.warn("Rally notify failed: %s", String(e));
  }
}

function sendRallyChatCard(nk: nkruntime.Nakama, logger: nkruntime.Logger, rally: RallyRecord): void {
  try {
    const channelId = nk.channelIdBuild("", rally.alliance_id, 2 as any);
    nk.channelMessageSend(
      channelId,
      {
        message_type: "RALLY",
        text: "Rally: Lair Lv." + rally.lair_level,
        sender_display_name: rally.leader_display_name,
        sender_alliance_tag: "",
        payload: {
          rally_id: rally.rally_id,
          leader_user_id: rally.leader_user_id,
          target_id: rally.lair_id,
          target_type: "wildling_lair",
          target_name: "Lair Lv." + rally.lair_level,
          kingdom_id: DEV_KINGDOM_ID,
          x: rally.world_x,
          y: rally.world_y,
          expiry_unix: rally.launch_at,
        },
        metadata: { crownspire_rally: true },
      },
      undefined,
      undefined,
      true
    );
  } catch (e) {
    logger.warn("Rally chat card failed: %s", String(e));
  }
}
