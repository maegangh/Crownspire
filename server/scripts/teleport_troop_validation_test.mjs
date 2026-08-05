/**
 * Malformed troop / deployment payload validation (mirrors phase55 checks).
 * Run: node server/scripts/teleport_troop_validation_test.mjs
 */

function isStrictNonNegInt(v) {
  return typeof v === "number" && isFinite(v) && !isNaN(v) && v >= 0 && Math.floor(v) === v;
}

function trimStr(v) {
  return String(v == null ? "" : v).replace(/^\s+|\s+$/g, "");
}

function validateDeploymentBegin(body) {
  if (!body || typeof body !== "object") return "Invalid JSON";
  const deploymentId = trimStr(body.deployment_id || "");
  const kind = trimStr(body.kind || "");
  if (deploymentId.length < 8 || deploymentId.length > 80) return "Invalid deployment_id.";
  if (kind !== "march" && kind !== "gather" && kind !== "rally" && kind !== "reinforce") {
    return "Invalid deployment kind.";
  }
  return null;
}

function validateRelocateCoords(body) {
  if (!Object.prototype.hasOwnProperty.call(body, "world_x") || !Object.prototype.hasOwnProperty.call(body, "world_y")) {
    return "Missing coordinates.";
  }
  if (typeof body.world_x !== "number" || typeof body.world_y !== "number") {
    return "Coordinates must be numbers.";
  }
  if (!isFinite(body.world_x) || !isFinite(body.world_y) || isNaN(body.world_x) || isNaN(body.world_y)) {
    return "Invalid coordinates.";
  }
  return null;
}

/** Retired set_troop_activity — always reject (server throws). */
function validateRetiredTroopActivity(_body) {
  return "crownspire_set_troop_activity is retired. Use deployment begin/end.";
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
function assert(c, m) {
  if (!c) throw new Error(m);
}

test("reject loose troop wipe payload", () => {
  assert(validateRetiredTroopActivity({ active_marches: 0, gathering: false }) != null, "retired");
});

test("reject malformed deployment begin", () => {
  assert(validateDeploymentBegin({}) != null, "empty");
  assert(validateDeploymentBegin({ deployment_id: "short", kind: "march" }) != null, "short id");
  assert(validateDeploymentBegin({ deployment_id: "march_12345678", kind: "nope" }) != null, "kind");
  assert(validateDeploymentBegin({ deployment_id: "march_12345678", kind: "march" }) === null, "ok");
});

test("reject NaN/inf/string coords", () => {
  assert(validateRelocateCoords({ world_x: "1", world_y: 2 }) != null, "string");
  assert(validateRelocateCoords({ world_x: NaN, world_y: 2 }) != null, "nan");
  assert(validateRelocateCoords({ world_x: Infinity, world_y: 2 }) != null, "inf");
  assert(validateRelocateCoords({ world_x: -1, world_y: 2 }) === null, "neg number type ok at parse; spacing rejects later");
  assert(validateRelocateCoords({ world_x: 1000, world_y: 1000 }) === null, "ok");
});

test("reject non-int local_count style values", () => {
  assert(!isStrictNonNegInt("1"), "string");
  assert(!isStrictNonNegInt(1.5), "float");
  assert(!isStrictNonNegInt(NaN), "nan");
  assert(!isStrictNonNegInt(-1), "neg");
  assert(isStrictNonNegInt(0), "zero");
  assert(isStrictNonNegInt(3), "int");
});

console.log(`\n${passed} tests passed`);
if (process.exitCode) process.exit(1);
