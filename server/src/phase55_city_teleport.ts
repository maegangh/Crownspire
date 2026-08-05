/**
 * Crownspire — Current-kingdom city teleport (durable OCC saga)
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Nakama Storage provides per-object version CAS, not multi-object SQL transactions.
 * Atomicity is achieved with:
 *  1) create-only idempotency op (version="*")
 *  2) kingdom lock via versioned CAS + TTL recovery
 *  3) staged durable saga (pending → … → completed|failed) with crash recovery
 *  4) versioned writes for inventory + kingdom registry
 *
 * Contract blockers: crownspire_map_blockers_v1 (matches MapPlacementContract.gd).
 */

const TELEPORT_ITEM_ID = "teleport_advanced_compass";
const TELEPORT_INV_COLLECTION = "crownspire_teleport_inventory";
const TELEPORT_OPS_COLLECTION = "crownspire_teleport_ops";
const TELEPORT_DEPLOY_COLLECTION = "crownspire_teleport_deployments";
const TELEPORT_LOCK_COLLECTION = "crownspire_kingdom_teleport_lock";
const CASTLE_MOVED_NOTIF_CODE = 5005;
const LOCK_TTL_SEC = 20;

const MAP_CONTRACT_ID = "crownspire_map_blockers_v1";
const WORLD_MAP_SIZE_T = 8192;
const CASTLE_EDGE_MARGIN_T = 900;
const CASTLE_MIN_SPACING_T = 500;
const TERRAIN_EDGE_MARGIN_T = 450;
const POI_EDGE_MARGIN_T = 300;
const MAX_PLACE_ATTEMPTS = 250;

const LAKE_COUNT_T = 6;
const LAKE_RADIUS_T = 700;
const MOUNTAIN_COUNT_T = 18;
const MOUNTAIN_RADIUS_T = 550;
const FOREST_COUNT_T = 35;
const FOREST_RADIUS_T = 425;
const ROCK_COUNT_T = 30;
const ROCK_RADIUS_T = 250;
const RESOURCE_COUNT_T = 40;
const RESOURCE_RADIUS_T = 160;
const WILDLING_COUNT_T = 30;
const WILDLING_RADIUS_T = 120;
const LAIR_COUNT_T = 10;
const LAIR_RADIUS_T = 360;

const OP_PENDING = "pending";
const OP_INV_CONSUMED = "inventory_consumed";
const OP_REGISTRY_UPDATED = "registry_updated";
const OP_PROFILE_UPDATED = "profile_updated";
const OP_COMPLETED = "completed";
const OP_FAILED = "failed";

interface StorageObj {
  value: any;
  version: string;
}

interface TeleportInvRecord {
  user_id: string;
  balances: { [itemId: string]: number };
  reconciled: boolean;
  import_fingerprint: string;
  updated_at: number;
}

interface MapBlocker {
  kind: string;
  x: number;
  y: number;
  radius: number;
}

