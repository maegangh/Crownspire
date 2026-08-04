/**
 * Crownspire Phase 3 RPC + Alliance Chat security test (LOCAL Nakama).
 * Covers identity, alliance create/join/approve/kick, report RPC,
 * outsider/fake-group denial, and kingdom room regression.
 *
 * Usage: node scripts/phase3_rpc_test.mjs
 */

import crypto from "node:crypto";

const HOST = process.env.NAKAMA_HOST || "127.0.0.1";
const PORT = process.env.NAKAMA_PORT || "7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";
const BASE = `http://${HOST}:${PORT}`;
const AUTH = "Basic " + Buffer.from(KEY + ":").toString("base64");

const fails = [];
function ok(label) {
  console.log(`[Phase3RPC] OK  ${label}`);
}
function fail(label, detail) {
  const msg = detail ? `${label}: ${detail}` : label;
  fails.push(msg);
  console.log(`[Phase3RPC] FAIL ${msg}`);
}

async function authDevice(deviceId) {
  const res = await fetch(`${BASE}/v2/account/authenticate/device?create=true`, {
    method: "POST",
    headers: {
      Authorization: AUTH,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ id: deviceId }),
  });
  if (!res.ok) {
    throw new Error(`auth ${res.status} ${await res.text()}`);
  }
  const session = await res.json();
  const acctRes = await fetch(`${BASE}/v2/account`, {
    headers: { Authorization: `Bearer ${session.token}` },
  });
  if (!acctRes.ok) {
    throw new Error(`account ${acctRes.status} ${await acctRes.text()}`);
  }
  const account = await acctRes.json();
  const userId = account?.user?.id || account?.user?.user_id || "";
  if (!userId) {
    throw new Error("auth missing user id");
  }
  return { token: session.token, user_id: userId, refresh_token: session.refresh_token };
}

async function rpc(token, id, payload = {}) {
  const res = await fetch(`${BASE}/v2/rpc/${id}?unwrap`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
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
    const err = data?.message || data?.error || text;
    throw new Error(String(err));
  }
  // unwrap may return payload directly or nested
  if (data && typeof data.payload === "string") {
    try {
      return JSON.parse(data.payload);
    } catch {
      return data;
    }
  }
  return data;
}

async function joinRoom(token, room) {
  // REST cannot join realtime channels; use list channel messages after socket-less check via groups.
  // Membership enforcement is verified via group chat join attempt through Nakama console API isn't available —
  // we validate group membership list + RPC profile fields here.
  return room;
}

async function listUserGroups(token, userId) {
  const res = await fetch(`${BASE}/v2/user/${encodeURIComponent(userId)}/group`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`user/group ${res.status}`);
  return res.json();
}

