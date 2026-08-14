"use strict";
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
var PROFILE_COLLECTION = "crownspire_profiles";
var PROFILE_KEY = "profile";
var REPORT_COLLECTION = "crownspire_chat_reports";
var RANK_COLLECTION = "crownspire_alliance_ranks";
var RATE_COLLECTION = "crownspire_rate_limits";
/** Nakama system storage owner — group IDs are NOT valid storage userIds. */
var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
var DEV_KINGDOM_ID = "kingdom_dev_001";
var PROFILE_VERSION = 2;
/** Consider a player online if heartbeat within this window. */
var PRESENCE_ONLINE_SEC = 90;
var DISPLAY_NAME_MIN = 3;
var DISPLAY_NAME_MAX = 24;
var ALLIANCE_NAME_MIN = 3;
var ALLIANCE_NAME_MAX = 24;
var ALLIANCE_TAG_MIN = 3;
var ALLIANCE_TAG_MAX = 4;
/** Beta: rename is free/frequent for testing. Raise for production. */
var DISPLAY_NAME_COOLDOWN_SEC = 5;
var REPORT_COOLDOWN_SEC = 10;
var ALLIANCE_CREATE_COOLDOWN_SEC = 30;
var REPORT_REASONS = {
    spam: true,
    harassment: true,
    hate_or_abuse: true,
    sexual_content: true,
    cheating_or_scam: true,
    impersonation: true,
    inappropriate_name: true,
    other: true,
};
function InitModule(ctx, logger, nk, initializer) {
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
    }
    else {
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
function rpcGetProfile(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}
function rpcSetDisplayName(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var data = parsePayload(payload);
    // Validate before rate-limit write so rejected names do not burn cooldown.
    var name = sanitizeDisplayName(String(data["display_name"] || ""));
    assertRateLimit(nk, ctx.userId, "set_display_name", DISPLAY_NAME_COOLDOWN_SEC);
    var profile = ensureProfile(nk, logger, ctx.userId);
    profile.display_name = name;
    profile.updated_at = nowUnix();
    writeProfile(nk, profile);
    // Mirror into Nakama account display name (non-authoritative cache for lobby UI).
    try {
        nk.accountUpdateId(ctx.userId, null, name, null, null, null, null);
    }
    catch (e) {
        logger.warn("accountUpdateId display_name mirror failed: %s", String(e));
    }
    return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}
function rpcGetPublicProfile(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId) {
        throw Err("user_id required");
    }
    var profile = ensureProfile(nk, logger, targetId);
    return JSON.stringify({
        ok: true,
        profile: publicProfile(profile),
    });
}
function ensureProfile(nk, logger, userId) {
    var existing = readProfile(nk, userId);
    if (existing) {
        var normalized = normalizeIdentityFields(nk, existing);
        var withCastle = ensureCastleCoords(nk, normalized);
        var synced = syncAllianceFields(nk, logger, withCastle);
        upsertKingdomCastleEntry(nk, synced);
        return synced;
    }
    var created = {
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
    var withCoords = ensureCastleCoords(nk, created);
    writeProfile(nk, withCoords);
    upsertKingdomCastleEntry(nk, withCoords);
    logger.info("Created Crownspire profile for %s kingdom=%s", userId, DEV_KINGDOM_ID);
    return withCoords;
}
/** Backfill Phase 5.1 identity fields on older profiles. */
function normalizeIdentityFields(nk, profile) {
    var changed = false;
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
function syncAllianceFields(nk, logger, profile) {
    var groups = nk.userGroupsList(profile.user_id, 100);
    var membership = null;
    var list = groups.userGroups || [];
    for (var i = 0; i < list.length; i++) {
        var ug = list[i];
        var state = Number(ug.state);
        // Active membership only (0 superadmin, 1 admin, 2 member). Ignore join requests (3).
        if ((state === 0 || state === 1 || state === 2) && ug.group) {
            membership = ug;
            break;
        }
    }
    var changed = false;
    if (!membership || !membership.group) {
        if (profile.alliance_id !== "" || profile.alliance_tag !== "" || profile.alliance_name !== "" || profile.crownspire_rank !== "") {
            profile.alliance_id = "";
            profile.alliance_tag = "";
            profile.alliance_name = "";
            profile.crownspire_rank = "";
            changed = true;
        }
    }
    else {
        var group = membership.group;
        var groupId = String(group.id);
        var meta = safeJson(group.metadata || {});
        var tag = String(meta["alliance_tag"] || "").toUpperCase();
        var name = String(group.name || "");
        var rank = resolveCrownspireRank(nk, groupId, profile.user_id, Number(membership.state));
        if (profile.alliance_id !== groupId ||
            profile.alliance_tag !== tag ||
            profile.alliance_name !== name ||
            profile.crownspire_rank !== rank) {
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
function resolveCrownspireRank(nk, groupId, userId, nakamaState) {
    var stored = readRank(nk, groupId, userId);
    if (stored && stored.crownspire_rank) {
        return stored.crownspire_rank;
    }
    // Default mapping from Nakama group state.
    if (nakamaState === 0)
        return "R5";
    if (nakamaState === 1)
        return "R4";
    return "R2";
}
function readProfile(nk, userId) {
    var objects = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: userId }]);
    if (!objects || objects.length === 0 || !objects[0].value) {
        return null;
    }
    return objects[0].value;
}
function writeProfile(nk, profile) {
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
function rankStorageKey(groupId, userId) {
    return groupId + ":" + userId;
}
function readRank(nk, groupId, userId) {
    var objects = nk.storageRead([
        { collection: RANK_COLLECTION, key: rankStorageKey(groupId, userId), userId: SYSTEM_USER },
    ]);
    if (!objects || objects.length === 0 || !objects[0].value) {
        return null;
    }
    return objects[0].value;
}
function writeRank(nk, groupId, userId, rank) {
    var record = {
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
function publicProfile(profile) {
    var now = nowUnix();
    var lastOnline = typeof profile.last_online === "number" ? profile.last_online : 0;
    var online = lastOnline > 0 && now - lastOnline <= PRESENCE_ONLINE_SEC;
    var power = typeof profile.power === "number" ? profile.power : 0;
    var highest = typeof profile.highest_power === "number" ? Math.max(profile.highest_power, power) : power;
    var kills = typeof profile.kills === "number" && profile.kills >= 0 ? Math.floor(profile.kills) : 0;
    var gear = Array.isArray(profile.public_equipment) ? profile.public_equipment : [];
    return {
        user_id: profile.user_id,
        display_name: profile.display_name,
        kingdom_id: profile.kingdom_id,
        alliance_id: profile.alliance_id,
        alliance_tag: profile.alliance_tag,
        alliance_name: profile.alliance_name,
        crownspire_rank: profile.crownspire_rank,
        avatar_id: profile.avatar_id || "avatar_01",
        power: power,
        kills: kills,
        highest_power: highest,
        // Public showcase only — never troops/resources/garrison/marches.
        public_equipment: gear,
        citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
        vip_level: typeof profile.vip_level === "number" ? profile.vip_level : 0,
        last_online: lastOnline,
        online_status: online ? "online" : "offline",
        world_x: typeof profile.world_x === "number" ? profile.world_x : 0,
        world_y: typeof profile.world_y === "number" ? profile.world_y : 0,
        peace_shield_expires_at: typeof profile.peace_shield_expires_at === "number"
            ? profile.peace_shield_expires_at
            : 0,
        anti_scout_expires_at: typeof profile.anti_scout_expires_at === "number"
            ? profile.anti_scout_expires_at
            : 0,
        beginner_protection_expires_at: typeof profile.beginner_protection_expires_at === "number"
            ? profile.beginner_protection_expires_at
            : 0,
        beginner_protection_cleared: Boolean(profile.beginner_protection_cleared),
        peace_shield_active: typeof profile.peace_shield_expires_at === "number" &&
            profile.peace_shield_expires_at > now,
        anti_scout_active: typeof profile.anti_scout_expires_at === "number" &&
            profile.anti_scout_expires_at > now,
        beginner_protection_active: !Boolean(profile.beginner_protection_cleared) &&
            typeof profile.beginner_protection_expires_at === "number" &&
            profile.beginner_protection_expires_at > now,
        created_at: profile.created_at,
        updated_at: profile.updated_at,
        profile_version: profile.profile_version,
    };
}
// ---------------------------------------------------------------------------
// Alliance (Nakama Groups)
// ---------------------------------------------------------------------------
function rpcCreateAlliance(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    assertRateLimit(nk, ctx.userId, "create_alliance", ALLIANCE_CREATE_COOLDOWN_SEC);
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (profile.alliance_id) {
        throw Err("Already in an alliance");
    }
    var data = parsePayload(payload);
    var name = sanitizeAllianceName(String(data["name"] || ""));
    var tag = sanitizeAllianceTag(String(data["tag"] || ""));
    assertAllianceTagUnique(nk, tag);
    var description = String(data["description"] || "").trim();
    description = description.replace(/[\u0000-\u001F\u007F]/g, "").substring(0, 280);
    if (description === "") {
        description = "A Crownspire alliance.";
    }
    var language = String(data["language"] || "en").trim().substring(0, 8) || "en";
    var joinType = String(data["join_type"] || "apply").trim().toLowerCase();
    if (joinType !== "open" && joinType !== "apply") {
        throw Err("join_type must be open or apply");
    }
    var minCitadel = Math.floor(Number(data["min_citadel_level"] !== undefined ? data["min_citadel_level"] : 0));
    if (isNaN(minCitadel) || minCitadel < 0 || minCitadel > 100) {
        throw Err("Invalid min_citadel_level");
    }
    var isOpen = joinType === "open";
    var metadata = {
        alliance_tag: tag,
        kingdom_id: profile.kingdom_id || DEV_KINGDOM_ID,
        crownspire: true,
    };
    var group;
    try {
        group = nk.groupCreate(ctx.userId, name, ctx.userId, language, description, null, isOpen, metadata, 100);
    }
    catch (e) {
        var msg = String(e);
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
    sendAllianceSystemMessage(nk, logger, group.id, (profile.display_name || "The Leader") + " raised the banner of [" + tag + "] " + name + ".", "created");
    logger.info("Alliance created group=%s tag=%s join_type=%s by %s", group.id, tag, joinType, ctx.userId);
    return JSON.stringify({
        ok: true,
        alliance: buildAllianceProfile(nk, logger, group),
        profile: publicProfile(profile),
    });
}
function rpcJoinAlliance(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (profile.alliance_id) {
        throw Err("Already in an alliance");
    }
    var data = parsePayload(payload);
    var groupId = String(data["alliance_id"] || "").trim();
    if (!groupId) {
        throw Err("alliance_id required");
    }
    var groups = nk.groupsGetId([groupId]);
    if (!groups || groups.length === 0) {
        throw Err("Alliance not found");
    }
    var group = groups[0];
    var meta = safeJson(group.metadata || {});
    if (!meta["crownspire"] && !meta["alliance_tag"]) {
        throw Err("Not a Crownspire alliance group");
    }
    var stored = readAllianceMeta(nk, groupId);
    var joinType = stored.join_type || (group.open ? "open" : "apply");
    var minCitadel = typeof stored.min_citadel_level === "number" ? stored.min_citadel_level : 0;
    var citadel = typeof profile.citadel_level === "number" ? profile.citadel_level : 1;
    if (citadel < minCitadel) {
        throw Err("Citadel level " + minCitadel + " required to join");
    }
    if (joinType === "invite_only") {
        throw Err("This alliance is invite only");
    }
    // Capacity check (edgeCount includes requests; prefer active members when listing).
    var memberLimit = Number(group.maxCount || 100);
    if (Number(group.edgeCount || 0) >= memberLimit && joinType === "open") {
        throw Err("Alliance is full");
    }
    if (joinType === "open") {
        try {
            nk.groupUserJoin(groupId, ctx.userId, ctx.username || "");
        }
        catch (e) {
            throw Err("Could not join alliance");
        }
        // Ensure membership for alliances that may still be private in Nakama but marked open in meta.
        var stateAfter = getNakamaGroupState(nk, groupId, ctx.userId);
        if (stateAfter < 0 || stateAfter > 2) {
            try {
                nk.groupUsersAdd(groupId, [ctx.userId]);
            }
            catch (e2) {
                throw Err("Could not join open alliance");
            }
        }
        writeRank(nk, groupId, ctx.userId, "R1");
        syncAllianceFields(nk, logger, profile);
        var refreshed = ensureProfile(nk, logger, ctx.userId);
        sendAllianceSystemMessage(nk, logger, groupId, (refreshed.display_name || "A player") + " joined the Alliance.", "joined");
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
    var pendingUsers = nk.groupUsersList(groupId, 100, 3);
    var pendingList = pendingUsers.groupUsers || [];
    for (var i = 0; i < pendingList.length; i++) {
        var gu = pendingList[i];
        if (!gu.user)
            continue;
        var uid = String(gu.user.userId || gu.user.id || "");
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
    }
    catch (e) {
        throw Err("Could not submit application");
    }
    notifyAllianceOfficers(nk, logger, groupId, "Alliance Application", {
        event: "application_received",
        alliance_id: groupId,
        applicant_user_id: ctx.userId,
        applicant_name: profile.display_name || ctx.username || "",
    }, ctx.userId);
    logger.info("Alliance join requested group=%s user=%s", groupId, ctx.userId);
    return JSON.stringify({
        ok: true,
        pending: true,
        alliance_id: groupId,
        message: "Application sent.",
    });
}
function rpcListJoinRequests(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "view_applications");
    var users = nk.groupUsersList(profile.alliance_id, 100, 3); // state 3 = join request
    var list = users.groupUsers || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        if (!gu.user) {
            continue;
        }
        var u = gu.user;
        var uid = String(u.userId || u.id || "");
        var applicant = ensureProfile(nk, logger, uid);
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
function rpcApproveJoin(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId) {
        throw Err("user_id required");
    }
    return approveJoinPhase4(ctx, logger, nk, profile, targetId);
}
function rpcKickMember(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId) {
        throw Err("user_id required");
    }
    return kickMemberPhase4(ctx, logger, nk, profile, targetId);
}
function rpcLeaveAlliance(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    return leaveAlliancePhase4(ctx, logger, nk, profile);
}
function requireAllianceAdmin(nk, groupId, userId) {
    var users = nk.groupUsersList(groupId, 100);
    var list = users.groupUsers || [];
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        if (!gu.user) {
            continue;
        }
        var uid = String(gu.user.userId || gu.user.id || "");
        if (uid === userId) {
            var state = Number(gu.state);
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
function rpcChatReport(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var data = parsePayload(payload);
    var reportedUserId = String(data["reported_user_id"] || "").trim();
    var messageId = String(data["message_id"] || "").trim();
    var channelId = String(data["channel_id"] || "").trim();
    var messageType = String(data["message_type"] || "TEXT").trim();
    var reason = String(data["reason"] || "").trim();
    var messageText = String(data["message_text"] || "").substring(0, 500);
    var createTime = String(data["create_time"] || data["timestamp"] || "");
    if (!reportedUserId)
        throw Err("reported_user_id required");
    if (!messageId)
        throw Err("message_id required");
    if (!channelId)
        throw Err("channel_id required");
    if (!REPORT_REASONS[reason])
        throw Err("Invalid report reason");
    if (reportedUserId === ctx.userId)
        throw Err("Cannot report yourself");
    // Rate-limit only after payload validation so bad requests do not burn cooldown.
    assertRateLimit(nk, ctx.userId, "chat_report", REPORT_COOLDOWN_SEC);
    // Reporter identity ALWAYS from authenticated context — never trust client reporter_user_id.
    var reportId = nk.uuidv4();
    var report = {
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
function sanitizeDisplayName(raw) {
    var name = (raw || "").trim();
    name = name.replace(/[\u0000-\u001F\u007F]/g, "");
    if (name.length < DISPLAY_NAME_MIN || name.length > DISPLAY_NAME_MAX) {
        throw Err("Display name must be " + DISPLAY_NAME_MIN + "-" + DISPLAY_NAME_MAX + " characters");
    }
    if (/[<>{}\\`]/.test(name)) {
        throw Err("Display name contains forbidden characters");
    }
    return name;
}
function sanitizeAllianceName(raw) {
    var name = (raw || "").trim();
    name = name.replace(/[\u0000-\u001F\u007F]/g, "");
    if (name.length < ALLIANCE_NAME_MIN || name.length > ALLIANCE_NAME_MAX) {
        throw Err("Alliance name must be " + ALLIANCE_NAME_MIN + "-" + ALLIANCE_NAME_MAX + " characters");
    }
    return name;
}
function sanitizeAllianceTag(raw) {
    var tag = (raw || "").trim().toUpperCase();
    tag = tag.replace(/[^A-Z0-9]/g, "");
    if (tag.length < ALLIANCE_TAG_MIN || tag.length > ALLIANCE_TAG_MAX) {
        throw Err("Alliance tag must be " + ALLIANCE_TAG_MIN + "-" + ALLIANCE_TAG_MAX + " alphanumeric characters");
    }
    return tag;
}
function defaultDevName(userId) {
    var suffix = userId.replace(/-/g, "").substring(0, 6);
    return "Dev_" + suffix;
}
function assertRateLimit(nk, userId, action, cooldownSec) {
    var key = action;
    var objects = nk.storageRead([{ collection: RATE_COLLECTION, key: key, userId: userId }]);
    var now = nowUnix();
    if (objects && objects.length > 0 && objects[0].value) {
        var last = Number(objects[0].value.last_unix || 0);
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
function parsePayload(payload) {
    if (!payload || payload === "") {
        return {};
    }
    try {
        return JSON.parse(payload);
    }
    catch (e) {
        throw Err("Invalid JSON payload");
    }
}
function safeJson(raw) {
    if (typeof raw === "object" && raw !== null) {
        return raw;
    }
    try {
        return JSON.parse(String(raw || "{}"));
    }
    catch (e) {
        return {};
    }
}
function nowUnix() {
    return Math.floor(Date.now() / 1000);
}
function Err(message) {
    // Nakama JS runtime surfaces Error message to clients.
    return new Error(message);
}
// Nakama expects this global initializer name.
//! Keep InitModule as the runtime entry export shape.
/**
 * Crownspire Phase 4 — Alliance roster / ranks / applications / invites / permissions
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js via tsconfig files order.
 */
var INVITE_COLLECTION = "crownspire_alliance_invites";
var ALLIANCE_META_COLLECTION = "crownspire_alliance_meta";
var INVITE_EXPIRY_SEC = 7 * 24 * 3600;
var DEFAULT_MEMBER_LIMIT = 50;
var RANK_ORDER = {
    R1: 1,
    R2: 2,
    R3: 3,
    R4: 4,
    R5: 5,
};
var ROLE_DISPLAY = {
    R5: "Leader",
    R4: "Officer",
    R3: "Veteran",
    R2: "Member",
    R1: "Recruit",
};
var ALLIANCE_NOTIF_CODE = 5003;
/** Configurable Phase-4 permission policy (server-authoritative). */
var RANK_PERMISSIONS = {
    R5: {
        view_members: true,
        view_applications: true,
        invite: true,
        approve: true,
        reject: true,
        kick: true,
        promote: true,
        demote: true,
        edit_profile: true,
        transfer_leadership: true,
    },
    R4: {
        view_members: true,
        view_applications: true,
        invite: true,
        approve: true,
        reject: true,
        kick: true,
        promote: true,
        demote: true,
        edit_profile: false,
        transfer_leadership: false,
    },
    R3: {
        view_members: true,
        view_applications: false,
        invite: true,
        approve: false,
        reject: false,
        kick: false,
        promote: false,
        demote: false,
        edit_profile: false,
        transfer_leadership: false,
    },
    R2: {
        view_members: true,
        view_applications: false,
        invite: false,
        approve: false,
        reject: false,
        kick: false,
        promote: false,
        demote: false,
        edit_profile: false,
        transfer_leadership: false,
    },
    R1: {
        view_members: true,
        view_applications: false,
        invite: false,
        approve: false,
        reject: false,
        kick: false,
        promote: false,
        demote: false,
        edit_profile: false,
        transfer_leadership: false,
    },
};
function registerPhase4AllianceRpcs(_initializer, logger) {
    // Kept for documentation only — Nakama requires registerRpc calls inside InitModule.
    logger.info("Crownspire Phase 4 alliance handlers available (registered in InitModule).");
}
function rankValue(rank) {
    return RANK_ORDER[rank] || 0;
}
function hasPerm(rank, perm) {
    var table = RANK_PERMISSIONS[rank] || RANK_PERMISSIONS["R1"];
    return !!table[perm];
}
function requirePerm(nk, logger, groupId, userId, perm) {
    var profile = ensureProfile(nk, logger, userId);
    if (profile.alliance_id !== groupId) {
        throw Err("Not an alliance member");
    }
    var rank = resolveCrownspireRank(nk, groupId, userId, getNakamaGroupState(nk, groupId, userId));
    if (!hasPerm(rank, perm)) {
        throw Err("Permission denied: " + perm);
    }
    return rank;
}
function getNakamaGroupState(nk, groupId, userId) {
    var users = nk.groupUsersList(groupId, 100);
    var list = users.groupUsers || [];
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        if (!gu.user)
            continue;
        var uid = String(gu.user.userId || gu.user.id || "");
        if (uid === userId) {
            return Number(gu.state);
        }
    }
    return -1;
}
function readAllianceMeta(nk, allianceId) {
    var objects = nk.storageRead([
        { collection: ALLIANCE_META_COLLECTION, key: allianceId, userId: SYSTEM_USER },
    ]);
    var defaults = {
        alliance_id: allianceId,
        description: "",
        language: "en",
        join_type: "apply",
        min_join_power_placeholder: 0,
        min_citadel_level: 0,
        announcement: "",
        emblem_placeholder: "",
        banner_placeholder: "",
        alliance_power_placeholder: 0,
        alliance_level_placeholder: 1,
        updated_at: nowUnix(),
    };
    if (objects && objects.length > 0 && objects[0].value) {
        var stored = objects[0].value;
        return {
            alliance_id: allianceId,
            description: stored.description || "",
            language: stored.language || "en",
            join_type: stored.join_type || "apply",
            min_join_power_placeholder: stored.min_join_power_placeholder || 0,
            min_citadel_level: typeof stored.min_citadel_level === "number" ? stored.min_citadel_level : 0,
            announcement: stored.announcement || "",
            emblem_placeholder: stored.emblem_placeholder || "",
            banner_placeholder: stored.banner_placeholder || "",
            alliance_power_placeholder: stored.alliance_power_placeholder || 0,
            alliance_level_placeholder: stored.alliance_level_placeholder || 1,
            updated_at: stored.updated_at || nowUnix(),
        };
    }
    return defaults;
}
function writeAllianceMeta(nk, meta) {
    meta.updated_at = nowUnix();
    nk.storageWrite([
        {
            collection: ALLIANCE_META_COLLECTION,
            key: meta.alliance_id,
            userId: SYSTEM_USER,
            value: meta,
            permissionRead: 1,
            permissionWrite: 0,
        },
    ]);
}
function buildAllianceProfile(nk, logger, group) {
    var meta = safeJson(group.metadata || {});
    var stored = readAllianceMeta(nk, String(group.id));
    var members = nk.groupUsersList(String(group.id), 100);
    var list = members.groupUsers || [];
    var memberCount = 0;
    var leaderId = "";
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        var state = Number(gu.state);
        if (state === 0 || state === 1 || state === 2) {
            memberCount++;
            if (state === 0 && gu.user) {
                leaderId = String(gu.user.userId || gu.user.id || "");
            }
        }
    }
    if (!leaderId) {
        // Fall back to stored R5
        for (var i = 0; i < list.length; i++) {
            var gu = list[i];
            if (!gu.user)
                continue;
            var uid = String(gu.user.userId || gu.user.id || "");
            var rank = resolveCrownspireRank(nk, String(group.id), uid, Number(gu.state));
            if (rank === "R5") {
                leaderId = uid;
                break;
            }
        }
    }
    var joinType = stored.join_type || (group.open ? "open" : "apply");
    return {
        alliance_id: String(group.id),
        name: String(group.name || ""),
        tag: String(meta["alliance_tag"] || ""),
        description: stored.description || String(group.description || ""),
        language: stored.language || "en",
        join_type: joinType,
        open: joinType === "open" || !!group.open,
        min_join_power_placeholder: stored.min_join_power_placeholder || 0,
        min_citadel_level: typeof stored.min_citadel_level === "number" ? stored.min_citadel_level : 0,
        announcement: stored.announcement || "",
        member_count: memberCount,
        member_limit: Number(group.maxCount || DEFAULT_MEMBER_LIMIT),
        leader_user_id: leaderId,
        kingdom_id: String(meta["kingdom_id"] || DEV_KINGDOM_ID),
        created_at: group.createTime ? Math.floor(Date.parse(String(group.createTime)) / 1000) : 0,
        emblem_placeholder: stored.emblem_placeholder || "",
        banner_placeholder: stored.banner_placeholder || "",
        alliance_power_placeholder: stored.alliance_power_placeholder || 0,
        alliance_level_placeholder: stored.alliance_level_placeholder || 1,
        power_authority: "placeholder",
        level_authority: "placeholder",
    };
}
function assertAllianceTagUnique(nk, tag, excludeGroupId) {
    if (excludeGroupId === void 0) { excludeGroupId = ""; }
    var result = nk.groupsList(undefined, undefined, undefined, undefined, 100, undefined);
    var groups = result.groups || [];
    var needle = String(tag || "").toUpperCase();
    for (var i = 0; i < groups.length; i++) {
        var g = groups[i];
        if (excludeGroupId && String(g.id) === excludeGroupId)
            continue;
        var meta = safeJson(g.metadata || {});
        if (!meta["crownspire"] && !meta["alliance_tag"])
            continue;
        var existing = String(meta["alliance_tag"] || "").toUpperCase();
        if (existing === needle) {
            throw Err("Alliance tag already taken");
        }
    }
}
function notifyAllianceUser(nk, logger, userId, subject, content) {
    try {
        nk.notificationSend(userId, subject, content, ALLIANCE_NOTIF_CODE, null, true);
    }
    catch (e) {
        logger.warn("Alliance notification failed user=%s err=%s", userId, String(e));
    }
}
function notifyAllianceOfficers(nk, logger, groupId, subject, content, excludeUserId) {
    if (excludeUserId === void 0) { excludeUserId = ""; }
    try {
        var users = nk.groupUsersList(groupId, 100);
        var list = users.groupUsers || [];
        var ids = [];
        for (var i = 0; i < list.length; i++) {
            var gu = list[i];
            var state = Number(gu.state);
            if (state !== 0 && state !== 1 && state !== 2)
                continue;
            if (!gu.user)
                continue;
            var uid = String(gu.user.userId || gu.user.id || "");
            if (!uid || uid === excludeUserId)
                continue;
            var rank = resolveCrownspireRank(nk, groupId, uid, state);
            if (rank === "R5" || rank === "R4") {
                ids.push(uid);
            }
        }
        if (ids.length === 0)
            return;
        nk.notificationsSend(ids.map(function (uid) {
            return {
                code: ALLIANCE_NOTIF_CODE,
                content: content,
                persistent: true,
                subject: subject,
                userId: uid,
            };
        }));
    }
    catch (e) {
        logger.warn("Alliance officer notify failed group=%s err=%s", groupId, String(e));
    }
}
function sendAllianceSystemMessage(nk, logger, groupId, text, eventType) {
    try {
        // ChanType.Group == 2
        var channelId = nk.channelIdBuild("", groupId, 2);
        nk.channelMessageSend(channelId, {
            message_type: "SYSTEM",
            text: text,
            sender_display_name: "System",
            sender_alliance_tag: "",
            payload: { event: eventType },
            metadata: { crownspire_system: true, event: eventType },
        }, undefined, undefined, true);
    }
    catch (e) {
        logger.warn("Alliance system message failed group=%s err=%s", groupId, String(e));
    }
}
function rpcGetAllianceProfile(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var allianceId = String(data["alliance_id"] || "").trim();
    if (!allianceId) {
        var profile = ensureProfile(nk, logger, ctx.userId);
        allianceId = profile.alliance_id;
    }
    if (!allianceId)
        throw Err("alliance_id required");
    var groups = nk.groupsGetId([allianceId]);
    if (!groups || groups.length === 0)
        throw Err("Alliance not found");
    return JSON.stringify({ ok: true, alliance: buildAllianceProfile(nk, logger, groups[0]) });
}
function rpcListMembers(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "view_members");
    var users = nk.groupUsersList(profile.alliance_id, 100);
    var list = users.groupUsers || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        var state = Number(gu.state);
        if (state !== 0 && state !== 1 && state !== 2)
            continue;
        if (!gu.user)
            continue;
        var uid = String(gu.user.userId || gu.user.id || "");
        var memberProfile = ensureProfile(nk, logger, uid);
        var rank = resolveCrownspireRank(nk, profile.alliance_id, uid, state);
        var pub = publicProfile(memberProfile);
        out.push({
            user_id: uid,
            display_name: pub.display_name || gu.user.displayName || gu.user.username || "Unknown",
            rank: rank,
            rank_display: ROLE_DISPLAY[rank] || rank,
            nakama_state: state,
            joined_at: gu.user.createTime ? Math.floor(Date.parse(String(gu.user.createTime)) / 1000) : 0,
            online_status: pub.online_status,
            last_online: pub.last_online,
            power: pub.power,
            citadel_level: pub.citadel_level,
            vip_level: pub.vip_level,
            avatar_id: pub.avatar_id,
            kingdom_id: memberProfile.kingdom_id || DEV_KINGDOM_ID,
            contribution_placeholder: 0,
        });
    }
    out.sort(function (a, b) {
        return rankValue(b.rank) - rankValue(a.rank);
    });
    return JSON.stringify({ ok: true, members: out, alliance_id: profile.alliance_id });
}
function rpcListAlliances(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var query = String(data["query"] || "").trim().toLowerCase();
    // groupsList(name?, langTag?, open?, members?, limit?, cursor?)
    var result = nk.groupsList(undefined, undefined, undefined, undefined, 50, undefined);
    var groups = result.groups || [];
    var out = [];
    for (var i = 0; i < groups.length; i++) {
        var g = groups[i];
        var meta = safeJson(g.metadata || {});
        if (!meta["crownspire"] && !meta["alliance_tag"])
            continue;
        var stored = readAllianceMeta(nk, String(g.id));
        var name = String(g.name || "");
        var tag = String(meta["alliance_tag"] || "");
        if (query !== "") {
            var hay = (name + " " + tag).toLowerCase();
            if (hay.indexOf(query) < 0)
                continue;
        }
        var joinType = stored.join_type || (g.open ? "open" : "apply");
        var desc = stored.description || String(g.description || "");
        out.push({
            alliance_id: String(g.id),
            name: name,
            tag: tag,
            description: desc,
            description_preview: desc.length > 80 ? desc.substring(0, 77) + "..." : desc,
            language: stored.language || "en",
            member_count: Number(g.edgeCount || 0),
            member_limit: Number(g.maxCount || DEFAULT_MEMBER_LIMIT),
            join_type: joinType,
            open: joinType === "open",
            min_citadel_level: typeof stored.min_citadel_level === "number" ? stored.min_citadel_level : 0,
            alliance_power_placeholder: stored.alliance_power_placeholder || 0,
            kingdom_id: String(meta["kingdom_id"] || DEV_KINGDOM_ID),
        });
    }
    return JSON.stringify({ ok: true, alliances: out });
}
function rpcUpdateAllianceProfile(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "edit_profile");
    var data = parsePayload(payload);
    var meta = readAllianceMeta(nk, profile.alliance_id);
    var nameUpdate = null;
    if (data["name"] !== undefined) {
        nameUpdate = sanitizeAllianceName(String(data["name"] || ""));
    }
    if (data["description"] !== undefined) {
        meta.description = String(data["description"] || "").substring(0, 280).replace(/[\u0000-\u001F\u007F]/g, "");
    }
    if (data["language"] !== undefined) {
        meta.language = String(data["language"] || "en").substring(0, 8);
    }
    if (data["announcement"] !== undefined) {
        meta.announcement = String(data["announcement"] || "").substring(0, 280).replace(/[\u0000-\u001F\u007F]/g, "");
    }
    if (data["min_citadel_level"] !== undefined) {
        var lvl = Math.floor(Number(data["min_citadel_level"]));
        if (isNaN(lvl) || lvl < 0 || lvl > 100)
            throw Err("Invalid min_citadel_level");
        meta.min_citadel_level = lvl;
    }
    var openFlag = null;
    if (data["join_type"] !== undefined) {
        var jt = String(data["join_type"] || "apply");
        if (jt !== "open" && jt !== "apply" && jt !== "invite_only")
            throw Err("Invalid join_type");
        meta.join_type = jt;
        openFlag = jt === "open";
    }
    writeAllianceMeta(nk, meta);
    try {
        nk.groupUpdate(profile.alliance_id, ctx.userId, nameUpdate, null, meta.language || null, meta.description || null, null, openFlag, null, null);
    }
    catch (e) {
        logger.warn("groupUpdate failed: %s", String(e));
        throw Err("Could not update alliance settings");
    }
    if (nameUpdate) {
        // Keep member profile alliance_name in sync for the editor at least.
        profile.alliance_name = nameUpdate;
        profile.updated_at = nowUnix();
        writeProfile(nk, profile);
    }
    var groups = nk.groupsGetId([profile.alliance_id]);
    return JSON.stringify({
        ok: true,
        alliance: groups && groups.length ? buildAllianceProfile(nk, logger, groups[0]) : meta,
        profile: publicProfile(profile),
    });
}
function rpcRejectJoin(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "reject");
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId)
        throw Err("user_id required");
    nk.groupUsersKick(profile.alliance_id, [targetId]); // removes join request
    notifyAllianceUser(nk, logger, targetId, "Alliance Application", {
        event: "application_rejected",
        alliance_id: profile.alliance_id,
        alliance_name: profile.alliance_name || "",
        alliance_tag: profile.alliance_tag || "",
    });
    sendAllianceSystemMessage(nk, logger, profile.alliance_id, "An application was declined.", "application_rejected");
    logger.info("Alliance join rejected group=%s user=%s by %s", profile.alliance_id, targetId, ctx.userId);
    return JSON.stringify({ ok: true });
}
function rpcSetMemberRank(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    var newRank = String(data["rank"] || "").trim().toUpperCase();
    if (!targetId)
        throw Err("user_id required");
    if (!RANK_ORDER[newRank])
        throw Err("Invalid rank");
    if (targetId === ctx.userId)
        throw Err("Cannot change your own rank");
    if (newRank === "R5")
        throw Err("Use transfer_leadership to assign R5");
    var targetState = getNakamaGroupState(nk, profile.alliance_id, targetId);
    if (targetState < 0 || targetState > 2)
        throw Err("Target is not an active member");
    var targetRank = resolveCrownspireRank(nk, profile.alliance_id, targetId, targetState);
    var isPromote = rankValue(newRank) > rankValue(targetRank);
    var actorRank = requirePerm(nk, logger, profile.alliance_id, ctx.userId, isPromote ? "promote" : "demote");
    if (rankValue(targetRank) >= rankValue(actorRank)) {
        throw Err("Cannot change rank of equal or higher member");
    }
    if (rankValue(newRank) >= rankValue(actorRank)) {
        throw Err("Cannot assign rank at or above your own");
    }
    // R4 may only manage up to R3
    if (actorRank === "R4" && rankValue(newRank) > rankValue("R3")) {
        throw Err("Officers may only assign up to R3");
    }
    if (targetRank === "R5")
        throw Err("Cannot demote R5; transfer leadership first");
    writeRank(nk, profile.alliance_id, targetId, newRank);
    // Keep Nakama admin bit roughly aligned: R4 -> admin, else member (never touch superadmin here).
    try {
        if (targetState !== 0) {
            if (newRank === "R4") {
                nk.groupUsersPromote(profile.alliance_id, [targetId]);
            }
            else if (targetState === 1 && rankValue(newRank) < rankValue("R4")) {
                nk.groupUsersDemote(profile.alliance_id, [targetId]);
            }
        }
    }
    catch (e) {
        logger.warn("Nakama promote/demote sync failed: %s", String(e));
    }
    var targetProfile = ensureProfile(nk, logger, targetId);
    syncAllianceFields(nk, logger, targetProfile);
    var event = isPromote ? "promoted" : "demoted";
    sendAllianceSystemMessage(nk, logger, profile.alliance_id, targetProfile.display_name + " was " + event + " to " + newRank + ".", event);
    logger.info("Rank set group=%s target=%s %s->%s by %s", profile.alliance_id, targetId, targetRank, newRank, ctx.userId);
    return JSON.stringify({ ok: true, user_id: targetId, rank: newRank, event: event });
}
function rpcTransferLeadership(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "transfer_leadership");
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId)
        throw Err("user_id required");
    if (targetId === ctx.userId)
        throw Err("Already leader");
    var targetState = getNakamaGroupState(nk, profile.alliance_id, targetId);
    if (targetState < 0 || targetState > 2)
        throw Err("Target is not an active member");
    writeRank(nk, profile.alliance_id, targetId, "R5");
    writeRank(nk, profile.alliance_id, ctx.userId, "R4");
    // Promote target to superadmin if API supports; demote old leader to admin.
    try {
        nk.groupUsersPromote(profile.alliance_id, [targetId]);
    }
    catch (e) {
        logger.warn("transfer promote target failed: %s", String(e));
    }
    var oldProfile = ensureProfile(nk, logger, ctx.userId);
    oldProfile.crownspire_rank = "R4";
    oldProfile.updated_at = nowUnix();
    writeProfile(nk, oldProfile);
    var newLeader = ensureProfile(nk, logger, targetId);
    syncAllianceFields(nk, logger, newLeader);
    syncAllianceFields(nk, logger, oldProfile);
    sendAllianceSystemMessage(nk, logger, profile.alliance_id, "Leadership transferred to " + (newLeader.display_name || targetId) + ".", "leadership_transferred");
    logger.info("Leadership transferred group=%s from=%s to=%s", profile.alliance_id, ctx.userId, targetId);
    return JSON.stringify({
        ok: true,
        alliance_id: profile.alliance_id,
        new_leader_user_id: targetId,
        former_leader_rank: "R4",
    });
}
function writeInvite(nk, invite) {
    nk.storageWrite([
        {
            collection: INVITE_COLLECTION,
            key: invite.invite_id,
            userId: SYSTEM_USER,
            value: invite,
            permissionRead: 0,
            permissionWrite: 0,
        },
    ]);
}
function readInvite(nk, inviteId) {
    var objects = nk.storageRead([{ collection: INVITE_COLLECTION, key: inviteId, userId: SYSTEM_USER }]);
    if (!objects || objects.length === 0 || !objects[0].value)
        return null;
    return objects[0].value;
}
function rpcInvitePlayer(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, profile.alliance_id, ctx.userId, "invite");
    var data = parsePayload(payload);
    var targetId = String(data["user_id"] || "").trim();
    if (!targetId)
        throw Err("user_id required");
    if (targetId === ctx.userId)
        throw Err("Cannot invite yourself");
    var targetProfile = ensureProfile(nk, logger, targetId);
    if (targetProfile.alliance_id)
        throw Err("Target already in an alliance");
    // Duplicate pending invite prevention (scan recent invites for target+alliance).
    // Lightweight: create new invite_id; client/list filters pending.
    var inviteId = nk.uuidv4();
    var now = nowUnix();
    var invite = {
        invite_id: inviteId,
        alliance_id: profile.alliance_id,
        alliance_name: profile.alliance_name,
        alliance_tag: profile.alliance_tag,
        inviter_user_id: ctx.userId,
        target_user_id: targetId,
        created_at: now,
        expires_at: now + INVITE_EXPIRY_SEC,
        status: "pending",
    };
    writeInvite(nk, invite);
    // Also index under target user for inbox list.
    nk.storageWrite([
        {
            collection: INVITE_COLLECTION,
            key: "inbox:" + targetId + ":" + inviteId,
            userId: SYSTEM_USER,
            value: { invite_id: inviteId, target_user_id: targetId },
            permissionRead: 0,
            permissionWrite: 0,
        },
    ]);
    logger.info("Invite created id=%s alliance=%s target=%s by %s", inviteId, profile.alliance_id, targetId, ctx.userId);
    return JSON.stringify({ ok: true, invite: invite });
}
function rpcListMyInvites(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var listed = nk.storageList(SYSTEM_USER, INVITE_COLLECTION, 100, undefined);
    var objects = listed.objects || [];
    var out = [];
    var now = nowUnix();
    for (var i = 0; i < objects.length; i++) {
        var obj = objects[i];
        if (!obj.value || !String(obj.key || "").startsWith("inbox:" + ctx.userId + ":"))
            continue;
        var inviteId = String(obj.value.invite_id || "");
        var invite = readInvite(nk, inviteId);
        if (!invite)
            continue;
        if (invite.status === "pending" && invite.expires_at < now) {
            invite.status = "expired";
            writeInvite(nk, invite);
        }
        if (invite.status === "pending") {
            out.push(invite);
        }
    }
    return JSON.stringify({ ok: true, invites: out });
}
function rpcAcceptInvite(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (profile.alliance_id)
        throw Err("Already in an alliance");
    var data = parsePayload(payload);
    var inviteId = String(data["invite_id"] || "").trim();
    if (!inviteId)
        throw Err("invite_id required");
    var invite = readInvite(nk, inviteId);
    if (!invite)
        throw Err("Invite not found");
    if (invite.target_user_id !== ctx.userId)
        throw Err("Invite not for this user");
    if (invite.status !== "pending")
        throw Err("Invite is not pending");
    if (invite.expires_at < nowUnix()) {
        invite.status = "expired";
        writeInvite(nk, invite);
        throw Err("Invite expired");
    }
    nk.groupUsersAdd(invite.alliance_id, [ctx.userId]);
    writeRank(nk, invite.alliance_id, ctx.userId, "R2");
    invite.status = "accepted";
    writeInvite(nk, invite);
    syncAllianceFields(nk, logger, profile);
    sendAllianceSystemMessage(nk, logger, invite.alliance_id, profile.display_name + " joined the Alliance.", "joined");
    return JSON.stringify({ ok: true, profile: publicProfile(profile), alliance_id: invite.alliance_id });
}
function rpcRejectInvite(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var inviteId = String(data["invite_id"] || "").trim();
    if (!inviteId)
        throw Err("invite_id required");
    var invite = readInvite(nk, inviteId);
    if (!invite)
        throw Err("Invite not found");
    if (invite.target_user_id !== ctx.userId)
        throw Err("Invite not for this user");
    if (invite.status !== "pending")
        throw Err("Invite is not pending");
    invite.status = "rejected";
    writeInvite(nk, invite);
    return JSON.stringify({ ok: true });
}
function rpcGetMyPermissions(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        return JSON.stringify({ ok: true, rank: "", permissions: {} });
    }
    var rank = resolveCrownspireRank(nk, profile.alliance_id, ctx.userId, getNakamaGroupState(nk, profile.alliance_id, ctx.userId));
    return JSON.stringify({
        ok: true,
        rank: rank,
        rank_display: ROLE_DISPLAY[rank] || rank,
        permissions: RANK_PERMISSIONS[rank] || {},
    });
}
/** Phase-4 enhanced leave: R5 cannot leave while other members remain. */
function leaveAlliancePhase4(ctx, logger, nk, profile) {
    var userId = String(ctx.userId || "");
    if (!userId)
        throw Err("Unauthenticated");
    var groupId = String(profile.alliance_id || "");
    if (!groupId)
        throw Err("Not in an alliance");
    var myRank = resolveCrownspireRank(nk, groupId, userId, getNakamaGroupState(nk, groupId, userId));
    var users = nk.groupUsersList(groupId, 100);
    var list = users.groupUsers || [];
    var otherMembers = 0;
    for (var i = 0; i < list.length; i++) {
        var gu = list[i];
        var state = Number(gu.state);
        if (state !== 0 && state !== 1 && state !== 2)
            continue;
        if (!gu.user)
            continue;
        var uid = String(gu.user.userId || gu.user.id || "");
        if (uid !== userId)
            otherMembers++;
    }
    if (myRank === "R5" && otherMembers > 0) {
        throw Err("R5 must transfer leadership before leaving while members remain");
    }
    nk.groupUserLeave(groupId, userId, ctx.username || "");
    profile.alliance_id = "";
    profile.alliance_tag = "";
    profile.alliance_name = "";
    profile.crownspire_rank = "";
    profile.updated_at = nowUnix();
    writeProfile(nk, profile);
    if (otherMembers === 0) {
        try {
            nk.groupDelete(groupId);
        }
        catch (e) {
            logger.warn("groupDelete after last leave failed: %s", String(e));
        }
    }
    else {
        sendAllianceSystemMessage(nk, logger, groupId, (profile.display_name || "A member") + " left the Alliance.", "left");
    }
    logger.info("Alliance leave group=%s user=%s", groupId, userId);
    return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}
/** Phase-4 enhanced kick with rank policy. */
function kickMemberPhase4(ctx, logger, nk, profile, targetId) {
    var userId = String(ctx.userId || "");
    if (!userId)
        throw Err("Unauthenticated");
    var groupId = String(profile.alliance_id || "");
    if (!groupId)
        throw Err("Not in an alliance");
    if (targetId === userId)
        throw Err("Cannot kick yourself");
    var actorRank = requirePerm(nk, logger, groupId, userId, "kick");
    var targetState = getNakamaGroupState(nk, groupId, targetId);
    if (targetState < 0 || targetState > 2)
        throw Err("Target is not an active member");
    var targetRank = resolveCrownspireRank(nk, groupId, targetId, targetState);
    if (targetRank === "R5")
        throw Err("Cannot kick R5");
    if (rankValue(targetRank) >= rankValue(actorRank)) {
        throw Err("Cannot kick equal or higher rank");
    }
    // R4 may kick R1–R3 only
    if (actorRank === "R4" && rankValue(targetRank) > rankValue("R3")) {
        throw Err("Cannot kick this rank");
    }
    nk.groupUsersKick(groupId, [targetId]);
    var targetProfile = ensureProfile(nk, logger, targetId);
    var name = targetProfile.display_name;
    targetProfile.alliance_id = "";
    targetProfile.alliance_tag = "";
    targetProfile.alliance_name = "";
    targetProfile.crownspire_rank = "";
    targetProfile.updated_at = nowUnix();
    writeProfile(nk, targetProfile);
    sendAllianceSystemMessage(nk, logger, groupId, (name || "A member") + " was removed from the Alliance.", "kicked");
    logger.info("Alliance kick group=%s user=%s by %s", groupId, targetId, userId);
    return JSON.stringify({ ok: true });
}
/** Approve join as R1 Recruit + system message. */
function approveJoinPhase4(ctx, logger, nk, profile, targetId) {
    var userId = String(ctx.userId || "");
    if (!userId)
        throw Err("Unauthenticated");
    var groupId = String(profile.alliance_id || "");
    if (!groupId)
        throw Err("Not in an alliance");
    requirePerm(nk, logger, groupId, userId, "approve");
    nk.groupUsersAdd(groupId, [targetId]);
    writeRank(nk, groupId, targetId, "R1");
    var targetProfile = ensureProfile(nk, logger, targetId);
    syncAllianceFields(nk, logger, targetProfile);
    sendAllianceSystemMessage(nk, logger, groupId, (targetProfile.display_name || "A player") + " joined the Alliance.", "joined");
    notifyAllianceUser(nk, logger, targetId, "Alliance Application", {
        event: "application_approved",
        alliance_id: groupId,
        alliance_name: profile.alliance_name || "",
        alliance_tag: profile.alliance_tag || "",
    });
    logger.info("Alliance join approved group=%s user=%s by %s", groupId, targetId, userId);
    return JSON.stringify({ ok: true, alliance_id: groupId, user_id: targetId, rank: "R1" });
}
/**
 * Crownspire Phase 5 — Alliance Help + Online Auto-Help foundation
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Concatenated into build/index.js via tsconfig files order.
 *
 * TODO (Production):
 * Replace beta_alliance_auto_help with the production alliance_auto_help
 * entitlement verified through Google Play Billing.
 * Production subscription: Ultra Value Monthly Card
 * Benefit: Alliance Auto-Help
 *
 * Help + Auto-Help systems must only ask EntitlementProvider whether an
 * entitlement is active. They must not know the billing source.
 */
var HELP_COLLECTION = "crownspire_help_requests";
var ENTITLEMENT_COLLECTION = "crownspire_entitlements";
var HELP_SCHEMA_VERSION = 1;
/** Conceptual production entitlement id (not granted in beta). */
var ENTITLEMENT_ALLIANCE_AUTO_HELP = "alliance_auto_help";
/** Development/closed-beta entitlement id. */
var ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP = "beta_alliance_auto_help";
/**
 * LOCAL DEVELOPMENT ONLY secret for grant/revoke tooling.
 * Normal game clients must never ship this value.
 */
var CROWNSPIR_DEV_ENTITLEMENT_SECRET = "crownspire-local-dev-entitlement-secret";
var HELP_STATUS_ACTIVE = "ACTIVE";
var HELP_STATUS_COMPLETED = "COMPLETED";
var HELP_STATUS_EXPIRED = "EXPIRED";
var HELP_STATUS_CANCELLED = "CANCELLED";
var HELP_TYPE_CONSTRUCTION = "CONSTRUCTION";
var HELP_TYPE_RESEARCH = "RESEARCH";
var HELP_TYPE_HEALING = "HEALING";
/** BETA configuration — not final balance values. */
var BETA_HELP_CONFIG = {
    label: "BETA_HELP_CONFIG",
    help_limit: 5,
    reduction_seconds_per_help: 60,
    max_reduction_seconds: 300,
    request_expiry_seconds: 24 * 3600,
    /** Optional percentage of remaining time per help (0 = unused). */
    reduction_percent_of_remaining: 0,
    create_cooldown_seconds: 1,
    help_cooldown_seconds: 1,
};
var HELP_NOTIF_CODE = 5001;
var StorageEntitlementProvider = {
    isActive: function (nk, userId, entitlementId) {
        var rec = this.getRecord(nk, userId, entitlementId);
        if (!rec || rec.status !== "active") {
            return false;
        }
        var now = nowUnix();
        if (rec.starts_at > 0 && now < rec.starts_at) {
            return false;
        }
        if (rec.expires_at > 0 && now >= rec.expires_at) {
            return false;
        }
        return true;
    },
    getRecord: function (nk, userId, entitlementId) {
        var objects = nk.storageRead([
            { collection: ENTITLEMENT_COLLECTION, key: entitlementId, userId: userId },
        ]);
        if (!objects || objects.length === 0 || !objects[0].value) {
            return null;
        }
        return objects[0].value;
    },
};
/**
 * Resolve whether Auto-Help is active for a user.
 * Beta maps conceptual alliance_auto_help → beta_alliance_auto_help.
 * Production will resolve alliance_auto_help via Google Play provider only.
 */
function isAllianceAutoHelpActive(nk, userId) {
    // TODO (Production): Replace beta_alliance_auto_help with production
    // alliance_auto_help entitlement verified through Google Play Billing.
    // Production subscription: Ultra Value Monthly Card
    // Benefit: Alliance Auto-Help
    if (StorageEntitlementProvider.isActive(nk, userId, ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP)) {
        return true;
    }
    // Future production path (provider swap only):
    // return ProductionBillingEntitlementProvider.isActive(nk, userId, ENTITLEMENT_ALLIANCE_AUTO_HELP);
    return false;
}
function getAutoHelpEntitlementPublic(nk, userId) {
    var beta = StorageEntitlementProvider.getRecord(nk, userId, ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP);
    var active = isAllianceAutoHelpActive(nk, userId);
    return {
        conceptual_id: ENTITLEMENT_ALLIANCE_AUTO_HELP,
        active_entitlement_id: active ? ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP : "",
        active: active,
        ui_label: active ? "Beta Testing Enabled" : "Inactive",
        ui_title: "Alliance Auto-Help",
        source: beta ? beta.source : "",
        starts_at: beta ? beta.starts_at : 0,
        expires_at: beta ? beta.expires_at : 0,
        status: beta ? beta.status : "none",
        // Never claim production Ultra Value Monthly Card here.
        production_ready: false,
    };
}
function registerPhase5HelpRpcs(_initializer, logger) {
    logger.info("Crownspire Phase 5 help handlers available (registered in InitModule).");
}
function isValidHelpType(t) {
    return t === HELP_TYPE_CONSTRUCTION || t === HELP_TYPE_RESEARCH || t === HELP_TYPE_HEALING;
}
function readHelpRequest(nk, requestId) {
    var objects = nk.storageRead([
        { collection: HELP_COLLECTION, key: requestId, userId: SYSTEM_USER },
    ]);
    if (!objects || objects.length === 0 || !objects[0].value) {
        return null;
    }
    return objects[0].value;
}
function writeHelpRequest(nk, req) {
    nk.storageWrite([
        {
            collection: HELP_COLLECTION,
            key: req.request_id,
            userId: SYSTEM_USER,
            value: req,
            permissionRead: 1,
            permissionWrite: 0,
        },
    ]);
}
function listAllianceHelpRequests(nk, allianceId) {
    var listed = nk.storageList(SYSTEM_USER, HELP_COLLECTION, 100, "");
    var objects = listed.objects || [];
    var out = [];
    for (var i = 0; i < objects.length; i++) {
        var v = objects[i].value;
        if (!v || v.alliance_id !== allianceId) {
            continue;
        }
        out.push(v);
    }
    return out;
}
function refreshHelpStatus(req, now) {
    if (req.status === HELP_STATUS_ACTIVE) {
        if (now >= req.expires_at) {
            req.status = HELP_STATUS_EXPIRED;
            req.updated_at = now;
        }
        else if (now >= req.current_finish_time) {
            req.status = HELP_STATUS_COMPLETED;
            req.updated_at = now;
        }
    }
    return req;
}
function publicHelpRequest(req) {
    return {
        request_id: req.request_id,
        alliance_id: req.alliance_id,
        owner_user_id: req.owner_user_id,
        owner_display_name: req.owner_display_name,
        project_type: req.project_type,
        project_id: req.project_id,
        project_display_name: req.project_display_name,
        created_at: req.created_at,
        expires_at: req.expires_at,
        original_finish_time: req.original_finish_time,
        current_finish_time: req.current_finish_time,
        help_count: req.help_count,
        help_limit: req.help_limit,
        helper_user_ids: req.helper_user_ids.slice(),
        status: req.status,
        schema_version: req.schema_version,
        last_reduction_seconds: req.last_reduction_seconds,
        updated_at: req.updated_at,
        remaining_seconds: Math.max(0, req.current_finish_time - nowUnix()),
    };
}
function notifyAllianceHelpEvent(nk, logger, allianceId, eventType, request, actorUserId) {
    try {
        var users = nk.groupUsersList(allianceId, 100);
        var list = users.groupUsers || [];
        var content = {
            event: eventType,
            request_id: request.request_id,
            project_type: request.project_type,
            project_id: request.project_id,
            project_display_name: request.project_display_name,
            owner_user_id: request.owner_user_id,
            help_count: request.help_count,
            help_limit: request.help_limit,
            status: request.status,
            current_finish_time: request.current_finish_time,
            last_reduction_seconds: request.last_reduction_seconds,
            actor_user_id: actorUserId,
        };
        for (var i = 0; i < list.length; i++) {
            var gu = list[i];
            if (!gu.user || Number(gu.state) > 2) {
                continue;
            }
            var uid = String(gu.user.userId || gu.user.id || "");
            if (!uid)
                continue;
            nk.notificationSend(uid, "Alliance Help", content, HELP_NOTIF_CODE, null, true);
        }
    }
    catch (e) {
        logger.warn("Help notification failed: %s", String(e));
    }
}
function computeHelpReduction(req, now) {
    var remaining = Math.max(0, req.current_finish_time - now);
    if (remaining <= 0) {
        return 0;
    }
    var reduction = BETA_HELP_CONFIG.reduction_seconds_per_help;
    if (BETA_HELP_CONFIG.reduction_percent_of_remaining > 0) {
        var pct = Math.floor((remaining * BETA_HELP_CONFIG.reduction_percent_of_remaining) / 100);
        if (pct > reduction) {
            reduction = pct;
        }
    }
    var alreadyReduced = Math.max(0, req.original_finish_time - req.current_finish_time);
    var maxLeft = Math.max(0, BETA_HELP_CONFIG.max_reduction_seconds - alreadyReduced);
    reduction = Math.min(reduction, maxLeft, remaining);
    // Never force below immediate completion (remaining can become 0).
    return Math.max(0, reduction);
}
function findActiveOwnerProjectRequest(nk, allianceId, ownerUserId, projectType, projectId) {
    var all = listAllianceHelpRequests(nk, allianceId);
    var now = nowUnix();
    for (var i = 0; i < all.length; i++) {
        var req = refreshHelpStatus(all[i], now);
        if (req.status !== HELP_STATUS_ACTIVE) {
            if (all[i].status !== req.status) {
                writeHelpRequest(nk, req);
            }
            continue;
        }
        if (req.owner_user_id === ownerUserId &&
            req.project_type === projectType &&
            req.project_id === projectId) {
            return req;
        }
    }
    return null;
}
function applyHelpToRequest(nk, logger, req, helperUserId) {
    var now = nowUnix();
    req = refreshHelpStatus(req, now);
    if (req.status !== HELP_STATUS_ACTIVE) {
        writeHelpRequest(nk, req);
        return { ok: false, error: "Request is not active (" + req.status + ")" };
    }
    if (req.owner_user_id === helperUserId) {
        return { ok: false, error: "Cannot help your own request" };
    }
    if (req.helper_user_ids.indexOf(helperUserId) >= 0) {
        return { ok: false, error: "Already helped this request" };
    }
    if (req.help_count >= req.help_limit) {
        req.status = HELP_STATUS_COMPLETED;
        req.updated_at = now;
        writeHelpRequest(nk, req);
        return { ok: false, error: "Help limit reached" };
    }
    var reduction = computeHelpReduction(req, now);
    if (reduction <= 0) {
        req.status = HELP_STATUS_COMPLETED;
        req.updated_at = now;
        writeHelpRequest(nk, req);
        return { ok: false, error: "No reducible time remaining" };
    }
    req.current_finish_time = Math.max(now, req.current_finish_time - reduction);
    req.help_count += 1;
    req.helper_user_ids.push(helperUserId);
    req.last_reduction_seconds = reduction;
    req.updated_at = now;
    if (req.help_count >= req.help_limit || req.current_finish_time <= now) {
        req.status = HELP_STATUS_COMPLETED;
    }
    writeHelpRequest(nk, req);
    notifyAllianceHelpEvent(nk, logger, req.alliance_id, "help_contributed", req, helperUserId);
    if (req.status === HELP_STATUS_COMPLETED) {
        notifyAllianceHelpEvent(nk, logger, req.alliance_id, "help_completed", req, helperUserId);
    }
    return { ok: true, request: req, seconds_reduced: reduction };
}
// ---------------------------------------------------------------------------
// Phase 5 RPCs
// ---------------------------------------------------------------------------
function rpcCreateHelpRequest(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    var data = parsePayload(payload);
    var projectType = String(data["project_type"] || "").trim().toUpperCase();
    var projectId = String(data["project_id"] || "").trim();
    var projectDisplayName = String(data["project_display_name"] || projectId).trim().substring(0, 64);
    var originalFinish = Math.floor(Number(data["original_finish_time"] || 0));
    if (!isValidHelpType(projectType)) {
        throw Err("Invalid project_type");
    }
    if (!projectId) {
        throw Err("project_id required");
    }
    if (!originalFinish || originalFinish <= nowUnix()) {
        throw Err("Project must have remaining time");
    }
    // Healing batch IDs must be unique — never reuse a completed/cancelled healing request id.
    if (projectType === HELP_TYPE_HEALING) {
        var existingSame = findActiveOwnerProjectRequest(nk, profile.alliance_id, ctx.userId, projectType, projectId);
        if (existingSame) {
            return JSON.stringify({ ok: true, request: publicHelpRequest(existingSame), deduped: true });
        }
        // Also reject recreating for a project_id that already completed (batch ID reuse).
        var all = listAllianceHelpRequests(nk, profile.alliance_id);
        for (var i = 0; i < all.length; i++) {
            var r = all[i];
            if (r.owner_user_id === ctx.userId &&
                r.project_type === HELP_TYPE_HEALING &&
                r.project_id === projectId &&
                r.status !== HELP_STATUS_ACTIVE) {
                throw Err("Healing batch request already closed; start a new batch for a new request");
            }
        }
    }
    else {
        var existing = findActiveOwnerProjectRequest(nk, profile.alliance_id, ctx.userId, projectType, projectId);
        if (existing) {
            return JSON.stringify({ ok: true, request: publicHelpRequest(existing), deduped: true });
        }
    }
    // Rate-limit only new request creation (after dedupe short-circuit).
    assertRateLimit(nk, ctx.userId, "create_help_request", BETA_HELP_CONFIG.create_cooldown_seconds);
    var now = nowUnix();
    var req = {
        request_id: nk.uuidv4(),
        alliance_id: profile.alliance_id,
        owner_user_id: ctx.userId,
        owner_display_name: profile.display_name || defaultDevName(ctx.userId),
        project_type: projectType,
        project_id: projectId,
        project_display_name: projectDisplayName || projectId,
        created_at: now,
        expires_at: now + BETA_HELP_CONFIG.request_expiry_seconds,
        original_finish_time: originalFinish,
        current_finish_time: originalFinish,
        help_count: 0,
        help_limit: BETA_HELP_CONFIG.help_limit,
        helper_user_ids: [],
        status: HELP_STATUS_ACTIVE,
        schema_version: HELP_SCHEMA_VERSION,
        last_reduction_seconds: 0,
        updated_at: now,
    };
    writeHelpRequest(nk, req);
    notifyAllianceHelpEvent(nk, logger, profile.alliance_id, "help_request_created", req, ctx.userId);
    logger.info("Help request created id=%s type=%s project=%s owner=%s", req.request_id, projectType, projectId, ctx.userId);
    return JSON.stringify({
        ok: true,
        request: publicHelpRequest(req),
        beta_config: {
            label: BETA_HELP_CONFIG.label,
            help_limit: BETA_HELP_CONFIG.help_limit,
            reduction_seconds_per_help: BETA_HELP_CONFIG.reduction_seconds_per_help,
            max_reduction_seconds: BETA_HELP_CONFIG.max_reduction_seconds,
            request_expiry_seconds: BETA_HELP_CONFIG.request_expiry_seconds,
        },
    });
}
function rpcHelpOne(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    assertRateLimit(nk, ctx.userId, "help_one", BETA_HELP_CONFIG.help_cooldown_seconds);
    var data = parsePayload(payload);
    var requestId = String(data["request_id"] || "").trim();
    if (!requestId) {
        throw Err("request_id required");
    }
    // Ignore any client-supplied reduction / alliance_id.
    var req = readHelpRequest(nk, requestId);
    if (!req) {
        throw Err("Help request not found");
    }
    if (req.alliance_id !== profile.alliance_id) {
        throw Err("Help request not in your alliance");
    }
    var result = applyHelpToRequest(nk, logger, req, ctx.userId);
    if (!result.ok || !result.request) {
        return JSON.stringify({ ok: false, error: result.error || "Help failed" });
    }
    return JSON.stringify({
        ok: true,
        request: publicHelpRequest(result.request),
        seconds_reduced: result.seconds_reduced || 0,
        auto_help: false,
    });
}
function rpcHelpAll(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        throw Err("Not in an alliance");
    }
    assertRateLimit(nk, ctx.userId, "help_all", BETA_HELP_CONFIG.help_cooldown_seconds);
    var data = parsePayload(payload);
    var asAutoHelp = !!data["as_auto_help"];
    if (asAutoHelp && !isAllianceAutoHelpActive(nk, ctx.userId)) {
        throw Err("Auto-Help entitlement inactive");
    }
    var all = listAllianceHelpRequests(nk, profile.alliance_id);
    var helped = [];
    var skipped = [];
    var totalReduced = 0;
    for (var i = 0; i < all.length; i++) {
        var req = all[i];
        if (req.owner_user_id === ctx.userId) {
            skipped.push({ request_id: req.request_id, error: "own request" });
            continue;
        }
        var result = applyHelpToRequest(nk, logger, req, ctx.userId);
        if (result.ok && result.request) {
            helped.push({
                request: publicHelpRequest(result.request),
                seconds_reduced: result.seconds_reduced || 0,
            });
            totalReduced += result.seconds_reduced || 0;
        }
        else {
            skipped.push({ request_id: req.request_id, error: result.error || "skipped" });
        }
    }
    return JSON.stringify({
        ok: true,
        helped: helped,
        skipped: skipped,
        helped_count: helped.length,
        total_seconds_reduced: totalReduced,
        auto_help: asAutoHelp,
        eligible_remaining: countEligibleHelp(nk, profile.alliance_id, ctx.userId),
    });
}
function countEligibleHelp(nk, allianceId, helperUserId) {
    var all = listAllianceHelpRequests(nk, allianceId);
    var now = nowUnix();
    var count = 0;
    for (var i = 0; i < all.length; i++) {
        var req = refreshHelpStatus(all[i], now);
        if (req.status !== HELP_STATUS_ACTIVE) {
            continue;
        }
        if (req.owner_user_id === helperUserId) {
            continue;
        }
        if (req.helper_user_ids.indexOf(helperUserId) >= 0) {
            continue;
        }
        if (req.help_count >= req.help_limit) {
            continue;
        }
        if (req.current_finish_time <= now) {
            continue;
        }
        count++;
    }
    return count;
}
function rpcListEligibleHelpRequests(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        return JSON.stringify({ ok: true, requests: [], eligible_count: 0, connected: true, in_alliance: false });
    }
    var all = listAllianceHelpRequests(nk, profile.alliance_id);
    var now = nowUnix();
    var out = [];
    for (var i = 0; i < all.length; i++) {
        var req = refreshHelpStatus(all[i], now);
        if (req.status !== all[i].status) {
            writeHelpRequest(nk, req);
        }
        if (req.status !== HELP_STATUS_ACTIVE)
            continue;
        if (req.owner_user_id === ctx.userId)
            continue;
        if (req.helper_user_ids.indexOf(ctx.userId) >= 0)
            continue;
        if (req.help_count >= req.help_limit)
            continue;
        if (req.current_finish_time <= now)
            continue;
        out.push(publicHelpRequest(req));
    }
    return JSON.stringify({
        ok: true,
        requests: out,
        eligible_count: out.length,
        connected: true,
        in_alliance: true,
        auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
        beta_config: {
            label: BETA_HELP_CONFIG.label,
            help_limit: BETA_HELP_CONFIG.help_limit,
            reduction_seconds_per_help: BETA_HELP_CONFIG.reduction_seconds_per_help,
            max_reduction_seconds: BETA_HELP_CONFIG.max_reduction_seconds,
        },
    });
}
function rpcListMyActiveHelpRequests(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        return JSON.stringify({
            ok: true,
            requests: [],
            in_alliance: false,
            auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
        });
    }
    var all = listAllianceHelpRequests(nk, profile.alliance_id);
    var now = nowUnix();
    var out = [];
    for (var i = 0; i < all.length; i++) {
        var req = refreshHelpStatus(all[i], now);
        if (req.status !== all[i].status) {
            writeHelpRequest(nk, req);
        }
        if (req.owner_user_id !== ctx.userId)
            continue;
        if (req.status !== HELP_STATUS_ACTIVE)
            continue;
        out.push(publicHelpRequest(req));
    }
    return JSON.stringify({
        ok: true,
        requests: out,
        in_alliance: true,
        auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
    });
}
function rpcCompleteOrCancelHelpRequest(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    var data = parsePayload(payload);
    var requestId = String(data["request_id"] || "").trim();
    var action = String(data["action"] || "complete").trim().toLowerCase();
    if (!requestId) {
        throw Err("request_id required");
    }
    var req = readHelpRequest(nk, requestId);
    if (!req) {
        throw Err("Help request not found");
    }
    if (req.owner_user_id !== ctx.userId) {
        throw Err("Only the owner can complete or cancel this request");
    }
    if (profile.alliance_id && req.alliance_id !== profile.alliance_id && action !== "cancel") {
        // Owner may cancel after leave; completing requires same alliance context normally.
    }
    var now = nowUnix();
    if (req.status !== HELP_STATUS_ACTIVE) {
        return JSON.stringify({ ok: true, request: publicHelpRequest(req), already_closed: true });
    }
    if (action === "cancel") {
        req.status = HELP_STATUS_CANCELLED;
    }
    else {
        req.status = HELP_STATUS_COMPLETED;
    }
    req.updated_at = now;
    writeHelpRequest(nk, req);
    notifyAllianceHelpEvent(nk, logger, req.alliance_id, action === "cancel" ? "help_cancelled" : "help_completed", req, ctx.userId);
    return JSON.stringify({ ok: true, request: publicHelpRequest(req) });
}
function rpcGetMyEntitlements(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var beta = StorageEntitlementProvider.getRecord(nk, ctx.userId, ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP);
    return JSON.stringify({
        ok: true,
        entitlements: beta ? [beta] : [],
        auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
    });
}
/**
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Requires matching CROWNSPIR_DEV_ENTITLEMENT_SECRET.
 * Normal clients must not ship this secret.
 */
function rpcDevSetEntitlement(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    var data = parsePayload(payload);
    if (String(data["dev_secret"] || "") !== CROWNSPIR_DEV_ENTITLEMENT_SECRET) {
        throw Err("Forbidden");
    }
    var targetUserId = String(data["user_id"] || ctx.userId).trim();
    if (!targetUserId) {
        throw Err("user_id required");
    }
    var entitlementId = String(data["entitlement_id"] || ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP).trim();
    if (entitlementId !== ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP) {
        // Production entitlements cannot be granted through this RPC.
        throw Err("Only beta_alliance_auto_help can be set via dev tooling");
    }
    var action = String(data["action"] || "grant").trim().toLowerCase();
    var now = nowUnix();
    var durationSec = Math.max(60, Math.floor(Number(data["duration_seconds"] || 30 * 24 * 3600)));
    if (action === "revoke") {
        var existing = StorageEntitlementProvider.getRecord(nk, targetUserId, entitlementId);
        var rec_1 = {
            entitlement_id: entitlementId,
            user_id: targetUserId,
            status: "revoked",
            starts_at: existing ? existing.starts_at : now,
            expires_at: now,
            source: "beta_test",
            updated_at: now,
        };
        nk.storageWrite([
            {
                collection: ENTITLEMENT_COLLECTION,
                key: entitlementId,
                userId: targetUserId,
                value: rec_1,
                permissionRead: 1,
                permissionWrite: 0,
            },
        ]);
        logger.info("Dev revoke entitlement user=%s id=%s", targetUserId, entitlementId);
        return JSON.stringify({ ok: true, entitlement: rec_1, auto_help: getAutoHelpEntitlementPublic(nk, targetUserId) });
    }
    if (action === "expire") {
        var existing = StorageEntitlementProvider.getRecord(nk, targetUserId, entitlementId);
        var rec_2 = {
            entitlement_id: entitlementId,
            user_id: targetUserId,
            status: "expired",
            starts_at: existing ? existing.starts_at : now - 10,
            expires_at: now - 1,
            source: "beta_test",
            updated_at: now,
        };
        nk.storageWrite([
            {
                collection: ENTITLEMENT_COLLECTION,
                key: entitlementId,
                userId: targetUserId,
                value: rec_2,
                permissionRead: 1,
                permissionWrite: 0,
            },
        ]);
        return JSON.stringify({ ok: true, entitlement: rec_2, auto_help: getAutoHelpEntitlementPublic(nk, targetUserId) });
    }
    // grant
    var rec = {
        entitlement_id: entitlementId,
        user_id: targetUserId,
        status: "active",
        starts_at: now,
        expires_at: now + durationSec,
        source: "beta_test",
        updated_at: now,
    };
    nk.storageWrite([
        {
            collection: ENTITLEMENT_COLLECTION,
            key: entitlementId,
            userId: targetUserId,
            value: rec,
            permissionRead: 1,
            permissionWrite: 0,
        },
    ]);
    logger.info("Dev grant entitlement user=%s id=%s expires=%d", targetUserId, entitlementId, rec.expires_at);
    return JSON.stringify({ ok: true, entitlement: rec, auto_help: getAutoHelpEntitlementPublic(nk, targetUserId) });
}
/**
 * Crownspire Phase 5.1 — Player Identity & Presence
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Concatenated into build/index.js via tsconfig files order.
 *
 * Extends CrownspireProfile with avatar, power, citadel, VIP, last_online.
 * Online status = last_online within PRESENCE_ONLINE_SEC (see index.ts).
 */
var ALLOWED_AVATAR_IDS = {
    avatar_01: true,
    avatar_02: true,
    avatar_03: true,
    avatar_04: true,
    avatar_05: true,
    avatar_06: true,
    avatar_07: true,
    avatar_08: true,
};
function sanitizeAvatarId(raw) {
    var id = String(raw || "").trim().toLowerCase();
    if (ALLOWED_AVATAR_IDS[id]) {
        return id;
    }
    return "avatar_01";
}
/**
 * Update avatar / social display stats.
 * Power / citadel / VIP are client-reported social snapshots for beta — not combat authority.
 */
function rpcUpdatePlayerIdentity(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    assertRateLimit(nk, ctx.userId, "update_player_identity", 2);
    var data = parsePayload(payload);
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (data["avatar_id"] !== undefined) {
        profile.avatar_id = sanitizeAvatarId(String(data["avatar_id"] || ""));
    }
    if (data["power"] !== undefined) {
        var power = Math.floor(Number(data["power"]));
        if (!isFinite(power) || power < 0) {
            throw Err("Invalid power");
        }
        profile.power = Math.min(power, 999999999);
        var prevHighest = typeof profile.highest_power === "number" ? profile.highest_power : 0;
        profile.highest_power = Math.max(prevHighest, profile.power);
    }
    if (data["kills"] !== undefined) {
        var kills = Math.floor(Number(data["kills"]));
        if (!isFinite(kills) || kills < 0) {
            throw Err("Invalid kills");
        }
        profile.kills = Math.min(kills, 999999999);
    }
    if (data["public_equipment"] !== undefined) {
        // Public showcase gear only — reject non-arrays; never store troop/resource secrets here.
        if (!Array.isArray(data["public_equipment"])) {
            throw Err("Invalid public_equipment");
        }
        profile.public_equipment = data["public_equipment"].slice(0, 12);
    }
    if (data["citadel_level"] !== undefined) {
        var lvl = Math.floor(Number(data["citadel_level"]));
        if (!isFinite(lvl) || lvl < 1) {
            throw Err("Invalid citadel_level");
        }
        profile.citadel_level = Math.min(lvl, 100);
    }
    if (data["vip_level"] !== undefined) {
        var vip = Math.floor(Number(data["vip_level"]));
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
function rpcPresenceHeartbeat(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw Err("Unauthenticated");
    }
    // Soft rate limit — clients pulse ~every 30s; allow burst reconnect.
    assertRateLimit(nk, ctx.userId, "presence_heartbeat", 8);
    var profile = ensureProfile(nk, logger, ctx.userId);
    var data = parsePayload(payload);
    // Optional light identity sync on heartbeat (keeps roster fresh).
    if (data["power"] !== undefined) {
        var power = Math.floor(Number(data["power"]));
        if (isFinite(power) && power >= 0) {
            profile.power = Math.min(power, 999999999);
        }
    }
    if (data["citadel_level"] !== undefined) {
        var lvl = Math.floor(Number(data["citadel_level"]));
        if (isFinite(lvl) && lvl >= 1) {
            profile.citadel_level = Math.min(lvl, 100);
        }
    }
    if (data["vip_level"] !== undefined) {
        var vip = Math.floor(Number(data["vip_level"]));
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
/**
 * Crownspire Phase 5.3 — Alliance Rallies (Wildling Lair battles)
 * LOCAL DEVELOPMENT / CLOSED BETA ONLY.
 * Concatenated into build/index.js via tsconfig files order.
 */
var RALLY_COLLECTION = "crownspire_rallies";
var RALLY_INDEX_COLLECTION = "crownspire_alliance_rally_index";
var RALLY_NOTIF_CODE = 5002;
var RALLY_SCHEMA_VERSION = 1;
var RALLY_STATUS_FORMING = "FORMING";
var RALLY_STATUS_LAUNCHED = "LAUNCHED";
var RALLY_STATUS_COMPLETED = "COMPLETED";
var RALLY_STATUS_CANCELLED = "CANCELLED";
var RALLY_ALLOWED_COUNTDOWNS = {
    60: true,
    300: true,
    600: true,
};
var RALLY_DEFAULT_COUNTDOWN = 60;
var RALLY_MAX_PARTICIPANTS = 10;
function rpcRallyCreate(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    assertRateLimit(nk, ctx.userId, "rally_create", 3);
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Join an Alliance to create a Rally.");
    // One active rally per player.
    var existing = findActiveRallyForUser(nk, profile.alliance_id, ctx.userId);
    if (existing)
        throw Err("You already have an active Rally.");
    var data = parsePayload(payload);
    var countdown = sanitizeCountdown(Number(data["countdown_seconds"]));
    var lairId = String(data["lair_id"] || "").trim();
    if (!lairId)
        throw Err("lair_id required");
    // Reject obviously fake / empty targets. Full kingdom lair registry is client+kingdom seeded in Phase 5.4.
    if (lairId.length < 6 || lairId.length > 96)
        throw Err("Invalid Alliance Lair target.");
    if (lairId.indexOf(" ") >= 0)
        throw Err("Invalid Alliance Lair target.");
    var lower = lairId.toLowerCase();
    if (lower === "fake" || lower === "null" || lower === "undefined" || lower.indexOf("fake_") === 0) {
        throw Err("Fake Alliance Lair target rejected.");
    }
    var heroIds = sanitizeStringArray(data["hero_ids"], 3);
    var troopCounts = sanitizeTroopCounts(data["troop_counts"] || data["troops"] || {});
    var troopTiers = data["troop_tiers"] || {};
    var power = Math.max(0, Math.floor(Number(data["power"] || 0)));
    var totalTroops = troopTotal(troopCounts);
    if (totalTroops <= 0)
        throw Err("Rally requires troops.");
    var now = nowUnix();
    var rallyId = nk.uuidv4();
    var participant = {
        user_id: ctx.userId,
        display_name: profile.display_name || "Leader",
        hero_ids: heroIds,
        troop_counts: troopCounts,
        troop_tiers: troopTiers,
        power: power,
        joined_at: now,
    };
    var rally = {
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
    sendAllianceSystemMessage(nk, logger, profile.alliance_id, (profile.display_name || "A player") + " started a Rally on Lair Lv." + rally.lair_level + ".", "rally_started");
    sendRallyChatCard(nk, logger, rally);
    notifyAllianceRally(nk, logger, rally, "rally_created");
    logger.info("Rally created id=%s alliance=%s leader=%s", rallyId, profile.alliance_id, ctx.userId);
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
function rpcRallyJoin(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    assertRateLimit(nk, ctx.userId, "rally_join", 2);
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id)
        throw Err("Not in an alliance");
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    if (!rallyId)
        throw Err("rally_id required");
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    rally = refreshRallyStatus(nk, rally);
    if (rally.alliance_id !== profile.alliance_id)
        throw Err("Rally belongs to another Alliance");
    if (rally.status !== RALLY_STATUS_FORMING)
        throw Err("Rally is not open to join");
    if (rally.participants.length >= rally.max_participants)
        throw Err("Rally is full");
    if (findParticipant(rally, ctx.userId))
        throw Err("Already joined this Rally");
    if (findActiveRallyForUser(nk, profile.alliance_id, ctx.userId))
        throw Err("You already have an active Rally");
    var troopCounts = sanitizeTroopCounts(data["troop_counts"] || data["troops"] || {});
    var totalTroops = troopTotal(troopCounts);
    if (totalTroops <= 0)
        throw Err("Join requires troops.");
    var power = Math.max(0, Math.floor(Number(data["power"] || 0)));
    var now = nowUnix();
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
    sendAllianceSystemMessage(nk, logger, profile.alliance_id, (profile.display_name || "A player") + " joined the Rally.", "rally_joined");
    notifyAllianceRally(nk, logger, rally, "rally_joined");
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
function rpcRallyLeave(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    rally = refreshRallyStatus(nk, rally);
    if (rally.status !== RALLY_STATUS_FORMING)
        throw Err("Cannot leave after launch");
    if (rally.leader_user_id === ctx.userId)
        throw Err("Leader must cancel the Rally instead of leaving");
    var before = rally.participants.length;
    rally.participants = rally.participants.filter(function (p) {
        return p.user_id !== ctx.userId;
    });
    if (rally.participants.length === before)
        throw Err("Not in this Rally");
    recomputeTotals(rally);
    rally.updated_at = nowUnix();
    writeRally(nk, rally);
    notifyAllianceRally(nk, logger, rally, "rally_left");
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
function rpcRallyCancel(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    if (rally.leader_user_id !== ctx.userId)
        throw Err("Only the Rally leader can cancel");
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
function rpcRallyLaunch(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    rally = refreshRallyStatus(nk, rally);
    if (rally.status === RALLY_STATUS_LAUNCHED) {
        return JSON.stringify({ ok: true, rally: publicRally(rally) });
    }
    if (rally.status !== RALLY_STATUS_FORMING)
        throw Err("Rally cannot launch");
    var auto = !!data["auto"];
    if (!auto && rally.leader_user_id !== ctx.userId)
        throw Err("Only the leader can Launch Now");
    if (auto && ctx.userId !== rally.leader_user_id && !findParticipant(rally, ctx.userId)) {
        throw Err("Not in this Rally");
    }
    // Auto-launch only when timer elapsed.
    if (auto && nowUnix() < rally.launch_at)
        throw Err("Rally timer has not finished");
    rally.status = RALLY_STATUS_LAUNCHED;
    rally.launched_at = nowUnix();
    rally.updated_at = nowUnix();
    writeRally(nk, rally);
    sendAllianceSystemMessage(nk, logger, rally.alliance_id, "Rally launched!", "rally_launched");
    notifyAllianceRally(nk, logger, rally, "rally_launched");
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
function rpcRallyGet(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    rally = refreshRallyStatus(nk, rally);
    if (profile.alliance_id && rally.alliance_id !== profile.alliance_id)
        throw Err("Rally belongs to another Alliance");
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
function rpcRallyListActive(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    if (!profile.alliance_id) {
        return JSON.stringify({ ok: true, rallies: [], connected: true, in_alliance: false });
    }
    var ids = listAllianceRallyIds(nk, profile.alliance_id);
    var out = [];
    for (var i = 0; i < ids.length; i++) {
        var rally = readRally(nk, ids[i]);
        if (!rally)
            continue;
        rally = refreshRallyStatus(nk, rally);
        if (rally.status === RALLY_STATUS_FORMING || rally.status === RALLY_STATUS_LAUNCHED) {
            out.push(publicRally(rally));
        }
    }
    return JSON.stringify({ ok: true, rallies: out, connected: true, in_alliance: true });
}
function rpcRallyComplete(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parsePayload(payload);
    var rallyId = String(data["rally_id"] || "").trim();
    var rally = readRally(nk, rallyId);
    if (!rally)
        throw Err("Rally not found");
    if (rally.leader_user_id !== ctx.userId)
        throw Err("Only the Rally leader can submit battle results");
    if (rally.status === RALLY_STATUS_COMPLETED) {
        return JSON.stringify({ ok: true, rally: publicRally(rally) });
    }
    if (rally.status !== RALLY_STATUS_LAUNCHED && rally.status !== RALLY_STATUS_FORMING) {
        throw Err("Rally is not active");
    }
    var result = data["result"] || {};
    var victory = !!result["victory"];
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
    sendAllianceSystemMessage(nk, logger, rally.alliance_id, victory ? "Rally Victory!" : "Rally Defeat.", victory ? "rally_victory" : "rally_defeat");
    notifyAllianceRally(nk, logger, rally, victory ? "rally_victory" : "rally_defeat");
    return JSON.stringify({ ok: true, rally: publicRally(rally) });
}
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function sanitizeCountdown(raw) {
    var n = Math.floor(Number(raw));
    if (RALLY_ALLOWED_COUNTDOWNS[n])
        return n;
    return RALLY_DEFAULT_COUNTDOWN;
}
function sanitizeTroopCounts(raw) {
    var src = raw || {};
    return {
        infantry: Math.max(0, Math.floor(Number(src["infantry"] != null ? src["infantry"] : src["Infantry"] || 0))),
        marksmen: Math.max(0, Math.floor(Number(src["marksmen"] != null ? src["marksmen"] : src["Marksmen"] || 0))),
        cavalry: Math.max(0, Math.floor(Number(src["cavalry"] != null ? src["cavalry"] : src["Cavalry"] || 0))),
    };
}
function troopTotal(counts) {
    return (counts.infantry || 0) + (counts.marksmen || 0) + (counts.cavalry || 0);
}
function sanitizeStringArray(raw, maxLen) {
    var out = [];
    if (!raw || !(raw instanceof Array))
        return out;
    for (var i = 0; i < raw.length && out.length < maxLen; i++) {
        var s = String(raw[i] || "").trim();
        if (s)
            out.push(s.substring(0, 64));
    }
    return out;
}
function recomputeTotals(rally) {
    var power = 0;
    var troops = 0;
    for (var i = 0; i < rally.participants.length; i++) {
        power += rally.participants[i].power || 0;
        troops += troopTotal(rally.participants[i].troop_counts || {});
    }
    rally.total_power = power;
    rally.total_troops = troops;
}
function findParticipant(rally, userId) {
    for (var i = 0; i < rally.participants.length; i++) {
        if (rally.participants[i].user_id === userId)
            return rally.participants[i];
    }
    return null;
}
function refreshRallyStatus(nk, rally) {
    if (rally.status === RALLY_STATUS_FORMING && nowUnix() >= rally.launch_at) {
        // Timer elapsed — leave FORMING until a client calls launch(auto=true).
        // Clients poll remaining_seconds; launch RPC finalizes.
    }
    return rally;
}
function publicRally(rally) {
    var now = nowUnix();
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
function writeRally(nk, rally) {
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
function readRally(nk, rallyId) {
    var objects = nk.storageRead([{ collection: RALLY_COLLECTION, key: rallyId, userId: SYSTEM_USER }]);
    if (!objects || objects.length === 0 || !objects[0].value)
        return null;
    return objects[0].value;
}
function indexAllianceRally(nk, allianceId, rallyId, active) {
    var objects = nk.storageRead([{ collection: RALLY_INDEX_COLLECTION, key: allianceId, userId: SYSTEM_USER }]);
    var ids = [];
    if (objects && objects.length > 0 && objects[0].value) {
        ids = (objects[0].value.rally_ids || []);
    }
    ids = ids.filter(function (id) {
        return id !== rallyId;
    });
    if (active)
        ids.unshift(rallyId);
    if (ids.length > 40)
        ids = ids.slice(0, 40);
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
function listAllianceRallyIds(nk, allianceId) {
    var objects = nk.storageRead([{ collection: RALLY_INDEX_COLLECTION, key: allianceId, userId: SYSTEM_USER }]);
    if (!objects || objects.length === 0 || !objects[0].value)
        return [];
    return (objects[0].value.rally_ids || []);
}
function findActiveRallyForUser(nk, allianceId, userId) {
    var ids = listAllianceRallyIds(nk, allianceId);
    for (var i = 0; i < ids.length; i++) {
        var rally = readRally(nk, ids[i]);
        if (!rally)
            continue;
        if (rally.status !== RALLY_STATUS_FORMING && rally.status !== RALLY_STATUS_LAUNCHED)
            continue;
        if (findParticipant(rally, userId))
            return rally;
    }
    return null;
}
function notifyAllianceRally(nk, logger, rally, eventType) {
    try {
        var users = nk.groupUsersList(rally.alliance_id, 100);
        var list = users.groupUsers || [];
        var ids = [];
        for (var i = 0; i < list.length; i++) {
            var gu = list[i];
            var state = Number(gu.state);
            if ((state === 0 || state === 1 || state === 2) && gu.user) {
                var uid = String(gu.user.userId || gu.user.id || "");
                if (uid)
                    ids.push(uid);
            }
        }
        if (ids.length === 0)
            return;
        nk.notificationsSend(ids.map(function (uid) {
            return {
                code: RALLY_NOTIF_CODE,
                content: { event: eventType, rally_id: rally.rally_id, rally: publicRally(rally) },
                persistent: false,
                senderId: rally.leader_user_id,
                subject: "Alliance Rally",
                userId: uid,
            };
        }));
    }
    catch (e) {
        logger.warn("Rally notify failed: %s", String(e));
    }
}
function sendRallyChatCard(nk, logger, rally) {
    try {
        var channelId = nk.channelIdBuild("", rally.alliance_id, 2);
        nk.channelMessageSend(channelId, {
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
        }, undefined, undefined, true);
    }
    catch (e) {
        logger.warn("Rally chat card failed: %s", String(e));
    }
}
/**
 * Crownspire — Kingdom world castles (beta)
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js.
 *
 * Assigns stable world_x/world_y per profile and maintains a kingdom registry
 * so clients can spawn real player castles on the world map.
 */
var KINGDOM_CASTLE_COLLECTION = "crownspire_kingdom_castles";
var WORLD_MAP_SIZE = 8192;
var CASTLE_EDGE_MARGIN = 900;
function hashUserToUnit(userId) {
    var h = 2166136261;
    var s = String(userId || "");
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619);
    }
    return (h >>> 0) / 4294967295;
}
function assignDeterministicCastleCoords(userId) {
    var u1 = hashUserToUnit(userId + ":x");
    var u2 = hashUserToUnit(userId + ":y");
    var span = WORLD_MAP_SIZE - CASTLE_EDGE_MARGIN * 2;
    return {
        x: Math.floor(CASTLE_EDGE_MARGIN + u1 * span),
        y: Math.floor(CASTLE_EDGE_MARGIN + u2 * span),
    };
}
function ensureCastleCoords(nk, profile) {
    var hasX = typeof profile.world_x === "number" && isFinite(profile.world_x);
    var hasY = typeof profile.world_y === "number" && isFinite(profile.world_y);
    if (hasX && hasY) {
        return profile;
    }
    var coords = assignDeterministicCastleCoords(profile.user_id);
    profile.world_x = coords.x;
    profile.world_y = coords.y;
    profile.updated_at = nowUnix();
    writeProfile(nk, profile);
    return profile;
}
function readKingdomCastleRegistry(nk, kingdomId) {
    var objects = nk.storageRead([
        { collection: KINGDOM_CASTLE_COLLECTION, key: kingdomId, userId: SYSTEM_USER },
    ]);
    if (objects && objects.length > 0 && objects[0].value) {
        var v = objects[0].value;
        return { castles: Array.isArray(v.castles) ? v.castles : [] };
    }
    return { castles: [] };
}
function writeKingdomCastleRegistry(nk, kingdomId, castles) {
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
function upsertKingdomCastleEntry(nk, profile) {
    var kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
    ensureCastleCoords(nk, profile);
    var reg = readKingdomCastleRegistry(nk, kingdomId);
    var now = nowUnix();
    var peaceExp = typeof profile.peace_shield_expires_at === "number"
        ? profile.peace_shield_expires_at
        : 0;
    var antiExp = typeof profile.anti_scout_expires_at === "number"
        ? profile.anti_scout_expires_at
        : 0;
    var begExp = typeof profile.beginner_protection_expires_at === "number"
        ? profile.beginner_protection_expires_at
        : 0;
    var begCleared = Boolean(profile.beginner_protection_cleared);
    var entry = {
        user_id: profile.user_id,
        display_name: profile.display_name || "",
        alliance_id: profile.alliance_id || "",
        alliance_tag: profile.alliance_tag || "",
        alliance_name: profile.alliance_name || "",
        avatar_id: profile.avatar_id || "avatar_01",
        world_x: Number(profile.world_x),
        world_y: Number(profile.world_y),
        citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
        power: typeof profile.power === "number" ? profile.power : 0,
        peace_shield_expires_at: peaceExp,
        anti_scout_expires_at: antiExp,
        beginner_protection_expires_at: begExp,
        beginner_protection_cleared: begCleared,
        peace_shield_active: peaceExp > now,
        anti_scout_active: antiExp > now,
        beginner_protection_active: !begCleared && begExp > now,
        updated_at: now,
    };
    var found = false;
    for (var i = 0; i < reg.castles.length; i++) {
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
function rpcListKingdomCastles(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var profile = ensureProfile(nk, logger, ctx.userId);
    ensureCastleCoords(nk, profile);
    upsertKingdomCastleEntry(nk, profile);
    var kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
    var reg = readKingdomCastleRegistry(nk, kingdomId);
    return JSON.stringify({
        ok: true,
        kingdom_id: kingdomId,
        castles: reg.castles,
        self: {
            user_id: profile.user_id,
            world_x: Number(profile.world_x),
            world_y: Number(profile.world_y),
        },
    });
}
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
var TELEPORT_ITEM_ID = "teleport_advanced_compass";
/** Multiplayer-authority consumables share teleport inventory OCC storage. */
var PEACE_SHIELD_INV_ITEM_ID = "boost_shield_peace_3d";
var ANTI_SCOUT_INV_ITEM_ID = "boost_anti_scout_24h";
var TELEPORT_INV_COLLECTION = "crownspire_teleport_inventory";
var TELEPORT_OPS_COLLECTION = "crownspire_teleport_ops";
var TELEPORT_DEPLOY_COLLECTION = "crownspire_teleport_deployments";
var TELEPORT_LOCK_COLLECTION = "crownspire_kingdom_teleport_lock";
var CASTLE_MOVED_NOTIF_CODE = 5005;
var LOCK_TTL_SEC = 20;
var SECURE_CONSUMABLE_ALLOWLIST = {};
SECURE_CONSUMABLE_ALLOWLIST[TELEPORT_ITEM_ID] = true;
SECURE_CONSUMABLE_ALLOWLIST[PEACE_SHIELD_INV_ITEM_ID] = true;
SECURE_CONSUMABLE_ALLOWLIST[ANTI_SCOUT_INV_ITEM_ID] = true;
var MAP_CONTRACT_ID = "crownspire_map_blockers_v1";
var WORLD_MAP_SIZE_T = 8192;
var CASTLE_EDGE_MARGIN_T = 900;
var CASTLE_MIN_SPACING_T = 500;
var TERRAIN_EDGE_MARGIN_T = 450;
var POI_EDGE_MARGIN_T = 300;
var MAX_PLACE_ATTEMPTS = 250;
var LAKE_COUNT_T = 6;
var LAKE_RADIUS_T = 700;
var MOUNTAIN_COUNT_T = 18;
var MOUNTAIN_RADIUS_T = 550;
var FOREST_COUNT_T = 35;
var FOREST_RADIUS_T = 425;
var ROCK_COUNT_T = 30;
var ROCK_RADIUS_T = 250;
var RESOURCE_COUNT_T = 40;
var RESOURCE_RADIUS_T = 160;
var WILDLING_COUNT_T = 30;
var WILDLING_RADIUS_T = 120;
var LAIR_COUNT_T = 10;
var LAIR_RADIUS_T = 360;
var OP_PENDING = "pending";
var OP_INV_CONSUMED = "inventory_consumed";
var OP_REGISTRY_UPDATED = "registry_updated";
var OP_PROFILE_UPDATED = "profile_updated";
var OP_COMPLETED = "completed";
var OP_FAILED = "failed";
function isSecureConsumableItemId(itemId) {
    return SECURE_CONSUMABLE_ALLOWLIST[String(itemId || "")] === true;
}
function normalizeInvRecord(rec, userId) {
    var out = rec && typeof rec === "object" ? rec : {};
    out.user_id = String(out.user_id || userId);
    if (!out.balances || typeof out.balances !== "object")
        out.balances = {};
    out.reconciled = !!out.reconciled;
    out.import_fingerprint = String(out.import_fingerprint || "");
    if (!out.item_reconciled || typeof out.item_reconciled !== "object")
        out.item_reconciled = {};
    if (!out.item_import_fingerprints || typeof out.item_import_fingerprints !== "object") {
        out.item_import_fingerprints = {};
    }
    out.updated_at = typeof out.updated_at === "number" ? out.updated_at : 0;
    return out;
}
function fnv1a32Teleport(text) {
    var h = 2166136261;
    var s = String(text || "");
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619);
    }
    return h >>> 0;
}
function kingdomSeedTeleport(kingdomId, salt) {
    return fnv1a32Teleport(String(salt) + "|" + String(kingdomId || ""));
}
function mulberry32Teleport(seed) {
    var state = seed >>> 0;
    return function () {
        state = (state + 0x6d2b79f5) >>> 0;
        var t = state;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
function findValidPackedTeleport(rng, occupied, radius, edge) {
    var minC = edge + radius;
    var maxC = WORLD_MAP_SIZE_T - edge - radius;
    if (maxC <= minC)
        return null;
    for (var a = 0; a < MAX_PLACE_ATTEMPTS; a++) {
        var x = minC + rng() * (maxC - minC);
        var y = minC + rng() * (maxC - minC);
        var ok = true;
        for (var i = 0; i < occupied.length; i++) {
            var o = occupied[i];
            var dx = x - o.x;
            var dy = y - o.y;
            if (Math.sqrt(dx * dx + dy * dy) < radius + o.radius) {
                ok = false;
                break;
            }
        }
        if (ok)
            return { x: x, y: y };
    }
    return null;
}
function appendPackedTeleport(out, occupied, rng, kind, count, radius, edge) {
    for (var i = 0; i < count; i++) {
        var pos = findValidPackedTeleport(rng, occupied, radius, edge);
        if (!pos)
            continue;
        var b = { kind: kind, x: pos.x, y: pos.y, radius: radius };
        occupied.push(b);
        out.push(b);
    }
}
function computeMapBlockers(kingdomId) {
    var kid = String(kingdomId || DEV_KINGDOM_ID);
    var out = [];
    var occupied = [];
    var terrainRng = mulberry32Teleport(kingdomSeedTeleport(kid, "terrain_v1"));
    appendPackedTeleport(out, occupied, terrainRng, "lake", LAKE_COUNT_T, LAKE_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
    appendPackedTeleport(out, occupied, terrainRng, "mountain", MOUNTAIN_COUNT_T, MOUNTAIN_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
    appendPackedTeleport(out, occupied, terrainRng, "forest", FOREST_COUNT_T, FOREST_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
    appendPackedTeleport(out, occupied, terrainRng, "rock", ROCK_COUNT_T, ROCK_RADIUS_T, TERRAIN_EDGE_MARGIN_T);
    var poiRng = mulberry32Teleport(kingdomSeedTeleport(kid, "poi_v1"));
    appendPackedTeleport(out, occupied, poiRng, "resource", RESOURCE_COUNT_T, RESOURCE_RADIUS_T, POI_EDGE_MARGIN_T);
    appendPackedTeleport(out, occupied, poiRng, "wildling", WILDLING_COUNT_T, WILDLING_RADIUS_T, POI_EDGE_MARGIN_T);
    appendPackedTeleport(out, occupied, poiRng, "lair", LAIR_COUNT_T, LAIR_RADIUS_T, POI_EDGE_MARGIN_T);
    return out;
}
function validateCastleCandidateServer(kingdomId, x, y, castles, selfUserId) {
    if (typeof x !== "number" || typeof y !== "number" || !isFinite(x) || !isFinite(y)) {
        return { ok: false, error: "Invalid coordinates." };
    }
    if (x < CASTLE_EDGE_MARGIN_T ||
        y < CASTLE_EDGE_MARGIN_T ||
        x > WORLD_MAP_SIZE_T - CASTLE_EDGE_MARGIN_T ||
        y > WORLD_MAP_SIZE_T - CASTLE_EDGE_MARGIN_T) {
        return { ok: false, error: "Too close to the map edge." };
    }
    for (var i = 0; i < castles.length; i++) {
        var c = castles[i];
        if (String(c.user_id) === selfUserId)
            continue;
        var cx = Number(c.world_x);
        var cy = Number(c.world_y);
        if (!isFinite(cx) || !isFinite(cy))
            continue;
        var dx = x - cx;
        var dy = y - cy;
        if (Math.sqrt(dx * dx + dy * dy) < CASTLE_MIN_SPACING_T) {
            return { ok: false, error: "Too close to another castle." };
        }
    }
    var blockers = computeMapBlockers(kingdomId);
    var softR = CASTLE_MIN_SPACING_T * 0.5;
    for (var i = 0; i < blockers.length; i++) {
        var b = blockers[i];
        var dx = x - b.x;
        var dy = y - b.y;
        if (Math.sqrt(dx * dx + dy * dy) < b.radius + softR) {
            return { ok: false, error: "Blocked by " + b.kind + "." };
        }
    }
    return { ok: true, error: "" };
}
function trimStr(v) {
    return String(v == null ? "" : v).replace(/^\s+|\s+$/g, "");
}
function isStrictNonNegInt(v) {
    return typeof v === "number" && isFinite(v) && !isNaN(v) && v >= 0 && Math.floor(v) === v;
}
function isStrictBool(v) {
    return v === true || v === false;
}
function storageReadOne(nk, collection, key, userId) {
    var objects = nk.storageRead([{ collection: collection, key: key, userId: userId }]);
    if (objects && objects.length > 0 && objects[0].value) {
        return { value: objects[0].value, version: String(objects[0].version || "") };
    }
    return null;
}
function storageWriteVersioned(nk, collection, key, userId, value, version, permissionRead) {
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
function readTeleportInvObj(nk, userId) {
    var obj = storageReadOne(nk, TELEPORT_INV_COLLECTION, userId, userId);
    if (obj) {
        obj.value = normalizeInvRecord(obj.value, userId);
        return obj;
    }
    return {
        value: normalizeInvRecord({
            user_id: userId,
            balances: {},
            reconciled: false,
            import_fingerprint: "",
            item_reconciled: {},
            item_import_fingerprints: {},
            updated_at: 0,
        }, userId),
        version: "*",
    };
}
function getSecureBalance(rec, itemId) {
    if (!isSecureConsumableItemId(itemId))
        return 0;
    var n = Number((rec.balances || {})[itemId] || 0);
    return isFinite(n) && n > 0 ? Math.floor(n) : 0;
}
function setSecureBalance(rec, itemId, amount) {
    if (!isSecureConsumableItemId(itemId))
        return;
    if (!rec.balances)
        rec.balances = {};
    var n = Math.max(0, Math.floor(amount));
    if (n <= 0)
        delete rec.balances[itemId];
    else
        rec.balances[itemId] = n;
}
function getTeleportBalance(rec) {
    return getSecureBalance(rec, TELEPORT_ITEM_ID);
}
function setTeleportBalance(rec, amount) {
    setSecureBalance(rec, TELEPORT_ITEM_ID, amount);
}
function isGrantOnlySecureItem(itemId) {
    return itemId === PEACE_SHIELD_INV_ITEM_ID || itemId === ANTI_SCOUT_INV_ITEM_ID;
}
function isSecureItemReconciled(rec, itemId) {
    if (itemId === TELEPORT_ITEM_ID)
        return !!rec.reconciled;
    // Peace Shield / Anti-Scout are grant-only — never bag-reconciled. Always usable for balance checks.
    if (isGrantOnlySecureItem(itemId))
        return true;
    return !!(rec.item_reconciled && rec.item_reconciled[itemId]);
}
function markSecureItemReconciled(rec, itemId, fingerprint) {
    if (itemId === TELEPORT_ITEM_ID) {
        rec.reconciled = true;
        rec.import_fingerprint = fingerprint;
        return;
    }
    if (!rec.item_reconciled)
        rec.item_reconciled = {};
    if (!rec.item_import_fingerprints)
        rec.item_import_fingerprints = {};
    rec.item_reconciled[itemId] = true;
    rec.item_import_fingerprints[itemId] = fingerprint;
}
function publicSecureBalances(rec) {
    var _a;
    return _a = {},
        _a[TELEPORT_ITEM_ID] = getSecureBalance(rec, TELEPORT_ITEM_ID),
        _a[PEACE_SHIELD_INV_ITEM_ID] = getSecureBalance(rec, PEACE_SHIELD_INV_ITEM_ID),
        _a[ANTI_SCOUT_INV_ITEM_ID] = getSecureBalance(rec, ANTI_SCOUT_INV_ITEM_ID),
        _a;
}
function publicSecureReconciled(rec) {
    var _a;
    return _a = {},
        _a[TELEPORT_ITEM_ID] = isSecureItemReconciled(rec, TELEPORT_ITEM_ID),
        // Grant-only items report ready=true; bag import is never used.
        _a[PEACE_SHIELD_INV_ITEM_ID] = true,
        _a[ANTI_SCOUT_INV_ITEM_ID] = true,
        _a;
}
function readRegistryObj(nk, kingdomId) {
    var obj = storageReadOne(nk, KINGDOM_CASTLE_COLLECTION, kingdomId, SYSTEM_USER);
    if (obj) {
        var v = obj.value;
        if (!Array.isArray(v.castles))
            v.castles = [];
        return obj;
    }
    return {
        value: { kingdom_id: kingdomId, castles: [], updated_at: 0 },
        version: "*",
    };
}
function readOpObj(nk, userId, requestId) {
    return storageReadOne(nk, TELEPORT_OPS_COLLECTION, requestId, userId);
}
function writeOpObj(nk, userId, requestId, value, version) {
    storageWriteVersioned(nk, TELEPORT_OPS_COLLECTION, requestId, userId, value, version, 1);
}
function readDeployObj(nk, userId) {
    var obj = storageReadOne(nk, TELEPORT_DEPLOY_COLLECTION, userId, userId);
    if (obj) {
        if (!Array.isArray(obj.value.deployments))
            obj.value.deployments = [];
        return obj;
    }
    return { value: { user_id: userId, deployments: [], updated_at: 0 }, version: "*" };
}
function userHasServerDeployments(nk, userId) {
    var obj = readDeployObj(nk, userId);
    return Array.isArray(obj.value.deployments) && obj.value.deployments.length > 0;
}
function userInActiveRally(nk, logger, userId, allianceId) {
    if (!allianceId)
        return false;
    try {
        var objects = nk.storageRead([
            { collection: "crownspire_alliance_rally_index", key: allianceId, userId: SYSTEM_USER },
        ]);
        if (!objects || objects.length === 0 || !objects[0].value)
            return false;
        var ids = Array.isArray(objects[0].value.rally_ids)
            ? objects[0].value.rally_ids
            : [];
        for (var i = 0; i < ids.length; i++) {
            var rid = String(ids[i] || "");
            if (!rid)
                continue;
            var rallyObjs = nk.storageRead([{ collection: "crownspire_rallies", key: rid, userId: SYSTEM_USER }]);
            if (!rallyObjs || rallyObjs.length === 0 || !rallyObjs[0].value)
                continue;
            var rally = rallyObjs[0].value;
            var status = String(rally.status || "");
            if (status !== "FORMING" && status !== "LAUNCHED")
                continue;
            if (String(rally.leader_user_id) === userId)
                return true;
            var parts = Array.isArray(rally.participants) ? rally.participants : [];
            for (var p = 0; p < parts.length; p++) {
                if (String(parts[p].user_id) === userId)
                    return true;
            }
        }
    }
    catch (e) {
        logger.warn("teleport rally check failed: %s", String(e));
    }
    return false;
}
function acquireKingdomLock(nk, kingdomId, userId, requestId) {
    var now = nowUnix();
    for (var attempt = 0; attempt < 8; attempt++) {
        var obj = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
        var cur = obj ? obj.value : null;
        var ver = obj ? obj.version : "*";
        var expired = !cur || !cur.expires_at || Number(cur.expires_at) <= now;
        var sameHolder = cur && String(cur.request_id) === requestId && String(cur.user_id) === userId;
        if (!expired && !sameHolder) {
            return { ok: false, error: "Kingdom teleport lock busy. Try again.", version: "" };
        }
        var next = {
            kingdom_id: kingdomId,
            user_id: userId,
            request_id: requestId,
            expires_at: now + LOCK_TTL_SEC,
            updated_at: now,
        };
        try {
            storageWriteVersioned(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER, next, ver, 1);
            var confirm = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
            if (confirm &&
                String(confirm.value.request_id) === requestId &&
                String(confirm.value.user_id) === userId) {
                return { ok: true, error: "", version: confirm.version };
            }
        }
        catch (_e) {
            // CAS conflict — retry
        }
    }
    return { ok: false, error: "Could not acquire kingdom teleport lock.", version: "" };
}
function releaseKingdomLock(nk, kingdomId, userId, requestId) {
    var obj = storageReadOne(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER);
    if (!obj)
        return;
    var cur = obj.value;
    if (String(cur.user_id) !== userId || String(cur.request_id) !== requestId)
        return;
    try {
        storageWriteVersioned(nk, TELEPORT_LOCK_COLLECTION, kingdomId, SYSTEM_USER, { kingdom_id: kingdomId, user_id: "", request_id: "", expires_at: 0, updated_at: nowUnix() }, obj.version, 1);
    }
    catch (_e) {
        // Best-effort release; TTL recovers crashed holders.
    }
}
function notifyKingdomCastleMoved(nk, logger, kingdomId, actorUserId, worldX, worldY, displayName) {
    var reg = readRegistryObj(nk, kingdomId).value;
    var recipients = [];
    var castles = Array.isArray(reg.castles) ? reg.castles : [];
    for (var i = 0; i < castles.length; i++) {
        var uid = String(castles[i].user_id || "");
        if (!uid || uid === actorUserId)
            continue;
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
    if (recipients.length === 0)
        return;
    try {
        nk.notificationsSend(recipients);
    }
    catch (e) {
        logger.warn("castle_moved notify failed: %s", String(e));
    }
}
function applyRegistryMove(nk, profile, worldX, worldY) {
    var kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
    for (var attempt = 0; attempt < 8; attempt++) {
        var regObj = readRegistryObj(nk, kingdomId);
        var reg = regObj.value;
        var castles = Array.isArray(reg.castles) ? reg.castles.slice() : [];
        var check = validateCastleCandidateServer(kingdomId, worldX, worldY, castles, profile.user_id);
        if (!check.ok)
            throw Err(check.error);
        var entry = {
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
        var found = false;
        for (var i = 0; i < castles.length; i++) {
            if (String(castles[i].user_id) === profile.user_id) {
                castles[i] = entry;
                found = true;
                break;
            }
        }
        if (!found)
            castles.push(entry);
        if (castles.length > 200) {
            castles.sort(function (a, b) {
                return Number(b.updated_at || 0) - Number(a.updated_at || 0);
            });
            castles.length = 200;
        }
        var next = { kingdom_id: kingdomId, castles: castles, updated_at: nowUnix() };
        try {
            storageWriteVersioned(nk, KINGDOM_CASTLE_COLLECTION, kingdomId, SYSTEM_USER, next, regObj.version, 2);
            return;
        }
        catch (_e) {
            // retry CAS
        }
    }
    throw Err("Kingdom castle registry busy. Try again.");
}
function restoreRegistryCoords(nk, profile, worldX, worldY) {
    profile.world_x = worldX;
    profile.world_y = worldY;
    applyRegistryMove(nk, profile, worldX, worldY);
}
function consumeSecureItemCAS(nk, userId, itemId) {
    if (!isSecureConsumableItemId(itemId))
        throw Err("Unsupported secure consumable.");
    for (var attempt = 0; attempt < 8; attempt++) {
        var invObj = readTeleportInvObj(nk, userId);
        var inv = normalizeInvRecord(invObj.value, userId);
        // Advanced Teleport still requires historical one-time bag reconcile.
        // Peace Shield / Anti-Scout are grant-only (never bag-imported).
        if (itemId === TELEPORT_ITEM_ID && !inv.reconciled) {
            throw Err("Teleport inventory not reconciled. Open the Bag once while online.");
        }
        var bal = getSecureBalance(inv, itemId);
        if (bal < 1) {
            if (itemId === TELEPORT_ITEM_ID)
                throw Err("No Advanced Teleport remaining.");
            if (itemId === PEACE_SHIELD_INV_ITEM_ID)
                throw Err("No Peace Shields available.");
            if (itemId === ANTI_SCOUT_INV_ITEM_ID)
                throw Err("No Anti-Scout items available.");
            throw Err("No items remaining.");
        }
        setSecureBalance(inv, itemId, bal - 1);
        inv.updated_at = nowUnix();
        try {
            storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, userId, userId, inv, invObj.version, 1);
            return getSecureBalance(inv, itemId);
        }
        catch (_e) {
            // retry OCC
        }
    }
    throw Err("Secure inventory busy. Try again.");
}
function refundSecureItemCAS(nk, userId, itemId) {
    if (!isSecureConsumableItemId(itemId))
        throw Err("Unsupported secure consumable.");
    for (var attempt = 0; attempt < 8; attempt++) {
        var invObj = readTeleportInvObj(nk, userId);
        var inv = normalizeInvRecord(invObj.value, userId);
        setSecureBalance(inv, itemId, getSecureBalance(inv, itemId) + 1);
        inv.updated_at = nowUnix();
        try {
            storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, userId, userId, inv, invObj.version, 1);
            return getSecureBalance(inv, itemId);
        }
        catch (_e) {
            // retry
        }
    }
    throw Err("Failed to refund secure consumable.");
}
/** TRUSTED INTERNAL — beta/admin grant into authoritative inventory. Never trust client counts. */
function trustedGrantSecureConsumableCAS(nk, userId, itemId, amount) {
    if (!isSecureConsumableItemId(itemId))
        throw Err("Unsupported secure consumable.");
    var add = Math.max(0, Math.floor(amount));
    if (add <= 0)
        throw Err("amount must be a positive integer.");
    if (add > 99)
        throw Err("amount exceeds max grant.");
    for (var attempt = 0; attempt < 8; attempt++) {
        var invObj = readTeleportInvObj(nk, userId);
        var inv = normalizeInvRecord(invObj.value, userId);
        // Grants also mark the item reconciled so use is possible without bag import.
        if (!isSecureItemReconciled(inv, itemId)) {
            markSecureItemReconciled(inv, itemId, "grant_v1:" + String(add) + ":" + String(nowUnix()));
        }
        var next = getSecureBalance(inv, itemId) + add;
        setSecureBalance(inv, itemId, next);
        inv.updated_at = nowUnix();
        try {
            storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, userId, userId, inv, invObj.version, 1);
            return getSecureBalance(inv, itemId);
        }
        catch (_e) {
            // retry
        }
    }
    throw Err("Secure inventory grant busy.");
}
function consumeInventoryCAS(nk, userId) {
    return consumeSecureItemCAS(nk, userId, TELEPORT_ITEM_ID);
}
function refundInventoryCAS(nk, userId) {
    return refundSecureItemCAS(nk, userId, TELEPORT_ITEM_ID);
}
function advanceTeleportSaga(nk, logger, profile, opObj, requestId) {
    var op = opObj.value;
    var opVersion = opObj.version;
    var kingdomId = String(op.kingdom_id || profile.kingdom_id || DEV_KINGDOM_ID);
    var worldX = Number(op.world_x);
    var worldY = Number(op.world_y);
    var oldX = Number(op.old_world_x);
    var oldY = Number(op.old_world_y);
    function persistOp(nextState, extra) {
        op = Object.assign({}, op, extra || {}, { state: nextState, updated_at: nowUnix() });
        writeOpObj(nk, profile.user_id, requestId, op, opVersion);
        var refreshed = readOpObj(nk, profile.user_id, requestId);
        if (!refreshed)
            throw Err("Teleport operation lost.");
        op = refreshed.value;
        opVersion = refreshed.version;
    }
    if (op.state === OP_COMPLETED && op.result)
        return op.result;
    if (op.state === OP_FAILED) {
        throw Err(String(op.error || "Teleport previously failed."));
    }
    var lock = acquireKingdomLock(nk, kingdomId, profile.user_id, requestId);
    if (!lock.ok)
        throw Err(lock.error);
    try {
        // Re-validate under lock for every non-terminal resume.
        if (op.state === OP_PENDING || op.state === OP_INV_CONSUMED) {
            if (userHasServerDeployments(nk, profile.user_id)) {
                throw Err("Cannot teleport while troops are deployed.");
            }
            if (userInActiveRally(nk, logger, profile.user_id, String(profile.alliance_id || ""))) {
                throw Err("Cannot teleport while in an active rally.");
            }
            var reg = readRegistryObj(nk, kingdomId).value;
            var check = validateCastleCandidateServer(kingdomId, worldX, worldY, Array.isArray(reg.castles) ? reg.castles : [], profile.user_id);
            if (!check.ok)
                throw Err(check.error);
        }
        if (op.state === OP_PENDING) {
            var newBal = consumeInventoryCAS(nk, profile.user_id);
            persistOp(OP_INV_CONSUMED, { balance_after_consume: newBal });
        }
        if (op.state === OP_INV_CONSUMED) {
            applyRegistryMove(nk, profile, worldX, worldY);
            persistOp(OP_REGISTRY_UPDATED, {});
        }
        if (op.state === OP_REGISTRY_UPDATED) {
            profile.world_x = worldX;
            profile.world_y = worldY;
            profile.updated_at = nowUnix();
            writeProfile(nk, profile);
            persistOp(OP_PROFILE_UPDATED, {});
        }
        if (op.state === OP_PROFILE_UPDATED || op.state === OP_REGISTRY_UPDATED) {
            // Ensure profile matches registry even if we landed mid-stage.
            if (Number(profile.world_x) !== worldX || Number(profile.world_y) !== worldY) {
                profile.world_x = worldX;
                profile.world_y = worldY;
                profile.updated_at = nowUnix();
                writeProfile(nk, profile);
            }
            var invObj = readTeleportInvObj(nk, profile.user_id);
            var balance = getTeleportBalance(invObj.value);
            var result = {
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
            notifyKingdomCastleMoved(nk, logger, kingdomId, profile.user_id, worldX, worldY, profile.display_name || "Player");
            return result;
        }
        throw Err("Unknown teleport operation state.");
    }
    catch (e) {
        var msg = e instanceof Error ? String(e.message || e) : String(e);
        try {
            // Compensate based on durable stage.
            if (op.state === OP_PROFILE_UPDATED) {
                // Profile+registry already moved; finish as completed rather than unwind.
                var invObj = readTeleportInvObj(nk, profile.user_id);
                var result = {
                    ok: true,
                    request_id: requestId,
                    kingdom_id: kingdomId,
                    world_x: worldX,
                    world_y: worldY,
                    item_id: TELEPORT_ITEM_ID,
                    balance: getTeleportBalance(invObj.value),
                    contract_id: MAP_CONTRACT_ID,
                    notif_code: CASTLE_MOVED_NOTIF_CODE,
                };
                persistOp(OP_COMPLETED, { result: result, ok: true });
                return result;
            }
            if (op.state === OP_REGISTRY_UPDATED) {
                restoreRegistryCoords(nk, profile, oldX, oldY);
                profile.world_x = oldX;
                profile.world_y = oldY;
                writeProfile(nk, profile);
                refundInventoryCAS(nk, profile.user_id);
                persistOp(OP_FAILED, { ok: false, error: msg });
            }
            else if (op.state === OP_INV_CONSUMED) {
                refundInventoryCAS(nk, profile.user_id);
                persistOp(OP_FAILED, { ok: false, error: msg });
            }
            else if (op.state === OP_PENDING) {
                // No irreversible side effects yet — keep pending so the same request_id can resume.
            }
            else {
                persistOp(OP_FAILED, { ok: false, error: msg });
            }
        }
        catch (compErr) {
            logger.error("teleport compensate failed: %s", String(compErr));
        }
        throw Err(msg);
    }
    finally {
        releaseKingdomLock(nk, kingdomId, profile.user_id, requestId);
    }
}
function rpcTeleportInventorySync(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    ensureProfile(nk, logger, ctx.userId);
    var body = {};
    try {
        body = payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid JSON");
    }
    if (!Object.prototype.hasOwnProperty.call(body, "local_count"))
        throw Err("Missing local_count.");
    if (!isStrictNonNegInt(body.local_count))
        throw Err("local_count must be a non-negative integer.");
    var clientCount = body.local_count;
    // SECURITY: Peace Shield / Anti-Scout must NEVER be imported from client Bag counts.
    // local_counts (if present) are ignored for balance mutation — grant-only inventory.
    // Advanced Teleport keeps historical one-time bag reconcile via local_count only.
    for (var attempt = 0; attempt < 8; attempt++) {
        var invObj = readTeleportInvObj(nk, ctx.userId);
        var rec = normalizeInvRecord(invObj.value, ctx.userId);
        var dirty = false;
        if (!rec.reconciled) {
            setTeleportBalance(rec, clientCount);
            markSecureItemReconciled(rec, TELEPORT_ITEM_ID, "bag_v1:" + String(clientCount) + ":" + String(nowUnix()));
            dirty = true;
            logger.info("Teleport inventory reconciled user=%s imported=%d", ctx.userId, clientCount);
        }
        if (dirty) {
            rec.updated_at = nowUnix();
            try {
                storageWriteVersioned(nk, TELEPORT_INV_COLLECTION, ctx.userId, ctx.userId, rec, invObj.version, 1);
            }
            catch (_e) {
                continue;
            }
        }
        var latest = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
        return JSON.stringify({
            ok: true,
            item_id: TELEPORT_ITEM_ID,
            balance: getTeleportBalance(latest),
            reconciled: true,
            balances: publicSecureBalances(latest),
            item_reconciled: publicSecureReconciled(latest),
            // Explicit: client bag claims for PvP protection items are not authoritative.
            protection_bag_import: false,
            contract_id: MAP_CONTRACT_ID,
        });
    }
    throw Err("Teleport inventory sync busy.");
}
function rpcTeleportInventoryGet(ctx, _logger, nk, _payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var rec = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
    return JSON.stringify({
        ok: true,
        item_id: TELEPORT_ITEM_ID,
        balance: getTeleportBalance(rec),
        reconciled: !!rec.reconciled,
        balances: publicSecureBalances(rec),
        item_reconciled: publicSecureReconciled(rec),
        protection_bag_import: false,
    });
}
/**
 * CLOSED BETA ONLY — grant allowlisted Peace Shield / Anti-Scout into authoritative inventory.
 *
 * Registration gate (InitModule): CROWNSPIRE_ENABLE_BETA_GRANTS must be exactly "true".
 * Auth gate: CROWNSPIRE_BETA_GRANT_SECRET must be non-empty and match payload.dev_secret.
 * Neither value is shipped to Godot/clients. Ordinary clients cannot enable this.
 * Grants bind to ctx.userId only (forged target rejected).
 */
function rpcDevGrantSecureConsumable(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    if (!isBetaSecureGrantsEnabled(ctx)) {
        throw Err("Forbidden");
    }
    var expectedSecret = getBetaGrantSecret(ctx);
    if (!expectedSecret) {
        throw Err("Forbidden");
    }
    var data = {};
    try {
        data = payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid JSON");
    }
    var provided = String(data["dev_secret"] || "");
    if (provided.length < 16 || provided !== expectedSecret) {
        throw Err("Forbidden");
    }
    var itemId = String(data["item_id"] || "").trim();
    if (itemId !== PEACE_SHIELD_INV_ITEM_ID && itemId !== ANTI_SCOUT_INV_ITEM_ID) {
        throw Err("Unsupported item_id for secure grant.");
    }
    if (!isStrictNonNegInt(data["amount"]) || data["amount"] < 1) {
        throw Err("amount must be a positive integer.");
    }
    var forged = String(data["user_id"] || data["target_user_id"] || "").trim();
    if (forged !== "" && forged !== ctx.userId) {
        throw Err("Cannot grant secure consumables to another user via this RPC.");
    }
    ensureProfile(nk, logger, ctx.userId);
    var balance = trustedGrantSecureConsumableCAS(nk, ctx.userId, itemId, data["amount"]);
    // Do not log secrets. Log item id + resulting balance only.
    logger.info("Beta secure grant user=%s item=%s balance=%d", ctx.userId, itemId, balance);
    var rec = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
    return JSON.stringify({
        ok: true,
        item_id: itemId,
        balance: balance,
        balances: publicSecureBalances(rec),
        item_reconciled: publicSecureReconciled(rec),
    });
}
function isBetaSecureGrantsEnabled(ctx) {
    var env = ctx && ctx.env ? ctx.env : {};
    return String(env["CROWNSPIRE_ENABLE_BETA_GRANTS"] || "") === "true";
}
function getBetaGrantSecret(ctx) {
    var env = ctx && ctx.env ? ctx.env : {};
    return String(env["CROWNSPIRE_BETA_GRANT_SECRET"] || "");
}
/** Additive deployment ledger — clients cannot wipe deployments in one call. */
function rpcTeleportDeploymentBegin(ctx, _logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var body = {};
    try {
        body = payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid JSON");
    }
    var deploymentId = trimStr(body.deployment_id || "");
    var kind = trimStr(body.kind || "");
    if (deploymentId.length < 8 || deploymentId.length > 80)
        throw Err("Invalid deployment_id.");
    if (kind !== "march" && kind !== "gather" && kind !== "rally" && kind !== "reinforce") {
        throw Err("Invalid deployment kind.");
    }
    for (var attempt = 0; attempt < 8; attempt++) {
        var obj = readDeployObj(nk, ctx.userId);
        var val = obj.value;
        var list = Array.isArray(val.deployments) ? val.deployments.slice() : [];
        var found = false;
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].deployment_id) === deploymentId) {
                found = true;
                break;
            }
        }
        if (!found)
            list.push({ deployment_id: deploymentId, kind: kind, started_at: nowUnix() });
        val.deployments = list;
        val.updated_at = nowUnix();
        try {
            storageWriteVersioned(nk, TELEPORT_DEPLOY_COLLECTION, ctx.userId, ctx.userId, val, obj.version, 1);
            return JSON.stringify({ ok: true, deployments: list });
        }
        catch (_e) {
            // retry
        }
    }
    throw Err("Deployment begin busy.");
}
function rpcTeleportDeploymentEnd(ctx, _logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var body = {};
    try {
        body = payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid JSON");
    }
    var deploymentId = trimStr(body.deployment_id || "");
    if (deploymentId.length < 8 || deploymentId.length > 80)
        throw Err("Invalid deployment_id.");
    for (var attempt = 0; attempt < 8; attempt++) {
        var obj = readDeployObj(nk, ctx.userId);
        var val = obj.value;
        var list = Array.isArray(val.deployments) ? val.deployments : [];
        var next = [];
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].deployment_id) !== deploymentId)
                next.push(list[i]);
        }
        val.deployments = next;
        val.updated_at = nowUnix();
        try {
            storageWriteVersioned(nk, TELEPORT_DEPLOY_COLLECTION, ctx.userId, ctx.userId, val, obj.version, 1);
            return JSON.stringify({ ok: true, deployments: next });
        }
        catch (_e) {
            // retry
        }
    }
    throw Err("Deployment end busy.");
}
/** Removed insecure clear-all troop activity writer. Kept name rejected. */
function rpcSetTroopActivity(ctx, _logger, _nk, _payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    throw Err("crownspire_set_troop_activity is retired. Use deployment begin/end.");
}
function rpcCityTeleportRelocate(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var body = {};
    try {
        body = payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid JSON");
    }
    var requestId = trimStr(body.request_id || "");
    if (requestId.length < 8 || requestId.length > 80)
        throw Err("Missing request_id.");
    var itemId = trimStr(body.item_id || TELEPORT_ITEM_ID);
    if (itemId !== TELEPORT_ITEM_ID)
        throw Err("Unsupported teleport item.");
    if (!Object.prototype.hasOwnProperty.call(body, "world_x") || !Object.prototype.hasOwnProperty.call(body, "world_y")) {
        throw Err("Missing coordinates.");
    }
    if (typeof body.world_x !== "number" || typeof body.world_y !== "number") {
        throw Err("Coordinates must be numbers.");
    }
    var worldX = body.world_x;
    var worldY = body.world_y;
    if (!isFinite(worldX) || !isFinite(worldY) || isNaN(worldX) || isNaN(worldY)) {
        throw Err("Invalid coordinates.");
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    ensureCastleCoords(nk, profile);
    var kingdomId = String(profile.kingdom_id || DEV_KINGDOM_ID);
    if (Object.prototype.hasOwnProperty.call(body, "kingdom_id")) {
        var claimed = trimStr(body.kingdom_id);
        if (claimed !== kingdomId)
            throw Err("Cannot teleport outside your current kingdom.");
    }
    var opObj = readOpObj(nk, ctx.userId, requestId);
    if (!opObj) {
        var createVal = {
            request_id: requestId,
            user_id: ctx.userId,
            kingdom_id: kingdomId,
            item_id: itemId,
            world_x: Math.floor(worldX),
            world_y: Math.floor(worldY),
            old_world_x: Number(profile.world_x),
            old_world_y: Number(profile.world_y),
            state: OP_PENDING,
            created_at: nowUnix(),
            updated_at: nowUnix(),
            contract_id: MAP_CONTRACT_ID,
        };
        try {
            writeOpObj(nk, ctx.userId, requestId, createVal, "*");
        }
        catch (_e) {
            // Another worker created it — read existing.
        }
        opObj = readOpObj(nk, ctx.userId, requestId);
        if (!opObj)
            throw Err("Failed to create teleport operation.");
    }
    var existing = opObj.value;
    if (existing.state === OP_COMPLETED && existing.result) {
        return JSON.stringify(existing.result);
    }
    if (existing.state === OP_FAILED) {
        throw Err(String(existing.error || "Teleport previously failed."));
    }
    var result = advanceTeleportSaga(nk, logger, profile, opObj, requestId);
    return JSON.stringify(result);
}
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
var PEACE_SHIELD_ITEM_ID = "boost_shield_peace_3d";
var ANTI_SCOUT_ITEM_ID = "boost_anti_scout_24h";
/** Design duration from Items.json — used only by trusted helpers / use RPCs, never client-supplied. */
var PEACE_SHIELD_DURATION_SEC = 3 * 24 * 60 * 60;
var ANTI_SCOUT_DURATION_SEC = 24 * 60 * 60;
var INV_AUTHORITY_REQUIRED = "Server inventory authority is required before this protection can be activated.";
/**
 * Guard for free/arbitrary activate payloads (no inventory spend).
 * Legitimate activation is crownspire_use_peace_shield / crownspire_use_anti_scout only.
 */
function protectionActive(expiresAt, now) {
    var exp = typeof expiresAt === "number" ? expiresAt : 0;
    return exp > now;
}
function hostileTargetSnapshot(profile, now) {
    var peaceExp = typeof profile.peace_shield_expires_at === "number"
        ? profile.peace_shield_expires_at
        : 0;
    var antiExp = typeof profile.anti_scout_expires_at === "number"
        ? profile.anti_scout_expires_at
        : 0;
    var begExp = typeof profile.beginner_protection_expires_at === "number"
        ? profile.beginner_protection_expires_at
        : 0;
    var begCleared = Boolean(profile.beginner_protection_cleared);
    return {
        user_id: profile.user_id,
        display_name: profile.display_name || "",
        kingdom_id: profile.kingdom_id || "",
        alliance_id: profile.alliance_id || "",
        alliance_tag: profile.alliance_tag || "",
        alliance_name: profile.alliance_name || "",
        world_x: typeof profile.world_x === "number" ? profile.world_x : 0,
        world_y: typeof profile.world_y === "number" ? profile.world_y : 0,
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
function evaluateHostileAction(action, attacker, target, now) {
    var act = String(action || "").trim().toLowerCase();
    if (act !== "attack" && act !== "scout") {
        return { ok: false, code: "invalid_action", reason: "Unsupported hostile action." };
    }
    if (!target || !target.user_id) {
        return { ok: false, code: "invalid_target", reason: "Target castle could not be resolved." };
    }
    if (attacker.user_id === target.user_id) {
        return { ok: false, code: "self", reason: "Cannot target your own city." };
    }
    var aAlliance = String(attacker.alliance_id || "").trim();
    var tAlliance = String(target.alliance_id || "").trim();
    if (aAlliance !== "" && tAlliance !== "" && aAlliance === tAlliance) {
        return {
            ok: false,
            code: "same_alliance",
            reason: act === "scout" ? "Cannot scout an alliance member." : "Cannot attack an alliance member.",
        };
    }
    var snap = hostileTargetSnapshot(target, now);
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
function rejectClientProtectionActivation(kind, ctxUserId, payload) {
    var data = payload && typeof payload === "object" ? payload : {};
    var forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
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
    var label = kind === "anti_scout" ? "Anti-Scout (" + ANTI_SCOUT_ITEM_ID + ")" : "Peace Shield (" + PEACE_SHIELD_ITEM_ID + ")";
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
function planBeginnerProtectionClientMutation(ctxUserId, payload, profile, now) {
    var data = payload && typeof payload === "object" ? payload : {};
    var forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
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
function rpcValidateHostileAction(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = {};
    try {
        data = payload ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid payload");
    }
    var action = String(data["action"] || "").trim().toLowerCase();
    var targetId = String(data["target_user_id"] || data["user_id"] || "").trim();
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
    var attacker = ensureProfile(nk, logger, ctx.userId);
    var target;
    try {
        target = ensureProfile(nk, logger, targetId);
    }
    catch (_e) {
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: "stale_target",
            reason: "Target castle is no longer available.",
            error: "Target castle is no longer available.",
        });
    }
    var now = nowUnix();
    var gate = evaluateHostileAction(action, attacker, target, now);
    var snap = hostileTargetSnapshot(target, now);
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
function rpcClearOwnBeginnerProtection(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = {};
    try {
        data = payload ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid payload");
    }
    // Force clear-only semantics regardless of client payload extras.
    var clearPayload = { clear: true };
    var forged = String(data["target_user_id"] || data["user_id"] || "").trim();
    if (forged !== "" && forged !== ctx.userId) {
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: "forbidden_target",
            reason: "Cannot modify another player's protection.",
            error: "Cannot modify another player's protection.",
        });
    }
    var profile = ensureProfile(nk, logger, ctx.userId);
    var now = nowUnix();
    var plan = planBeginnerProtectionClientMutation(ctx.userId, clearPayload, profile, now);
    if (!plan.ok || !plan.clear) {
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: plan.code,
            reason: plan.reason,
            error: plan.reason,
        });
    }
    var before = typeof profile.beginner_protection_expires_at === "number"
        ? profile.beginner_protection_expires_at
        : 0;
    profile.beginner_protection_expires_at = 0;
    profile.beginner_protection_cleared = true;
    // Invariant: clear must never increase expiry.
    if (profile.beginner_protection_expires_at > before) {
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
function trustedApplyPeaceShield(profile, now, durationSec) {
    var dur = durationSec > 0 ? Math.floor(durationSec) : PEACE_SHIELD_DURATION_SEC;
    var current = typeof profile.peace_shield_expires_at === "number"
        ? profile.peace_shield_expires_at
        : 0;
    var base = Math.max(now, current);
    profile.peace_shield_expires_at = base + dur;
    profile.updated_at = now;
}
/**
 * TRUSTED INTERNAL ONLY — never register as a public client RPC.
 * PRODUCT stacking = EXTEND (same as Peace Shield).
 */
function trustedApplyAntiScout(profile, now, durationSec) {
    var dur = durationSec > 0 ? Math.floor(durationSec) : ANTI_SCOUT_DURATION_SEC;
    var current = typeof profile.anti_scout_expires_at === "number"
        ? profile.anti_scout_expires_at
        : 0;
    var base = Math.max(now, current);
    profile.anti_scout_expires_at = base + dur;
    profile.updated_at = now;
}
function parseProtectionUsePayload(payload) {
    try {
        return payload && payload.length > 0 ? JSON.parse(payload) : {};
    }
    catch (_e) {
        throw Err("Invalid payload");
    }
}
function rejectForgedProtectionUseFields(ctxUserId, data) {
    var forgedTarget = String(data["target_user_id"] || data["user_id"] || "").trim();
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
function rpcUsePeaceShield(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parseProtectionUsePayload(payload);
    var forged = rejectForgedProtectionUseFields(ctx.userId, data);
    if (forged)
        return JSON.stringify(Object.assign({ authority_verified: true }, forged));
    var invProbe = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
    if (getSecureBalance(invProbe, PEACE_SHIELD_ITEM_ID) < 1) {
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: "insufficient",
            reason: "No Peace Shields available.",
            error: "No Peace Shields available.",
        });
    }
    var remaining = 0;
    try {
        remaining = consumeSecureItemCAS(nk, ctx.userId, PEACE_SHIELD_ITEM_ID);
    }
    catch (e) {
        var msg = e instanceof Error ? String(e.message || e) : String(e);
        var code = msg.indexOf("No Peace Shields") >= 0 ? "insufficient" : "inventory_busy";
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: code,
            reason: msg.indexOf("No Peace Shields") >= 0 ? "No Peace Shields available." : "Unable to activate Peace Shield right now.",
            error: msg.indexOf("No Peace Shields") >= 0 ? "No Peace Shields available." : "Unable to activate Peace Shield right now.",
        });
    }
    try {
        var profile = ensureProfile(nk, logger, ctx.userId);
        var now = nowUnix();
        trustedApplyPeaceShield(profile, now, PEACE_SHIELD_DURATION_SEC);
        writeProfile(nk, profile);
        upsertKingdomCastleEntry(nk, profile);
        var expiresAt = Number(profile.peace_shield_expires_at || 0);
        logger.info("Peace Shield used user=%s expires_at=%d remaining=%d", ctx.userId, expiresAt, remaining);
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
    }
    catch (e) {
        try {
            refundSecureItemCAS(nk, ctx.userId, PEACE_SHIELD_ITEM_ID);
        }
        catch (refundErr) {
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
function rpcUseAntiScout(ctx, logger, nk, payload) {
    if (!ctx.userId)
        throw Err("Unauthenticated");
    var data = parseProtectionUsePayload(payload);
    var forged = rejectForgedProtectionUseFields(ctx.userId, data);
    if (forged)
        return JSON.stringify(Object.assign({ authority_verified: true }, forged));
    var invProbe = normalizeInvRecord(readTeleportInvObj(nk, ctx.userId).value, ctx.userId);
    if (getSecureBalance(invProbe, ANTI_SCOUT_ITEM_ID) < 1) {
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: "insufficient",
            reason: "No Anti-Scout items available.",
            error: "No Anti-Scout items available.",
        });
    }
    var remaining = 0;
    try {
        remaining = consumeSecureItemCAS(nk, ctx.userId, ANTI_SCOUT_ITEM_ID);
    }
    catch (e) {
        var msg = e instanceof Error ? String(e.message || e) : String(e);
        var insufficient = msg.indexOf("No Anti-Scout") >= 0;
        return JSON.stringify({
            ok: false,
            authority_verified: true,
            code: insufficient ? "insufficient" : "inventory_busy",
            reason: insufficient ? "No Anti-Scout items available." : "Unable to activate Anti-Scout right now.",
            error: insufficient ? "No Anti-Scout items available." : "Unable to activate Anti-Scout right now.",
        });
    }
    try {
        var profile = ensureProfile(nk, logger, ctx.userId);
        var now = nowUnix();
        trustedApplyAntiScout(profile, now, ANTI_SCOUT_DURATION_SEC);
        writeProfile(nk, profile);
        upsertKingdomCastleEntry(nk, profile);
        var expiresAt = Number(profile.anti_scout_expires_at || 0);
        logger.info("Anti-Scout used user=%s expires_at=%d remaining=%d", ctx.userId, expiresAt, remaining);
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
    }
    catch (e) {
        try {
            refundSecureItemCAS(nk, ctx.userId, ANTI_SCOUT_ITEM_ID);
        }
        catch (refundErr) {
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
function trustedSetBeginnerProtection(profile, now, opts) {
    if (opts.clear === true) {
        profile.beginner_protection_expires_at = 0;
        profile.beginner_protection_cleared = true;
    }
    else if (typeof opts.expires_at === "number") {
        profile.beginner_protection_expires_at = Math.floor(opts.expires_at);
        profile.beginner_protection_cleared =
            profile.beginner_protection_expires_at <= now;
    }
    else if (typeof opts.duration_sec === "number" && opts.duration_sec > 0) {
        profile.beginner_protection_expires_at = now + Math.floor(opts.duration_sec);
        profile.beginner_protection_cleared = false;
    }
    profile.updated_at = now;
}
/**
 * Crownspire Phase 6 — Direct Message RPC delivery.
 *
 * Private messages are sent through an authenticated Nakama RPC instead of
 * relying on the recipient already being subscribed to a DirectMessage socket
 * channel. The server builds the authoritative DM channel, persists the
 * message, and sends a delivery notification to the recipient.
 *
 * Notification code 5004 is reserved for DM delivery (not Rally 5002 / Help 5001 /
 * Alliance 5003 / Castle 5005).
 */
var DM_NOTIF_CODE = 5004;
var DM_MAX_TEXT_LENGTH = 280;
var DM_SUPPORTED_TYPES = {
    TEXT: true,
    MAP_LOCATION: true,
    RALLY: true,
};
function rpcDmSend(ctx, logger, nk, payload) {
    if (!ctx.userId) {
        throw new Error("Unauthenticated");
    }
    var data = parsePayload(payload);
    var recipientId = String(data.recipient_user_id || "").trim();
    if (recipientId === "" || recipientId === ctx.userId) {
        throw new Error("Invalid DM recipient");
    }
    // Verify the recipient is a real Nakama account before creating a thread.
    var recipients = nk.usersGetId([recipientId]);
    if (!recipients || recipients.length !== 1) {
        throw new Error("Player not found");
    }
    var messageType = String(data.message_type || "TEXT").trim().toUpperCase();
    if (!DM_SUPPORTED_TYPES[messageType]) {
        throw new Error("Unsupported DM message type");
    }
    var text = String(data.text || "").trim();
    if (messageType === "TEXT" && text === "") {
        throw new Error("Message is empty");
    }
    if (text.length > DM_MAX_TEXT_LENGTH) {
        throw new Error("Message exceeds 280 characters");
    }
    var messagePayload = (data.payload && typeof data.payload === "object") ? data.payload : {};
    // Keep structured payloads bounded. This is validation, not authority for gameplay actions.
    var payloadJson = JSON.stringify(messagePayload);
    if (payloadJson.length > 4096) {
        throw new Error("DM payload too large");
    }
    // 1s sender→recipient cooldown (preserves old RtAfter notify window; key cannot
    // collide with rally_*/help_*/dm_notify_* because assertRateLimit keys by action).
    assertRateLimit(nk, ctx.userId, "dm_send_" + recipientId, 1);
    // Server-backed identity: never trust display name or alliance tag supplied by the client.
    var profile = ensureProfile(nk, logger, ctx.userId);
    var senderName = String(profile.display_name || "Player").substring(0, 64);
    var allianceTag = String(profile.alliance_tag || "").substring(0, 8);
    var kingdomId = String(profile.kingdom_id || "");
    // DirectMessage == 2. Nakama canonicalizes the channel for this sender/recipient pair.
    var channelId = nk.channelIdBuild(ctx.userId, recipientId, 2);
    var content = {
        v: 1,
        message_type: messageType,
        text: text,
        sender_display_name: senderName,
        sender_alliance_tag: allianceTag,
        kingdom_id: kingdomId,
        payload: messagePayload,
        metadata: {
            client_schema: 1,
            tag_authority: "alliance_backend",
            display_name_authority: "alliance_backend",
            delivery_authority: "crownspire_dm_send_rpc",
        },
    };
    var ack = nk.channelMessageSend(channelId, content, ctx.userId, undefined, true);
    var preview = text.substring(0, 120);
    var notifContent = {
        sender_user_id: ctx.userId,
        sender_display_name: senderName,
        preview: preview,
        channel_id: channelId,
        message_id: String(ack.messageId || ""),
    };
    try {
        nk.notificationSend(recipientId, "Direct Message", notifContent, DM_NOTIF_CODE, null, true);
    }
    catch (e) {
        // Message persistence already succeeded. Log notification failure so the recipient
        // can still recover the DM through history on reconnect/open.
        logger.warn("DM delivery notification failed recipient=%s err=%s", recipientId, String(e));
    }
    return JSON.stringify({
        ok: true,
        channel_id: channelId,
        message_id: String(ack.messageId || ""),
        create_time: String(ack.createTime || ""),
    });
}