function fnv1a32Teleport(text: string): number {
  let h = 2166136261;
  const s = String(text || "");
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function kingdomSeedTeleport(kingdomId: string, salt: string): number {
  return fnv1a32Teleport(String(salt) + "|" + String(kingdomId || ""));
}

function mulberry32Teleport(seed: number): () => number {
  let state = seed >>> 0;
  return function (): number {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function findValidPackedTeleport(
  rng: () => number,
  occupied: MapBlocker[],
  radius: number,
  edge: number
): { x: number; y: number } | null {
  const minC = edge + radius;
  const maxC = WORLD_MAP_SIZE_T - edge - radius;
  if (maxC <= minC) return null;
  for (let a = 0; a < MAX_PLACE_ATTEMPTS; a++) {
    const x = minC + rng() * (maxC - minC);
    const y = minC + rng() * (maxC - minC);
    let ok = true;
    for (let i = 0; i < occupied.length; i++) {
      const o = occupied[i];
      const dx = x - o.x;
      const dy = y - o.y;
      if (Math.sqrt(dx * dx + dy * dy) < radius + o.radius) {
        ok = false;
        break;
      }
    }
    if (ok) return { x: x, y: y };
  }
  return null;
}

function appendPackedTeleport(
  out: MapBlocker[],
  occupied: MapBlocker[],
  rng: () => number,
  kind: string,
  count: number,
  radius: number,
  edge: number
): void {
  for (let i = 0; i < count; i++) {
    const pos = findValidPackedTeleport(rng, occupied, radius, edge);
    if (!pos) continue;
    const b: MapBlocker = { kind: kind, x: pos.x, y: pos.y, radius: radius };
    occupied.push(b);
    out.push(b);
  }
}

function computeMapBlockers(kingdomId: string): MapBlocker[] {
  const kid = String(kingdomId || DEV_KINGDOM_ID);
  const out: MapBlocker[] = [];
  const occupied: MapBlocker[] = [];
  const terrainRng = mulberry32Teleport(kingdomSeedTeleport(kid, "terrain_v1"));
  appendPackedTeleport(out, occupied, terrainRng, "lake", LAKE_COUNT_T, LAKE_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
  appendPackedTeleport(out, occupied, terrainRng, "mountain", MOUNTAIN_COUNT_T, MOUNTAIN_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
  appendPackedTeleport(out, occupied, terrainRng, "forest", FOREST_COUNT_T, FOREST_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
  appendPackedTeleport(out, occupied, terrainRng, "rock", ROCK_COUNT_T, ROCK_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
  const poiRng = mulberry32Teleport(kingdomSeedTeleport(kid, "poi_v1"));
  appendPackedTeleport(out, occupied, poiRng, "resource", RESOURCE_COUNT_T, RESOURCE_RADIUS_T, POI_EDGE_MARGIN_T);
  appendPackedTeleport(out, occupied, poiRng, "wildling", WILDLING_COUNT_T, WILDLING_RADIUS_T, POI_EDGE_MARGIN_T);
  appendPackedTeleport(out, occupied, poiRng, "lair", LAIR_COUNT_T, LAIR_RADIUS_T, POI_EDGE_MARGIN_T);
  return out;
}

function validateCastleCandidateServer(
  kingdomId: string,
  x: number,
  y: number,
  castles: any[],
  selfUserId: string
): { ok: boolean; error: string } {
  if (typeof x !== "number" || typeof y !== "number" || !isFinite(x) || !isFinite(y)) {
    return { ok: false, error: "Invalid coordinates." };
  }
  if (
    x < CASTLE_EDGE_MARGIN_T ||
    y < CASTLE_EDGE_MARGIN_T ||
    x > WORLD_MAP_SIZE_T - CASTLE_EDGE_MARGIN_T ||
    y > WORLD_MAP_SIZE_T - CASTLE_EDGE_MARGIN_T
  ) {
    return { ok: false, error: "Too close to the map edge." };
  }
  for (let i = 0; i < castles.length; i++) {
    const c = castles[i];
    if (String(c.user_id) === selfUserId) continue;
    const cx = Number(c.world_x);
    const cy = Number(c.world_y);
    if (!isFinite(cx) || !isFinite(cy)) continue;
    const dx = x - cx;
    const dy = y - cy;
    if (Math.sqrt(dx * dx + dy * dy) < CASTLE_MIN_SPACING_T) {
      return { ok: false, error: "Too close to another castle." };
    }
  }
  const blockers = computeMapBlockers(kingdomId);
  const softR = CASTLE_MIN_SPACING_T * 0.5;
  for (let i = 0; i < blockers.length; i++) {
    const b = blockers[i];
    const dx = x - b.x;
    const dy = y - b.y;
    if (Math.sqrt(dx * dx + dy * dy) < b.radius + softR) {
      return { ok: false, error: "Blocked by " + b.kind + "." };
    }
  }
  return { ok: true, error: "" };
}

function trimStr(v: any): string {
  return String(v == null ? "" : v).replace(/^\s+|\s+$/g, "");
}

function isStrictNonNegInt(v: any): boolean {
  return typeof v === "number" && isFinite(v) && !isNaN(v) && v >= 0 && Math.floor(v) === v;
}

function isStrictBool(v: any): boolean {
  return v === true || v === false;
}

function storageReadOne(
  nk: nkruntime.Nakama,
  collection: string,
  key: string,
  userId: string
): StorageObj | null {
  const objects = nk.storageRead([{ collection: collection, key: key, userId: userId }]);
  if (objects && objects.length > 0 && objects[0].value) {
    return { value: objects[0].value, version: String(objects[0].version || "") };
  }
  return null;
}

function storageWriteVersioned(
  nk: nkruntime.Nakama,
  collection: string,
  key: string,
  userId: string,
  value: any,
  version: string,
  permissionRead: 0 | 1 | 2
): void {
  nk.storageWrite([
    {
      collection: collection,
      key: key,
      userId: userId,
      value: value,
      version: version,
      permissionRead: permissionRead,
      permissionWrite: 0,
    },
  ]);
}

function readTeleportInvObj(nk: nkruntime.Nakama, userId: string): StorageObj {
  const obj = storageReadOne(nk, TELEPORT_INV_COLLECTION, userId, userId);
  if (obj) return obj;
  return {
    value: {
      user_id: userId,
      balances: {},
      reconciled: false,
      import_fingerprint: "",
      updated_at: 0,
    } as TeleportInvRecord,
    version: "*",
  };
}

function getTeleportBalance(rec: TeleportInvRecord): number {
  const n = Number(rec.balances[TELEPORT_ITEM_ID] || 0);
  return isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function setTeleportBalance(rec: TeleportInvRecord, amount: number): void {
  if (!rec.balances) rec.balances = {};
  const n = Math.max(0, Math.floor(amount));
  if (n <= 0) delete rec.balances[TELEPORT_ITEM_ID];
  else rec.balances[TELEPORT_ITEM_ID] = n;
}

function readRegistryObj(nk: nkruntime.Nakama, kingdomId: string): StorageObj {
  const obj = storageReadOne(nk, KINGDOM_CASTLE_COLLECTION, kingdomId, SYSTEM_USER);
  if (obj) {
    const v = obj.value as any;
    if (!Array.isArray(v.castles)) v.castles = [];
    return obj;
  }
  return {
    value: { kingdom_id: kingdomId, castles: [], updated_at: 0 },
    version: "*",
  };
}

function readOpObj(nk: nkruntime.Nakama, userId: string, requestId: string): StorageObj | null {
  return storageReadOne(nk, TELEPORT_OPS_COLLECTION, requestId, userId);
}

function writeOpObj(nk: nkruntime.Nakama, userId: string, requestId: string, value: any, version: string): void {
  storageWriteVersioned(nk, TELEPORT_OPS_COLLECTION, requestId, userId, value, version, 1);
}

function readDeployObj(nk: nkruntime.Nakama, userId: string): StorageObj {
  const obj = storageReadOne(nk, TELEPORT_DEPLOY_COLLECTION, userId, userId);
  if (obj) {
    if (!Array.isArray((obj.value as any).deployments)) (obj.value as any).deployments = [];
    return obj;
  }
  return { value: { user_id: userId, deployments: [], updated_at: 0 }, version: "*" };
}

function userHasServerDeployments(nk: nkruntime.Nakama, userId: string): boolean {
  const obj = readDeployObj(nk, userId);
  return Array.isArray((obj.value as any).deployments) && (obj.value as any).deployments.length > 0;
}

function userInActiveRally(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, allianceId: string): boolean {
  if (!allianceId) return false;
  try {
    const objects = nk.storageRead([
      { collection: "crownspire_alliance_rally_index", key: allianceId, userId: SYSTEM_USER },
    ]);
    if (!objects || objects.length === 0 || !objects[0].value) return false;
    const ids: any[] = Array.isArray((objects[0].value as any).rally_ids)
      ? (objects[0].value as any).rally_ids
      : [];
    for (let i = 0; i < ids.length; i++) {
      const rid = String(ids[i] || "");
      if (!rid) continue;
      const rallyObjs = nk.storageRead([{ collection: "crownspire_rallies", key: rid, userId: SYSTEM_USER }]);
      if (!rallyObjs || rallyObjs.length === 0 || !rallyObjs[0].value) continue;
      const rally = rallyObjs[0].value as any;
      const status = String(rally.status || "");
      if (status !== "FORMING" && status !== "LAUNCHED") continue;
      if (String(rally.leader_user_id) === userId) return true;
      const parts: any[] = Array.isArray(rally.participants) ? rally.participants : [];
      for (let p = 0; p < parts.length; p++) {
        if (String(parts[p].user_id) === userId) return true;
      }
    }
  } catch (e) {
    logger.warn("teleport rally check failed: %s", String(e));
  }
  return false;
}

function acquireKingdomLock(
  nk: nkruntime.Nakama,
  kingdomId: string,
  userId: string,
  requestId: string
): { ok: boolean; error: string; version: string } {
  const now = nowUnix();
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
    const cur = obj ? (obj.value as any) : null;
    const ver = obj ? obj.version : "*";
    const expired = !cur || !cur.expires_at || Number(cur.expires_at) <= now;
    const sameHolder = cur && String(cur.request_id) === requestId && String(cur.user_id) === userId;
    if (!expired && !sameHolder) {
      return { ok: false, error: "Kingdom teleport lock busy. Try again.", version: "" };
    }
    const next = {
      kingdom_id: kingdomId,
      user_id: userId,
      request_id: requestId,
      expires_at: now + LOCK_TTL_SEC,
      updated_at: now,
    };
    try {
      storageWriteVersioned(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER, next, ver, 1);
      const confirm = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
      if (
        confirm &&
        String((confirm.value as any).request_id) === requestId &&
        String((confirm.value as any).user_id) === userId
      ) {
        return { ok: true, error: "", version: confirm.version };
      }
    } catch (_e) {
      // CAS conflict — retry
    }
  }
  return { ok: false, error: "Could not acquire kingdom teleport lock.", version: "" };
}

function releaseKingdomLock(nk: nkruntime.Nakama, kingdomId: string, userId: string, requestId: string): void {
  const obj = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
  if (!obj) return;
  const cur = obj.value as any;
  if (String(cur.user_id) !== userId || String(cur.request_id) !== requestId) return;
  try {
    storageWriteVersioned(
      nk,
      TELEPORT_LOCK_COLLECTION,
      kingdomId,
      SYSTEM_USER,
      { kingdom_id: kingdomId, user_id: "", request_id: "", expires_at: 0, updated_at: nowUnix() },
      obj.version,
      1
    );
  } catch (_e) {
    // Best-effort release; TTL recovers crashed holders.
  }
}

function notifyKingdomCastleMoved(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  kingdomId: string,
  actorUserId: string,
  worldX: number,
  worldY: number,
  displayName: string
): void {
  const reg = readRegistryObj(nk, kingdomId).value as any;
  const recipients: nkruntime.NotificationRequest[] = [];
  const castles: any[] = Array.isArray(reg.castles) ? reg.castles : [];
  for (let i = 0; i < castles.length; i++) {
    const uid = String(castles[i].user_id || "");
    if (!uid || uid === actorUserId) continue;
    recipients.push({
      userId: uid,
      subject: "Castle Moved",
      content: {
        type: "castle_moved",
        kingdom_id: kingdomId,
        user_id: actorUserId,
        display_name: displayName || "Player",
        world_x: worldX,
        world_y: worldY,
        contract_id: MAP_CONTRACT_ID,
      },
      code: CASTLE_MOVED_NOTIF_CODE,
      persistent: false,
    });
  }
  if (recipients.length === 0) return;
  try {
    nk.notificationsSend(recipients);
  } catch (e) {
    logger.warn("castle_moved notify failed: %s", String(e));
  }
}

function applyRegistryMove(
  nk: nkruntime.Nakama,
  profile: CrownspireProfile,
  worldX: number,
  worldY: number
): void {
  const kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
  for (let attempt = 0; attempt < 8; attempt++) {
    const regObj = readRegistryObj(nk, kingdomId);
    const reg = regObj.value as any;
    const castles: any[] = Array.isArray(reg.castles) ? reg.castles.slice() : [];
    const check = validateCastleCandidateServer(kingdomId, worldX, worldY, castles, profile.user_id);
    if (!check.ok) throw Err(check.error);
    const entry = {
      user_id: profile.user_id,
      display_name: profile.display_name || "",
      alliance_tag: profile.alliance_tag || "",
      alliance_name: profile.alliance_name || "",
      avatar_id: profile.avatar_id || "avatar_01",
      world_x: worldX,
      world_y: worldY,
      citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
      power: typeof profile.power === "number" ? profile.power : 0,
      updated_at: nowUnix(),
    };
    let found = false;
    for (let i = 0; i < castles.length; i++) {
      if (String(castles[i].user_id) === profile.user_id) {
        castles[i] = entry;
        found = true;
        break;
      }
    }
    if (!found) castles.push(entry);
    if (castles.length > 200) {
      castles.sort(function (a, b) {
        return Number(b.updated_at || 0) - Number(a.updated_at || 0);
      });
      castles.length = 200;
    }
    const next = { kingdom_id: kingdomId, castles: castles, updated_at: nowUnix() };
    try {
      storageWriteVersioned(nk, KINGDOM_CASTLE_COLLECTION, kingdomId, SYSTEM_USER, next, regObj.version, 2);
      return;
    } catch (_e) {
      // retry CAS
    }
  }
  throw Err("Kingdom castle registry busy. Try again.");
}

function restoreRegistryCoords(
  nk: nkruntime.Nakama,
  profile: CrownspireProfile,
  worldX: number,
  worldY: number
): void {
  (profile as any).world_x = worldX;
  (profile as any).world_y = worldY;
  applyRegistryMove(nk, profile, worldX, worldY);
}

function consumeInventoryCAS(nk: nkruntime.Nakama, userId: string): number {
  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readTeleportInvObj(nk, userId);
    const inv = invObj.value as TeleportInvRecord;
    if (!inv.reconciled) throw Err("Teleport inventory not reconciled. Open the Bag once while online.");
    const bal = getTeleportBalance(inv);
    if (bal < 1) throw Err("No Advanced Teleport remaining.");
    setTeleportBalance(inv, bal - 1);
    inv.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, userId, userId, inv, invObj.version, 1);
      return getTeleportBalance(inv);
    } catch (_e) {
      // retry
    }
  }
  throw Err("Teleport inventory busy. Try again.");
}

function refundInventoryCAS(nk: nkruntime.Nakama, userId: string): number {
  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readTeleportInvObj(nk, userId);
    const inv = invObj.value as TeleportInvRecord;
    setTeleportBalance(inv, getTeleportBalance(inv) + 1);
    inv.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, userId, userId, inv, invObj.version, 1);
      return getTeleportBalance(inv);
    } catch (_e) {
      // retry
    }
  }
  throw Err("Failed to refund teleport item.");
}

function advanceTeleportSaga(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  profile: CrownspireProfile,
  opObj: StorageObj,
  requestId: string
): any {
  let op = opObj.value as any;
  let opVersion = opObj.version;
  const kingdomId = String(op.kingdom_id || profile.kingdom_id || DEV_KINGDOM_ID);
  const worldX = Number(op.world_x);
  const worldY = Number(op.world_y);
  const oldX = Number(op.old_world_x);
  const oldY = Number(op.old_world_y);

  function persistOp(nextState: string, extra: any): void {
    op = Object.assign({}, op, extra || {}, { state: nextState, updated_at: nowUnix() });
    writeOpObj(nk, profile.user_id, requestId, op, opVersion);
    const refreshed = readOpObj(nk, profile.user_id, requestId);
    if (!refreshed) throw Err("Teleport operation lost.");
    op = refreshed.value;
    opVersion = refreshed.version;
  }

  if (op.state === OP_COMPLETED && op.result) return op.result;
  if (op.state === OP_FAILED) {
    throw Err(String(op.error || "Teleport previously failed."));
  }

  const lock = acquireKingdomLock(nk, kingdomId, profile.user_id, requestId);
  if (!lock.ok) throw Err(lock.error);

  try {
    // Re-validate under lock for every non-terminal resume.
    if (op.state === OP_PENDING || op.state === OP_INV_CONSUMED) {
      if (userHasServerDeployments(nk, profile.user_id)) {
        throw Err("Cannot teleport while troops are deployed.");
      }
      if (userInActiveRally(nk, logger, profile.user_id, String(profile.alliance_id || ""))) {
        throw Err("Cannot teleport while in an active rally.");
      }
      const reg = readRegistryObj(nk, kingdomId).value as any;
      const check = validateCastleCandidateServer(
        kingdomId,
        worldX,
        worldY,
        Array.isArray(reg.castles) ? reg.castles : [],
        profile.user_id
      );
      if (!check.ok) throw Err(check.error);
    }

    if (op.state === OP_PENDING) {
      const newBal = consumeInventoryCAS(nk, profile.user_id);
      persistOp(OP_INV_CONSUMED, { balance_after_consume: newBal });
    }

    if (op.state === OP_INV_CONSUMED) {
      applyRegistryMove(nk, profile, worldX, worldY);
      persistOp(OP_REGISTRY_UPDATED, {});
    }

    if (op.state === OP_REGISTRY_UPDATED) {
      (profile as any).world_x = worldX;
      (profile as any).world_y = worldY;
      profile.updated_at = nowUnix();
      writeProfile(nk, profile);
      persistOp(OP_PROFILE_UPDATED, {});
    }

    if (op.state === OP_PROFILE_UPDATED || op.state === OP_REGISTRY_UPDATED) {
      // Ensure profile matches registry even if we landed mid-stage.
      if (Number((profile as any).world_x) !== worldX || Number((profile as any).world_y) !== worldY) {
        (profile as any).world_x = worldX;
        (profile as any).world_y = worldY;
        profile.updated_at = nowUnix();
        writeProfile(nk, profile);
      }
      const invObj = readTeleportInvObj(nk, profile.user_id);
      const balance = getTeleportBalance(invObj.value as TeleportInvRecord);
      const result = {
        ok: true,
        request_id: requestId,
        kingdom_id: kingdomId,
        world_x: worldX,
        world_y: worldY,
        item_id: TELEPORT_ITEM_ID,
        balance: balance,
        contract_id: MAP_CONTRACT_ID,
        notif_code: CASTLE_MOVED_NOTIF_CODE,
      };
      persistOp(OP_COMPLETED, { result: result, ok: true });
      notifyKingdomCastleMoved(
        nk,
        logger,
        kingdomId,
        profile.user_id,
        worldX,
        worldY,
        profile.display_name || "Player"
      );
      return result;
    }

    throw Err("Unknown teleport operation state.");
  } catch (e) {
    const msg = e instanceof Error ? String(e.message || e) : String(e);
    try {
      // Compensate based on durable stage.
      if (op.state === OP_PROFILE_UPDATED) {
        // Profile+registry already moved; finish as completed rather than unwind.
        const invObj = readTeleportInvObj(nk, profile.user_id);
        const result = {
          ok: true,
          request_id: requestId,
          kingdom_id: kingdomId,
          world_x: worldX,
          world_y: worldY,
          item_id: TELEPORT_ITEM_ID,
          balance: getTeleportBalance(invObj.value as TeleportInvRecord),
          contract_id: MAP_CONTRACT_ID,
          notif_code: CASTLE_MOVED_NOTIF_CODE,
        };
        persistOp(OP_COMPLETED, { result: result, ok: true });
        return result;
      }
      if (op.state === OP_REGISTRY_UPDATED) {
        restoreRegistryCoords(nk, profile, oldX, oldY);
        (profile as any).world_x = oldX;
        (profile as any).world_y = oldY;
        writeProfile(nk, profile);
        refundInventoryCAS(nk, profile.user_id);
        persistOp(OP_FAILED, { ok: false, error: msg });
      } else if (op.state === OP_INV_CONSUMED) {
        refundInventoryCAS(nk, profile.user_id);
        persistOp(OP_FAILED, { ok: false, error: msg });
      } else if (op.state === OP_PENDING) {
        // No irreversible side effects yet — keep pending so the same request_id can resume.
      } else {
        persistOp(OP_FAILED, { ok: false, error: msg });
      }
    } catch (compErr) {
      logger.error("teleport compensate failed: %s", String(compErr));
    }
    throw Err(msg);
  } finally {
    releaseKingdomLock(nk, kingdomId, profile.user_id, requestId);
  }
}

function rpcTeleportInventorySync(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  ensureProfile(nk, logger, ctx.userId);
  let body: any = {};
  try {
    body = payload && payload.length > 0 ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid JSON");
  }
  if (!Object.prototype.hasOwnProperty.call(body, "local_count")) throw Err("Missing local_count.");
  if (!isStrictNonNegInt(body.local_count)) throw Err("local_count must be a non-negative integer.");
  const clientCount = body.local_count as number;

  for (let attempt = 0; attempt < 8; attempt++) {
    const invObj = readTeleportInvObj(nk, ctx.userId);
    const rec = invObj.value as TeleportInvRecord;
    if (!rec.reconciled) {
      setTeleportBalance(rec, clientCount);
      rec.reconciled = true;
      rec.import_fingerprint = "bag_v1:" + String(clientCount) + ":" + String(nowUnix());
      rec.updated_at = nowUnix();
      try {
        storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, ctx.userId, ctx.userId, rec, invObj.version, 1);
      } catch (_e) {
        continue;
      }
      logger.info("Teleport inventory reconciled user=%s imported=%d", ctx.userId, clientCount);
    }
    const latest = readTeleportInvObj(nk, ctx.userId).value as TeleportInvRecord;
    return JSON.stringify({
      ok: true,
      item_id: TELEPORT_ITEM_ID,
      balance: getTeleportBalance(latest),
      reconciled: true,
      contract_id: MAP_CONTRACT_ID,
    });
  }
  throw Err("Teleport inventory sync busy.");
}

