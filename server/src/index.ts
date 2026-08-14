/**
 * Crownspire Nakama Server Runtime — Phase 3 + Phase 4
 * LOCAL DEVELOPMENT ONLY
 *
 * Phase 3 RPCs: profile, create/join/leave alliance, approve, kick, chat_report
 * Phase 4 RPCs: roster, ranks, permissions, reject, invites, transfer, list alliances
 * (see phase4_alliance.ts)
 *
 * Rank mapping:
 *  Nakama Superadmin (0) -> Crownspire R5
 *  Nakama Admin (1)      -> Crownspire R4
 *  Nakama Member (2)     -> Crownspire R1–R3 via crownspire_alliance_ranks
 */

const PROFILE_COLLECTION = "crownspire_profiles";
const PROFILE_KEY = "profile";
const REPORT_COLLECTION = "crownspire_chat_reports";
const RANK_COLLECTION = "crownspire_alliance_ranks";
const RATE_COLLECTION = "crownspire_rate_limits";
/** Nakama system storage owner — group IDs are NOT valid storage userIds. */
const SYSTEM_USER = "00000000-0000-0000-0000-000000000000";

const DEV_KINGDOM_ID = "kingdom_dev_001";
const PROFILE_VERSION = 2;
/** Consider a player online if heartbeat within this window. */
const PRESENCE_ONLINE_SEC = 90;

const DISPLAY_NAME_MIN = 3;
const DISPLAY_NAME_MAX = 24;
const ALLIANCE_NAME_MIN = 3;
const ALLIANCE_NAME_MAX = 24;
const ALLIANCE_TAG_MIN = 3;
const ALLIANCE_TAG_MAX = 4;

/** Beta: rename is free/frequent for testing. Raise for production. */
const DISPLAY_NAME_COOLDOWN_SEC = 5;
const REPORT_COOLDOWN_SEC = 10;
const ALLIANCE_CREATE_COOLDOWN_SEC = 30;

const REPORT_REASONS: { [key: string]: boolean } = {
  spam: true,
  harassment: true,
  hate_or_abuse: true,
  sexual_content: true,
  cheating_or_scam: true,
  impersonation: true,
  inappropriate_name: true,
  other: true,
};

interface CrownspireProfile {
  user_id: string;
  display_name: string;
  kingdom_id: string;
  alliance_id: string;
  alliance_tag: string;
  alliance_name: string;
  crownspire_rank: string;
  /** Phase 5.1 identity — default fantasy avatar id (avatar_01..avatar_08). */
  avatar_id: string;
  /** Client-reported power snapshot for social display (not combat authority). */
  power: number;
  /** Lifetime social kill counter (client-reported snapshot; not combat authority). */
  kills?: number;
  /** Peak reported power snapshot for social display. */
  highest_power?: number;
  /**
   * Optional public gear showcase only.
   * Must NEVER include troops, resources, garrison, marches, or scout intel.
   */
  public_equipment?: any[];
  citadel_level: number;
  vip_level: number;
  /** Unix seconds — updated by presence heartbeat while online. */
  last_online: number;
  /** Stable world-map castle coordinates (kingdom map). */
  world_x?: number;
  world_y?: number;
  /** Unix seconds — Peace Shield expiry (0 = inactive). */
  peace_shield_expires_at?: number;
  /** Unix seconds — Anti-Scout expiry (0 = inactive). */
  anti_scout_expires_at?: number;
  /** Unix seconds — Beginner Protection expiry (0 = inactive). Product duration TBD. */
  beginner_protection_expires_at?: number;
  beginner_protection_cleared?: boolean;
  created_at: number;
  updated_at: number;
  profile_version: number;
}

