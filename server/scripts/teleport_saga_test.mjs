/**
 * In-memory versioned storage mock + teleport saga concurrency / crash-stage tests.
 * Mirrors server/src/phase55_city_teleport.ts durable mechanisms without Nakama.
 * Run: node server/scripts/teleport_saga_test.mjs
 */

const LOCK_TTL_SEC = 20;
const CASTLE_MIN = 500;

class VersionedStore {
  constructor() {
    this.objs = new Map(); // collection|user|key -> {value, version}
    this.failNextWrite = null; // collection key to fail once
    this.writeLog = [];
  }
  _k(c, u, k) {
    return `${c}|${u}|${k}`;
  }
  read(c, u, k) {
    const hit = this.objs.get(this._k(c, u, k));
    return hit ? { value: JSON.parse(JSON.stringify(hit.value)), version: hit.version } : null;
  }
  write(c, u, k, value, version) {
    const key = this._k(c, u, k);
    this.writeLog.push({ c, u, k, version, state: value && value.state });
    if (this.failNextWrite === key) {
      this.failNextWrite = null;
      throw new Error("simulated storage failure");
    }
    const cur = this.objs.get(key);
    if (version === "*") {
      if (cur) throw new Error("version mismatch create");
    } else if (!cur || cur.version !== version) {
      throw new Error("version mismatch");
    }
    const nextVer = String((cur ? Number(cur.version) : 0) + 1);
    this.objs.set(key, { value: JSON.parse(JSON.stringify(value)), version: nextVer });
    return nextVer;
  }
}

function now() {
  return Math.floor(Date.now() / 1000);
}

function acquireLock(store, kingdomId, userId, requestId) {
  const t = now();
  for (let i = 0; i < 8; i++) {
    const obj = store.read("lock", "sys", kingdomId);
    const cur = obj ? obj.value : null;
    const ver = obj ? obj.version : "*";
    const expired = !cur || !cur.expires_at || Number(cur.expires_at) <= t;
    const same = cur && cur.request_id === requestId && cur.user_id === userId;
    if (!expired && !same) return false;
    try {
      store.write(
        "lock",
        "sys",
        kingdomId,
        { user_id: userId, request_id: requestId, expires_at: t + LOCK_TTL_SEC },
        ver
      );
      return true;
    } catch (_e) {
      /* retry */
    }
  }
  return false;
}

function releaseLock(store, kingdomId, userId, requestId) {
  const obj = store.read("lock", "sys", kingdomId);
  if (!obj) return;
  if (obj.value.user_id !== userId || obj.value.request_id !== requestId) return;
  try {
    store.write("lock", "sys", kingdomId, { user_id: "", request_id: "", expires_at: 0 }, obj.version);
  } catch (_e) {
    /* TTL recovers */
  }
}

function spacingOk(castles, x, y, selfId) {
  for (const c of castles) {
    if (c.user_id === selfId) continue;
    const dx = x - c.world_x;
    const dy = y - c.world_y;
    if (Math.sqrt(dx * dx + dy * dy) < CASTLE_MIN) return false;
  }
  return true;
}

