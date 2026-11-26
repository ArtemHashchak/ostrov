class_name SandboxSeahorse
extends RefCounted
## Полигон (раздел «Море», у начала пирса) — морской конёк (модель автора, 3 расцветки; скелет и клипы
## процедурные, см. tools/seahorse/build_seahorse.py):
##  * на суше (за рядами моделей со скелетом): три конька на тумбах держатся хвостом за лист травы /
##    веточку коралла (поза grip, по очереди кормятся и косятся глазами), четвёртый — все клипы по кругу;
##    показ ×4 (конёк 14 см); точка телепорта «pack_seahorse»;
##  * под водой: живые коньки всех расцветок — у витрины «модели со скелетом» (SandboxSeaSkel.build_sea),
##    сцена «коньки держатся за траву» — в списке сцен моря.

const P := preload("res://scripts/sandbox/sandbox_props.gd")
const IDS := ["seahorse_yellow", "seahorse_lilac", "seahorse_red"]
const SHOW := 4.0

## Витрина «держится»: конёк в позе grip на стебле, по очереди кормится/косится.
class Clinger extends Node3D:
	var s: SeaSkel
	var hs: SeaHoldfast
	var lbl: Label3D
	var head := ""
	var cd := 2.0
	var rng := RandomNumberGenerator.new()
	func _ready() -> void:
		s.rest_pose = "grip"
	func _process(dt: float) -> void:
		if s == null or hs == null:
			return
		s.drive(dt, 0.0, 0.05, 0.0, true)
		cd -= dt
		if cd <= 0.0 and not s.busy():
			var r := "grip_eat" if rng.randf() < 0.55 else "grip_look"
			s.act(r)
			cd = rng.randf_range(3.0, 6.0)
		# завиток хвоста — на стебле
		var g: Variant = s.bone_point("tail_grip")
		if g != null:
			s.global_position = hs.grip_point() - s.global_basis * (g as Vector3)
		if lbl:
			lbl.text = "%s\nклип: %s" % [head, s._cur]


static func build(root: Node3D, c: Vector2) -> void:
	var have := IDS.filter(func(i: String) -> bool: return SeaSkel.has(i))
	if have.is_empty():
		return
	var z := c.y - 33.5
	var step := 3.0
	var x0 := c.x - 1.5 * step
	var rng := RandomNumberGenerator.new()
	rng.seed = 1407
	for k in have.size() + 1:
		var x := x0 + k * step
		var g := P.ground(x, z)
		var h := 0.9
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.5
		cm.height = h
		post.mesh = cm
		post.material_override = P._post_mat()
		root.add_child(post)
		post.global_position = Vector3(x, g + h * 0.5, z)
		var top := g + h
		if k < have.size():
			var id := String(have[k])
			var d := SeaSkel.def(id)
			var hs := SeaHoldfast.create(0.3, "coral" if k == 2 else "grass", float(k) * 1.7)
			hs.scale = Vector3.ONE * SHOW
			root.add_child(hs)
			hs.global_position = Vector3(x, top, z)
			hs.rotation.y = PI * 0.5            # конёк боком к дорожке, мордой влево
			var cl := Clinger.new()
			cl.name = "SeahorseCling_" + id
			cl.rng.seed = rng.randi()
			cl.hs = hs
			cl.s = SeaSkel.create(id, 0.14 * SHOW, 31 + k)
			root.add_child(cl)
			cl.add_child(cl.s)
			cl.s.rotation.y = PI * 0.5
			cl.s.global_position = hs.grip_point()
			cl.head = "%s · 0.14 м (×%d)\n%s треуг. · держится хвостом" % [String(d.name), int(SHOW), _n(int(d.tris))]
			cl.lbl = P.label(root, Vector3(x, top + 0.3 * SHOW + 0.95, z), cl.head, 20, P.SIGN_COLOR, 26.0)
		else:
			var id := String(have[0])
			var sc := SandboxSeaSkel.Showcase.new()
			sc.name = "SeahorseShow_all"
			sc.s = SeaSkel.create(id, 0.14 * SHOW, 77)
			sc.add_child(sc.s)
			root.add_child(sc)
			var hb := SeaSkel.bounds(id).size.y * SHOW * 0.14 / 0.158
			sc.global_position = Vector3(x, top + 0.15 + hb * 0.5, z)
			sc.rotation.y = PI * 0.5
			sc.head = "Морской конёк · все клипы (×%d)" % int(SHOW)
			sc.lbl = P.label(root, Vector3(x, top + hb + 0.75, z), sc.head, 20, P.SIGN_COLOR, 26.0)
	P.signpost(root, c.x - 9.5, z, "МОРСКОЙ КОНЁК",
		"модель автора как есть, 3 расцветки\nскелет и клипы — процедурные:\nзависание, плавник, хвост держится,\nкормёжка, глаза, испуг")


static func _n(i: int) -> String:
	return str(i) if i < 1000 else "%.1fk" % (i / 1000.0)
