/**
 * Permanent public Player ID — external lookup alias for Nakama user_id.
 * LOCAL DEVELOPMENT ONLY. Do not deploy until audited.
 *
 * Internal Nakama user_id remains account/wallet/save/voucher authority.
 * Public Player ID is an immutable, server-assigned, human-friendly alias.
 *
 * Assignment is NOT a multi-object transaction. Recovery uses an explicit
 * per-user pending claim (O(1) read, no collection scan):
 *   1) create-only pending candidate on the user
 *   2) create-only unique lookup reservation
 *   3) create-only user mapping
 * An interrupted attempt is repaired from that pending record on the next
 * authenticated ensure. Lookup uniqueness remains create-only (version="*").
 * Same-user extra reservations are deleted only when this user owns them.
 * Conflicting committed state fails closed (identity_conflict).
 */

const PUBLIC_PLAYER_ID_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const PUBLIC_PLAYER_ID_LENGTH = 8;
const PUBLIC_PLAYER_ID_SCHEMA = 1;
const PUBLIC_PLAYER_ID_COLLECTION = "crownspire_player_identity";
const PUBLIC_PLAYER_ID_KEY = "public_player_id";
const PUBLIC_PLAYER_ID_PENDING_KEY = "public_player_id_pending";
const PUBLIC_PLAYER_ID_LOOKUP_COLLECTION = "crownspire_public_player_ids";
const PUBLIC_PLAYER_ID_MAX_ATTEMPTS = 16;
/** 256 - (256 % 31) — rejection sampling bound for unbiased alphabet picks. */
const PUBLIC_PLAYER_ID_REJECT_AT = 248;

interface PublicPlayerIdRecord {
  public_player_id: string;
  user_id: string;
  created_at: number;
  schema_version: number;
  active: boolean;
}

interface PublicPlayerIdEnsureResult {
  ok: boolean;
  public_player_id: string;
  created: boolean;
  error?: string;
}

interface PublicPlayerIdSafeLookup {
  ok: boolean;
  exists: boolean;
  error: string;
  public_player_id: string;
  display_name: string;
  avatar_id: string;
  kingdom_id: string;
  realm_id: string;
}

function normalizePublicPlayerId(raw: string): string {
  const compact = String(raw || "")
    .toUpperCase()
    .replace(/[-\s]/g, "");
  if (compact.length !== PUBLIC_PLAYER_ID_LENGTH) {
    return "";
  }
  for (let i = 0; i < compact.length; i++) {
    if (PUBLIC_PLAYER_ID_ALPHABET.indexOf(compact.charAt(i)) < 0) {
      return "";
    }
  }
  return compact;
}

function formatPublicPlayerId(normalized: string): string {
  const id = normalizePublicPlayerId(normalized);
  if (!id) {
    return "";
  }
  return id.substring(0, 4) + "-" + id.substring(4, 8);
}

function isValidPublicPlayerId(raw: string): boolean {
  return normalizePublicPlayerId(raw) !== "";
}

function generatePublicPlayerId(nk: nkruntime.Nakama): string {
  let out = "";
  while (out.length < PUBLIC_PLAYER_ID_LENGTH) {
    const uuid = String(nk.uuidv4() || "").replace(/-/g, "");
    for (let i = 0; i + 1 < uuid.length && out.length < PUBLIC_PLAYER_ID_LENGTH; i += 2) {
      const byte = parseInt(uuid.substring(i, i + 2), 16);
      if (isNaN(byte) || byte >= PUBLIC_PLAYER_ID_REJECT_AT) {
        continue;
      }
      out += PUBLIC_PLAYER_ID_ALPHABET.charAt(byte % PUBLIC_PLAYER_ID_ALPHABET.length);
    }
  }
  return out;
}

function publicPlayerIdUserRecord(userId: string, normalized: string, createdAt: number): PublicPlayerIdRecord {
  return {
    public_player_id: normalized,
    user_id: userId,
    created_at: createdAt,
    schema_version: PUBLIC_PLAYER_ID_SCHEMA,
    active: true,
  };
}

function publicPlayerIdLookupRecord(userId: string, normalized: string, createdAt: number): PublicPlayerIdRecord {
  return publicPlayerIdUserRecord(userId, normalized, createdAt);
}

