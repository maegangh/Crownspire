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

const HELP_COLLECTION = "crownspire_help_requests";
const ENTITLEMENT_COLLECTION = "crownspire_entitlements";
const HELP_SCHEMA_VERSION = 1;

/** Conceptual production entitlement id (not granted in beta). */
const ENTITLEMENT_ALLIANCE_AUTO_HELP = "alliance_auto_help";
/** Development/closed-beta entitlement id. */
const ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP = "beta_alliance_auto_help";

/**
 * LOCAL DEVELOPMENT ONLY secret for grant/revoke tooling.
 * Normal game clients must never ship this value.
 */
const CROWNSPIR_DEV_ENTITLEMENT_SECRET = "crownspire-local-dev-entitlement-secret";

const HELP_STATUS_ACTIVE = "ACTIVE";
const HELP_STATUS_COMPLETED = "COMPLETED";
const HELP_STATUS_EXPIRED = "EXPIRED";
const HELP_STATUS_CANCELLED = "CANCELLED";

const HELP_TYPE_CONSTRUCTION = "CONSTRUCTION";
const HELP_TYPE_RESEARCH = "RESEARCH";
const HELP_TYPE_HEALING = "HEALING";

/** BETA configuration — not final balance values. */
const BETA_HELP_CONFIG = {
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

const HELP_NOTIF_CODE = 5001;

interface HelpRequest {
  request_id: string;
  alliance_id: string;
  owner_user_id: string;
  owner_display_name: string;
  project_type: string;
  project_id: string;
  project_display_name: string;
  created_at: number;
  expires_at: number;
  original_finish_time: number;
  current_finish_time: number;
  help_count: number;
  help_limit: number;
  helper_user_ids: string[];
  status: string;
  schema_version: number;
  last_reduction_seconds: number;
  updated_at: number;
}

interface EntitlementRecord {
  entitlement_id: string;
  user_id: string;
  status: string; // active | revoked | expired
  starts_at: number;
  expires_at: number;
  source: string; // beta_test | google_play (future)
  updated_at: number;
}

/** Entitlement abstraction — Help/Auto-Help must not know the provider source. */
interface EntitlementProvider {
  isActive(nk: nkruntime.Nakama, userId: string, entitlementId: string): boolean;
  getRecord(nk: nkruntime.Nakama, userId: string, entitlementId: string): EntitlementRecord | null;
}

const StorageEntitlementProvider: EntitlementProvider = {
  isActive: function (nk: nkruntime.Nakama, userId: string, entitlementId: string): boolean {
    const rec = this.getRecord(nk, userId, entitlementId);
    if (!rec || rec.status !== "active") {
      return false;
    }
    const now = nowUnix();
    if (rec.starts_at > 0 && now < rec.starts_at) {
      return false;
    }
    if (rec.expires_at > 0 && now >= rec.expires_at) {
      return false;
    }
    return true;
  },
  getRecord: function (nk: nkruntime.Nakama, userId: string, entitlementId: string): EntitlementRecord | null {
    const objects = nk.storageRead([
      { collection: ENTITLEMENT_COLLECTION, key: entitlementId, userId: userId },
    ]);
    if (!objects || objects.length === 0 || !objects[0].value) {
      return null;
    }
    return objects[0].value as EntitlementRecord;
  },
};

/**
 * Resolve whether Auto-Help is active for a user.
 * Beta maps conceptual alliance_auto_help → beta_alliance_auto_help.
 * Production will resolve alliance_auto_help via Google Play provider only.
 */
function isAllianceAutoHelpActive(nk: nkruntime.Nakama, userId: string): boolean {
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

function getAutoHelpEntitlementPublic(nk: nkruntime.Nakama, userId: string): any {
  const beta = StorageEntitlementProvider.getRecord(nk, userId, ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP);
  const active = isAllianceAutoHelpActive(nk, userId);
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

function registerPhase5HelpRpcs(_initializer: nkruntime.Initializer, logger: nkruntime.Logger): void {
  logger.info("Crownspire Phase 5 help handlers available (registered in InitModule).");
}

function isValidHelpType(t: string): boolean {
  return t === HELP_TYPE_CONSTRUCTION || t === HELP_TYPE_RESEARCH || t === HELP_TYPE_HEALING;
}

function readHelpRequest(nk: nkruntime.Nakama, requestId: string): HelpRequest | null {
  const objects = nk.storageRead([
    { collection: HELP_COLLECTION, key: requestId, userId: SYSTEM_USER },
  ]);
  if (!objects || objects.length === 0 || !objects[0].value) {
    return null;
  }
  return objects[0].value as HelpRequest;
}

function writeHelpRequest(nk: nkruntime.Nakama, req: HelpRequest): void {
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

function listAllianceHelpRequests(nk: nkruntime.Nakama, allianceId: string): HelpRequest[] {
  const listed = nk.storageList(SYSTEM_USER, HELP_COLLECTION, 100, "");
  const objects = listed.objects || [];
  const out: HelpRequest[] = [];
  for (let i = 0; i < objects.length; i++) {
    const v = objects[i].value as HelpRequest;
    if (!v || v.alliance_id !== allianceId) {
      continue;
    }
    out.push(v);
  }
  return out;
}

function refreshHelpStatus(req: HelpRequest, now: number): HelpRequest {
  if (req.status === HELP_STATUS_ACTIVE) {
    if (now >= req.expires_at) {
      req.status = HELP_STATUS_EXPIRED;
      req.updated_at = now;
    } else if (now >= req.current_finish_time) {
      req.status = HELP_STATUS_COMPLETED;
      req.updated_at = now;
    }
  }
  return req;
}

function publicHelpRequest(req: HelpRequest): any {
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

function notifyAllianceHelpEvent(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  allianceId: string,
  eventType: string,
  request: HelpRequest,
  actorUserId: string
): void {
  try {
    const users = nk.groupUsersList(allianceId, 100);
    const list = users.groupUsers || [];
    const content = {
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
    for (let i = 0; i < list.length; i++) {
      const gu = list[i];
      if (!gu.user || Number(gu.state) > 2) {
        continue;
      }
      const uid = String(gu.user.userId || (gu.user as any).id || "");
      if (!uid) continue;
      nk.notificationSend(
        uid,
        "Alliance Help",
        content,
        HELP_NOTIF_CODE,
        null,
        true
      );
    }
  } catch (e) {
    logger.warn("Help notification failed: %s", String(e));
  }
}

function computeHelpReduction(req: HelpRequest, now: number): number {
  const remaining = Math.max(0, req.current_finish_time - now);
  if (remaining <= 0) {
    return 0;
  }
  let reduction = BETA_HELP_CONFIG.reduction_seconds_per_help;
  if (BETA_HELP_CONFIG.reduction_percent_of_remaining > 0) {
    const pct = Math.floor((remaining * BETA_HELP_CONFIG.reduction_percent_of_remaining) / 100);
    if (pct > reduction) {
      reduction = pct;
    }
  }
  const alreadyReduced = Math.max(0, req.original_finish_time - req.current_finish_time);
  const maxLeft = Math.max(0, BETA_HELP_CONFIG.max_reduction_seconds - alreadyReduced);
  reduction = Math.min(reduction, maxLeft, remaining);
  // Never force below immediate completion (remaining can become 0).
  return Math.max(0, reduction);
}

function findActiveOwnerProjectRequest(
  nk: nkruntime.Nakama,
  allianceId: string,
  ownerUserId: string,
  projectType: string,
  projectId: string
): HelpRequest | null {
  const all = listAllianceHelpRequests(nk, allianceId);
  const now = nowUnix();
  for (let i = 0; i < all.length; i++) {
    let req = refreshHelpStatus(all[i], now);
    if (req.status !== HELP_STATUS_ACTIVE) {
      if (all[i].status !== req.status) {
        writeHelpRequest(nk, req);
      }
      continue;
    }
    if (
      req.owner_user_id === ownerUserId &&
      req.project_type === projectType &&
      req.project_id === projectId
    ) {
      return req;
    }
  }
  return null;
}

function applyHelpToRequest(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  req: HelpRequest,
  helperUserId: string
): { ok: boolean; error?: string; request?: HelpRequest; seconds_reduced?: number } {
  const now = nowUnix();
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
  const reduction = computeHelpReduction(req, now);
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

function rpcCreateHelpRequest(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }

  const data = parsePayload(payload);
  const projectType = String(data["project_type"] || "").trim().toUpperCase();
  const projectId = String(data["project_id"] || "").trim();
  const projectDisplayName = String(data["project_display_name"] || projectId).trim().substring(0, 64);
  const originalFinish = Math.floor(Number(data["original_finish_time"] || 0));

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
    const existingSame = findActiveOwnerProjectRequest(nk, profile.alliance_id, ctx.userId, projectType, projectId);
    if (existingSame) {
      return JSON.stringify({ ok: true, request: publicHelpRequest(existingSame), deduped: true });
    }
    // Also reject recreating for a project_id that already completed (batch ID reuse).
    const all = listAllianceHelpRequests(nk, profile.alliance_id);
    for (let i = 0; i < all.length; i++) {
      const r = all[i];
      if (
        r.owner_user_id === ctx.userId &&
        r.project_type === HELP_TYPE_HEALING &&
        r.project_id === projectId &&
        r.status !== HELP_STATUS_ACTIVE
      ) {
        throw Err("Healing batch request already closed; start a new batch for a new request");
      }
    }
  } else {
    const existing = findActiveOwnerProjectRequest(nk, profile.alliance_id, ctx.userId, projectType, projectId);
    if (existing) {
      return JSON.stringify({ ok: true, request: publicHelpRequest(existing), deduped: true });
    }
  }

  // Rate-limit only new request creation (after dedupe short-circuit).
  assertRateLimit(nk, ctx.userId, "create_help_request", BETA_HELP_CONFIG.create_cooldown_seconds);

  const now = nowUnix();
  const req: HelpRequest = {
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

function rpcHelpOne(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  assertRateLimit(nk, ctx.userId, "help_one", BETA_HELP_CONFIG.help_cooldown_seconds);

  const data = parsePayload(payload);
  const requestId = String(data["request_id"] || "").trim();
  if (!requestId) {
    throw Err("request_id required");
  }
  // Ignore any client-supplied reduction / alliance_id.
  const req = readHelpRequest(nk, requestId);
  if (!req) {
    throw Err("Help request not found");
  }
  if (req.alliance_id !== profile.alliance_id) {
    throw Err("Help request not in your alliance");
  }

  const result = applyHelpToRequest(nk, logger, req, ctx.userId);
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

function rpcHelpAll(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    throw Err("Not in an alliance");
  }
  assertRateLimit(nk, ctx.userId, "help_all", BETA_HELP_CONFIG.help_cooldown_seconds);

  const data = parsePayload(payload);
  const asAutoHelp = !!data["as_auto_help"];
  if (asAutoHelp && !isAllianceAutoHelpActive(nk, ctx.userId)) {
    throw Err("Auto-Help entitlement inactive");
  }

  const all = listAllianceHelpRequests(nk, profile.alliance_id);
  const helped: any[] = [];
  const skipped: any[] = [];
  let totalReduced = 0;
  for (let i = 0; i < all.length; i++) {
    const req = all[i];
    if (req.owner_user_id === ctx.userId) {
      skipped.push({ request_id: req.request_id, error: "own request" });
      continue;
    }
    const result = applyHelpToRequest(nk, logger, req, ctx.userId);
    if (result.ok && result.request) {
      helped.push({
        request: publicHelpRequest(result.request),
        seconds_reduced: result.seconds_reduced || 0,
      });
      totalReduced += result.seconds_reduced || 0;
    } else {
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

function countEligibleHelp(nk: nkruntime.Nakama, allianceId: string, helperUserId: string): number {
  const all = listAllianceHelpRequests(nk, allianceId);
  const now = nowUnix();
  let count = 0;
  for (let i = 0; i < all.length; i++) {
    let req = refreshHelpStatus(all[i], now);
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

function rpcListEligibleHelpRequests(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    return JSON.stringify({ ok: true, requests: [], eligible_count: 0, connected: true, in_alliance: false });
  }
  const all = listAllianceHelpRequests(nk, profile.alliance_id);
  const now = nowUnix();
  const out: any[] = [];
  for (let i = 0; i < all.length; i++) {
    let req = refreshHelpStatus(all[i], now);
    if (req.status !== all[i].status) {
      writeHelpRequest(nk, req);
    }
    if (req.status !== HELP_STATUS_ACTIVE) continue;
    if (req.owner_user_id === ctx.userId) continue;
    if (req.helper_user_ids.indexOf(ctx.userId) >= 0) continue;
    if (req.help_count >= req.help_limit) continue;
    if (req.current_finish_time <= now) continue;
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

function rpcListMyActiveHelpRequests(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  if (!profile.alliance_id) {
    return JSON.stringify({
      ok: true,
      requests: [],
      in_alliance: false,
      auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
    });
  }
  const all = listAllianceHelpRequests(nk, profile.alliance_id);
  const now = nowUnix();
  const out: any[] = [];
  for (let i = 0; i < all.length; i++) {
    let req = refreshHelpStatus(all[i], now);
    if (req.status !== all[i].status) {
      writeHelpRequest(nk, req);
    }
    if (req.owner_user_id !== ctx.userId) continue;
    if (req.status !== HELP_STATUS_ACTIVE) continue;
    out.push(publicHelpRequest(req));
  }
  return JSON.stringify({
    ok: true,
    requests: out,
    in_alliance: true,
    auto_help: getAutoHelpEntitlementPublic(nk, ctx.userId),
  });
}

function rpcCompleteOrCancelHelpRequest(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const profile = ensureProfile(nk, logger, ctx.userId);
  const data = parsePayload(payload);
  const requestId = String(data["request_id"] || "").trim();
  const action = String(data["action"] || "complete").trim().toLowerCase();
  if (!requestId) {
    throw Err("request_id required");
  }
  const req = readHelpRequest(nk, requestId);
  if (!req) {
    throw Err("Help request not found");
  }
  if (req.owner_user_id !== ctx.userId) {
    throw Err("Only the owner can complete or cancel this request");
  }
  if (profile.alliance_id && req.alliance_id !== profile.alliance_id && action !== "cancel") {
    // Owner may cancel after leave; completing requires same alliance context normally.
  }
  const now = nowUnix();
  if (req.status !== HELP_STATUS_ACTIVE) {
    return JSON.stringify({ ok: true, request: publicHelpRequest(req), already_closed: true });
  }
  if (action === "cancel") {
    req.status = HELP_STATUS_CANCELLED;
  } else {
    req.status = HELP_STATUS_COMPLETED;
  }
  req.updated_at = now;
  writeHelpRequest(nk, req);
  notifyAllianceHelpEvent(
    nk,
    logger,
    req.alliance_id,
    action === "cancel" ? "help_cancelled" : "help_completed",
    req,
    ctx.userId
  );
  return JSON.stringify({ ok: true, request: publicHelpRequest(req) });
}

function rpcGetMyEntitlements(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const beta = StorageEntitlementProvider.getRecord(nk, ctx.userId, ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP);
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
function rpcDevSetEntitlement(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const data = parsePayload(payload);
  if (String(data["dev_secret"] || "") !== CROWNSPIR_DEV_ENTITLEMENT_SECRET) {
    throw Err("Forbidden");
  }
  const targetUserId = String(data["user_id"] || ctx.userId).trim();
  if (!targetUserId) {
    throw Err("user_id required");
  }
  const entitlementId = String(data["entitlement_id"] || ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP).trim();
  if (entitlementId !== ENTITLEMENT_BETA_ALLIANCE_AUTO_HELP) {
    // Production entitlements cannot be granted through this RPC.
    throw Err("Only beta_alliance_auto_help can be set via dev tooling");
  }
  const action = String(data["action"] || "grant").trim().toLowerCase();
  const now = nowUnix();
  const durationSec = Math.max(60, Math.floor(Number(data["duration_seconds"] || 30 * 24 * 3600)));

  if (action === "revoke") {
    const existing = StorageEntitlementProvider.getRecord(nk, targetUserId, entitlementId);
    const rec: EntitlementRecord = {
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
        value: rec,
        permissionRead: 1,
        permissionWrite: 0,
      },
    ]);
    logger.info("Dev revoke entitlement user=%s id=%s", targetUserId, entitlementId);
    return JSON.stringify({ ok: true, entitlement: rec, auto_help: getAutoHelpEntitlementPublic(nk, targetUserId) });
  }

  if (action === "expire") {
    const existing = StorageEntitlementProvider.getRecord(nk, targetUserId, entitlementId);
    const rec: EntitlementRecord = {
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
        value: rec,
        permissionRead: 1,
        permissionWrite: 0,
      },
    ]);
    return JSON.stringify({ ok: true, entitlement: rec, auto_help: getAutoHelpEntitlementPublic(nk, targetUserId) });
  }

  // grant
  const rec: EntitlementRecord = {
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