function advance(store, userId, requestId, crashAfter) {
  let opObj = store.read("ops", userId, requestId);
  if (!opObj) throw new Error("missing op");
  let op = opObj.value;
  let opVer = opObj.version;
  if (op.state === "completed") return op.result;
  if (op.state === "failed") throw new Error(op.error || "failed");

  const kingdomId = op.kingdom_id;
  if (!acquireLock(store, kingdomId, userId, requestId)) throw new Error("lock busy");

  const persist = (state, extra) => {
    op = Object.assign({}, op, extra || {}, { state, updated_at: now() });
    store.write("ops", userId, requestId, op, opVer);
    opObj = store.read("ops", userId, requestId);
    op = opObj.value;
    opVer = opObj.version;
    if (crashAfter === state) throw new Error("crash@" + state);
  };

  try {
    if (op.state === "pending" || op.state === "inventory_consumed") {
      const reg = store.read("reg", "sys", kingdomId);
      const castles = (reg && reg.value.castles) || [];
      if (!spacingOk(castles, op.world_x, op.world_y, userId)) throw new Error("too close");
    }
    if (op.state === "pending") {
      const inv = store.read("inv", userId, userId);
      if (!inv || inv.value.balance < 1) throw new Error("no compass");
      const next = { balance: inv.value.balance - 1 };
      store.write("inv", userId, userId, next, inv.version);
      persist("inventory_consumed", { balance_after_consume: next.balance });
    }
    if (op.state === "inventory_consumed") {
      const reg = store.read("reg", "sys", kingdomId) || {
        value: { castles: [] },
        version: "*",
      };
      const castles = (reg.value.castles || []).slice();
      if (!spacingOk(castles, op.world_x, op.world_y, userId)) throw new Error("too close");
      let found = false;
      for (let i = 0; i < castles.length; i++) {
        if (castles[i].user_id === userId) {
          castles[i] = { user_id: userId, world_x: op.world_x, world_y: op.world_y };
          found = true;
          break;
        }
      }
      if (!found) castles.push({ user_id: userId, world_x: op.world_x, world_y: op.world_y });
      store.write("reg", "sys", kingdomId, { castles }, reg.version);
      persist("registry_updated", {});
    }
    if (op.state === "registry_updated") {
      const prof = store.read("prof", userId, "profile") || { value: {}, version: "*" };
      store.write(
        "prof",
        userId,
        "profile",
        { world_x: op.world_x, world_y: op.world_y },
        prof.version
      );
      persist("profile_updated", {});
    }
    if (op.state === "profile_updated" || op.state === "registry_updated") {
      const inv = store.read("inv", userId, userId);
      const result = {
        ok: true,
        request_id: requestId,
        world_x: op.world_x,
        world_y: op.world_y,
        balance: inv ? inv.value.balance : 0,
      };
      persist("completed", { result, ok: true });
      return result;
    }
    throw new Error("unknown state");
  } catch (e) {
    const msg = String(e.message || e);
    if (msg.startsWith("crash@")) throw e;
    if (op.state === "inventory_consumed") {
      const inv = store.read("inv", userId, userId);
      store.write("inv", userId, userId, { balance: inv.value.balance + 1 }, inv.version);
      persist("failed", { error: msg, ok: false });
    } else if (op.state === "pending") {
      /* leave pending */
    }
    throw e;
  } finally {
    releaseLock(store, kingdomId, userId, requestId);
  }
}

function createOp(store, userId, requestId, kingdomId, x, y, oldX, oldY) {
  store.write(
    "ops",
    userId,
    requestId,
    {
      request_id: requestId,
      kingdom_id: kingdomId,
      world_x: x,
      world_y: y,
      old_world_x: oldX,
      old_world_y: oldY,
      state: "pending",
    },
    "*"
  );
}

function assert(cond, msg) {
  if (!cond) throw new Error("ASSERT: " + msg);
}

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log("PASS", name);
  } catch (e) {
    console.error("FAIL", name, e.message || e);
    process.exitCode = 1;
  }
}

test("idempotent completed retry", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 2 }, "*");
  s.write("reg", "sys", "k1", { castles: [{ user_id: "u1", world_x: 1000, world_y: 1000 }] }, "*");
  s.write("prof", "u1", "profile", { world_x: 1000, world_y: 1000 }, "*");
  createOp(s, "u1", "req1", "k1", 3000, 3000, 1000, 1000);
  const r1 = advance(s, "u1", "req1", null);
  const r2 = advance(s, "u1", "req1", null);
  assert(r1.world_x === 3000 && r2.world_x === 3000, "same result");
  assert(s.read("inv", "u1", "u1").value.balance === 1, "consumed once");
});

test("crash after inventory_consumed recovers without double consume", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 1 }, "*");
  s.write("reg", "sys", "k1", { castles: [{ user_id: "u1", world_x: 1000, world_y: 1000 }] }, "*");
  s.write("prof", "u1", "profile", { world_x: 1000, world_y: 1000 }, "*");
  createOp(s, "u1", "req2", "k1", 3200, 3200, 1000, 1000);
  try {
    advance(s, "u1", "req2", "inventory_consumed");
  } catch (e) {
    assert(String(e.message).includes("crash@"), "expected crash");
  }
  assert(s.read("inv", "u1", "u1").value.balance === 0, "consumed");
  assert(s.read("ops", "u1", "req2").value.state === "inventory_consumed", "stage");
  const r = advance(s, "u1", "req2", null);
  assert(r.ok && r.balance === 0, "completed after resume");
  assert(s.read("inv", "u1", "u1").value.balance === 0, "no double consume");
  assert(s.read("prof", "u1", "profile").value.world_x === 3200, "profile moved");
});

test("crash after registry_updated resumes to completed", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 1 }, "*");
  s.write("reg", "sys", "k1", { castles: [{ user_id: "u1", world_x: 1000, world_y: 1000 }] }, "*");
  s.write("prof", "u1", "profile", { world_x: 1000, world_y: 1000 }, "*");
  createOp(s, "u1", "req3", "k1", 3400, 3400, 1000, 1000);
  try {
    advance(s, "u1", "req3", "registry_updated");
  } catch (_e) {
    /* crash */
  }
  const r = advance(s, "u1", "req3", null);
  assert(r.ok, "ok");
  assert(s.read("reg", "sys", "k1").value.castles[0].world_x === 3400, "registry");
  assert(s.read("prof", "u1", "profile").value.world_x === 3400, "profile");
});

