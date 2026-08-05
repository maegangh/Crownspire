/**
 * Multi-seed crownspire_map_blockers_v1 coords (must match MapPlacementContract.gd / phase55).
 * Run: node server/scripts/contract_compare.mjs
 */

function fnv1a32(text) {
  let h = 2166136261;
  const s = String(text || "");
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
function kingdomSeed(kid, salt) {
  return fnv1a32(String(salt) + "|" + String(kid || ""));
}
function mulberry32(seed) {
  let state = seed >>> 0;
  return function () {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const WORLD = 8192;
const MAX_A = 250;
function findValid(rng, occupied, radius, edge) {
  const minC = edge + radius;
  const maxC = WORLD - edge - radius;
  if (maxC <= minC) return null;
  for (let a = 0; a < MAX_A; a++) {
    const x = minC + rng() * (maxC - minC);
    const y = minC + rng() * (maxC - minC);
    let ok = true;
    for (const o of occupied) {
      const dx = x - o.x;
      const dy = y - o.y;
      if (Math.sqrt(dx * dx + dy * dy) < radius + o.radius) {
        ok = false;
        break;
      }
    }
    if (ok) return { x, y };
  }
  return null;
}
function append(out, occupied, rng, kind, count, radius, edge) {
  for (let i = 0; i < count; i++) {
    const pos = findValid(rng, occupied, radius, edge);
    if (!pos) continue;
    const b = { kind, x: pos.x, y: pos.y, radius };
    occupied.push(b);
    out.push(b);
  }
}
function compute(kid) {
  const out = [];
  const occupied = [];
  const terrain = mulberry32(kingdomSeed(kid, "terrain_v1"));
  append(out, occupied, terrain, "lake", 6, 700, 450);
  append(out, occupied, terrain, "mountain", 18, 550, 450);
  append(out, occupied, terrain, "forest", 35, 425, 450);
  append(out, occupied, terrain, "rock", 30, 250, 450);
  const poi = mulberry32(kingdomSeed(kid, "poi_v1"));
  append(out, occupied, poi, "resource", 40, 160, 300);
  append(out, occupied, poi, "wildling", 30, 120, 300);
  append(out, occupied, poi, "lair", 10, 360, 300);
  return out;
}

const seeds = ["kingdom_dev_001", "kingdom_alpha", "k_seed_xyz"];
const report = {};
for (const kid of seeds) {
  const all = compute(kid);
  const resources = all.filter((b) => b.kind === "resource").slice(0, 5);
  report[kid] = {
    total: all.length,
    resources: resources.map((r) => ({ x: r.x, y: r.y })),
  };
  console.log(JSON.stringify({ seed: kid, total: all.length, first_resource: resources[0] }));
}
const fs = await import("fs");
fs.writeFileSync(new URL("./contract_coords.json", import.meta.url), JSON.stringify(report, null, 2));
console.log("wrote contract_coords.json");
