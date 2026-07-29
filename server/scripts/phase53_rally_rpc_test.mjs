/**
 * Phase 5.3 Alliance Rally RPC smoke test.
 * LOCAL DEVELOPMENT ONLY.
 *
 * Respects server assertRateLimit("rally_create", 3) — do not remove gameplay limiter.
 */
const HOST = process.env.NAKAMA_HOST || "http://127.0.0.1:7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";
/** Matches phase53_rally.ts assertRateLimit(..., "rally_create", 3) plus small buffer. */
const RALLY_CREATE_COOLDOWN_MS = 3200;

async function authDevice(id) {
  const res = await fetch(`${HOST}/v2/account/authenticate/device?create=true&username=`, {
    method: "POST",
    headers: {
      Authorization: "Basic " + Buffer.from(KEY + ":").toString("base64"),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ id }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(data));
  return { token: data.token, user_id: data.user_id || data.userId };
}

async function rpc(token, id, payload = {}) {
  const res = await fetch(`${HOST}/v2/rpc/${id}?unwrap`, {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`${id}: ${JSON.stringify(data)}`);
  return typeof data === "string" ? JSON.parse(data) : data;
}

function ok(msg) {
  console.log("[Phase53RPC] OK ", msg);
}
function fail(msg, detail) {
  console.error("[Phase53RPC] FAIL", msg, detail || "");
  process.exitCode = 1;
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

/** Wait out rally_create cooldown for the same user before the next create. */
async function waitRallyCreateCooldown(reason) {
  console.log("[Phase53RPC] wait rally_create cooldown (" + reason + ")…");
  await sleep(RALLY_CREATE_COOLDOWN_MS);
}

async function ensureAlliance(leader, member) {
  const tag = ("R" + String(Date.now() % 1000).padStart(3, "0")).slice(0, 4);
  const created = await rpc(leader.token, "crownspire_create_alliance", {
    name: "RallyTest" + String(Date.now()).slice(-5),
    tag,
  });
  const allianceId =
    created.alliance_id ||
    created.group_id ||
    (created.alliance && (created.alliance.alliance_id || created.alliance.id)) ||
    "";
  if (!allianceId) {
    fail("alliance id missing", JSON.stringify(created));
    return null;
  }
  ok("alliance created " + allianceId);

  await rpc(member.token, "crownspire_join_alliance", { alliance_id: allianceId });
  const apps = await rpc(leader.token, "crownspire_list_alliance_join_requests", {});
  for (const r of apps.requests || apps.applications || []) {
    await rpc(leader.token, "crownspire_approve_alliance_join", { user_id: r.user_id });
  }
  ok("member approved into alliance");
  return allianceId;
}

async function main() {
  console.log("[Phase53RPC] BEGIN against", HOST);
  const stamp = Date.now();
  const A = await authDevice(`p53-a-${stamp}`);
  const B = await authDevice(`p53-b-${stamp}`);
  ok("authenticate");

  await rpc(A.token, "crownspire_set_display_name", { display_name: "RallyLead" + String(stamp).slice(-3) });
  await rpc(B.token, "crownspire_set_display_name", { display_name: "RallyJoin" + String(stamp).slice(-3) });

  const allianceId = await ensureAlliance(A, B);
  if (!allianceId) return;

  const troops = { infantry: 100, marksmen: 50, cavalry: 25 };
  const create = await rpc(A.token, "crownspire_rally_create", {
    lair_id: "lair_test_" + stamp,
    lair_level: 5,
    countdown_seconds: 60,
    hero_ids: ["hero_a"],
    troop_counts: troops,
    troop_tiers: { infantry: { 1: 100 }, marksmen: { 1: 50 }, cavalry: { 1: 25 } },
    power: 2500,
    world_x: 1200,
    world_y: 800,
    recommended_power: 10000,
    species: "beast",
  });
  if (!create?.ok || !create.rally?.rally_id) {
    fail("create rally", JSON.stringify(create));
    return;
  }
  const rallyId = create.rally.rally_id;
  if (create.rally.countdown_seconds !== 60) fail("default countdown", JSON.stringify(create.rally));
  else ok("create rally " + rallyId);

  const listed = await rpc(A.token, "crownspire_rally_list_active", {});
  if (!listed?.ok || !(listed.rallies || []).some((r) => r.rally_id === rallyId)) {
    fail("list active", JSON.stringify(listed));
  } else ok("list active");

  const joined = await rpc(B.token, "crownspire_rally_join", {
    rally_id: rallyId,
    hero_ids: ["hero_b"],
    troop_counts: { infantry: 80, marksmen: 40, cavalry: 20 },
    troop_tiers: { infantry: { 1: 80 }, marksmen: { 1: 40 }, cavalry: { 1: 20 } },
    power: 1800,
  });
  if (!joined?.ok || (joined.rally.participants || []).length < 2) {
    fail("join rally", JSON.stringify(joined));
  } else ok("join rally participants=" + joined.rally.participants.length);

  // Second create while in rally should fail.
  try {
    const dup = await rpc(B.token, "crownspire_rally_create", {
      lair_id: "lair_dup",
      lair_level: 1,
      countdown_seconds: 60,
      hero_ids: ["h"],
      troop_counts: { infantry: 10, marksmen: 0, cavalry: 0 },
      power: 100,
    });
    if (dup?.ok) fail("one rally rule", JSON.stringify(dup));
    else ok("one rally per player enforced");
  } catch (_e) {
    ok("one rally per player enforced (rpc error)");
  }

  const launched = await rpc(A.token, "crownspire_rally_launch", { rally_id: rallyId, auto: false });
  if (!launched?.ok || launched.rally.status !== "LAUNCHED") {
    fail("launch now", JSON.stringify(launched));
  } else ok("launch now");

  const completed = await rpc(A.token, "crownspire_rally_complete", {
    rally_id: rallyId,
    result: {
      victory: true,
      summary: "Victory",
      damage_dealt: 5000,
      remaining_hp: 0,
      rewards: { food: 100 },
      rounds: 3,
    },
  });
  if (!completed?.ok || completed.rally.status !== "COMPLETED" || !completed.rally.result?.victory) {
    fail("complete victory", JSON.stringify(completed));
  } else ok("complete victory");

  // Fresh rally for cancel path (same user — honor rally_create cooldown)
  await waitRallyCreateCooldown("before cancel-path create");
  const create2 = await rpc(A.token, "crownspire_rally_create", {
    lair_id: "lair_cancel_" + stamp,
    lair_level: 2,
    countdown_seconds: 300,
    hero_ids: ["hero_a"],
    troop_counts: troops,
    power: 2500,
    world_x: 1,
    world_y: 1,
  });
  if (create2?.ok) {
    const cancel = await rpc(A.token, "crownspire_rally_cancel", { rally_id: create2.rally.rally_id });
    if (!cancel?.ok || cancel.rally.status !== "CANCELLED") fail("cancel", JSON.stringify(cancel));
    else ok("cancel rally");
  } else {
    fail("create for cancel", JSON.stringify(create2));
  }

  // Invalid countdown sanitized to 60
  await waitRallyCreateCooldown("before countdown-sanitize create");
  const create3 = await rpc(A.token, "crownspire_rally_create", {
    lair_id: "lair_cd_" + stamp,
    lair_level: 1,
    countdown_seconds: 999,
    hero_ids: ["hero_a"],
    troop_counts: troops,
    power: 1000,
  });
  if (create3?.ok && create3.rally.countdown_seconds === 60) ok("invalid countdown sanitized");
  else fail("countdown sanitize", JSON.stringify(create3));
  if (create3?.ok) {
    await rpc(A.token, "crownspire_rally_cancel", { rally_id: create3.rally.rally_id });
  }

  // Fake lair target rejection (Phase 5.4)
  await waitRallyCreateCooldown("before fake-target create");
  try {
    const fake = await rpc(A.token, "crownspire_rally_create", {
      lair_id: "fake_target",
      lair_level: 1,
      countdown_seconds: 60,
      hero_ids: ["hero_a"],
      troop_counts: troops,
      power: 1000,
    });
    if (fake?.ok) fail("fake lair rejected", JSON.stringify(fake));
    else ok("fake lair rejected");
  } catch (_e) {
    ok("fake lair rejected (rpc error)");
  }

  if (process.exitCode) console.log("[Phase53RPC] DONE WITH FAILURES");
  else console.log("[Phase53RPC] PASS");
}

main().catch((e) => {
  fail("uncaught", String(e));
});
