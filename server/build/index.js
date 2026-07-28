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
    logger.info("Crownspire runtime loaded (Phase 3+4+5+5.1 identity/alliance/help/social). LOCAL DEVELOPMENT ONLY.");
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
        // Refresh alliance fields from live group membership.
        return syncAllianceFields(nk, logger, normalized);
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
    writeProfile(nk, created);
    logger.info("Created Crownspire profile for %s kingdom=%s", userId, DEV_KINGDOM_ID);
    return created;
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
    return {
        user_id: profile.user_id,
        display_name: profile.display_name,
        kingdom_id: profile.kingdom_id,
        alliance_id: profile.alliance_id,
        alliance_tag: profile.alliance_tag,
        alliance_name: profile.alliance_name,
        crownspire_rank: profile.crownspire_rank,
        avatar_id: profile.avatar_id || "avatar_01",
        power: typeof profile.power === "number" ? profile.power : 0,
        citadel_level: typeof profile.citadel_level === "number" ? profile.citadel_level : 1,
        vip_level: typeof profile.vip_level === "number" ? profile.vip_level : 0,
        last_online: lastOnline,
        online_status: online ? "online" : "offline",
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
    var description = "Crownspire development alliance";
    // Private group: join requires approval (join request workflow).
    var metadata = {
        alliance_tag: tag,
        kingdom_id: profile.kingdom_id || DEV_KINGDOM_ID,
        crownspire: true,
    };
    var group = nk.groupCreate(ctx.userId, name, ctx.userId, null, description, null, false, // open = false (private) — join creates a request
    metadata, 50);
    writeRank(nk, group.id, ctx.userId, "R5");
    writeAllianceMeta(nk, {
        alliance_id: group.id,
        description: description,
        language: "en",
        join_type: "apply",
        min_join_power_placeholder: 0,
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
    logger.info("Alliance created group=%s tag=%s by %s", group.id, tag, ctx.userId);
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
    // Validate group exists and is a Crownspire alliance.
    var groups = nk.groupsGetId([groupId]);
    if (!groups || groups.length === 0) {
        throw Err("Alliance not found");
    }
    var group = groups[0];
    var meta = safeJson(group.metadata || {});
    if (!meta["crownspire"] && !meta["alliance_tag"]) {
        throw Err("Not a Crownspire alliance group");
    }
    // Private group -> creates join request. Does NOT grant chat access until approved.
    nk.groupUserJoin(groupId, ctx.userId, ctx.username || "");
    logger.info("Alliance join requested group=%s user=%s", groupId, ctx.userId);
    return JSON.stringify({
        ok: true,
        pending: true,
        alliance_id: groupId,
        message: "Join request submitted. Awaiting approval.",
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
            power_placeholder: 0,
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
    R5: "Lord Paramount",
    R4: "Marshal",
    R3: "Officer",
    R2: "Member",
    R1: "Recruit",
};
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
    if (objects && objects.length > 0 && objects[0].value) {
        return objects[0].value;
    }
    return {
        alliance_id: allianceId,
        description: "",
        language: "en",
        join_type: "apply",
        min_join_power_placeholder: 0,
        emblem_placeholder: "",
        banner_placeholder: "",
        alliance_power_placeholder: 0,
        alliance_level_placeholder: 1,
        updated_at: nowUnix(),
    };
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
    return {
        alliance_id: String(group.id),
        name: String(group.name || ""),
        tag: String(meta["alliance_tag"] || ""),
        description: stored.description || String(group.description || ""),
        language: stored.language || "en",
        join_type: stored.join_type || "apply",
        min_join_power_placeholder: stored.min_join_power_placeholder || 0,
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
    var query = String(data["query"] || "").trim();
    // groupsList(name?, langTag?, open?, members?, limit?, cursor?)
    var result = nk.groupsList(query !== "" ? query : undefined, undefined, undefined, undefined, 20, undefined);
    var groups = result.groups || [];
    var out = [];
    for (var i = 0; i < groups.length; i++) {
        var g = groups[i];
        var meta = safeJson(g.metadata || {});
        if (!meta["crownspire"] && !meta["alliance_tag"])
            continue;
        out.push({
            alliance_id: String(g.id),
            name: String(g.name || ""),
            tag: String(meta["alliance_tag"] || ""),
            member_count: Number(g.edgeCount || 0),
            member_limit: Number(g.maxCount || DEFAULT_MEMBER_LIMIT),
            join_type: "apply",
            kingdom_id: String(meta["kingdom_id"] || DEV_KINGDOM_ID),
            open: !!g.open,
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
    if (data["description"] !== undefined) {
        meta.description = String(data["description"] || "").substring(0, 280).replace(/[\u0000-\u001F\u007F]/g, "");
    }
    if (data["language"] !== undefined) {
        meta.language = String(data["language"] || "en").substring(0, 8);
    }
    if (data["join_type"] !== undefined) {
        var jt = String(data["join_type"] || "apply");
        if (jt !== "apply" && jt !== "invite_only")
            throw Err("Invalid join_type");
        meta.join_type = jt;
    }
    writeAllianceMeta(nk, meta);
    // Optional description mirror onto Nakama group.
    try {
        nk.groupUpdate(profile.alliance_id, ctx.userId, null, null, meta.description || null, null, null, null, null);
    }
    catch (e) {
        logger.warn("groupUpdate description failed: %s", String(e));
    }
    var groups = nk.groupsGetId([profile.alliance_id]);
    return JSON.stringify({
        ok: true,
        alliance: groups && groups.length ? buildAllianceProfile(nk, logger, groups[0]) : meta,
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
    return JSON.stringify({
        ok: true,
        last_online: profile.last_online,
        online_status: "online",
        profile: publicProfile(profile),
    });
}
