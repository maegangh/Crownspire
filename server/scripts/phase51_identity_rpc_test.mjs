/**
 * Phase 5.1 identity/presence RPC smoke test.
 * LOCAL DEVELOPMENT ONLY.
 */
const HOST = process.env.NAKAMA_HOST || "http://127.0.0.1:7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "defaultkey";

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
  console.log("[Phase51RPC] OK ", msg);
}
function fail(msg, detail) {
  console.error("[Phase51RPC] FAIL", msg, detail || "");
  process.exitCode = 1;
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function main() {
  console.log("[Phase51RPC] BEGIN against", HOST);
  const stamp = Date.now();
  const A = await authDevice(`p51-a-${stamp}`);
  const B = await authDevice(`p51-b-${stamp}`);
  ok("authenticate");

  const profileA = await rpc(A.token, "crownspire_get_profile", {});
  if (!profileA?.profile?.user_id) fail("get profile", JSON.stringify(profileA));
  else ok("get profile has identity fields=" + !!profileA.profile.avatar_id);

  const renamed = await rpc(A.token, "crownspire_set_display_name", {
    display_name: "BetaHero" + String(stamp).slice(-4),
  });
  if (!renamed?.ok) fail("rename", JSON.stringify(renamed));
  else ok("rename free beta");

  const identity = await rpc(A.token, "crownspire_update_player_identity", {
    avatar_id: "avatar_03",
    power: 12345,
    citadel_level: 7,
    vip_level: 2,
  });
  if (!identity?.ok || identity.profile?.avatar_id !== "avatar_03") fail("update identity", JSON.stringify(identity));
  else ok("update identity avatar/power/citadel/vip");

  await sleep(2200);
  const badAvatar = await rpc(A.token, "crownspire_update_player_identity", { avatar_id: "not_real" });
  if (badAvatar?.profile?.avatar_id !== "avatar_01") fail("invalid avatar fallback", JSON.stringify(badAvatar));
  else ok("invalid avatar sanitized");

  const hb = await rpc(A.token, "crownspire_presence_heartbeat", {
    power: 12345,
    citadel_level: 7,
    vip_level: 2,
  });
  if (!hb?.ok || hb.online_status !== "online") fail("heartbeat", JSON.stringify(hb));
  else ok("presence heartbeat online");

  await sleep(2200);
  await rpc(A.token, "crownspire_update_player_identity", { avatar_id: "avatar_05" });
  const pub2 = await rpc(B.token, "crownspire_get_public_profile", { user_id: profileA.profile.user_id });
  if (!pub2?.ok || pub2.profile?.avatar_id !== "avatar_05") fail("public profile", JSON.stringify(pub2));
  else ok("public profile shows avatar/power");

  if (process.exitCode) console.log("[Phase51RPC] FAILED");
  else console.log("[Phase51RPC] PASS");
}

main().catch((e) => {
  console.error("[Phase51RPC] ERROR", e);
  process.exit(1);
});
