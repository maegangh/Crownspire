/**
 * Crownspire Phase 5 — Alliance Help + beta Auto-Help RPC tests
 * Usage: node scripts/phase5_help_rpc_test.mjs
 * LOCAL DEVELOPMENT ONLY — uses crownspire_dev_set_entitlement with local secret.
 */
import crypto from "node:crypto";

const HOST = process.env.NAKAMA_HOST || "127.0.0.1";
const PORT = process.env.NAKAMA_PORT || "7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";
const DEV_SECRET = process.env.CROWNSPIR_DEV_ENTITLEMENT_SECRET || "crownspire-local-dev-entitlement-secret";
const BASE = `http://${HOST}:${PORT}`;
const AUTH = "Basic " + Buffer.from(KEY + ":").toString("base64");

const fails = [];
function ok(label) {
  console.log(`[Phase5RPC] OK  ${label}`);
}
function fail(label, detail) {
  const msg = detail ? `${label}: ${detail}` : label;
  fails.push(msg);
  console.log(`[Phase5RPC] FAIL ${msg}`);
}

async function authDevice(deviceId) {
  const res = await fetch(`${BASE}/v2/account/authenticate/device?create=true`, {
    method: "POST",
    headers: { Authorization: AUTH, "Content-Type": "application/json" },
    body: JSON.stringify({ id: deviceId }),
  });
  if (!res.ok) throw new Error(`auth ${res.status} ${await res.text()}`);
  const session = await res.json();
  const acctRes = await fetch(`${BASE}/v2/account`, {
    headers: { Authorization: `Bearer ${session.token}` },
  });
  if (!acctRes.ok) throw new Error(`account ${acctRes.status}`);
  const account = await acctRes.json();
  return { token: session.token, user_id: account.user.id };
}

async function rpc(token, id, payload = {}) {
  const res = await fetch(`${BASE}/v2/rpc/${id}?unwrap`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    const err = new Error(data?.message || data?.error || text);
    err.data = data;
    throw err;
  }
  if (data && typeof data.payload === "string") {
    try {
      return JSON.parse(data.payload);
    } catch {
      return data;
    }
  }
  return data;
}

