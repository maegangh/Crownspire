/**
 * Beta Alliance RPC smoke test — create (open + apply), join, list, settings, leave.
 * Requires local Nakama on 127.0.0.1:7350 with defaultkey.
 */
const HOST = process.env.NAKAMA_HOST || "http://127.0.0.1:7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

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
  return { token: data.token };
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
  if (!res.ok) {
    const err = data.error || data.message || JSON.stringify(data);
    throw new Error(`${id}: ${err}`);
  }
  return typeof data === "string" ? JSON.parse(data || "{}") : data;
}

async function main() {
  const stamp = Date.now().toString(36).slice(-6).toUpperCase();
  const leader = await authDevice(`alliance_beta_leader_${stamp}`);
  const joiner = await authDevice(`alliance_beta_joiner_${stamp}`);

  const leaderProfile = await rpc(leader.token, "crownspire_get_profile", {});
  const joinerProfile = await rpc(joiner.token, "crownspire_get_profile", {});
  leader.user_id = leaderProfile.profile.user_id;
  joiner.user_id = joinerProfile.profile.user_id;

  const openName = `Open Banner ${stamp}`;
  const openTag = `O${stamp.slice(0, 3)}`;
  const createdOpen = await rpc(leader.token, "crownspire_create_alliance", {
    name: openName,
    tag: openTag,
    description: "Open beta alliance",
    language: "en",
    join_type: "open",
    min_citadel_level: 0,
  });
  assert(createdOpen.ok === true, `create open failed: ${JSON.stringify(createdOpen)}`);
  assert(createdOpen.alliance?.join_type === "open", "join_type should be open");
  assert(createdOpen.profile?.crownspire_rank === "R5", "creator should be R5");
  const openId = createdOpen.alliance.alliance_id;
  console.log("[AllianceBeta] created open", openTag, openId);

  const leader2 = await authDevice(`alliance_beta_leader2_${stamp}`);
  await rpc(leader2.token, "crownspire_get_profile", {});
  const applyName = `Apply Banner ${stamp}`;
  const applyTag = `A${stamp.slice(0, 3)}`;
  const createdApply = await rpc(leader2.token, "crownspire_create_alliance", {
    name: applyName,
    tag: applyTag,
    description: "Approval required alliance",
    language: "en",
    join_type: "apply",
    min_citadel_level: 1,
  });
  assert(createdApply.ok === true, `create apply failed: ${JSON.stringify(createdApply)}`);
  assert(createdApply.alliance?.join_type === "apply", "join_type should be apply");
  const applyId = createdApply.alliance.alliance_id;
  console.log("[AllianceBeta] created apply", applyTag, applyId);

  const listed = await rpc(joiner.token, "crownspire_list_alliances", { query: stamp });
  assert(listed.ok === true, "list failed");
  const foundOpen = (listed.alliances || []).find((a) => a.alliance_id === openId);
  const foundApply = (listed.alliances || []).find((a) => a.alliance_id === applyId);
  assert(foundOpen, "open alliance missing from list");
  assert(foundApply, "apply alliance missing from list");
  assert(foundOpen.join_type === "open", "list open join_type");
  assert(foundApply.join_type === "apply", "list apply join_type");
  assert(!String(foundOpen.name || "").toLowerCase().includes("placeholder"), "placeholder name leak");

  const joined = await rpc(joiner.token, "crownspire_join_alliance", { alliance_id: openId });
  assert(joined.ok === true, `open join failed: ${JSON.stringify(joined)}`);
  assert(joined.pending === false, "open join should not be pending");
  assert(joined.profile?.alliance_id === openId, "joiner profile alliance_id");
  console.log("[AllianceBeta] open join ok");

  const left = await rpc(joiner.token, "crownspire_leave_alliance", {});
  assert(left.ok === true, `leave failed: ${JSON.stringify(left)}`);

  const applied = await rpc(joiner.token, "crownspire_join_alliance", { alliance_id: applyId });
  assert(applied.ok === true, `apply failed: ${JSON.stringify(applied)}`);
  assert(applied.pending === true, "apply should be pending");
  console.log("[AllianceBeta] application sent");

  const dup = await rpc(joiner.token, "crownspire_join_alliance", { alliance_id: applyId });
  assert(dup.ok === true && dup.pending === true, "duplicate apply should remain pending");

  const reqs = await rpc(leader2.token, "crownspire_list_alliance_join_requests", {});
  assert(reqs.ok === true, "list requests failed");
  const apps = reqs.applications || reqs.requests || [];
  assert(apps.some((a) => a.user_id === joiner.user_id), "joiner missing from applications");

  const approved = await rpc(leader2.token, "crownspire_approve_alliance_join", {
    user_id: joiner.user_id,
  });
  assert(approved.ok === true, `approve failed: ${JSON.stringify(approved)}`);
  console.log("[AllianceBeta] application approved");

  const settings = await rpc(leader2.token, "crownspire_update_alliance_profile", {
    description: "Updated desc",
    announcement: "Beta announce",
    language: "en",
    join_type: "open",
    min_citadel_level: 0,
  });
  assert(settings.ok === true, `settings failed: ${JSON.stringify(settings)}`);
  assert(settings.alliance?.join_type === "open", "settings join_type");
  assert(settings.alliance?.announcement === "Beta announce", "announcement");
  console.log("[AllianceBeta] settings ok");

  console.log("[AllianceBeta] PASS");
}

main().catch((err) => {
  console.error("[AllianceBeta] FAIL", err);
  process.exit(1);
});
