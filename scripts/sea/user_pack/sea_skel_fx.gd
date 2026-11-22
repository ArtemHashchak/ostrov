class_name SeaSkelFx
extends RefCounted
## Эффекты клипов моделей со скелетом (по заданиям автора):
##  • cavitation — щелчок креветки-щелкуна: на кадре 7 клипа snap — вспышка и пузырь кавитации,
##    который раздувается и схлопывается (~0.25 с), плюс россыпь мелких пузырьков вверх;
##  • ink — чернильное облако кальмара: тёмная сфера раздувается и тает за ~3 с.
## Узлы самоудаляются (Tween), материалы общие.

static var _mats: Dictionary = {}

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"bubble":
			m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
			m.roughness = 0.05
			m.metallic_specular = 1.0
			m.rim_enabled = true
			m.rim = 1.0
		"flash":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.97, 0.85, 0.9)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"ink":
			m.albedo_color = Color(0.05, 0.03, 0.06, 0.85)
			m.roughness = 1.0
			m.disable_receive_shadows = true
	_mats[key] = m
	return m

static func _sphere(parent: Node, pos: Vector3, r: float, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _mat(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * r
	return mi

## Пузырь кавитации со вспышкой через delay с (кадр щелчка).
static func cavitation(parent: Node, pos: Vector3, delay: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tw := parent.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(parent) or not parent.is_inside_tree():
			return
		var fl := _sphere(parent, pos, 0.01, "flash")
		var b := _sphere(parent, pos, 0.005, "bubble")
		var t := parent.create_tween().set_parallel(true)
		t.tween_property(fl, "scale", Vector3.ONE * 0.05, 0.06)
		t.tween_property(b, "scale", Vector3.ONE * 0.035, 0.12).set_ease(Tween.EASE_OUT)
		t.chain().tween_property(b, "scale", Vector3.ONE * 0.002, 0.08).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(func() -> void:
			fl.queue_free()
			b.queue_free())
		for i in 5:
			var s := _sphere(parent, pos + Vector3(randf_range(-0.01, 0.01), 0.0, randf_range(-0.01, 0.01)), randf_range(0.004, 0.008), "bubble")
			var u := parent.create_tween()
			u.tween_property(s, "global_position", s.global_position + Vector3(randf_range(-0.03, 0.03), randf_range(0.12, 0.3), randf_range(-0.03, 0.03)), randf_range(0.7, 1.2))
			u.tween_callback(s.queue_free))

## Чернильное облако размера ~size (м).
static func ink(parent: Node, pos: Vector3, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var c := _sphere(parent, pos, size * 0.2, "ink")
	var m := _mat("ink").duplicate() as StandardMaterial3D
	c.material_override = m
	var t := parent.create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector3(1.2, 0.9, 1.4) * size * 1.6, 2.8).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 3.0).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(c.queue_free)