function rpcTeleportInventoryGet(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const rec = readTeleportInvObj(nk, ctx.userId).value as TeleportInvRecord;
  return JSON.stringify({
    ok: true,
    item_id: TELEPORT_ITEM_ID,
    balance: getTeleportBalance(rec),
    reconciled: !!rec.reconciled,
  });
}

/** Additive deployment ledger — clients cannot wipe deployments in one call. */
function rpcTeleportDeploymentBegin(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  let body: any = {};
  try {
    body = payload && payload.length > 0 ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid JSON");
  }
  const deploymentId = trimStr(body.deployment_id || "");
  const kind = trimStr(body.kind || "");
  if (deploymentId.length < 8 || deploymentId.length > 80) throw Err("Invalid deployment_id.");
  if (kind !== "march" && kind !== "gather" && kind !== "rally" && kind !== "reinforce") {
    throw Err("Invalid deployment kind.");
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readDeployObj(nk, ctx.userId);
    const val = obj.value as any;
    const list: any[] = Array.isArray(val.deployments) ? val.deployments.slice() : [];
    let found = false;
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].deployment_id) === deploymentId) {
        found = true;
        break;
      }
    }
    if (!found) list.push({ deployment_id: deploymentId, kind: kind, started_at: nowUnix() });
    val.deployments = list;
    val.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, TELEPORT_DEPLOY_COLLECTION, ctx.userId, ctx.userId, val, obj.version, 1);
      return JSON.stringify({ ok: true, deployments: list });
    } catch (_e) {
      // retry
    }
  }
  throw Err("Deployment begin busy.");
}

