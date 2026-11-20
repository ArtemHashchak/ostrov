class_name UserRocks
extends RefCounted
## Валуны пака пользователя (Rocks/Stone0XX — поверхности камня, без сеток): наши формы
## (tools/user_pack2/rocks_gen.py: сколы, трещины, плоское основание; 3.6k треуг., LOD1/LOD2 — импорт Godot)
## + общие текстуры камня пользователя (assets/user_pack/rocks/tex, 1024), трипланарно (user_rock.gdshader).
## Заменяют валуны-заглушки polyhaven в рассадке (flora → ResourceRock) и на тестовом острове.

const DIR := "res://assets/user_pack/rocks/"
## порядок важен: flora берёт первые два для рудных жил (округлые валуны)
const SHAPES := ["boulder_round", "boulder_split", "rock_angular", "rock_slab", "rock_karst", "rock_low"]
## форма → [набор камня, мох 0..1, оттенок, яркость]; альбедо наборов откалибровано VISUAL-UNIFY (класс rock)
const LOOK := {
	"boulder_round": ["stone004", 0.0, Color(1.0, 0.98, 0.95), 1.0],    # серый растрескавшийся
	"boulder_split": ["stone002", 0.5, Color(0.95, 0.96, 0.92), 0.82],  # серо-зелёный, во мху (джунгли)
	"rock_angular": ["stone007", 0.15, Color(1.0, 0.97, 0.93), 1.0],   # слоистый, свежие сколы
	"rock_slab": ["stone006", 0.0, Color(1.0, 0.97, 0.92), 1.0],        # песчаник — у воды
	"rock_karst": ["stone005", 0.25, Color(0.97, 0.96, 0.92), 1.0],     # светлый известняк, источенный
	"rock_low": ["stone006", 0.1, Color(0.96, 0.92, 0.86), 0.97],       # окатыш полу в песке
}

static var _mats := {}

static func available() -> bool:
	return ResourceLoader.exists(DIR + SHAPES[0] + ".glb")

static func path(i: int) -> String:
	return DIR + SHAPES[posmod(i, SHAPES.size())] + ".glb"

static func is_user_rock(p: String) -> bool:
	return p.begins_with(DIR)

static func material(shape: String) -> ShaderMaterial:
	if _mats.has(shape):
		return _mats[shape]
	var look: Array = LOOK.get(shape, LOOK["boulder_round"])
	var set: String = look[0]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/shaders/user_rock.gdshader")
	m.set_shader_parameter(&"albedo_tex", load(DIR + "tex/%s_albedo.png" % set))
	m.set_shader_parameter(&"normal_tex", load(DIR + "tex/%s_normal.png" % set))
	m.set_shader_parameter(&"orh_tex", load(DIR + "tex/%s_orh.png" % set))
	m.set_shader_parameter(&"moss", float(look[1]))
	m.set_shader_parameter(&"tint", look[2])
	m.set_shader_parameter(&"gain", float(look[3]))
	_mats[shape] = m
	return m

## Одеть экземпляр сцены валуна (если это валун пака) — материал на все сетки.
static func dress(node: Node, scene_path: String) -> void:
	if not is_user_rock(scene_path):
		return
	var shape := scene_path.get_file().get_basename()
	var m := material(shape)
	_apply(node, m)

static func _apply(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_apply(c, m)

## Готовый валун (узел), длинная ось = size м.
static func make(i: int, size := 1.0) -> Node3D:
	var p := path(i)
	var inst := (load(p) as PackedScene).instantiate() as Node3D
	dress(inst, p)
	inst.scale = Vector3.ONE * size
	return inst