interface AllianceRankRecord {
  group_id: string;
  user_id: string;
  crownspire_rank: string;
  updated_at: number;
}

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer) {
  initializer.registerRpc("crownspire_get_profile", rpcGetProfile);
  initializer.registerRpc("crownspire_set_display_name", rpcSetDisplayName);
  initializer.registerRpc("crownspire_get_public_profile", rpcGetPublicProfile);
  initializer.registerRpc("crownspire_create_alliance", rpcCreateAlliance);
  initializer.registerRpc("crownspire_join_alliance", rpcJoinAlliance);
  initializer.registerRpc("crownspire_leave_alliance", rpcLeaveAlliance);
  initializer.registerRpc("crownspire_list_alliance_join_requests", rpcListJoinRequests);
  initializer.registerRpc("crownspire_approve_alliance_join", rpcApproveJoin);
  initializer.registerRpc("crownspire_kick_alliance_member", rpcKickMember);
  initializer.registerRpc("crownspire_chat_report", rpcChatReport);
  // Phase 4 — must register inside InitModule (Nakama AST extracts keys from here only).
  initializer.registerRpc("crownspire_get_alliance_profile", rpcGetAllianceProfile);
  initializer.registerRpc("crownspire_list_members", rpcListMembers);
  initializer.registerRpc("crownspire_list_alliances", rpcListAlliances);
  initializer.registerRpc("crownspire_update_alliance_profile", rpcUpdateAllianceProfile);
  initializer.registerRpc("crownspire_reject_alliance_join", rpcRejectJoin);
  initializer.registerRpc("crownspire_set_member_rank", rpcSetMemberRank);
  initializer.registerRpc("crownspire_transfer_leadership", rpcTransferLeadership);
  initializer.registerRpc("crownspire_invite_player", rpcInvitePlayer);
  initializer.registerRpc("crownspire_list_my_invites", rpcListMyInvites);
  initializer.registerRpc("crownspire_accept_invite", rpcAcceptInvite);
  initializer.registerRpc("crownspire_reject_invite", rpcRejectInvite);
  initializer.registerRpc("crownspire_get_my_permissions", rpcGetMyPermissions);

  // Phase 5 — Alliance Help + beta Auto-Help (register inside InitModule only).
  initializer.registerRpc("crownspire_create_help_request", rpcCreateHelpRequest);
  initializer.registerRpc("crownspire_help_one", rpcHelpOne);
  initializer.registerRpc("crownspire_help_all", rpcHelpAll);
  initializer.registerRpc("crownspire_list_eligible_help_requests", rpcListEligibleHelpRequests);
  initializer.registerRpc("crownspire_list_my_active_help_requests", rpcListMyActiveHelpRequests);
  initializer.registerRpc("crownspire_complete_or_cancel_help_request", rpcCompleteOrCancelHelpRequest);
  initializer.registerRpc("crownspire_get_my_entitlements", rpcGetMyEntitlements);
  initializer.registerRpc("crownspire_dev_set_entitlement", rpcDevSetEntitlement);

  // Phase 5.1 — player identity, presence, social polish.
  initializer.registerRpc("crownspire_update_player_identity", rpcUpdatePlayerIdentity);
  initializer.registerRpc("crownspire_presence_heartbeat", rpcPresenceHeartbeat);

  // Kingdom world castles (stable positions for multiplayer map).
  initializer.registerRpc("crownspire_list_kingdom_castles", rpcListKingdomCastles);

  // Current-kingdom targeted city teleport + secure consumable inventory.
  initializer.registerRpc("crownspire_teleport_inventory_sync", rpcTeleportInventorySync);
  initializer.registerRpc("crownspire_teleport_inventory_get", rpcTeleportInventoryGet);
  initializer.registerRpc("crownspire_teleport_deployment_begin", rpcTeleportDeploymentBegin);
  initializer.registerRpc("crownspire_teleport_deployment_end", rpcTeleportDeploymentEnd);
  // Retired: clients could clear the troop ledger to bypass teleport checks.
  initializer.registerRpc("crownspire_set_troop_activity", rpcSetTroopActivity);
  initializer.registerRpc("crownspire_city_teleport_relocate", rpcCityTeleportRelocate);
  // Closed-beta secure consumable grant — only when server env explicitly enables it.
  // Production-beta enable: runtime.env CROWNSPIRE_ENABLE_BETA_GRANTS=true and
  // CROWNSPIRE_BETA_GRANT_SECRET=<server-only secret>. Default: not registered.
  if (isBetaSecureGrantsEnabled(ctx) && getBetaGrantSecret(ctx).length >= 16) {
    initializer.registerRpc("crownspire_dev_grant_secure_consumable", rpcDevGrantSecureConsumable);
    logger.info("Beta secure consumable grant RPC registered (CROWNSPIRE_ENABLE_BETA_GRANTS=true).");
  } else {
    logger.info("Beta secure consumable grant RPC NOT registered (flag/secret gate closed).");
  }

  // Phase 5.3 — Alliance Rallies (Wildling Lair).
  initializer.registerRpc("crownspire_rally_create", rpcRallyCreate);
  initializer.registerRpc("crownspire_rally_join", rpcRallyJoin);
  initializer.registerRpc("crownspire_rally_leave", rpcRallyLeave);
  initializer.registerRpc("crownspire_rally_cancel", rpcRallyCancel);
  initializer.registerRpc("crownspire_rally_launch", rpcRallyLaunch);
  initializer.registerRpc("crownspire_rally_get", rpcRallyGet);
  initializer.registerRpc("crownspire_rally_list_active", rpcRallyListActive);
  initializer.registerRpc("crownspire_rally_complete", rpcRallyComplete);

  // Phase 6 — Direct Message delivery through authenticated server RPC.
  initializer.registerRpc("crownspire_dm_send", rpcDmSend);

  // Phase 5.6 — Hostile validation + authoritative Peace Shield / Anti-Scout use + beginner clear.
  // Free activate_* / beginner GRANT RPCs are NOT registered.
  initializer.registerRpc("crownspire_validate_hostile_action", rpcValidateHostileAction);
  initializer.registerRpc("crownspire_use_peace_shield", rpcUsePeaceShield);
  initializer.registerRpc("crownspire_use_anti_scout", rpcUseAntiScout);
  initializer.registerRpc("crownspire_clear_own_beginner_protection", rpcClearOwnBeginnerProtection);

  logger.info("Crownspire runtime loaded (Phase 3+4+5+5.1+5.3+6+castles identity/alliance/help/social/rallies/dm-rpc). LOCAL DEVELOPMENT ONLY.");
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

function rpcGetProfile(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}

function rpcSetDisplayName(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  // Validate before rate-limit write so rejected names do not burn cooldown.
  const name = sanitizeDisplayName(String(data["display_name"] || ""));
  assertRateLimit(nk, ctx.userId, "set_display_name", DISPLAY_NAME_COOLDOWN_SEC);

  const profile = ensureProfile(nk, logger, ctx.userId);
  profile.display_name = name;
  profile.updated_at = nowUnix();
  writeProfile(nk, profile);

  // Mirror into Nakama account display name (non-authoritative cache for lobby UI).
  try {
    nk.accountUpdateId(ctx.userId, null, name, null, null, null, null);
  } catch (e) {
    logger.warn("accountUpdateId display_name mirror failed: %s", String(e));
  }

  return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}

function rpcGetPublicProfile(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) {
    throw Err("user_id required");
  }
  const profile = ensureProfile(nk, logger, targetId);
  return JSON.stringify({
    ok: true,
    profile: publicProfile(profile),
  });
}