test("parallel overlapping claims — only one wins", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 1 }, "*");
  s.write("inv", "u2", "u2", { balance: 1 }, "*");
  s.write(
    "reg",
    "sys",
    "k1",
    {
      castles: [
        { user_id: "u1", world_x: 1000, world_y: 1000 },
        { user_id: "u2", world_x: 2000, world_y: 2000 },
      ],
    },
    "*"
  );
  s.write("prof", "u1", "profile", { world_x: 1000, world_y: 1000 }, "*");
  s.write("prof", "u2", "profile", { world_x: 2000, world_y: 2000 }, "*");
  // Overlapping destinations (~100 apart < 500)
  createOp(s, "u1", "a", "k1", 4000, 4000, 1000, 1000);
  createOp(s, "u2", "b", "k1", 4100, 4000, 2000, 2000);

  let wins = 0;
  let fails = 0;
  const run = (uid, rid) => {
    try {
      advance(s, uid, rid, null);
      wins++;
    } catch (_e) {
      fails++;
    }
  };
  // Interleave by running sequentially under shared store (CAS+lock) — second loses spacing or lock.
  run("u1", "a");
  run("u2", "b");
  assert(wins === 1 && fails === 1, `wins=${wins} fails=${fails}`);
});

test("storage fail on op create does not consume", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 3 }, "*");
  s.failNextWrite = "ops|u1|reqX";
  let threw = false;
  try {
    createOp(s, "u1", "reqX", "k1", 3000, 3000, 1000, 1000);
  } catch (_e) {
    threw = true;
  }
  assert(threw, "create failed");
  assert(s.read("inv", "u1", "u1").value.balance === 3, "untouched");
  assert(s.read("ops", "u1", "reqX") === null, "no op");
});

test("lock expires after TTL", () => {
  const s = new VersionedStore();
  s.write(
    "lock",
    "sys",
    "k1",
    { user_id: "dead", request_id: "old", expires_at: now() - 1 },
    "*"
  );
  assert(acquireLock(s, "k1", "u1", "new") === true, "recovered lock");
});

test("genuinely interleaved overlapping claims", () => {
  const s = new VersionedStore();
  s.write("inv", "u1", "u1", { balance: 1 }, "*");
  s.write("inv", "u2", "u2", { balance: 1 }, "*");
  s.write(
    "reg",
    "sys",
    "k1",
    {
      castles: [
        { user_id: "u1", world_x: 1000, world_y: 1000 },
        { user_id: "u2", world_x: 2000, world_y: 2000 },
      ],
    },
    "*"
  );
  s.write("prof", "u1", "profile", { world_x: 1000, world_y: 1000 }, "*");
  s.write("prof", "u2", "profile", { world_x: 2000, world_y: 2000 }, "*");
  createOp(s, "u1", "p1", "k1", 4500, 4500, 1000, 1000);
  createOp(s, "u2", "p2", "k1", 4550, 4500, 2000, 2000);
  // Simulate two workers: u1 consumes under lock, then crashes before registry;
  // u2 tries while lock held / then after recovery both resume — only one completes.
  try {
    advance(s, "u1", "p1", "inventory_consumed");
  } catch (_e) {
    /* crash holding stage */
  }
  let u2ok = false;
  try {
    advance(s, "u2", "p2", null);
    u2ok = true;
  } catch (_e) {
    u2ok = false;
  }
  // u1 still holds pending inventory_consumed; lock released in finally, so u2 may proceed
  // and claim overlapping spot first — then u1 resume must fail spacing and refund.
  const r1 = (() => {
    try {
      return advance(s, "u1", "p1", null);
    } catch (e) {
      return { ok: false, error: String(e.message || e) };
    }
  })();
  const successes = [u2ok, r1.ok === true].filter(Boolean).length;
  assert(successes === 1, `exactly one success got=${successes} u2=${u2ok} u1=${JSON.stringify(r1)}`);
  const bal1 = s.read("inv", "u1", "u1").value.balance;
  const bal2 = s.read("inv", "u2", "u2").value.balance;
  assert(bal1 + bal2 === 1, `exactly one compass consumed bal1=${bal1} bal2=${bal2}`);
});

console.log(`\n${passed} tests passed`);
if (process.exitCode) process.exit(1);