function readAssignedPublicPlayerId(nk: nkruntime.Nakama, userId: string): PublicPlayerIdRecord | null {
  const obj = storageReadOne(nk, PUBLIC_PLAYER_ID_COLLECTION, PUBLIC_PLAYER_ID_KEY, userId);
  if (!obj || !obj.value) {
    return null;
  }
  const value = obj.value as PublicPlayerIdRecord;
  const normalized = normalizePublicPlayerId(String(value.public_player_id || ""));
  const owner = String(value.user_id || "").trim();
  if (!normalized || owner !== userId || value.active === false) {
    return null;
  }
  value.public_player_id = normalized;
  return value;
}

function tryWriteStorage(
  nk: nkruntime.Nakama,
  collection: string,
  key: string,
  userId: string,
  value: any,
  version: string
): { ok: boolean; version: string } {
  try {
    const acks = nk.storageWrite([
      {
        collection: collection,
        key: key,
        userId: userId,
        value: value,
        version: version,
        permissionRead: 0,
        permissionWrite: 0,
      },
    ]);
    const ackVersion = acks && acks.length > 0 ? String(acks[0].version || "") : "";
    return { ok: true, version: ackVersion };
  } catch (_e) {
    return { ok: false, version: "" };
  }
}

function tryCreateOnlyStorage(
  nk: nkruntime.Nakama,
  collection: string,
  key: string,
  userId: string,
  value: any
): { ok: boolean; version: string } {
  return tryWriteStorage(nk, collection, key, userId, value, "*");
}

function deletePublicPlayerIdLookup(nk: nkruntime.Nakama, normalized: string, version: string): void {
  try {
    const req: any = {
      collection: PUBLIC_PLAYER_ID_LOOKUP_COLLECTION,
      key: normalized,
      userId: SYSTEM_USER,
    };
    if (version) {
      req.version = version;
    }
    nk.storageDelete([req]);
  } catch (_e) {
    // Best-effort cleanup of an unused reservation owned by this flow.
  }
}

function deleteOwnedPublicPlayerIdLookup(nk: nkruntime.Nakama, normalized: string, userId: string): void {
  const rec = lookupPublicPlayerIdRecord(nk, normalized);
  if (!rec || rec.user_id !== userId) {
    return;
  }
  deletePublicPlayerIdLookup(nk, normalized, "");
}

function readPendingPublicPlayerId(
  nk: nkruntime.Nakama,
  userId: string
): { record: PublicPlayerIdRecord; version: string } | null {
  const obj = storageReadOne(nk, PUBLIC_PLAYER_ID_COLLECTION, PUBLIC_PLAYER_ID_PENDING_KEY, userId);
  if (!obj || !obj.value) {
    return null;
  }
  const value = obj.value as PublicPlayerIdRecord;
  const owner = String(value.user_id || "").trim();
  if (owner !== userId) {
    return null;
  }
  value.user_id = owner;
  value.public_player_id = normalizePublicPlayerId(String(value.public_player_id || ""));
  return { record: value, version: String(obj.version || "") };
}

function deletePendingPublicPlayerId(nk: nkruntime.Nakama, userId: string, version: string): void {
  try {
    const req: any = {
      collection: PUBLIC_PLAYER_ID_COLLECTION,
      key: PUBLIC_PLAYER_ID_PENDING_KEY,
      userId: userId,
    };
    if (version) {
      req.version = version;
    }
    nk.storageDelete([req]);
  } catch (_e) {
    // Best-effort: committed mapping is authority if present.
  }
}

function failClosedIdentityConflict(): PublicPlayerIdEnsureResult {
  return { ok: false, public_player_id: "", created: false, error: "identity_conflict" };
}