function ensureProfile(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string): CrownspireProfile {
  const existing = readProfile(nk, userId);
  if (existing) {
    const normalized = normalizeIdentityFields(nk, existing);
    const withCastle = ensureCastleCoords(nk, normalized);
    const synced = syncAllianceFields(nk, logger, withCastle);
    upsertKingdomCastleEntry(nk, synced);
    return synced;
  }

  const created: CrownspireProfile = {
    user_id: userId,
    display_name: defaultDevName(userId),
    kingdom_id: DEV_KINGDOM_ID,
    alliance_id: "",
    alliance_tag: "",
    alliance_name: "",
    crownspire_rank: "",
    avatar_id: "avatar_01",
    power: 0,
    citadel_level: 1,
    vip_level: 0,
    last_online: nowUnix(),
    created_at: nowUnix(),
    updated_at: nowUnix(),
    profile_version: PROFILE_VERSION,
  };
  const withCoords = ensureCastleCoords(nk, created);
  writeProfile(nk, withCoords);
  upsertKingdomCastleEntry(nk, withCoords);
  logger.info("Created Crownspire profile for %s kingdom=%s", userId, DEV_KINGDOM_ID);
  return withCoords;
}

/** Backfill Phase 5.1 identity fields on older profiles. */
function normalizeIdentityFields(nk: nkruntime.Nakama, profile: CrownspireProfile): CrownspireProfile {
  let changed = false;
  if (!profile.avatar_id) {
    profile.avatar_id = "avatar_01";
    changed = true;
  }
  if (typeof profile.power !== "number") {
    profile.power = 0;
    changed = true;
  }
  if (typeof profile.citadel_level !== "number" || profile.citadel_level < 1) {
    profile.citadel_level = 1;
    changed = true;
  }
  if (typeof profile.vip_level !== "number") {
    profile.vip_level = 0;
    changed = true;
  }
  if (typeof profile.last_online !== "number") {
    profile.last_online = profile.updated_at || nowUnix();
    changed = true;
  }
  if (changed) {
    writeProfile(nk, profile);
  }
  return profile;
}

