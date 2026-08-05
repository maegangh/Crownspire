extends RefCounted
class_name MapPlacementContract

## Shared kingdom map placement contract (client + Nakama TS must match).
## Contract id: crownspire_map_blockers_v1
## Uses portable mulberry32 — NOT Godot RandomNumberGenerator (not reproducible on server).

const CONTRACT_ID: String = "crownspire_map_blockers_v1"
const WORLD_SIZE: float = 8192.0
const CASTLE_EDGE_MARGIN: float = 900.0
const CASTLE_MIN_SPACING: float = 500.0

## Terrain packing (lakes → mountains). Independent of any player's castle.
const TERRAIN_EDGE_MARGIN: float = 450.0
const LAKE_COUNT: int = 6
const LAKE_RADIUS: float = 700.0
const MOUNTAIN_COUNT: int = 18
const MOUNTAIN_RADIUS: float = 550.0
const FOREST_COUNT: int = 35
const FOREST_RADIUS: float = 425.0
const ROCK_COUNT: int = 30
const ROCK_RADIUS: float = 250.0

## Deterministic POI layers (resources / wildlings / lairs) for occupancy checks.
const RESOURCE_COUNT: int = 40
const RESOURCE_RADIUS: float = 160.0
const WILDLING_COUNT: int = 30
const WILDLING_RADIUS: float = 120.0
const LAIR_COUNT: int = 10
const LAIR_RADIUS: float = 360.0
const POI_EDGE_MARGIN: float = 300.0

const MAX_ATTEMPTS: int = 250


static func kingdom_seed(kingdom_id: String, salt: String) -> int:
	## Portable FNV-1a 32-bit (matches server fnv1a32Teleport).
	var h: int = 2166136261
	var s: String = "%s|%s" % [salt, str(kingdom_id)]
	for i in range(s.length()):
		h = _imul32(h ^ s.unicode_at(i), 16777619)
	return h & 0xFFFFFFFF


static func _imul32(a: int, b: int) -> int:
	## Match JavaScript Math.imul / unsigned 32-bit multiply.
	return int((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF


static func mulberry32(seed_u32: int) -> Callable:
	var state: Array = [seed_u32 & 0xFFFFFFFF]
	return func() -> float:
		var t: int = (int(state[0]) + 0x6D2B79F5) & 0xFFFFFFFF
		state[0] = t
		var r: int = t
		r = _imul32(r ^ (r >> 15), r | 1)
		r = (r ^ (r + _imul32(r ^ (r >> 7), r | 61))) & 0xFFFFFFFF
		return float((r ^ (r >> 14)) & 0xFFFFFFFF) / 4294967296.0


static func compute_blockers(kingdom_id: String) -> Array:
	## Returns Array of {kind, x, y, radius} for all shared blocked zones.
	var kid: String = str(kingdom_id).strip_edges()
	if kid == "":
		kid = "kingdom_dev_001"
	var out: Array = []
	var occupied: Array = [] ## {x,y,radius}
	var terrain_rng: Callable = mulberry32(kingdom_seed(kid, "terrain_v1"))
	_append_packed(out, occupied, terrain_rng, "lake", LAKE_COUNT, LAKE_RADIUS, TERRAIN_EDGE_MARGIN)
	_append_packed(out, occupied, terrain_rng, "mountain", MOUNTAIN_COUNT, MOUNTAIN_RADIUS, TERRAIN_EDGE_MARGIN)
	_append_packed(out, occupied, terrain_rng, "forest", FOREST_COUNT, FOREST_RADIUS, TERRAIN_EDGE_MARGIN)
	_append_packed(out, occupied, terrain_rng, "rock", ROCK_COUNT, ROCK_RADIUS, TERRAIN_EDGE_MARGIN)

	var poi_rng: Callable = mulberry32(kingdom_seed(kid, "poi_v1"))
	_append_packed(out, occupied, poi_rng, "resource", RESOURCE_COUNT, RESOURCE_RADIUS, POI_EDGE_MARGIN)
	_append_packed(out, occupied, poi_rng, "wildling", WILDLING_COUNT, WILDLING_RADIUS, POI_EDGE_MARGIN)
	_append_packed(out, occupied, poi_rng, "lair", LAIR_COUNT, LAIR_RADIUS, POI_EDGE_MARGIN)
	return out


static func blockers_of_kinds(kingdom_id: String, kinds: PackedStringArray) -> Array:
	var all: Array = compute_blockers(kingdom_id)
	var filtered: Array = []
	for b in all:
		if str(b.get("kind", "")) in kinds:
			filtered.append(b)
	return filtered


static func validate_castle_candidate(
	kingdom_id: String,
	x: float,
	y: float,
	other_castles: Array,
	self_user_id: String = ""
) -> Dictionary:
	## Local/server-shared geometry check (castles + contract blockers).
	if not is_finite(x) or not is_finite(y):
		return {"ok": false, "error": "Invalid coordinates."}
	if x < CASTLE_EDGE_MARGIN or y < CASTLE_EDGE_MARGIN \
			or x > WORLD_SIZE - CASTLE_EDGE_MARGIN or y > WORLD_SIZE - CASTLE_EDGE_MARGIN:
		return {"ok": false, "error": "Too close to the map edge."}
	for c in other_castles:
		var uid: String = str(c.get("user_id", ""))
		if self_user_id != "" and uid == self_user_id:
			continue
		var cx: float = float(c.get("world_x", c.get("x", 0.0)))
		var cy: float = float(c.get("world_y", c.get("y", 0.0)))
		if Vector2(x, y).distance_to(Vector2(cx, cy)) < CASTLE_MIN_SPACING:
			return {"ok": false, "error": "Too close to another castle."}
	for b in compute_blockers(kingdom_id):
		var bx: float = float(b.get("x", 0.0))
		var by: float = float(b.get("y", 0.0))
		var br: float = float(b.get("radius", 0.0))
		## Castle footprint uses CASTLE_MIN_SPACING/2 as soft radius vs POI radius.
		var need: float = br + (CASTLE_MIN_SPACING * 0.5)
		if Vector2(x, y).distance_to(Vector2(bx, by)) < need:
			var kind: String = str(b.get("kind", "obstacle"))
			return {"ok": false, "error": "Blocked by %s." % kind}
	return {"ok": true, "error": ""}


static func _append_packed(
	out: Array,
	occupied: Array,
	rng: Callable,
	kind: String,
	count: int,
	radius: float,
	edge: float
) -> void:
	for _i in range(count):
		var pos: Vector2 = _find_valid(rng, occupied, radius, edge)
		if pos == Vector2.INF:
			continue
		occupied.append({"x": pos.x, "y": pos.y, "radius": radius})
		out.append({"kind": kind, "x": pos.x, "y": pos.y, "radius": radius})


static func _find_valid(rng: Callable, occupied: Array, radius: float, edge: float) -> Vector2:
	var min_c: float = edge + radius
	var max_c: float = WORLD_SIZE - edge - radius
	if max_c <= min_c:
		return Vector2.INF
	for _a in range(MAX_ATTEMPTS):
		var x: float = min_c + float(rng.call()) * (max_c - min_c)
		var y: float = min_c + float(rng.call()) * (max_c - min_c)
		var ok := true
		for area in occupied:
			var ax: float = float(area.get("x", 0.0))
			var ay: float = float(area.get("y", 0.0))
			var ar: float = float(area.get("radius", 0.0))
			if Vector2(x, y).distance_to(Vector2(ax, ay)) < (radius + ar):
				ok = false
				break
		if ok:
			return Vector2(x, y)
	return Vector2.INF
