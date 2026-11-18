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

func _add_showcase() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var prof: Dictionary = PROFILES[&"home"]
	var last_tree: Dictionary = {}
	for e: Dictionary in showcase:
		var kind: StringName = e.kind
		var q: Vector2 = e.pos
		var p := Vector3(q.x, _h(q.x, q.y), q.y)
		match kind:
			&"palm", &"broadleaf", &"banyan", &"mangrove":
				var rec := _add_tree(kind, p, rng, Vector2(p.x, p.z) + Vector2(0, 30))
				rec["idx"] = clampi(int(e.get("idx", 0)), 0, int(VARIANTS[kind]) - 1)
				rec["yaw"] = 0.4 + float(e.get("idx", 0)) * 1.3
				last_tree = rec
			&"liana":
				if not last_tree.is_empty():
					_add_liana(last_tree, rng)
			_:
				_place(kind, p, rng, Vector2(p.x, p.z), prof, &"meadow", 0.0)