function syncAllianceFields(nk: nkruntime.Nakama, logger: nkruntime.Logger, profile: CrownspireProfile): CrownspireProfile {
  const groups = nk.userGroupsList(profile.user_id, 100);
  let membership: nkruntime.UserGroupListUserGroup | null = null;
  const list = groups.userGroups || [];
  for (let i = 0; i < list.length; i++) {
    const ug = list[i];
    const state = Number(ug.state);
    // Active membership only (0 superadmin, 1 admin, 2 member). Ignore join requests (3).
    if ((state === 0 || state === 1 || state === 2) && ug.group) {
      membership = ug;
      break;
    }
  }

  let changed = false;
  if (!membership || !membership.group) {
    if (profile.alliance_id !== "" || profile.alliance_tag !== "" || profile.alliance_name !== "" || profile.crownspire_rank !== "") {
      profile.alliance_id = "";
      profile.alliance_tag = "";
      profile.alliance_name = "";
      profile.crownspire_rank = "";
      changed = true;
    }
  } else {
    const group = membership.group;
    const groupId = String(group.id);
    const meta = safeJson(group.metadata || {});
    const tag = String(meta["alliance_tag"] || "").toUpperCase();
    const name = String(group.name || "");
    const rank = resolveCrownspireRank(nk, groupId, profile.user_id, Number(membership.state));
    if (
      profile.alliance_id !== groupId ||
      profile.alliance_tag !== tag ||
      profile.alliance_name !== name ||
      profile.crownspire_rank !== rank
    ) {
      profile.alliance_id = groupId;
      profile.alliance_tag = tag;
      profile.alliance_name = name;
      profile.crownspire_rank = rank;
      changed = true;
    }
  }

  if (changed) {
    profile.updated_at = nowUnix();
    writeProfile(nk, profile);
  }
  return profile;
}

function resolveCrownspireRank(nk: nkruntime.Nakama, groupId: string, userId: string, nakamaState: number): string {
  const stored = readRank(nk, groupId, userId);
  if (stored && stored.crownspire_rank) {
    return stored.crownspire_rank;
  }
  // Default mapping from Nakama group state.
  if (nakamaState === 0) return "R5";
  if (nakamaState === 1) return "R4";
  return "R2";
}

function readProfile(nk: nkruntime.Nakama, userId: string): CrownspireProfile | null {
  const objects = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: userId }]);
  if (!objects || objects.length === 0 || !objects[0].value) {
    return null;
  }
  return objects[0].value as CrownspireProfile;
}

function writeProfile(nk: nkruntime.Nakama, profile: CrownspireProfile): void {
  nk.storageWrite([
    {
      collection: PROFILE_COLLECTION,
      key: PROFILE_KEY,
      userId: profile.user_id,
      value: profile,
      permissionRead: 2, // public read of profile fields we expose via RPC
      permissionWrite: 0, // server-only write
    },
  ]);
}

function rankStorageKey(groupId: string, userId: string): string {
  return groupId + ":" + userId;
}

function readRank(nk: nkruntime.Nakama, groupId: string, userId: string): AllianceRankRecord | null {
  const objects = nk.storageRead([
    { collection: RANK_COLLECTION, key: rankStorageKey(groupId, userId), userId: SYSTEM_USER },
  ]);
  if (!objects || objects.length === 0 || !objects[0].value) {
    return null;
  }
  return objects[0].value as AllianceRankRecord;
}

function writeRank(nk: nkruntime.Nakama, groupId: string, userId: string, rank: string): void {
  const record: AllianceRankRecord = {
    group_id: groupId,
    user_id: userId,
    crownspire_rank: rank,
    updated_at: nowUnix(),
  };
  nk.storageWrite([
    {
      collection: RANK_COLLECTION,
      key: rankStorageKey(groupId, userId),
      userId: SYSTEM_USER,
      value: record,
      permissionRead: 1,
      permissionWrite: 0,
    },
  ]);
}