function repairOrValidateCommittedLookup(
  nk: nkruntime.Nakama,
  userId: string,
  committed: PublicPlayerIdRecord
): PublicPlayerIdEnsureResult | null {
  const normalized = committed.public_player_id;
  const lookup = lookupPublicPlayerIdRecord(nk, normalized);
  if (lookup) {
    if (lookup.user_id !== userId) {
      return failClosedIdentityConflict();
    }
    return null;
  }
  const createdAt = committed.created_at || nowUnix();
  const reserved = tryCreateOnlyStorage(
    nk,
    PUBLIC_PLAYER_ID_LOOKUP_COLLECTION,
    normalized,
    SYSTEM_USER,
    publicPlayerIdLookupRecord(userId, normalized, createdAt)
  );
  if (reserved.ok) {
    return null;
  }
  const again = lookupPublicPlayerIdRecord(nk, normalized);
  if (again && again.user_id === userId) {
    return null;
  }
  return failClosedIdentityConflict();
}

function cleanupPendingAfterCommit(
  nk: nkruntime.Nakama,
  userId: string,
  committedNormalized: string
): void {
  const pending = readPendingPublicPlayerId(nk, userId);
  if (pending) {
    const extra = pending.record.public_player_id;
    if (extra && extra !== committedNormalized) {
      deleteOwnedPublicPlayerIdLookup(nk, extra, userId);
    }
    deletePendingPublicPlayerId(nk, userId, pending.version);
  }
}

/**
 * Assign or return the permanent Public Player ID for an authenticated Nakama user.
 * Never trusts a client-supplied ID. Never silently reassigns an existing mapping.
 * Interrupted pending+lookup attempts are repaired from the per-user pending claim.
 */
function ensurePublicPlayerId(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  userId: string,
  generateFn?: (nk: nkruntime.Nakama) => string
): PublicPlayerIdEnsureResult {
  const uid = String(userId || "").trim();
  if (!uid) {
    return { ok: false, public_player_id: "", created: false, error: "unauthenticated" };
  }

  const existing = readAssignedPublicPlayerId(nk, uid);
  if (existing) {
    const conflict = repairOrValidateCommittedLookup(nk, uid, existing);
    if (conflict) {
      return conflict;
    }
    cleanupPendingAfterCommit(nk, uid, existing.public_player_id);
    return {
      ok: true,
      public_player_id: formatPublicPlayerId(existing.public_player_id),
      created: false,
    };
  }

  const generate = generateFn || generatePublicPlayerId;
  let pending = readPendingPublicPlayerId(nk, uid);

  for (let attempt = 0; attempt < PUBLIC_PLAYER_ID_MAX_ATTEMPTS; attempt++) {
    let candidate = pending ? pending.record.public_player_id : "";
    if (!candidate) {
      candidate = normalizePublicPlayerId(generate(nk));
      if (!candidate) {
        continue;
      }
      const createdAt = nowUnix();
      const pendingValue = publicPlayerIdUserRecord(uid, candidate, createdAt);
      if (!pending) {
        const created = tryCreateOnlyStorage(
          nk,
          PUBLIC_PLAYER_ID_COLLECTION,
          PUBLIC_PLAYER_ID_PENDING_KEY,
          uid,
          pendingValue
        );
        if (!created.ok) {
          pending = readPendingPublicPlayerId(nk, uid);
          continue;
        }
        pending = { record: pendingValue, version: created.version };
      } else {
        const replaced = tryWriteStorage(
          nk,
          PUBLIC_PLAYER_ID_COLLECTION,
          PUBLIC_PLAYER_ID_PENDING_KEY,
          uid,
          pendingValue,
          pending.version
        );
        if (!replaced.ok) {
          pending = readPendingPublicPlayerId(nk, uid);
          continue;
        }
        pending = { record: pendingValue, version: replaced.version };
      }
    }
    if (!pending) {
      continue;
    }

    const createdAt = pending.record.created_at || nowUnix();
    const lookupValue = publicPlayerIdLookupRecord(uid, candidate, createdAt);
    const existingLookup = lookupPublicPlayerIdRecord(nk, candidate);
    if (existingLookup) {
      if (existingLookup.user_id !== uid) {
        pending = { record: publicPlayerIdUserRecord(uid, "", createdAt), version: pending.version };
        continue;
      }
    } else {
      const reserved = tryCreateOnlyStorage(
        nk,
        PUBLIC_PLAYER_ID_LOOKUP_COLLECTION,
        candidate,
        SYSTEM_USER,
        lookupValue
      );
      if (!reserved.ok) {
        const raced = lookupPublicPlayerIdRecord(nk, candidate);
        if (!raced || raced.user_id !== uid) {
          pending = { record: publicPlayerIdUserRecord(uid, "", createdAt), version: pending.version };
          continue;
        }
      }
    }

    const userValue = publicPlayerIdUserRecord(uid, candidate, createdAt);
    const mapped = tryCreateOnlyStorage(
      nk,
      PUBLIC_PLAYER_ID_COLLECTION,
      PUBLIC_PLAYER_ID_KEY,
      uid,
      userValue
    );
    if (mapped.ok) {
      deletePendingPublicPlayerId(nk, uid, pending.version);
      return {
        ok: true,
        public_player_id: formatPublicPlayerId(candidate),
        created: true,
      };
    }

    const winner = readAssignedPublicPlayerId(nk, uid);
    if (winner) {
      if (winner.public_player_id !== candidate) {
        deleteOwnedPublicPlayerIdLookup(nk, candidate, uid);
      }
      const conflict = repairOrValidateCommittedLookup(nk, uid, winner);
      if (conflict) {
        return conflict;
      }
      cleanupPendingAfterCommit(nk, uid, winner.public_player_id);
      return {
        ok: true,
        public_player_id: formatPublicPlayerId(winner.public_player_id),
        created: false,
      };
    }
  }

  if (logger) {
    logger.error("Public Player ID assignment failed for user after collisions/retries");
  }
  return { ok: false, public_player_id: "", created: false, error: "assignment_failed" };
}

