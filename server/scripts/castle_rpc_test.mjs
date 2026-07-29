/**
 * Kingdom castle registry smoke — two users get stable world coords and appear in list.
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
  if (!res.ok) throw new Error(`${id}: ${JSON.stringify(data)}`);
  return typeof data === "string" ? JSON.parse(data || "{}") : data;
}

async function main() {
  const stamp = Date.now().toString(36);
  const a = await authDevice(`castle_a_${stamp}`);
  const b = await authDevice(`castle_b_${stamp}`);
  const pa = await rpc(a.token, "crownspire_get_profile", {});
  const pb = await rpc(b.token, "crownspire_get_profile", {});
  assert(pa.ok && pb.ok, "profiles");
  assert(pa.profile.world_x > 0 && pa.profile.world_y > 0, "A coords");
  assert(pb.profile.world_x > 0 && pb.profile.world_y > 0, "B coords");
  assert(
    pa.profile.world_x !== pb.profile.world_x || pa.profile.world_y !== pb.profile.world_y,
    "coords should differ for different users"
  );

  const listA = await rpc(a.token, "crownspire_list_kingdom_castles", {});
  assert(listA.ok === true, "list ok");
  const ids = (listA.castles || []).map((c) => c.user_id);
  assert(ids.includes(pa.profile.user_id), "A in registry");
  assert(ids.includes(pb.profile.user_id), "B in registry");

  // Stable across reconnect list.
  const listA2 = await rpc(a.token, "crownspire_list_kingdom_castles", {});
  const aEntry = listA2.castles.find((c) => c.user_id === pa.profile.user_id);
  assert(aEntry.world_x === pa.profile.world_x && aEntry.world_y === pa.profile.world_y, "stable coords");
  console.log("[CastleRPC] PASS castles=", listA2.castles.length);
}

main().catch((e) => {
  console.error("[CastleRPC] FAIL", e);
  process.exit(1);
});
