class_name SandboxFloraPack
extends RefCounted
## «Сад пака» на полигоне: ВСЕ готовые растения из пака пользователя (FloraPack) рядами с подписями —
## пальмы, мангры, зонтичные деревья, подлесок джунглей, кусты, папоротники, орхидеи, кокосы.
## Место — ровный берег рядом с зоной «Пак моделей» (ищется по высотам при сборке полигона).

const P := preload("res://scripts/sandbox/sandbox_props.gd")

const NAMES := {
	"palm": "Пальма кокосовая", "mangrove": "Мангр", "umbrella": "Дерево с зонтичной кроной",
	"alocasia_big": "Алоказия крупная", "alocasia_young": "Алоказия молодая", "alocasia_var": "Алоказия пёстрая",
	"bamboo_small": "Бамбук мелкий", "banana": "Банан", "colocasia1": "Колоказия (1)", "colocasia2": "Колоказия (2)",
	"dieffenbachia": "Диффенбахия", "dracaena_branched": "Драцена ветвистая", "dracaena_fragrans": "Драцена душистая",
	"fern_asplenium": "Асплениум", "fern_low": "Папоротник низкий", "fern_nephrolepis": "Нефролепис",
	"fern_nest": "Папоротник-гнездо", "fern_sword": "Папоротник мечевидный", "fern_pinnate_small": "Папоротник перистый",
	"grass_curculigo": "Куркулиго", "monstera": "Монстера", "orchid_pink": "Орхидея розовая", "orchid_white": "Орхидея белая",
	"epi": "Орхидея-эпифит", "palm_areca": "Пальма арека", "palm_bush_stemless": "Пальма кустовая",
	"palm_rhapis": "Рапис", "palm_short_trunk": "Пальма низкая", "sapling_umbrella": "Саженец зонтичный",
	"shrub_bluehibiscus": "Куст с фиолетовыми цветами", "shrub_ixora": "Иксора", "shrub_smallleaf": "Кустарник мелколистный",
	"spathiphyllum": "Спатифиллум", "coconut": "Кокосы",
}

static func build(root: Node3D, near: Vector2) -> void:
	if not FloraPack.available():
		return
	var meta := FloraPack._load()
	var trees: Array = []
	var plants: Array = []
	var nuts: Array = []
	for id: String in meta:
		match String(meta[id].get("group", "")):
			"tree":
				trees.append(id)
			"plant":
				plants.append(id)
			"coconut":
				nuts.append(id)
	trees.sort()
	plants.sort()
	nuts.sort()
	# ряды: деревья — шаг 11 м, растения — 3 м по 12 в ряд
	var w := 12 * 3.0
	var rows := int(ceil(plants.size() / 12.0))
	var depth := 14.0 + rows * 3.2 + 4.0
	var c := _find_place(near, maxf(w, 6 * 11.0), depth)
	var x0 := c.x - 5.5 * 11.0 * 0.5
	var z0 := c.y - depth * 0.5
	P.signpost(root, c.x - 6.0, z0 - 3.0, "САД ПАКА", "Все готовые растения из пака пользователя\nв игре: ближний LOD автора (LOD1), вдали — LOD2")
	var i := 0
	for id: String in trees:
		var col := i % 6
		var row := i / 6
		var x := x0 + col * 11.0
		var z := z0 + row * 12.0 - 26.0
		_put(root, FloraPack.mesh(id, 1), Vector3(x, P.ground(x, z) - 0.05, z), 0.0)
		P.tag(root, x, z + 1.5, "%s · %s\n%d / %d треуг." % [NAMES.get(id.split("_")[0], id), id, int(meta[id].get("tris_l1", 0)), int(meta[id].get("tris_l2", 0))], 1.4, 40.0)
		i += 1
	for k in plants.size():
		var id: String = plants[k]
		var x := c.x - w * 0.5 + (k % 12) * 3.0
		var z := z0 + 14.0 + (k / 12) * 3.2
		var g := P.ground(x, z)
		var sp := FloraPack._species_of(id)
		if sp == "epi":
			# эпифит — на столбике (как на стволе)
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.18
			cm.bottom_radius = 0.22
			cm.height = 2.0
			post.mesh = cm
			post.material_override = FloraLib.bark_material("pack:Umbrella_Bark")
			root.add_child(post)
			post.global_position = Vector3(x, g + 1.0, z)
			_put(root, FloraPack.mesh(id, 1), Vector3(x + 0.18, g + 1.5, z), 0.0)
		else:
			_put(root, FloraPack.mesh(id, 1), Vector3(x, g - 0.02, z), 0.6)
		P.tag(root, x, z + 1.1, "%s\n%s · %d тр." % [NAMES.get(sp, sp), id, int(meta[id].get("tris_l1", 0))], 0.35 if sp != "epi" else 2.3, 18.0)
	# кокосы: на подставке
	var zc := z0 + 14.0 + rows * 3.2 + 1.5
	for k in nuts.size():
		var id: String = nuts[k]
		var x := c.x - w * 0.5 + k * 1.0
		var g := P.ground(x, zc)
		_put(root, FloraPack.mesh(id, 1), Vector3(x, g + 0.15, zc), 0.0)
	P.tag(root, c.x - w * 0.5 + 5.0, zc + 0.8, "Кокосы: зелёный, жёлто-зелёный, с плодоножкой, бурый орех, «мохнатый», половинки, осколки", 0.6, 18.0)

static func _put(root: Node3D, mesh: Mesh, pos: Vector3, yaw: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw

## Ровное место на суше рядом с near: кольцо кандидатов, без воды и крутизны, вдали от других зон.
static func _find_place(near: Vector2, w: float, d: float) -> Vector2:
	var best := near + Vector2(0, -60)
	var best_s := 1e9
	for ri in [55.0, 75.0, 95.0, 120.0]:
		for ai in 24:
			var a := TAU * ai / 24.0
			var c: Vector2 = near + Vector2(cos(a), sin(a)) * ri
			var bad := false
			for zid in SandboxZones.ZONES:
				var z: Dictionary = SandboxZones.ZONES[zid]
				if (z.c as Vector2).distance_to(c) < float(z.r) + maxf(w, d) * 0.6:
					bad = true
			if bad:
				continue
			var hs: Array = []
			for j in 5:
				for k in 5:
					var q := c + Vector2((k - 2) * w * 0.25, (j - 2) * d * 0.25)
					hs.append(P.ground(q.x, q.y))
			var lo: float = hs.min()
			var hi: float = hs.max()
			if lo < 1.0:
				continue
			var s: float = (hi - lo) + ri * 0.02
			if s < best_s:
				best_s = s
				best = c
	return best
