/**
 * Crownspire Phase 4 — Alliance roster / ranks / applications / invites / permissions
 * LOCAL DEVELOPMENT ONLY. Concatenated into build/index.js via tsconfig files order.
 */

const INVITE_COLLECTION = "crownspire_alliance_invites";
const ALLIANCE_META_COLLECTION = "crownspire_alliance_meta";
const INVITE_EXPIRY_SEC = 7 * 24 * 3600;
const DEFAULT_MEMBER_LIMIT = 50;

const RANK_ORDER: { [key: string]: number } = {
  R1: 1,
  R2: 2,
  R3: 3,
  R4: 4,
  R5: 5,
};

const ROLE_DISPLAY: { [key: string]: string } = {
  R5: "Lord Paramount",
  R4: "Marshal",
  R3: "Officer",
  R2: "Member",
  R1: "Recruit",
};

/** Configurable Phase-4 permission policy (server-authoritative). */
const RANK_PERMISSIONS: { [rank: string]: { [perm: string]: boolean } } = {
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

interface AllianceInvite {
  invite_id: string;
  alliance_id: string;
  alliance_name: string;
  alliance_tag: string;
  inviter_user_id: string;
  target_user_id: string;
  created_at: number;
  expires_at: number;
  status: string; // pending | accepted | rejected | expired | cancelled
}

interface AllianceMeta {
  alliance_id: string;
  description: string;
  language: string;
  join_type: string; // apply | invite_only | open (open reserved)
  min_join_power_placeholder: number;
  emblem_placeholder: string;
  banner_placeholder: string;
  alliance_power_placeholder: number;
  alliance_level_placeholder: number;
  updated_at: number;
}

function registerPhase4AllianceRpcs(_initializer: nkruntime.Initializer, logger: nkruntime.Logger): void {
  // Kept for documentation only — Nakama requires registerRpc calls inside InitModule.
  logger.info("Crownspire Phase 4 alliance handlers available (registered in InitModule).");
}

function rankValue(rank: string): number {
  return RANK_ORDER[rank] || 0;
}

function hasPerm(rank: string, perm: string): boolean {
  const table = RANK_PERMISSIONS[rank] || RANK_PERMISSIONS["R1"];
  return !!table[perm];
}

function requirePerm(nk: nkruntime.Nakama, logger: nkruntime.Logger, groupId: string, userId: string, perm: string): string {
  const profile = ensureProfile(nk, logger, userId);
  if (profile.alliance_id !== groupId) {
    throw Err("Not an alliance member");
  }
  const rank = resolveCrownspireRank(nk, groupId, userId, getNakamaGroupState(nk, groupId, userId));
  if (!hasPerm(rank, perm)) {
    throw Err("Permission denied: " + perm);
  }
  return rank;
}

function getNakamaGroupState(nk: nkruntime.Nakama, groupId: string, userId: string): number {
  const users = nk.groupUsersList(groupId, 100);
  const list = users.groupUsers || [];
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    if (!gu.user) continue;
    const uid = String(gu.user.userId || (gu.user as any).id || "");
    if (uid === userId) {
      return Number(gu.state);
    }
  }
  return -1;
}