function publicProfile(profile: CrownspireProfile): any {
  const now = nowUnix();
  const lastOnline = typeof profile.last_online === "number" ? profile.last_online : 0;
  const online = lastOnline > 0 && now - lastOnline <= PRESENCE_ONLINE_SEC;
  const power = typeof profile.power === "number" ? profile.power : 0;
  const highest =
    typeof profile.highest_power === "number" ? Math.max(profile.highest_power, power) : power;
  const kills = typeof profile.kills === "number" && profile.kills >= 0 ? Math.floor(profile.kills) : 0;
  const gear = Array.isArray(profile.public_equipment) ? profile.public_equipment : [];
  return {
    user_id: profile.user_id,
    display_name: profile.display_name,
    kingdom_id: profile.kingdom_id,
    alliance_id: profile.alliance_id,
    alliance_tag: profile.alliance_tag,
    alliance_name: profile.alliance_name,
    crownspire_rank: profile.crownspire_rank,
    avatar_id: profile.avatar_id || "avatar_01",
    power,
    kills,
    highest_power: highest,
    // Public showcase only — never troops/resources/garrison/marches.
    public_equipment: gear,
    citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
    vip_level: typeof profile.vip_level === "number" ? profile.vip_level : 0,
    last_online: lastOnline,
    online_status: online ? "online" : "offline",
    world_x: typeof (profile as any).world_x === "number" ? (profile as any).world_x : 0,
    world_y: typeof (profile as any).world_y === "number" ? (profile as any).world_y : 0,
    peace_shield_expires_at:
      typeof (profile as any).peace_shield_expires_at === "number"
        ? (profile as any).peace_shield_expires_at
        : 0,
    anti_scout_expires_at:
      typeof (profile as any).anti_scout_expires_at === "number"
        ? (profile as any).anti_scout_expires_at
        : 0,
    beginner_protection_expires_at:
      typeof (profile as any).beginner_protection_expires_at === "number"
        ? (profile as any).beginner_protection_expires_at
        : 0,
    beginner_protection_cleared: Boolean((profile as any).beginner_protection_cleared),
    peace_shield_active:
      typeof (profile as any).peace_shield_expires_at === "number" &&
      (profile as any).peace_shield_expires_at > now,
    anti_scout_active:
      typeof (profile as any).anti_scout_expires_at === "number" &&
      (profile as any).anti_scout_expires_at > now,
    beginner_protection_active:
      !Boolean((profile as any).beginner_protection_cleared) &&
      typeof (profile as any).beginner_protection_expires_at === "number" &&
      (profile as any).beginner_protection_expires_at > now,
    created_at: profile.created_at,
    updated_at: profile.updated_at,
    profile_version: profile.profile_version,
  };
}

// ---------------------------------------------------------------------------
// Alliance (Nakama Groups)
// ---------------------------------------------------------------------------