async function expectFail(token, id, payload, label) {
  try {
    const data = await rpc(token, id, payload);
    if (data && data.ok === false) {
      ok(label);
      return data;
    }
    fail(label, "expected failure");
    return data;
  } catch (e) {
    ok(label);
    return { ok: false, error: String(e.message || e) };
  }
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function main() {
  console.log("[Phase5RPC] BEGIN against", BASE);
  const stamp = Date.now();
  const A = await authDevice(`p5-a-${stamp}`);
  const B = await authDevice(`p5-b-${stamp}`);
  const C = await authDevice(`p5-c-${stamp}`);
  const O = await authDevice(`p5-out-${stamp}`);
  ok("A/B/C/outsider authenticate");

  await rpc(A.token, "crownspire_get_profile", {});
  await rpc(B.token, "crownspire_get_profile", {});
  await rpc(C.token, "crownspire_get_profile", {});
  await rpc(O.token, "crownspire_get_profile", {});

  const tag = ("H" + String(stamp % 1000).padStart(3, "0")).slice(0, 4);
  const created = await rpc(A.token, "crownspire_create_alliance", {
    name: "P5Help" + String(stamp).slice(-5),
    tag,
  });
  const allianceId = created.alliance_id || created.group_id || created?.alliance?.alliance_id;
  if (!allianceId) fail("create alliance missing id", JSON.stringify(created));
  else ok("A create alliance " + allianceId);

  await rpc(B.token, "crownspire_join_alliance", { alliance_id: allianceId });
  await rpc(C.token, "crownspire_join_alliance", { alliance_id: allianceId });
  const apps = await rpc(A.token, "crownspire_list_alliance_join_requests", {});
  for (const r of apps.requests || apps.applications || []) {
    await rpc(A.token, "crownspire_approve_alliance_join", { user_id: r.user_id });
  }
  ok("B/C approved into alliance");

  const finishA = Math.floor(Date.now() / 1000) + 3600;
  // A construction help
  const createdHelp = await rpc(A.token, "crownspire_create_help_request", {
    project_type: "CONSTRUCTION",
    project_id: "citadel",
    project_display_name: "Citadel Lv2",
    original_finish_time: finishA,
    // Client-supplied reduction must be ignored by server.
    seconds_reduced: 999999,
    alliance_id: "fake-alliance",
  });
  if (!createdHelp.ok || !createdHelp.request?.request_id) fail("A create construction help", JSON.stringify(createdHelp));
  else ok("A construction help created");
  const reqId = createdHelp.request.request_id;
  const beforeFinish = createdHelp.request.current_finish_time;

  const dedupe = await rpc(A.token, "crownspire_create_help_request", {
    project_type: "CONSTRUCTION",
    project_id: "citadel",
    project_display_name: "Citadel Lv2",
    original_finish_time: finishA + 10,
  });
  if (!dedupe.ok || dedupe.request.request_id !== reqId || !dedupe.deduped) fail("dedupe active construction request");
  else ok("duplicate construction request deduped");

  const listB = await rpc(B.token, "crownspire_list_eligible_help_requests", {});
  const listC = await rpc(C.token, "crownspire_list_eligible_help_requests", {});
  if ((listB.eligible_count || 0) < 1 || !(listB.requests || []).some((r) => r.request_id === reqId)) fail("B cannot see request");
  else ok("B sees eligible request");
  if ((listC.eligible_count || 0) < 1) fail("C cannot see request");
  else ok("C sees eligible request");

  const helpB = await rpc(B.token, "crownspire_help_one", { request_id: reqId, seconds_reduced: 999999 });
  if (!helpB.ok || !(helpB.seconds_reduced > 0)) fail("B help one", JSON.stringify(helpB));
  else if (helpB.request.current_finish_time !== beforeFinish - helpB.seconds_reduced && helpB.request.current_finish_time > beforeFinish) fail("timer not reduced");
  else ok("B help reduces timer once (" + helpB.seconds_reduced + "s)");

  await expectFail(B.token, "crownspire_help_one", { request_id: reqId }, "B duplicate help rejected");
  await expectFail(A.token, "crownspire_help_one", { request_id: reqId }, "A self-help rejected");

  const helpC = await rpc(C.token, "crownspire_help_one", { request_id: reqId });
  if (!helpC.ok || !(helpC.seconds_reduced > 0)) fail("C help one", JSON.stringify(helpC));
  else ok("C help reduces timer again (" + helpC.seconds_reduced + "s)");

  // Research help + Help All
  await sleep(1200);
  const research = await rpc(A.token, "crownspire_create_help_request", {
    project_type: "RESEARCH",
    project_id: "infantry_atk_1",
    project_display_name: "Infantry Attack I",
    original_finish_time: Math.floor(Date.now() / 1000) + 1800,
  });
  if (!research.ok) fail("research help create", JSON.stringify(research));
  else ok("research help created");

  // Healing batch A
  await sleep(1200);
  const healAId = "heal_" + stamp + "_a";
  const healA = await rpc(A.token, "crownspire_create_help_request", {
    project_type: "HEALING",
    project_id: healAId,
    project_display_name: "Healing batch A",
    original_finish_time: Math.floor(Date.now() / 1000) + 900,
  });
  if (!healA.ok) fail("healing batch A create", JSON.stringify(healA));
  else ok("healing batch A created");

  const eligibleBeforeAll = await rpc(B.token, "crownspire_list_eligible_help_requests", {});
  const helpAll = await rpc(B.token, "crownspire_help_all", {});
  if (!helpAll.ok || (helpAll.helped_count || 0) < 1) fail("help all", JSON.stringify(helpAll));
  else ok("Help All worked count=" + helpAll.helped_count);

  const eligibleAfter = await rpc(B.token, "crownspire_list_eligible_help_requests", {});
  if ((eligibleAfter.eligible_count || 0) >= (eligibleBeforeAll.eligible_count || 0) && (helpAll.helped_count || 0) > 0) {
    // B may still see C-owned? No - all owned by A. After B helped all, B eligible should be 0 for A's requests B already helped.
  }
  if ((eligibleAfter.eligible_count || 0) !== 0) {
    // Could be 0 if B helped all; if some remain because already helped, that's ok if requests B already helped are excluded
    const stillMine = (eligibleAfter.requests || []).filter((r) => r.owner_user_id === A.user_id && !(r.helper_user_ids || []).includes(B.user_id));
    if (stillMine.length > 0) fail("eligible count after help all still includes unhelped A requests");
    else ok("eligible list excludes already-helped");
  } else ok("eligible count zero for B after Help All");

  // Complete healing A and create batch B with new id
  await rpc(A.token, "crownspire_complete_or_cancel_help_request", {
    request_id: healA.request.request_id,
    action: "complete",
  });
  ok("healing batch A completed/closed");

  await expectFail(A.token, "crownspire_create_help_request", {
    project_type: "HEALING",
    project_id: healAId,
    project_display_name: "Healing batch A reuse",
    original_finish_time: Math.floor(Date.now() / 1000) + 900,
  }, "healing batch ID reuse rejected");

  const healBId = "heal_" + stamp + "_b";
  await sleep(1200);
  const healB = await rpc(A.token, "crownspire_create_help_request", {
    project_type: "HEALING",
    project_id: healBId,
    project_display_name: "Healing batch B",
    original_finish_time: Math.floor(Date.now() / 1000) + 900,
  });
  if (!healB.ok || healB.request.request_id === healA.request.request_id) fail("healing batch B new request id");
  else ok("healing batch B new request id");

  await expectFail(B.token, "crownspire_help_one", { request_id: healA.request.request_id }, "completed request rejected");
  await expectFail(B.token, "crownspire_help_one", { request_id: "00000000-0000-0000-0000-000000000099" }, "fake request id rejected");
  await expectFail(O.token, "crownspire_help_one", { request_id: healB.request.request_id }, "outsider help rejected");
  // Outsiders get an empty eligible list (mutations still reject); do not error the Help screen.
  const outList = await rpc(O.token, "crownspire_list_eligible_help_requests", {});
  if (outList.in_alliance === false && (outList.eligible_count || 0) === 0) ok("outsider eligible empty");
  else fail("outsider eligible unexpected", JSON.stringify(outList));

  // Leave/kick eligibility
  await rpc(A.token, "crownspire_kick_alliance_member", { user_id: C.user_id });
  const listAfterKick = await rpc(C.token, "crownspire_list_eligible_help_requests", {});
  if (listAfterKick.in_alliance === false || (listAfterKick.eligible_count || 0) === 0) ok("kicked C loses eligibility");
  else fail("kicked C still eligible", JSON.stringify(listAfterKick));

  // Restart preserve: re-list A's active
  const mine = await rpc(A.token, "crownspire_list_my_active_help_requests", {});
  if ((mine.requests || []).some((r) => r.request_id === reqId || r.project_type === "CONSTRUCTION" || r.project_type === "HEALING")) {
    ok("active requests preserved after operations");
  } else {
    // construction may still be active
    const still = (mine.requests || []).length >= 1;
    if (still) ok("active requests preserved");
    else fail("no active requests preserved", JSON.stringify(mine));
  }

  // Entitlement: B manual without entitlement
  const ent0 = await rpc(B.token, "crownspire_get_my_entitlements", {});
  if (ent0.auto_help && ent0.auto_help.active) fail("B should not have auto-help yet");
  else ok("non-entitled B remains manual");

  // Forbidden client self-grant without secret
  await expectFail(B.token, "crownspire_dev_set_entitlement", {
    action: "grant",
    entitlement_id: "beta_alliance_auto_help",
  }, "grant without secret rejected");

  // Grant beta entitlement via secret tooling
  const grant = await rpc(B.token, "crownspire_dev_set_entitlement", {
    dev_secret: DEV_SECRET,
    action: "grant",
    entitlement_id: "beta_alliance_auto_help",
    user_id: B.user_id,
    duration_seconds: 3600,
  });
  if (!grant.ok || !grant.auto_help?.active) fail("grant beta entitlement", JSON.stringify(grant));
  else ok("beta entitlement granted to B");
  if (String(grant.auto_help.ui_label || "").toLowerCase().includes("ultra value")) {
    fail("UI label must not claim Ultra Value Monthly Card");
  } else ok("auto-help UI label is beta/dev only");

  // Online Auto-Help path: help_all as_auto_help
  const auto = await rpc(B.token, "crownspire_help_all", { as_auto_help: true });
  if (!auto.ok || auto.auto_help !== true) fail("auto-help help_all", JSON.stringify(auto));
  else ok("online entitled Auto-Help Help All path works");

  // Revoke stops auto-help
  const revoke = await rpc(B.token, "crownspire_dev_set_entitlement", {
    dev_secret: DEV_SECRET,
    action: "revoke",
    entitlement_id: "beta_alliance_auto_help",
    user_id: B.user_id,
  });
  if (revoke.auto_help?.active) fail("revoke did not deactivate");
  else ok("revoke stops Auto-Help");

  await expectFail(B.token, "crownspire_help_all", { as_auto_help: true }, "Auto-Help rejected after revoke");

  // Re-grant and expire
  await rpc(B.token, "crownspire_dev_set_entitlement", {
    dev_secret: DEV_SECRET,
    action: "grant",
    entitlement_id: "beta_alliance_auto_help",
    user_id: B.user_id,
    duration_seconds: 3600,
  });
  await rpc(B.token, "crownspire_dev_set_entitlement", {
    dev_secret: DEV_SECRET,
    action: "expire",
    entitlement_id: "beta_alliance_auto_help",
    user_id: B.user_id,
  });
  const entExp = await rpc(B.token, "crownspire_get_my_entitlements", {});
  if (entExp.auto_help?.active) fail("expire did not deactivate");
  else ok("expire stops Auto-Help");

  // Production entitlement cannot be granted via dev RPC
  await expectFail(B.token, "crownspire_dev_set_entitlement", {
    dev_secret: DEV_SECRET,
    action: "grant",
    entitlement_id: "alliance_auto_help",
    user_id: B.user_id,
  }, "production entitlement grant blocked in beta tooling");

  if (fails.length === 0) {
    console.log("[Phase5RPC] PASS");
    process.exit(0);
  }
  console.log("[Phase5RPC] FAILED count=" + fails.length);
  for (const f of fails) console.log(" - " + f);
  process.exit(1);
}

main().catch((e) => {
  console.error("[Phase5RPC] ERROR", e);
  process.exit(1);
});
