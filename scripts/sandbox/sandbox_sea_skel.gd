class_name SandboxSeaSkel
extends RefCounted
## Полигон (раздел «Море», на берегу) — морские модели со скелетом и клипами автора (SeaSkel, 2026-11-22):
##  * на суше: витрины в три ряда (рифовые рыбы · крупные · донные), каждая модель по кругу
##    показывает все свои клипы; подпись — вид, треугольники (LOD0 / LOD1), текущий клип;
##  * под водой у пирса: живые особи всех видов со скелетом с поведением по заданиям автора
##    (испуг, угроза и бросок мурены, скат зарывается, манта кормится, черепаха дышит, щелчок
##    креветки…), стая сардин (VAT) и стая хирургов; точки телепорта «pack_skel_row» и «pack_skel_sea».

const P := preload("res://scripts/sandbox/sandbox_props.gd")

## Ряды витрин: модели в порядке показа и масштаб показа (мелкие — крупнее, чтобы читались).
const ROWS := [
	["clownfish", "tang_blue", "tang_yellow", "tang_regal", "copperband", "angel_emperor", "angel_emperor_juv",
		"angel_blueyellow", "triggerfish_clown", "mandarin", "aulonocara", "discus", "sardine"],
	["barracuda", "giant_grouper", "moray", "squid_red", "dolphin", "manta", "stingray", "turtle_green", "turtle_hawksbill"],
	["lobster", "shrimp_pistol", "starfish_orange", "starfish_spiny", "seacucumber_spotted", "seacucumber_grey"],
]

## Витрина: модель на месте, клипы по кругу (по 1–2 цикла каждый).
class Showcase extends Node3D:
	var s: SeaSkel
	var lbl: Label3D
	var head := ""
	var clips: Array = []
	var i := -1
	var left := 0.0
	func _ready() -> void:
		var ap := s.player()
		if ap:
			for a in ap.get_animation_list():
				clips.append(String(a))
	func _process(dt: float) -> void:
		var ap := s.player() if s else null
		if ap == null or clips.is_empty():
			return
		left -= dt
		if left > 0.0:
			return
		i = (i + 1) % clips.size()
		var c := String(clips[i])
		ap.play(c, 0.2)
		ap.seek(0.0, true)
		var ln := ap.get_animation(c).length
		left = maxf(ln * (2.0 if ap.get_animation(c).loop_mode != Animation.LOOP_NONE else 1.0), 1.6) + 0.4
		if lbl:
			lbl.text = "%s\nклип: %s  (%d/%d)" % [head, c, i + 1, clips.size()]


static func build(root: Node3D, c: Vector2) -> void:
	var z_rows := [c.y - 17.0, c.y - 22.5, c.y - 27.5]
	var step := 3.4
	var placed := 0
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var x0 := c.x - (row.size() - 1) * step * 0.5
		var z: float = z_rows[r]
		for k in row.size():
			var id := String(row[k])
			if not SeaSkel.has(id):
				continue
			var d := SeaSkel.def(id)
			var L := float(d.len)
			var x := x0 + k * step
			var g := P.ground(x, z)
			var ground_kind := bool(d.get("ground", false))
			# показ: мелкие ×3…×6, крупные — уменьшены до ~2.6 м
			var k_show := clampf(0.45 / L, 1.0, 6.0) if L < 0.45 else minf(1.0, 2.6 / L)
			var h := 0.35 if ground_kind else 1.1
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55 if ground_kind else 0.1
			cm.bottom_radius = 0.6 if ground_kind else 0.18
			cm.height = h
			post.mesh = cm
			post.material_override = P._post_mat()
			root.add_child(post)
			post.global_position = Vector3(x, g + h * 0.5, z)
			var sc := Showcase.new()
			sc.name = "SkelShow_" + id
			sc.s = SeaSkel.create(id, L * k_show, 77 + k)
			sc.add_child(sc.s)
			root.add_child(sc)
			var hb := SeaSkel.bounds(id).size.y * k_show
			sc.global_position = Vector3(x, g + h + (0.0 if ground_kind else 0.15 + hb * 0.5), z)
			sc.rotation.y = PI * 0.5 if not ground_kind else PI * 0.25   # боком к дорожке
			var tri := "%s треуг." % _n(int(d.tris))
			if d.has("tris_lod1"):
				tri += " · LOD1 %s" % _n(int(d.tris_lod1))
			var show := "" if is_equal_approx(k_show, 1.0) else ("  (×%s)" % str(snappedf(k_show, 0.1)))
			sc.head = "%s · %s м%s\n%s · клипов %d" % [String(d.name), str(snappedf(L, 0.01)), show, tri,
				sc.s.player().get_animation_list().size() if sc.s.player() else 0]
			sc.lbl = P.label(root, Vector3(x, g + h + 0.3 + hb + (0.0 if ground_kind else 0.15) + 0.55, z), sc.head, 20, P.SIGN_COLOR, 26.0)
			placed += 1
	P.signpost(root, c.x - 22.0, c.y - 17.0, "МОРЕ: МОДЕЛИ СО СКЕЛЕТОМ",
		"%d моделей автора · клипы по кругу\nпод водой у пирса — живые, с поведением" % placed)


## Тик стай витрины (вне режиссёра сцен; duration = 0 — без конца).
class Ticker extends Node:
	var stage: SeaScene
	func _process(dt: float) -> void:
		if is_instance_valid(stage):
			stage.tick(dt)


static func _n(i: int) -> String:
	return str(i) if i < 1000 else "%.1fk" % (i / 1000.0)
