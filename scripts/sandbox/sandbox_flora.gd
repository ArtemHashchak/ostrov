class_name SandboxFlora
extends Flora
## Флора «Полигона»: обычная рассадка по острову, но зоны полигона чистые,
## а в зоне «Растения» стоят ряды всех видов деревьев и ресурсов.
## Раскладку задаёт Sandbox до добавления узла: SandboxFlora.showcase / clear.

## [{kind: StringName, pos: Vector2, idx: int}] — что поставить в ряды.
static var showcase: Array = []
## [[Vector3 центр, float радиус]] — зоны без случайной растительности.
static var clear: Array = []

var _showcase_done := false

func _enter_tree() -> void:
	super._enter_tree()
	clear_zones = clear.duplicate()

func _build_trees() -> void:
	if not _showcase_done:
		_showcase_done = true
		_add_showcase()
	super._build_trees()

var _show_recs: Array = []

func _add_showcase() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var last_tree: Dictionary = {}
	_show_recs.clear()
	for e: Dictionary in showcase:
		var kind: StringName = e.kind
		var q: Vector2 = e.pos
		var p := Vector3(q.x, _h(q.x, q.y), q.y)
		match kind:
			&"palm", &"broadleaf", &"banyan", &"mangrove":
				var rec := _add_tree(kind, p, rng, Vector2(p.x, p.z) + Vector2(0, 30))
				rec["idx"] = clampi(int(e.get("idx", 0)), 0, variants_of(kind) - 1)
				rec["yaw"] = 0.4 + float(e.get("idx", 0)) * 1.3
				last_tree = rec
				_show_recs.append(rec)
			&"liana":
				if not last_tree.is_empty():
					_add_liana(last_tree, rng)
			&"bush":
				_place(kind, p, rng, Vector2(p.x, p.z), PROFILES[&"home"], &"meadow", 0.0)
			&"stick", &"stone":
				_show_recs.append(_add_rec({"t": T_PICKUP, "kind": kind, "idx": 7, "pos": p, "yaw": 0.3}))
			&"boulder", &"iron_ore", &"sulfur":
				var ore: StringName = &"" if kind == &"boulder" else kind
				_show_recs.append(_add_rec({"t": T_ROCK, "kind": kind, "ore": ore, "pos": p, "yaw": 0.5,
					"scene": BOULDERS[0], "size": 1.6, "units": 4 if ore != &"" else 7}))
			_:
				_show_recs.append(_add_rec({"t": T_NODE, "kind": kind, "idx": 1, "pos": p + Vector3(0, -0.05, 0), "yaw": 0.2}))

## Вернуть ряды зоны «Растения»: деревья вместо пней, ресурсы на место,
## убрать поваленные стволы, брёвна и щепки в области area (XZ).
func reset_showcase(area: Rect2) -> void:
	var carried: Array = []
	for pl in get_tree().get_nodes_in_group(&"player"):
		var co: Variant = pl.get(&"carried_object")
		if co != null:
			carried.append(co)
	for g in [&"fallen_trunks", &"log", &"stumps"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and area.has_point(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z)) \
					and not carried.has(n) and not (n as Node).is_queued_for_deletion():
				(n as Node).queue_free()
	for rec: Dictionary in _show_recs:
		var n: Variant = rec.get("node")
		if n != null and is_instance_valid(n):
			rec["_out"] = true
			if n is ChoppableTree:
				trees.erase(n)
			(n as Node).queue_free()
		rec["node"] = null
		rec["state"] = 0
		rec["keep"] = false
		_live.erase(rec)
		if rec["t"] == T_TREE:
			_promoted.erase(rec)
			_set_mm_visible(rec, true)
			set_tree_collision(rec, true)
			for l: Dictionary in rec.get("lianas", []):
				var ln: Variant = l.get("node")
				if ln != null and is_instance_valid(ln):
					l["_out"] = true
					(ln as Node).queue_free()
				l["node"] = null
				l["state"] = 0
				l["keep"] = false
				_live.erase(l)
	_tick(true)