function rpcTeleportDeploymentEnd(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  let body: any = {};
  try {
    body = payload && payload.length > 0 ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid JSON");
  }
  const deploymentId = trimStr(body.deployment_id || "");
  if (deploymentId.length < 8 || deploymentId.length > 80) throw Err("Invalid deployment_id.");
  for (let attempt = 0; attempt < 8; attempt++) {
    const obj = readDeployObj(nk, ctx.userId);
    const val = obj.value as any;
    const list: any[] = Array.isArray(val.deployments) ? val.deployments : [];
    const next: any[] = [];
    for (let i = 0; i < list.length; i++) {
      if (String(list[i].deployment_id) !== deploymentId) next.push(list[i]);
    }
    val.deployments = next;
    val.updated_at = nowUnix();
    try {
      storageWriteVersioned(nk, TELEPORT_DEPLOY_COLLECTION, ctx.userId, ctx.userId, val, obj.version, 1);
      return JSON.stringify({ ok: true, deployments: next });
    } catch (_e) {
      // retry
    }
  }
  throw Err("Deployment end busy.");
}

/** Removed insecure clear-all troop activity writer. Kept name rejected. */
function rpcSetTroopActivity(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  throw Err("crownspire_set_troop_activity is retired. Use deployment begin/end.");
}

function rpcCityTeleportRelocate(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  let body: any = {};
  try {
    body = payload && payload.length > 0 ? JSON.parse(payload) : {};
  } catch (_e) {
    throw Err("Invalid JSON");
  }

  const requestId = trimStr(body.request_id || "");
  if (requestId.length < 8 || requestId.length > 80) throw Err("Missing request_id.");
  const itemId = trimStr(body.item_id || TELEPORT_ITEM_ID);
  if (itemId !== TELEPORT_ITEM_ID) throw Err("Unsupported teleport item.");
  if (!Object.prototype.hasOwnProperty.call(body, "world_x") || !Object.prototype.hasOwnProperty.call(body, "world_y")) {
    throw Err("Missing coordinates.");
  }
  if (typeof body.world_x !== "number" || typeof body.world_y !== "number") {
    throw Err("Coordinates must be numbers.");
  }
  const worldX = body.world_x as number;
  const worldY = body.world_y as number;
  if (!isFinite(worldX) || !isFinite(worldY) || isNaN(worldX) || isNaN(worldY)) {
    throw Err("Invalid coordinates.");
  }

  const profile = ensureProfile(nk, logger, ctx.userId);
  ensureCastleCoords(nk, profile);
  const kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
  if (Object.prototype.hasOwnProperty.call(body, "kingdom_id")) {
    const claimed = trimStr(body.kingdom_id);
    if (claimed !== kingdomId) throw Err("Cannot teleport outside your current kingdom.");
  }

  let opObj = readOpObj(nk, ctx.userId, requestId);
  if (!opObj) {
    const createVal = {
      request_id: requestId,
      user_id: ctx.userId,
      kingdom_id: kingdomId,
      item_id: itemId,
      world_x: Math.floor(worldX),
      world_y: Math.floor(worldY),
      old_world_x: Number((profile as any).world_x),
      old_world_y: Number((profile as any).world_y),
      state: OP_PENDING,
      created_at: nowUnix(),
      updated_at: nowUnix(),
      contract_id: MAP_CONTRACT_ID,
    };
    try {
      writeOpObj(nk, ctx.userId, requestId, createVal, "*");
    } catch (_e) {
      // Another worker created it — read existing.
    }
    opObj = readOpObj(nk, ctx.userId, requestId);
    if (!opObj) throw Err("Failed to create teleport operation.");
  }

  const existing = opObj.value as any;
  if (existing.state === OP_COMPLETED && existing.result) {
    return JSON.stringify(existing.result);
  }
  if (existing.state === OP_FAILED) {
    throw Err(String(existing.error || "Teleport previously failed."));
  }

  const result = advanceTeleportSaga(nk, logger, profile, opObj, requestId);
  return JSON.stringify(result);
}