function readAllianceMeta(nk: nkruntime.Nakama, allianceId: string): AllianceMeta {
  const objects = nk.storageRead([
    { collection: ALLIANCE_META_COLLECTION, key: allianceId, userId: SYSTEM_USER },
  ]);
  if (objects && objects.length > 0 && objects[0].value) {
    return objects[0].value as AllianceMeta;
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

function writeAllianceMeta(nk: nkruntime.Nakama, meta: AllianceMeta): void {
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

function buildAllianceProfile(nk: nkruntime.Nakama, logger: nkruntime.Logger, group: nkruntime.Group): any {
  const meta = safeJson(group.metadata || {});
  const stored = readAllianceMeta(nk, String(group.id));
  const members = nk.groupUsersList(String(group.id), 100);
  const list = members.groupUsers || [];
  let memberCount = 0;
  let leaderId = "";
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    const state = Number(gu.state);
    if (state === 0 || state === 1 || state === 2) {
      memberCount++;
      if (state === 0 && gu.user) {
        leaderId = String(gu.user.userId || (gu.user as any).id || "");
      }
    }
  }
  if (!leaderId) {
    // Fall back to stored R5
    for (let i = 0; i < list.length; i++) {
      const gu = list[i];
      if (!gu.user) continue;
      const uid = String(gu.user.userId || (gu.user as any).id || "");
      const rank = resolveCrownspireRank(nk, String(group.id), uid, Number(gu.state));
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

function sendAllianceSystemMessage(nk: nkruntime.Nakama, logger: nkruntime.Logger, groupId: string, text: string, eventType: string): void {
  try {
    // ChanType.Group == 2
    const channelId = nk.channelIdBuild("", groupId, 2 as any);
    nk.channelMessageSend(
      channelId,
      {
        message_type: "SYSTEM",
        text: text,
        sender_display_name: "System",
        sender_alliance_tag: "",
        payload: { event: eventType },
        metadata: { crownspire_system: true, event: eventType },
      },
      undefined,
      undefined,
      true
    );
  } catch (e) {
    logger.warn("Alliance system message failed group=%s err=%s", groupId, String(e));
  }
}

function rpcGetAllianceProfile(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  let allianceId = String(data["alliance_id"] || "").trim();
  if (!allianceId) {
    const profile = ensureProfile(nk, logger, ctx.userId);
    allianceId = profile.alliance_id;
  }
  if (!allianceId) throw Err("alliance_id required");
  const groups = nk.groupsGetId([allianceId]);
  if (!groups || groups.length === 0) throw Err("Alliance not found");
  return JSON.stringify({ ok: true, alliance: buildAllianceProfile(nk, logger, groups[0]) });
}

function rpcListMembers(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "view_members");

  const users = nk.groupUsersList(profile.alliance_id, 100);
  const list = users.groupUsers || [];
  const out: any[] = [];
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    const state = Number(gu.state);
    if (state !== 0 && state !== 1 && state !== 2) continue;
    if (!gu.user) continue;
    const uid = String(gu.user.userId || (gu.user as any).id || "");
    const memberProfile = ensureProfile(nk, logger, uid);
    const rank = resolveCrownspireRank(nk, profile.alliance_id, uid, state);
    const pub = publicProfile(memberProfile);
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

function rpcListAlliances(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const query = String(data["query"] || "").trim();
  // groupsList(name?, langTag?, open?, members?, limit?, cursor?)
  const result = nk.groupsList(query !== "" ? query : undefined, undefined, undefined, undefined, 20, undefined);
  const groups = result.groups || [];
  const out: any[] = [];
  for (let i = 0; i < groups.length; i++) {
    const g = groups[i];
    const meta = safeJson(g.metadata || {});
    if (!meta["crownspire"] && !meta["alliance_tag"]) continue;
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

function rpcUpdateAllianceProfile(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "edit_profile");

  const data = parsePayload(payload);
  const meta = readAllianceMeta(nk, profile.alliance_id);
  if (data["description"] !== undefined) {
    meta.description = String(data["description"] || "").substring(0, 280).replace(/[\u0000-\u001F\u007F]/g, "");
  }
  if (data["language"] !== undefined) {
    meta.language = String(data["language"] || "en").substring(0, 8);
  }
  if (data["join_type"] !== undefined) {
    const jt = String(data["join_type"] || "apply");
    if (jt !== "apply" && jt !== "invite_only") throw Err("Invalid join_type");
    meta.join_type = jt;
  }
  writeAllianceMeta(nk, meta);

  // Optional description mirror onto Nakama group.
  try {
    nk.groupUpdate(profile.alliance_id, ctx.userId, null, null, meta.description || null, null, null, null, null);
  } catch (e) {
    logger.warn("groupUpdate description failed: %s", String(e));
  }

  const groups = nk.groupsGetId([profile.alliance_id]);
  return JSON.stringify({
    ok: true,
    alliance: groups && groups.length ? buildAllianceProfile(nk, logger, groups[0]) : meta,
  });
}

function rpcRejectJoin(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "reject");

  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) throw Err("user_id required");

  nk.groupUsersKick(profile.alliance_id, [targetId]); // removes join request
  logger.info("Alliance join rejected group=%s user=%s by %s", profile.alliance_id, targetId, ctx.userId);
  return JSON.stringify({ ok: true });
}

function rpcSetMemberRank(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");

  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  const newRank = String(data["rank"] || "").trim().toUpperCase();
  if (!targetId) throw Err("user_id required");
  if (!RANK_ORDER[newRank]) throw Err("Invalid rank");
  if (targetId === ctx.userId) throw Err("Cannot change your own rank");
  if (newRank === "R5") throw Err("Use transfer_leadership to assign R5");

  const targetState = getNakamaGroupState(nk, profile.alliance_id, targetId);
  if (targetState < 0 || targetState > 2) throw Err("Target is not an active member");
  const targetRank = resolveCrownspireRank(nk, profile.alliance_id, targetId, targetState);
  const isPromote = rankValue(newRank) > rankValue(targetRank);
  const actorRank = requirePerm(nk, logger, profile.alliance_id, ctx.userId, isPromote ? "promote" : "demote");

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
  if (targetRank === "R5") throw Err("Cannot demote R5; transfer leadership first");

  writeRank(nk, profile.alliance_id, targetId, newRank);

  // Keep Nakama admin bit roughly aligned: R4 -> admin, else member (never touch superadmin here).
  try {
    if (targetState !== 0) {
      if (newRank === "R4") {
        nk.groupUsersPromote(profile.alliance_id, [targetId]);
      } else if (targetState === 1 && rankValue(newRank) < rankValue("R4")) {
        nk.groupUsersDemote(profile.alliance_id, [targetId]);
      }
    }
  } catch (e) {
    logger.warn("Nakama promote/demote sync failed: %s", String(e));
  }

  const targetProfile = ensureProfile(nk, logger, targetId);
  syncAllianceFields(nk, logger, targetProfile);

  const event = isPromote ? "promoted" : "demoted";
  sendAllianceSystemMessage(
    nk,
    logger,
    profile.alliance_id,
    targetProfile.display_name + " was " + event + " to " + newRank + ".",
    event
  );

  logger.info("Rank set group=%s target=%s %s->%s by %s", profile.alliance_id, targetId, targetRank, newRank, ctx.userId);
  return JSON.stringify({ ok: true, user_id: targetId, rank: newRank, event: event });
}

function rpcTransferLeadership(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "transfer_leadership");

  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) throw Err("user_id required");
  if (targetId === ctx.userId) throw Err("Already leader");

  const targetState = getNakamaGroupState(nk, profile.alliance_id, targetId);
  if (targetState < 0 || targetState > 2) throw Err("Target is not an active member");

  writeRank(nk, profile.alliance_id, targetId, "R5");
  writeRank(nk, profile.alliance_id, ctx.userId, "R4");

  // Promote target to superadmin if API supports; demote old leader to admin.
  try {
    nk.groupUsersPromote(profile.alliance_id, [targetId]);
  } catch (e) {
    logger.warn("transfer promote target failed: %s", String(e));
  }

  const oldProfile = ensureProfile(nk, logger, ctx.userId);
  oldProfile.crownspire_rank = "R4";
  oldProfile.updated_at = nowUnix();
  writeProfile(nk, oldProfile);

  const newLeader = ensureProfile(nk, logger, targetId);
  syncAllianceFields(nk, logger, newLeader);
  syncAllianceFields(nk, logger, oldProfile);

  sendAllianceSystemMessage(
    nk,
    logger,
    profile.alliance_id,
    "Leadership transferred to " + (newLeader.display_name || targetId) + ".",
    "leadership_transferred"
  );

  logger.info("Leadership transferred group=%s from=%s to=%s", profile.alliance_id, ctx.userId, targetId);
  return JSON.stringify({
    ok: true,
    alliance_id: profile.alliance_id,
    new_leader_user_id: targetId,
    former_leader_rank: "R4",
  });
}

function writeInvite(nk: nkruntime.Nakama, invite: AllianceInvite): void {
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

function readInvite(nk: nkruntime.Nakama, inviteId: string): AllianceInvite | null {
  const objects = nk.storageRead([{ collection: INVITE_COLLECTION, key: inviteId, userId: SYSTEM_USER }]);
  if (!objects || objects.length === 0 || !objects[0].value) return null;
  return objects[0].value as AllianceInvite;
}

function rpcInvitePlayer(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) throw Err("Not in an alliance");
  requirePerm(nk, logger, profile.alliance_id, ctx.userId, "invite");

  const data = parsePayload(payload);
  const targetId = String(data["user_id"] || "").trim();
  if (!targetId) throw Err("user_id required");
  if (targetId === ctx.userId) throw Err("Cannot invite yourself");

  const targetProfile = ensureProfile(nk, logger, targetId);
  if (targetProfile.alliance_id) throw Err("Target already in an alliance");

  // Duplicate pending invite prevention (scan recent invites for target+alliance).
  // Lightweight: create new invite_id; client/list filters pending.
  const inviteId = nk.uuidv4();
  const now = nowUnix();
  const invite: AllianceInvite = {
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

function rpcListMyInvites(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const listed = nk.storageList(SYSTEM_USER, INVITE_COLLECTION, 100, undefined);
  const objects = listed.objects || [];
  const out: any[] = [];
  const now = nowUnix();
  for (let i = 0; i < objects.length; i++) {
    const obj = objects[i];
    if (!obj.value || !String(obj.key || "").startsWith("inbox:" + ctx.userId + ":")) continue;
    const inviteId = String((obj.value as any).invite_id || "");
    const invite = readInvite(nk, inviteId);
    if (!invite) continue;
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

function rpcAcceptInvite(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (profile.alliance_id) throw Err("Already in an alliance");

  const data = parsePayload(payload);
  const inviteId = String(data["invite_id"] || "").trim();
  if (!inviteId) throw Err("invite_id required");
  const invite = readInvite(nk, inviteId);
  if (!invite) throw Err("Invite not found");
  if (invite.target_user_id !== ctx.userId) throw Err("Invite not for this user");
  if (invite.status !== "pending") throw Err("Invite is not pending");
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

function rpcRejectInvite(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const data = parsePayload(payload);
  const inviteId = String(data["invite_id"] || "").trim();
  if (!inviteId) throw Err("invite_id required");
  const invite = readInvite(nk, inviteId);
  if (!invite) throw Err("Invite not found");
  if (invite.target_user_id !== ctx.userId) throw Err("Invite not for this user");
  if (invite.status !== "pending") throw Err("Invite is not pending");
  invite.status = "rejected";
  writeInvite(nk, invite);
  return JSON.stringify({ ok: true });
}

function rpcGetMyPermissions(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) throw Err("Unauthenticated");
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    return JSON.stringify({ ok: true, rank: "", permissions: {} });
  }
  const rank = resolveCrownspireRank(
    nk,
    profile.alliance_id,
    ctx.userId,
    getNakamaGroupState(nk, profile.alliance_id, ctx.userId)
  );
  return JSON.stringify({
    ok: true,
    rank: rank,
    rank_display: ROLE_DISPLAY[rank] || rank,
    permissions: RANK_PERMISSIONS[rank] || {},
  });
}

/** Phase-4 enhanced leave: R5 cannot leave while other members remain. */
function leaveAlliancePhase4(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, profile: CrownspireProfile): string {
  const userId = String(ctx.userId || "");
  if (!userId) throw Err("Unauthenticated");
  const groupId = String(profile.alliance_id || "");
  if (!groupId) throw Err("Not in an alliance");
  const myRank = resolveCrownspireRank(nk, groupId, userId, getNakamaGroupState(nk, groupId, userId));
  const users = nk.groupUsersList(groupId, 100);
  const list = users.groupUsers || [];
  let otherMembers = 0;
  for (let i = 0; i < list.length; i++) {
    const gu = list[i];
    const state = Number(gu.state);
    if (state !== 0 && state !== 1 && state !== 2) continue;
    if (!gu.user) continue;
    const uid = String(gu.user.userId || (gu.user as any).id || "");
    if (uid !== userId) otherMembers++;
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
    } catch (e) {
      logger.warn("groupDelete after last leave failed: %s", String(e));
    }
  } else {
    sendAllianceSystemMessage(nk, logger, groupId, (profile.display_name || "A member") + " left the Alliance.", "left");
  }

  logger.info("Alliance leave group=%s user=%s", groupId, userId);
  return JSON.stringify({ ok: true, profile: publicProfile(profile) });
}

/** Phase-4 enhanced kick with rank policy. */
function kickMemberPhase4(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, profile: CrownspireProfile, targetId: string): string {
  const userId = String(ctx.userId || "");
  if (!userId) throw Err("Unauthenticated");
  const groupId = String(profile.alliance_id || "");
  if (!groupId) throw Err("Not in an alliance");
  if (targetId === userId) throw Err("Cannot kick yourself");
  const actorRank = requirePerm(nk, logger, groupId, userId, "kick");
  const targetState = getNakamaGroupState(nk, groupId, targetId);
  if (targetState < 0 || targetState > 2) throw Err("Target is not an active member");
  const targetRank = resolveCrownspireRank(nk, groupId, targetId, targetState);
  if (targetRank === "R5") throw Err("Cannot kick R5");
  if (rankValue(targetRank) >= rankValue(actorRank)) {
    throw Err("Cannot kick equal or higher rank");
  }
  // R4 may kick R1–R3 only
  if (actorRank === "R4" && rankValue(targetRank) > rankValue("R3")) {
    throw Err("Cannot kick this rank");
  }

  nk.groupUsersKick(groupId, [targetId]);
  const targetProfile = ensureProfile(nk, logger, targetId);
  const name = targetProfile.display_name;
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
function approveJoinPhase4(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, profile: CrownspireProfile, targetId: string): string {
  const userId = String(ctx.userId || "");
  if (!userId) throw Err("Unauthenticated");
  const groupId = String(profile.alliance_id || "");
  if (!groupId) throw Err("Not in an alliance");
  requirePerm(nk, logger, groupId, userId, "approve");
  nk.groupUsersAdd(groupId, [targetId]);
  writeRank(nk, groupId, targetId, "R1");
  const targetProfile = ensureProfile(nk, logger, targetId);
  syncAllianceFields(nk, logger, targetProfile);
  sendAllianceSystemMessage(
    nk,
    logger,
    groupId,
    (targetProfile.display_name || "A player") + " joined the Alliance.",
    "joined"
  );
  logger.info("Alliance join approved group=%s user=%s by %s", groupId, targetId, userId);
  return JSON.stringify({ ok: true, alliance_id: groupId, user_id: targetId, rank: "R1" });
}