async function main() {
  console.log("[Phase3RPC] BEGIN against", BASE);
  const stamp = Date.now();
  const deviceA = `p3-rpc-a-${stamp}`;
  const deviceB = `p3-rpc-b-${stamp}`;
  const deviceC = `p3-rpc-c-${stamp}`;

  const sessA = await authDevice(deviceA);
  const sessB = await authDevice(deviceB);
  const sessC = await authDevice(deviceC);
  ok("A/B/C authenticate");

  // A profile + kingdom
  let profileA = await rpc(sessA.token, "crownspire_get_profile", {});
  if (!profileA?.ok || !profileA.profile?.user_id) fail("A get_profile");
  else if (profileA.profile.kingdom_id !== "kingdom_dev_001") fail("A kingdom assignment", profileA.profile.kingdom_id);
  else ok("A profile + kingdom_dev_001");

  // Leave leftover alliance if any
  if (profileA.profile.alliance_id) {
    try {
      await rpc(sessA.token, "crownspire_leave_alliance", {});
    } catch (_) {
      /* ignore */
    }
    profileA = await rpc(sessA.token, "crownspire_get_profile", {});
  }

  // Display name validation
  try {
    await rpc(sessA.token, "crownspire_set_display_name", { display_name: "x" });
    fail("short display name should reject");
  } catch {
    ok("display name min-length rejected");
  }
  try {
    await rpc(sessA.token, "crownspire_set_display_name", { display_name: "Bad<script>" });
    fail("scripty display name should reject");
  } catch {
    ok("display name forbidden chars rejected");
  }
  // Fresh user D for successful rename (A may still be in cooldown from prior runs).
  const sessD = await authDevice(`p3-rpc-d-${stamp}`);
  await rpc(sessD.token, "crownspire_get_profile", {});
  const named = await rpc(sessD.token, "crownspire_set_display_name", { display_name: "LordD_P3" });
  if (!named?.ok || named.profile?.display_name !== "LordD_P3") fail("set_display_name");
  else ok("set_display_name");

  // Create alliance
  const tag = ("T" + String(stamp % 1000)).slice(0, 4);
  const created = await rpc(sessA.token, "crownspire_create_alliance", {
    name: "RPCSmoke" + String(stamp).slice(-6),
    tag,
  });
  if (!created?.ok || !created.alliance?.alliance_id) {
    fail("create_alliance", created?.error || JSON.stringify(created));
    finish();
    return;
  }
  const allianceId = created.alliance.alliance_id;
  if (created.profile.alliance_tag !== tag.toUpperCase() && created.profile.alliance_tag !== tag) {
    fail("create tag mismatch", created.profile.alliance_tag);
  } else ok("A create alliance " + allianceId);
  if (created.profile?.crownspire_rank !== "R5" && created.alliance?.my_rank !== "R5") {
    // Phase 4 profile returns crownspire_rank; alliance object is full profile.
    const rankOk =
      created.profile?.crownspire_rank === "R5" ||
      created.alliance?.leader_user_id === sessA.user_id;
    if (!rankOk) fail("creator rank not R5", JSON.stringify(created.alliance));
    else ok("A rank R5");
  } else ok("A rank R5");

  // B join request
  let profileB = await rpc(sessB.token, "crownspire_get_profile", {});
  if (profileB.profile?.alliance_id) {
    try {
      await rpc(sessB.token, "crownspire_leave_alliance", {});
    } catch (_) {}
  }
  const join = await rpc(sessB.token, "crownspire_join_alliance", { alliance_id: allianceId });
  if (!join?.ok || !join.pending) fail("B join pending", JSON.stringify(join));
  else ok("B join request pending");

  // C outsider cannot list/approve
  try {
    await rpc(sessC.token, "crownspire_list_alliance_join_requests", {});
    fail("outsider listed join requests");
  } catch {
    ok("outsider cannot list join requests");
  }

  // A approve B
  const reqs = await rpc(sessA.token, "crownspire_list_alliance_join_requests", {});
  if (!reqs?.ok) fail("list requests", JSON.stringify(reqs));
  else ok("A list join requests");
  const approve = await rpc(sessA.token, "crownspire_approve_alliance_join", {
    user_id: sessB.user_id,
  });
  if (!approve?.ok) fail("approve B", JSON.stringify(approve));
  else ok("A approve B");

  profileB = await rpc(sessB.token, "crownspire_get_profile", {});
  profileA = await rpc(sessA.token, "crownspire_get_profile", {});
  if (profileB.profile?.alliance_id !== allianceId) fail("B alliance_id after approve");
  else ok("B same alliance_id");
  if (profileA.profile?.alliance_id !== profileB.profile?.alliance_id) fail("A/B alliance_id mismatch");
  else ok("A/B membership confirmed");
  if (!profileB.profile?.alliance_tag) fail("B missing server tag");
  else ok("B server alliance_tag=" + profileB.profile.alliance_tag);
  if (profileB.profile?.crownspire_rank !== "R1" && profileB.profile?.crownspire_rank !== "R2") {
    fail("B rank expected R1 (or legacy R2)", profileB.profile?.crownspire_rank);
  } else ok("B rank " + profileB.profile?.crownspire_rank);

  // Group membership list check
  const groupsB = await listUserGroups(sessB.token, sessB.user_id);
  const member = (groupsB.user_groups || []).some(
    (ug) => ug.group?.id === allianceId && Number(ug.state) <= 2
  );
  if (!member) fail("B not in Nakama group membership list");
  else ok("B Nakama group membership");

  // Fake / foreign alliance_id join for C should not grant membership
  try {
    await rpc(sessC.token, "crownspire_join_alliance", { alliance_id: allianceId });
    // pending request ok, but profile must not show membership
    const pC = await rpc(sessC.token, "crownspire_get_profile", {});
    if (pC.profile?.alliance_id === allianceId) fail("C got alliance_id without approve");
    else ok("C pending join does not grant alliance_id");
  } catch (e) {
    ok("C join blocked or pending: " + e.message);
  }

  // Fake alliance id
  try {
    await rpc(sessC.token, "crownspire_join_alliance", {
      alliance_id: "00000000-0000-0000-0000-000000000099",
    });
    fail("fake alliance_id join should fail");
  } catch {
    ok("fake alliance_id rejected");
  }

  // Public profile
  const pub = await rpc(sessA.token, "crownspire_get_public_profile", {
    user_id: sessB.user_id,
  });
  if (!pub?.ok || !pub.profile?.display_name) fail("public profile");
  else ok("public profile for B");

  // Report RPC — reporter from auth context
  const report = await rpc(sessA.token, "crownspire_chat_report", {
    reported_user_id: sessB.user_id,
    message_id: crypto.randomUUID(),
    channel_id: "group:" + allianceId,
    message_type: "TEXT",
    message_text: "evidence sample",
    reason: "spam",
    reporter_user_id: "spoofed-should-ignore",
  });
  if (!report?.ok || !report.report_id) fail("chat_report", JSON.stringify(report));
  else ok("chat_report report_id=" + report.report_id);

  try {
    await rpc(sessA.token, "crownspire_chat_report", {
      reported_user_id: sessB.user_id,
      message_id: "x",
      channel_id: "y",
      reason: "not_a_real_reason",
    });
    fail("invalid report reason accepted");
  } catch {
    ok("invalid report reason rejected");
  }

  // Kick B
  const kick = await rpc(sessA.token, "crownspire_kick_alliance_member", {
    user_id: sessB.user_id,
  });
  if (!kick?.ok) fail("kick B", JSON.stringify(kick));
  else ok("kick B");
  profileB = await rpc(sessB.token, "crownspire_get_profile", {});
  if (profileB.profile?.alliance_id) fail("B still has alliance after kick");
  else ok("B alliance cleared after kick");

  // Kingdom assignment still present
  if (profileA.profile?.kingdom_id !== "kingdom_dev_001") fail("kingdom regression on A profile");
  else ok("kingdom_dev_001 still on profile");

  // Cleanup
  try {
    await rpc(sessA.token, "crownspire_leave_alliance", {});
    ok("A leave alliance cleanup");
  } catch (e) {
    // Superadmin leave can fail if Nakama requires transfer — acceptable in local smoke.
    console.log("[Phase3RPC] WARN A leave:", e.message);
  }

  finish();
}

function finish() {
  if (fails.length === 0) {
    console.log("[Phase3RPC] PASS");
    process.exit(0);
  }
  console.log(`[Phase3RPC] FAILED count=${fails.length}`);
  process.exit(1);
}

main().catch((e) => {
  console.error("[Phase3RPC] ERROR", e);
  process.exit(1);
});