function rpcCreateAlliance(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  assertRateLimit(nk, ctx.userId, "create_alliance", ALLIANCE_CREATE_COOLDOWN_SEC);

  const profile = ensureProfile(nk, logger, ctx.userId);
  if (profile.alliance_id) {
    throw Err("Already in an alliance");
  }

  const data = parsePayload(payload);
  const name = sanitizeAllianceName(String(data["name"] || ""));
  const tag = sanitizeAllianceTag(String(data["tag"] || ""));
  assertAllianceTagUnique(nk, tag);

  let description = String(data["description"] || "").trim();
  description = description.replace(/[\u0000-\u001F\u007F]/g, "").substring(0, 280);
  if (description === "") {
    description = "A Crownspire alliance.";
  }
  const language = String(data["language"] || "en").trim().substring(0, 8) || "en";
  let joinType = String(data["join_type"] || "apply").trim().toLowerCase();
  if (joinType !== "open" && joinType !== "apply") {
    throw Err("join_type must be open or apply");
  }
  let minCitadel = Math.floor(Number(data["min_citadel_level"] !== undefined ? data["min_citadel_level"] : 0));
  if (isNaN(minCitadel) || minCitadel < 0 || minCitadel > 100) {
    throw Err("Invalid min_citadel_level");
  }

  const isOpen = joinType === "open";
  const metadata: { [key: string]: any } = {
    alliance_tag: tag,
    kingdom_id: profile.kingdom_id || DEV_KINGDOM_ID,
    crownspire: true,
  };

  let group: nkruntime.Group;
  try {
    group = nk.groupCreate(
      ctx.userId,
      name,
      ctx.userId,
      language,
      description,
      null,
      isOpen,
      metadata,
      100
    );
  } catch (e) {
    const msg = String(e);
    if (msg.toLowerCase().indexOf("name") >= 0 || msg.toLowerCase().indexOf("unique") >= 0) {
      throw Err("Alliance name already taken");
    }
    throw Err("Could not create alliance");
  }

  writeRank(nk, group.id, ctx.userId, "R5");
  writeAllianceMeta(nk, {
    alliance_id: group.id,
    description: description,
    language: language,
    join_type: joinType,
    min_join_power_placeholder: 0,
    min_citadel_level: minCitadel,
    announcement: "",
    emblem_placeholder: "",
    banner_placeholder: "",
    alliance_power_placeholder: 0,
    alliance_level_placeholder: 1,
    updated_at: nowUnix(),
  });
  profile.alliance_id = group.id;
  profile.alliance_tag = tag;
  profile.alliance_name = name;
  profile.crownspire_rank = "R5";
  profile.updated_at = nowUnix();
  writeProfile(nk, profile);

  sendAllianceSystemMessage(
    nk,
    logger,
    group.id,
    (profile.display_name || "The Leader") + " raised the banner of [" + tag + "] " + name + ".",
    "created"
  );

  logger.info("Alliance created group=%s tag=%s join_type=%s by %s", group.id, tag, joinType, ctx.userId);
  return JSON.stringify({
    ok: true,
    alliance: buildAllianceProfile(nk, logger, group),
    profile: publicProfile(profile),
  });
}

function rpcJoinAlliance(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (profile.alliance_id) {
    throw Err("Already in an alliance");
  }
  const data = parsePayload(payload);
  const groupId = String(data["alliance_id"] || "").trim();
  if (!groupId) {
    throw Err("alliance_id required");
  }

  const groups = nk.groupsGetId([groupId]);
  if (!groups || groups.length === 0) {
    throw Err("Alliance not found");
  }
  const group = groups[0];
  const meta = safeJson(group.metadata || {});
  if (!meta["crownspire"] && !meta["alliance_tag"]) {
    throw Err("Not a Crownspire alliance group");
  }

  const stored = readAllianceMeta(nk, groupId);
  const joinType = stored.join_type || (group.open ? "open" : "apply");
  const minCitadel = typeof stored.min_citadel_level === "number" ? stored.min_citadel_level : 0;
  const citadel = typeof profile.citadel_level === "number" ? profile.citadel_level : 1;
  if (citadel < minCitadel) {
    throw Err("Citadel level " + minCitadel + " required to join");
  }
  if (joinType === "invite_only") {
    throw Err("This alliance is invite only");
  }

  // Capacity check (edgeCount includes requests; prefer active members when listing).
  const memberLimit = Number(group.maxCount || 100);
  if (Number(group.edgeCount || 0) >= memberLimit && joinType === "open") {
    throw Err("Alliance is full");
  }

  if (joinType === "open") {
    try {
      nk.groupUserJoin(groupId, ctx.userId, ctx.username || "");
    } catch (e) {
      throw Err("Could not join alliance");
    }
    // Ensure membership for alliances that may still be private in Nakama but marked open in meta.
    const stateAfter = getNakamaGroupState(nk, groupId, ctx.userId);
    if (stateAfter < 0 || stateAfter > 2) {
      try {
        nk.groupUsersAdd(groupId, [ctx.userId]);
      } catch (e2) {
        throw Err("Could not join open alliance");
      }
    }
    writeRank(nk, groupId, ctx.userId, "R1");
    syncAllianceFields(nk, logger, profile);
    const refreshed = ensureProfile(nk, logger, ctx.userId);
    sendAllianceSystemMessage(
      nk,
      logger,
      groupId,
      (refreshed.display_name || "A player") + " joined the Alliance.",
      "joined"
    );
    logger.info("Alliance open join group=%s user=%s", groupId, ctx.userId);
    return JSON.stringify({
      ok: true,
      pending: false,
      alliance_id: groupId,
      alliance: buildAllianceProfile(nk, logger, groups[0]),
      profile: publicProfile(refreshed),
      message: "Joined alliance.",
    });
  }

  // Approval-required: create join request. Check duplicate pending.
  const pendingUsers = nk.groupUsersList(groupId, 100, 3);
  const pendingList = pendingUsers.groupUsers || [];
  for (let i = 0; i < pendingList.length; i++) {
    const gu = pendingList[i];
    if (!gu.user) continue;
    const uid = String(gu.user.userId || (gu.user as any).id || "");
    if (uid === ctx.userId) {
      return JSON.stringify({
        ok: true,
        pending: true,
        alliance_id: groupId,
        message: "Application already sent.",
      });
    }
  }

  try {
    nk.groupUserJoin(groupId, ctx.userId, ctx.username || "");
  } catch (e) {
    throw Err("Could not submit application");
  }
  notifyAllianceOfficers(
    nk,
    logger,
    groupId,
    "Alliance Application",
    {
      event: "application_received",
      alliance_id: groupId,
      applicant_user_id: ctx.userId,
      applicant_name: profile.display_name || ctx.username || "",
    },
    ctx.userId
  );
  logger.info("Alliance join requested group=%s user=%s", groupId, ctx.userId);
  return JSON.stringify({
    ok: true,
    pending: true,
    alliance_id: groupId,
    message: "Application sent.",
  });
}