function lookupPublicPlayerIdRecord(nk: nkruntime.Nakama, rawId: string): PublicPlayerIdRecord | null {
  const normalized = normalizePublicPlayerId(rawId);
  if (!normalized) {
    return null;
  }
  const obj = storageReadOne(nk, PUBLIC_PLAYER_ID_LOOKUP_COLLECTION, normalized, SYSTEM_USER);
  if (!obj || !obj.value) {
    return null;
  }
  const value = obj.value as PublicPlayerIdRecord;
  const owner = String(value.user_id || "").trim();
  const mapped = normalizePublicPlayerId(String(value.public_player_id || ""));
  if (!owner || mapped !== normalized || value.active === false) {
    return null;
  }
  value.public_player_id = mapped;
  value.user_id = owner;
  return value;
}

/**
 * Server-internal lookup for a future Top-Up Center backend.
 * Never return email, UUID, wallet, vouchers, entitlements, or login providers.
 * Invalid and missing IDs both surface as PLAYER_NOT_FOUND so callers cannot enumerate why.
 */
function safeLookupPublicPlayer(nk: nkruntime.Nakama, rawId: string): PublicPlayerIdSafeLookup {
  const notFound: PublicPlayerIdSafeLookup = {
    ok: true,
    exists: false,
    error: "PLAYER_NOT_FOUND",
    public_player_id: "",
    display_name: "",
    avatar_id: "",
    kingdom_id: "",
    realm_id: "",
  };
  const record = lookupPublicPlayerIdRecord(nk, rawId);
  if (!record) {
    return notFound;
  }
  let displayName = "";
  let avatarId = "";
  let kingdomId = "";
  try {
    const profile = readProfile(nk, record.user_id);
    if (profile) {
      displayName = String(profile.display_name || "").trim();
      avatarId = String(profile.avatar_id || "").trim();
      kingdomId = String(profile.kingdom_id || "").trim();
    }
  } catch (_e) {
    // Profile is optional confirmation data only.
  }
  return {
    ok: true,
    exists: true,
    error: "",
    public_player_id: formatPublicPlayerId(record.public_player_id),
    display_name: displayName,
    avatar_id: avatarId,
    kingdom_id: kingdomId,
    realm_id: kingdomId,
  };
}

function rpcAccountGetPublicPlayerId(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) {
    throw Err("Unauthenticated");
  }
  const result = ensurePublicPlayerId(nk, logger, ctx.userId);
  if (!result.ok || !result.public_player_id) {
    return JSON.stringify({ ok: false, error: result.error || "assignment_failed" });
  }
  return JSON.stringify({
    ok: true,
    public_player_id: result.public_player_id,
  });
}
