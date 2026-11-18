class_name TeamFlag
extends StaticBody3D
## Флаг команды: пока цел — команда возрождается (Game.can_respawn).
## Шест из грубого дерева, основание из камней, полотнище цвета команды
## развевается (вершинный шейдер — работает и в gl_compatibility).

const POLE_H := 3.2
const CLOTH_W := 1.25
const CLOTH_H := 0.8

var team: int = 0
var preview: bool = false
var fallen: bool = false
var _cloth: MeshInstance3D
var _cloth_mat: ShaderMaterial
var _pole_root: Node3D

var health: float:
	get:
		if team >= 0 and team < Game.teams.size():
			return Game.teams[team].flag_hp
		return 0.0
var max_health: float:
	get:
		return Game.FLAG_MAX_HP

const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color = vec4(0.85, 0.3, 0.25, 1.0);
uniform float wind = 1.0;
uniform float alpha = 1.0;
void vertex() {
	float k = UV.x;
	float w = sin(TIME * 4.2 - UV.x * 7.0) * 0.13 + sin(TIME * 2.3 - UV.x * 4.0 + UV.y * 2.0) * 0.06;
	VERTEX.z += w * k * wind;
	VERTEX.y += sin(TIME * 3.1 - UV.x * 5.0) * 0.03 * k * wind;
}
void fragment() {
	float folds = 0.86 + 0.14 * sin(UV.x * 22.0 + TIME * 4.2);
	ALBEDO = color.rgb * folds;
	ROUGHNESS = 0.92;
	ALPHA = alpha;
}
"""

func setup(owner_team: int, is_preview: bool = false) -> TeamFlag:
	team = owner_team
	preview = is_preview
	return self

func _ready() -> void:
	if preview:
		collision_layer = 0
		collision_mask = 0
	else:
		add_to_group(&"flag")
		add_to_group(&"buildable")
		Events.flag_destroyed.connect(_on_flag_destroyed)
	_pole_root = Node3D.new()
	add_child(_pole_root)
	# основание — кольцо камней
	for i in 9:
		var a := TAU * i / 9.0 + sin(i * 2.3) * 0.15
		var st := MeshInstance3D.new()
		var k := 0.8 + 0.35 * absf(sin(i * 1.7 + 0.4))
		st.mesh = BuildMats.rock_mesh(0.17)
		st.material_override = BuildMats.mat(&"stone")
		st.position = Vector3(cos(a) * 0.36, 0.05 * k, sin(a) * 0.36)
		st.rotation = Vector3(sin(i * 3.1) * 0.4, a + i, cos(i * 2.2) * 0.3)
		st.scale = Vector3(1.15 * k, 0.6 * k, 0.85 * k)
		add_child(st)
	var pole := MeshInstance3D.new()
	pole.mesh = BuildMats.cylinder(0.055, POLE_H, 8)
	pole.material_override = BuildMats.mat(&"pole")
	pole.position.y = POLE_H * 0.5
	_pole_root.add_child(pole)
	var rope := MeshInstance3D.new()
	rope.mesh = BuildMats.torus(0.05, 0.075)
	rope.material_override = BuildMats.mat(&"rope")
	rope.position.y = POLE_H - 0.15
	_pole_root.add_child(rope)
	_cloth = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(CLOTH_W, CLOTH_H)
	pm.subdivide_width = 14
	pm.subdivide_depth = 6
	_cloth.mesh = pm
	_cloth_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CLOTH_SHADER if preview else CLOTH_SHADER.replace("ALPHA = alpha;", "")
	_cloth_mat.shader = sh
	_cloth_mat.set_shader_parameter(&"color", Game.team_color(team))
	_cloth.material_override = _cloth_mat
	_cloth.position = Vector3(CLOTH_W * 0.5 + 0.05, POLE_H - CLOTH_H * 0.5 - 0.1, 0)
	_pole_root.add_child(_cloth)
	if preview:
		_cloth_mat.set_shader_parameter(&"alpha", 0.5)
		set_preview_valid(true)
		return
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.35
	cy.height = POLE_H
	cs.shape = cy
	cs.position.y = POLE_H * 0.5
	add_child(cs)

## Призрак: полупрозрачный, зелёный/красный.
func set_preview_valid(ok: bool) -> void:
	if not preview:
		return
	var m := BuildMats.mat(&"ghost_ok" if ok else &"ghost_bad")
	for c in find_children("*", "MeshInstance3D", true, false):
		if c != _cloth:
			(c as MeshInstance3D).material_override = m

func get_interact_text(player: Node) -> String:
	var mine := int(player.get(&"team")) == team
	if fallen:
		return "Флаг %s уничтожен" % Game.TEAM_NAMES[team]
	if mine:
		return "Твой флаг: %d/%d" % [int(health), int(max_health)]
	return "Флаг «%s»: %d/%d" % [Game.TEAM_NAMES[team], int(health), int(max_health)]

func interact(_player: Node) -> void:
	pass

func apply_damage(amount: float, source: Node, _kind: StringName = &"melee") -> void:
	if preview or fallen or amount <= 0.0:
		return
	if source:
		var st: Variant = source.get(&"team")
		if st != null and int(st) == team:
			return # свои не ломают свой флаг
	Game.damage_flag(team, amount, source)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_pole_root, ^"rotation:z", 0.05, 0.05)
		tw.tween_property(_pole_root, ^"rotation:z", 0.0, 0.15)

func on_hit(by: Node, hit: Dictionary) -> void:
	var dmg := float(hit.get("damage", 0.0))
	if dmg <= 0.0:
		var tool := String(hit.get("tool", "hand"))
		dmg = 20.0 if tool.begins_with("axe") else (8.0 if tool == "rock" or tool == "stone" or tool == "spear" else 3.0)
	apply_damage(dmg, by, &"melee")

func is_dead() -> bool:
	return fallen

func _on_flag_destroyed(t: int, _by: Node) -> void:
	if t != team or fallen:
		return
	fallen = true
	# в матче объявление даёт MatchDirector — здесь только вне матча (тесты, песочница)
	if MatchDirector.instance() == null:
		BuildEnv.toast("Флаг команды «%s» уничтожен!" % Game.TEAM_NAMES[team])
	var tw := create_tween()
	tw.tween_property(_pole_root, ^"rotation:z", -PI * 0.47, 1.1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_cloth_mat.set_shader_parameter(&"color", Game.team_color(team).darkened(0.6))
	_cloth_mat.set_shader_parameter(&"wind", 0.15)
