/**
 * Crownspire Phase 4 — roster / ranks / applications / invites / permissions
 * Usage: node scripts/phase4_rpc_test.mjs
 */
import crypto from "node:crypto";

const HOST = process.env.NAKAMA_HOST || "127.0.0.1";
const PORT = process.env.NAKAMA_PORT || "7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";
const BASE = `http://${HOST}:${PORT}`;
const AUTH = "Basic " + Buffer.from(KEY + ":").toString("base64");

const fails = [];
function ok(label) {
  console.log(`[Phase4RPC] OK  ${label}`);
}
function fail(label, detail) {
  const msg = detail ? `${label}: ${detail}` : label;
  fails.push(msg);
  console.log(`[Phase4RPC] FAIL ${msg}`);
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
  if (!res.ok) throw new Error(data?.message || data?.error || text);
  if (data && typeof data.payload === "string") {
    try {
      return JSON.parse(data.payload);
    } catch {
      return data;
    }
  }
  return data;
}

async function main() {
  console.log("[Phase4RPC] BEGIN against", BASE);
  const stamp = Date.now();
  const A = await authDevice(`p4-a-${stamp}`);
  const B = await authDevice(`p4-b-${stamp}`);
  const C = await authDevice(`p4-c-${stamp}`);
  ok("A/B/C authenticate");

  await rpc(A.token, "crownspire_get_profile", {});
  await rpc(B.token, "crownspire_get_profile", {});
  await rpc(C.token, "crownspire_get_profile", {});

  // A create
  const tag = ("P" + String(stamp % 1000)).slice(0, 4);
  const created = await rpc(A.token, "crownspire_create_alliance", {
    name: "P4Ally" + String(stamp).slice(-5),
    tag,
  });
  if (!created?.ok) {
    fail("create", JSON.stringify(created));
    return finish();
  }
  const allianceId = created.alliance.alliance_id || created.profile.alliance_id;
  ok("A create alliance " + allianceId);

  const permsA = await rpc(A.token, "crownspire_get_my_permissions", {});
  if (permsA.rank !== "R5" || !permsA.permissions?.transfer_leadership) fail("A permissions R5");
  else ok("A R5 permissions");

  // B apply
  const join = await rpc(B.token, "crownspire_join_alliance", { alliance_id: allianceId });
  if (!join?.pending) fail("B pending join");
  else ok("B applied");

  const apps = await rpc(A.token, "crownspire_list_alliance_join_requests", {});
  if (!apps?.ok || !(apps.applications || apps.requests || []).length) fail("A list applications");
  else ok("A sees application");

  const approve = await rpc(A.token, "crownspire_approve_alliance_join", { user_id: B.user_id });
  if (!approve?.ok) fail("approve B", JSON.stringify(approve));
  else ok("A approve B -> " + (approve.rank || "?"));

  const members = await rpc(A.token, "crownspire_list_members", {});
  const roster = members.members || [];
  if (!roster.find((m) => m.user_id === B.user_id)) fail("B missing from roster");
  else ok("B on roster");

  const profileB = await rpc(B.token, "crownspire_get_profile", {});
  if (profileB.profile?.alliance_id !== allianceId) fail("B alliance_id");
  else ok("B membership confirmed");
  if (profileB.profile?.crownspire_rank !== "R1") fail("B should be R1 recruit", profileB.profile?.crownspire_rank);
  else ok("B rank R1");

  // Promote B to R2 then R3
  let setRank = await rpc(A.token, "crownspire_set_member_rank", { user_id: B.user_id, rank: "R2" });
  if (!setRank?.ok) fail("promote R2", setRank?.error || JSON.stringify(setRank));
  else ok("promote B to R2");
  setRank = await rpc(A.token, "crownspire_set_member_rank", { user_id: B.user_id, rank: "R3" });
  if (!setRank?.ok) fail("promote R3");
  else ok("promote B to R3");

  // Unauthorized: B cannot kick A
  try {
    await rpc(B.token, "crownspire_kick_alliance_member", { user_id: A.user_id });
    fail("B should not kick A");
  } catch {
    ok("B cannot kick A");
  }

  // Fake alliance id
  try {
    await rpc(C.token, "crownspire_join_alliance", {
      alliance_id: "00000000-0000-0000-0000-000000000099",
    });
    fail("fake alliance accepted");
  } catch {
    ok("fake alliance rejected");
  }

  // Invite C
  const invite = await rpc(A.token, "crownspire_invite_player", { user_id: C.user_id });
  if (!invite?.ok || !invite.invite?.invite_id) fail("invite C");
  else ok("invite C");

  // Separate reject flow with fresh invite
  const invite2 = await rpc(A.token, "crownspire_invite_player", { user_id: C.user_id });
  if (invite2?.ok && invite2.invite?.invite_id) {
    const rejected = await rpc(C.token, "crownspire_reject_invite", {
      invite_id: invite2.invite.invite_id,
    });
    if (!rejected?.ok) fail("reject invite");
    else ok("C reject invite flow");
  }

  const accept = await rpc(C.token, "crownspire_accept_invite", {
    invite_id: invite.invite.invite_id,
  });
  if (!accept?.ok) fail("accept invite", JSON.stringify(accept));
  else ok("C accept invite");

  const roster2 = (await rpc(A.token, "crownspire_list_members", {})).members || [];
  if (!roster2.find((m) => m.user_id === C.user_id)) fail("C missing after invite accept");
  else ok("C on roster");

  // Transfer leadership A->B then B leaves? First promote B to R4 then transfer
  await rpc(A.token, "crownspire_set_member_rank", { user_id: B.user_id, rank: "R4" });
  const transfer = await rpc(A.token, "crownspire_transfer_leadership", { user_id: B.user_id });
  if (!transfer?.ok) fail("transfer leadership", JSON.stringify(transfer));
  else ok("leadership A->B");

  const pA = await rpc(A.token, "crownspire_get_profile", {});
  const pB = await rpc(B.token, "crownspire_get_profile", {});
  if (pB.profile?.crownspire_rank !== "R5") fail("B not R5 after transfer", pB.profile?.crownspire_rank);
  else ok("B is R5");
  if (pA.profile?.crownspire_rank !== "R4") fail("A not R4 after transfer", pA.profile?.crownspire_rank);
  else ok("A is R4");

  // R5 leave blocked while members remain
  try {
    await rpc(B.token, "crownspire_leave_alliance", {});
    fail("R5 leave should block with members");
  } catch {
    ok("R5 leave blocked with members");
  }

  // A (R4) kicks C
  const kick = await rpc(A.token, "crownspire_kick_alliance_member", { user_id: C.user_id });
  if (!kick?.ok) fail("kick C", JSON.stringify(kick));
  else ok("kick C");
  const pC = await rpc(C.token, "crownspire_get_profile", {});
  if (pC.profile?.alliance_id) fail("C still in alliance");
  else ok("C cleared after kick");

  // B leaves (still R5 with A remaining) — should block
  try {
    await rpc(B.token, "crownspire_leave_alliance", {});
    fail("R5 leave still blocked");
  } catch {
    ok("R5 leave still blocked with A remaining");
  }

  // Transfer back to A, then B leaves as member
  await rpc(B.token, "crownspire_transfer_leadership", { user_id: A.user_id });
  const leaveB = await rpc(B.token, "crownspire_leave_alliance", {});
  if (!leaveB?.ok) fail("B leave", JSON.stringify(leaveB));
  else ok("B leave");

  // Duplicate apply prevention while in alliance
  // A is sole R5 — leave should dissolve
  const leaveA = await rpc(A.token, "crownspire_leave_alliance", {});
  if (!leaveA?.ok) fail("A leave dissolve", JSON.stringify(leaveA));
  else ok("A leave (sole member)");

  // Restart persistence: recreate with fresh user D (A is rate-limited on create).
  const D = await authDevice(`p4-d-${stamp}`);
  await rpc(D.token, "crownspire_get_profile", {});
  const created2 = await rpc(D.token, "crownspire_create_alliance", {
    name: "P4Persist" + String(stamp).slice(-4),
    tag: ("Z" + String(stamp % 1000).padStart(3, "0")).slice(0, 4),
  });
  const aid2 = created2.alliance?.alliance_id || created2.profile?.alliance_id;
  await rpc(B.token, "crownspire_join_alliance", { alliance_id: aid2 });
  await rpc(D.token, "crownspire_approve_alliance_join", { user_id: B.user_id });
  const persistMembers = (await rpc(D.token, "crownspire_list_members", {})).members || [];
  if (persistMembers.length < 2) fail("persist roster");
  else ok("roster persists after recreate/approve");

  // Cleanup
  await rpc(D.token, "crownspire_kick_alliance_member", { user_id: B.user_id }).catch(() => {});
  await rpc(D.token, "crownspire_leave_alliance", {}).catch(() => {});

  finish();
}

function finish() {
  if (fails.length === 0) {
    console.log("[Phase4RPC] PASS");
    process.exit(0);
  }
  console.log(`[Phase4RPC] FAILED count=${fails.length}`);
  process.exit(1);
}

main().catch((e) => {
  console.error("[Phase4RPC] ERROR", e);
  process.exit(1);
});