function rpcListJoinRequests(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "view_applications");

  const users = nk.groupUsersList(profile.alliance_id, 100, 3); // state 3 = join request
  const list = users.groupUsers || [];
  const out: any[] = [];
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    if (!gu.user) {
      continue;
    }
    const u = gu.user;
    const uid = String(u.userId || (u as any).id || "");
    const applicant = ensureProfile(nk, logger, uid);
    out.push({
      user_id: uid,
      username: u.username,
      display_name: applicant.display_name || u.displayName || "",
      power: typeof applicant.power === "number" ? applicant.power : 0,
      power_placeholder: typeof applicant.power === "number" ? applicant.power : 0,
      citadel_level: typeof applicant.citadel_level === "number" ? applicant.citadel_level : 1,
      message: "",
      status: "pending",
      created_at: nowUnix(),
      state: gu.state,
    });
  }
  return JSON.stringify({ ok: true, requests: out, applications: out });
}

function rpcApproveJoin(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) {
    throw Err("user_id required");
  }
  return approveJoinPhase4(ctx, logger, nk, profile, targetId);
}

function rpcKickMember(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) {
    throw Err("user_id required");
  }
  return kickMemberPhase4(ctx, logger, nk, profile, targetId);
}

function rpcLeaveAlliance(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  return leaveAlliancePhase4(ctx, logger, nk, profile);
}

function requireAllianceAdmin(nk: nkruntime.Nakama, groupId: string, userId: string): void {
  const users = nk.groupUsersList(groupId, 100);
  const list = users.groupUsers || [];
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    if (!gu.user) {
      continue;
    }
    const uid = String(gu.user.userId || (gu.user as any).id || "");
    if (uid === userId) {
      const state = Number(gu.state);
      if (state === 0 || state === 1) {
        return;
      }
      throw Err("Alliance admin permission required");
    }
  }
  throw Err("Not an alliance member");
}

// ---------------------------------------------------------------------------
// Chat report RPC
// ---------------------------------------------------------------------------

function rpcChatReport(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }

  const data = parsePayload(payload);
  const reportedUserId = String(data["reported_user_id"] || "").trim();
  const messageId = String(data["message_id"] || "").trim();
  const channelId = String(data["channel_id"] || "").trim();
  const messageType = String(data["message_type"] || "TEXT").trim();
  const reason = String(data["reason"] || "").trim();
  const messageText = String(data["message_text"] || "").substring(0, 500);
  const createTime = String(data["create_time"] || data["timestamp"] || "");

  if (!reportedUserId) throw Err("reported_user_id required");
  if (!messageId) throw Err("message_id required");
  if (!channelId) throw Err("channel_id required");
  if (!REPORT_REASONS[reason]) throw Err("Invalid report reason");
  if (reportedUserId === ctx.userId) throw Err("Cannot report yourself");

  // Rate-limit only after payload validation so bad requests do not burn cooldown.
  assertRateLimit(nk, ctx.userId, "chat_report", REPORT_COOLDOWN_SEC);

  // Reporter identity ALWAYS from authenticated context — never trust client reporter_user_id.
  const reportId = nk.uuidv4();
  const report = {
    report_id: reportId,
    reporter_user_id: ctx.userId,
    reported_user_id: reportedUserId,
    message_id: messageId,
    channel_id: channelId,
    message_type: messageType,
    message_text: messageText,
    reason: reason,
    create_time: createTime,
    created_at: nowUnix(),
    status: "open",
    // Evidence only — no automatic punishment in this phase.
  };

  nk.storageWrite([
    {
      collection: REPORT_COLLECTION,
      key: reportId,
      userId: SYSTEM_USER, // system-owned moderation inbox
      value: report,
      permissionRead: 0,
      permissionWrite: 0,
    },
  ]);

  logger.info("Chat report stored id=%s reporter=%s reported=%s reason=%s", reportId, ctx.userId, reportedUserId, reason);
  return JSON.stringify({
    ok: true,
    report_id: reportId,
    status: "open",
    message: "Report submitted for moderation review. No automatic punishment applied.",
  });
}

// ---------------------------------------------------------------------------
// Validation / helpers
// ---------------------------------------------------------------------------

function sanitizeDisplayName(raw: string): string {
  let name = (raw || "").trim();
  name = name.replace(/[\u0000-\u001F\u007F]/g, "");
  if (name.length < DISPLAY_NAME_MIN || name.length > DISPLAY_NAME_MAX) {
    throw Err("Display name must be " + DISPLAY_NAME_MIN + "-" + DISPLAY_NAME_MAX + " characters");
  }
  if (/[<>{}\\`]/.test(name)) {
    throw Err("Display name contains forbidden characters");
  }
  return name;
}

function sanitizeAllianceName(raw: string): string {
  let name = (raw || "").trim();
  name = name.replace(/[\u0000-\u001F\u007F]/g, "");
  if (name.length < ALLIANCE_NAME_MIN || name.length > ALLIANCE_NAME_MAX) {
    throw Err("Alliance name must be " + ALLIANCE_NAME_MIN + "-" + ALLIANCE_NAME_MAX + " characters");
  }
  return name;
}

function sanitizeAllianceTag(raw: string): string {
  let tag = (raw || "").trim().toUpperCase();
  tag = tag.replace(/[^A-Z0-9]/g, "");
  if (tag.length < ALLIANCE_TAG_MIN || tag.length > ALLIANCE_TAG_MAX) {
    throw Err("Alliance tag must be " + ALLIANCE_TAG_MIN + "-" + ALLIANCE_TAG_MAX + " alphanumeric characters");
  }
  return tag;
}

function defaultDevName(userId: string): string {
  const suffix = userId.replace(/-/g, "").substring(0, 6);
  return "Dev_" + suffix;
}

function assertRateLimit(nk: nkruntime.Nakama, userId: string, action: string, cooldownSec: number): void {
  const key = action;
  const objects = nk.storageRead([{ collection: RATE_COLLECTION, key: key, userId: userId }]);
  const now = nowUnix();
  if (objects && objects.length > 0 && objects[0].value) {
    const last = Number((objects[0].value as any).last_unix || 0);
    if (now - last < cooldownSec) {
      throw Err("Rate limited. Try again shortly.");
    }
  }
  nk.storageWrite([
    {
      collection: RATE_COLLECTION,
      key: key,
      userId: userId,
      value: { last_unix: now, action: action },
      permissionRead: 0,
      permissionWrite: 0,
    },
  ]);
}

function parsePayload(payload: string): any {
  if (!payload || payload === "") {
    return {};
  }
  try {
    return JSON.parse(payload);
  } catch (e) {
    throw Err("Invalid JSON payload");
  }
}

function safeJson(raw: any): any {
  if (typeof raw === "object" && raw !== null) {
    return raw;
  }
  try {
    return JSON.parse(String(raw || "{}"));
  } catch (e) {
    return {};
  }
}

function nowUnix(): number {
  return Math.floor(Date.now() / 1000);
}

function Err(message: string): Error {
  // Nakama JS runtime surfaces Error message to clients.
  return new Error(message);
}

// Nakama expects this global initializer name.
//! Keep InitModule as the runtime entry export shape.
