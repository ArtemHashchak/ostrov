class_name ReefSpecies
extends RefCounted
## Виды тропических рыб фона: форма, размер, окраска (параметры reef_fish.gdshader),
## поведение (mode 0 — стая, 1 — у рифа), численность группы.

const FISH := {
	# --- у рифа, небольшими группами ---
	&"yellow_tang": {"name": "Жёлтый хирург", "shape": &"disc", "size": [0.16, 0.22], "mode": 1, "n": [4, 10], "roam": [1.6, 0.6, 1.6], "speed": 0.55,
		"col": {"col_back": Color(1.0, 0.85, 0.05), "col_belly": Color(1.0, 0.9, 0.2), "col_fin": Color(1.0, 0.82, 0.05), "fin_mix": 0.3,
			"col_tail": Color(0.98, 0.95, 0.75), "tail_u": 0.97, "glow": 0.18}},
	&"blue_tang": {"name": "Синий хирург", "shape": &"oval", "size": [0.18, 0.26], "mode": 1, "n": [3, 8], "roam": [2.2, 0.7, 2.2], "speed": 0.6,
		"col": {"col_back": Color(0.08, 0.25, 0.95), "col_belly": Color(0.2, 0.45, 1.0), "col_fin": Color(0.05, 0.12, 0.5), "fin_mix": 0.6,
			"col_tail": Color(1.0, 0.85, 0.05), "tail_u": 0.82, "col_stripe": Color(0.03, 0.04, 0.12), "stripe_count": 1.0, "stripe_width": 0.32,
			"stripe_range": Vector2(0.55, 0.95), "glow": 0.2}},
	&"butterfly": {"name": "Рыба-бабочка", "shape": &"butterfly", "size": [0.12, 0.17], "mode": 1, "n": [2, 6], "roam": [1.4, 0.5, 1.4], "speed": 0.5,
		"col": {"col_back": Color(1.0, 0.92, 0.4), "col_belly": Color(0.98, 0.97, 0.92), "col_fin": Color(1.0, 0.8, 0.08), "fin_mix": 0.85,
			"col_bar": Color(0.04, 0.04, 0.05), "bar_count": 1.0, "bar_width": 0.22, "bar_range": Vector2(0.03, 0.2),
			"col_stripe": Color(0.15, 0.12, 0.1), "stripe_count": 6.0, "stripe_width": 0.15, "stripe_range": Vector2(0.15, 0.85), "glow": 0.15}},
	&"moorish_idol": {"name": "Мавританский идол", "shape": &"idol", "size": [0.16, 0.22], "mode": 1, "n": [2, 4], "roam": [2.0, 0.6, 2.0], "speed": 0.45,
		"col": {"col_back": Color(1.0, 0.95, 0.7), "col_belly": Color(0.98, 0.98, 0.95), "col_fin": Color(0.98, 0.97, 0.92), "fin_mix": 0.2,
			"col_bar": Color(0.03, 0.03, 0.04), "bar_count": 2.0, "bar_width": 0.42, "bar_range": Vector2(0.12, 0.92),
			"col_tail": Color(0.05, 0.05, 0.05), "tail_u": 0.86, "col_face": Color(1.0, 0.6, 0.15), "face_u": 0.04, "glow": 0.15}},
	&"emperor_angel": {"name": "Императорский ангел", "shape": &"angel", "size": [0.24, 0.34], "mode": 1, "n": [1, 3], "roam": [2.0, 0.6, 2.0], "speed": 0.35,
		"col": {"col_back": Color(0.08, 0.15, 0.6), "col_belly": Color(0.12, 0.2, 0.7), "col_fin": Color(0.1, 0.25, 0.85), "fin_mix": 0.5,
			"col_stripe": Color(1.0, 0.85, 0.15), "stripe_count": 9.0, "stripe_width": 0.4, "stripe_range": Vector2(0.05, 0.98),
			"col_tail": Color(1.0, 0.8, 0.1), "tail_u": 0.82, "col_face": Color(0.05, 0.05, 0.1), "face_u": 0.14, "glow": 0.2}},
	&"parrotfish": {"name": "Рыба-попугай", "shape": &"parrot", "size": [0.35, 0.55], "mode": 1, "n": [2, 5], "roam": [3.5, 0.5, 3.5], "speed": 0.3,
		"col": {"col_back": Color(0.1, 0.65, 0.55), "col_belly": Color(0.35, 0.85, 0.7), "col_fin": Color(0.95, 0.45, 0.6), "fin_mix": 0.7,
			"col_spot": Color(0.05, 0.4, 0.45), "spot_scale": 22.0, "col_face": Color(0.95, 0.5, 0.65), "face_u": 0.06,
			"col_tail": Color(0.95, 0.5, 0.65), "tail_u": 0.9, "glow": 0.15}},
	&"wrasse": {"name": "Губан", "shape": &"slim", "size": [0.14, 0.22], "mode": 1, "n": [3, 7], "roam": [2.5, 0.5, 2.5], "speed": 0.8,
		"col": {"col_back": Color(0.15, 0.75, 0.4), "col_belly": Color(0.45, 0.9, 0.6), "col_fin": Color(0.9, 0.35, 0.6), "fin_mix": 0.6,
			"col_stripe": Color(0.95, 0.35, 0.6), "stripe_count": 3.0, "stripe_width": 0.2, "stripe_range": Vector2(0.2, 0.85), "glow": 0.18}},
	&"grouper": {"name": "Групер", "shape": &"grouper", "size": [0.5, 0.8], "mode": 1, "n": [1, 2], "roam": [1.5, 0.3, 1.5], "speed": 0.2,
		"col": {"col_back": Color(0.38, 0.25, 0.16), "col_belly": Color(0.62, 0.48, 0.35), "col_fin": Color(0.3, 0.2, 0.12), "fin_mix": 0.5,
			"col_spot": Color(0.85, 0.55, 0.25), "spot_scale": 16.0, "glow": 0.06}},
	&"clownfish": {"name": "Рыба-клоун", "shape": &"clown", "size": [0.07, 0.1], "mode": 1, "n": [2, 4], "roam": [0.35, 0.25, 0.35], "speed": 0.9,
		"col": {"col_back": Color(1.0, 0.42, 0.04), "col_belly": Color(1.0, 0.55, 0.12), "col_fin": Color(1.0, 0.45, 0.05), "fin_mix": 0.3,
			"col_bar": Color(0.98, 0.98, 0.98), "bar_count": 3.0, "bar_width": 0.28, "bar_range": Vector2(0.05, 0.98), "glow": 0.25}},
	&"chromis": {"name": "Хромис", "shape": &"oval", "size": [0.06, 0.09], "mode": 1, "n": [20, 45], "roam": [1.2, 0.8, 1.2], "speed": 0.9,
		"col": {"col_back": Color(0.25, 0.85, 0.75), "col_belly": Color(0.55, 0.95, 0.9), "col_fin": Color(0.4, 0.9, 0.85), "fin_mix": 0.3, "glow": 0.3, "metal": 0.25}},
	&"anthias": {"name": "Антиас", "shape": &"oval", "size": [0.07, 0.1], "mode": 1, "n": [25, 55], "roam": [1.8, 1.0, 1.8], "speed": 0.8,
		"col": {"col_back": Color(1.0, 0.45, 0.35), "col_belly": Color(1.0, 0.65, 0.5), "col_fin": Color(1.0, 0.3, 0.55), "fin_mix": 0.6, "glow": 0.3}},
	&"damsel": {"name": "Ласточка", "shape": &"oval", "size": [0.07, 0.1], "mode": 1, "n": [8, 20], "roam": [1.4, 0.6, 1.4], "speed": 0.9,
		"col": {"col_back": Color(0.1, 0.3, 1.0), "col_belly": Color(0.2, 0.55, 1.0), "col_fin": Color(1.0, 0.85, 0.1), "fin_mix": 0.4,
			"col_tail": Color(1.0, 0.85, 0.1), "tail_u": 0.82, "glow": 0.3}},
	# --- стаи ---
	&"snapper": {"name": "Синеполосый луциан", "shape": &"oval", "size": [0.22, 0.3], "mode": 0, "n": [20, 40], "roam": [5.0, 0.5, 5.0], "speed": 0.25,
		"radius": 1.6, "col": {"col_back": Color(1.0, 0.82, 0.1), "col_belly": Color(1.0, 0.92, 0.6), "col_fin": Color(1.0, 0.8, 0.1), "fin_mix": 0.8,
			"col_stripe": Color(0.2, 0.55, 1.0), "stripe_count": 4.0, "stripe_width": 0.18, "stripe_range": Vector2(0.3, 0.95), "glow": 0.2}},
	&"fusilier": {"name": "Фузилёр", "shape": &"slim", "size": [0.18, 0.26], "mode": 0, "n": [40, 80], "roam": [9.0, 1.0, 9.0], "speed": 0.3,
		"radius": 2.6, "col": {"col_back": Color(0.15, 0.45, 0.95), "col_belly": Color(0.85, 0.9, 1.0), "col_fin": Color(0.9, 0.9, 1.0), "fin_mix": 0.2,
			"col_tail": Color(1.0, 0.85, 0.15), "tail_u": 0.84, "col_stripe": Color(1.0, 0.85, 0.2), "stripe_count": 1.0, "stripe_width": 0.15,
			"stripe_range": Vector2(0.6, 0.85), "glow": 0.18, "metal": 0.3}},
	&"sardine": {"name": "Сардина", "shape": &"slim", "size": [0.1, 0.14], "mode": 0, "n": [120, 220], "roam": [7.0, 0.6, 7.0], "speed": 0.4,
		"radius": 2.4, "col": {"col_back": Color(0.25, 0.4, 0.55), "col_belly": Color(0.92, 0.95, 0.98), "col_fin": Color(0.8, 0.85, 0.9), "fin_mix": 0.2,
			"metal": 0.7, "glow": 0.08}},
}

## Охотники и одиночки для сценок.
const ACTORS := {
	&"barracuda": {"shape": &"barracuda", "size": 1.2, "col": {"col_back": Color(0.35, 0.42, 0.48), "col_belly": Color(0.9, 0.92, 0.95),
		"col_fin": Color(0.25, 0.3, 0.35), "fin_mix": 0.6, "col_bar": Color(0.2, 0.25, 0.3), "bar_count": 14.0, "bar_width": 0.22,
		"bar_range": Vector2(0.15, 0.8), "metal": 0.6, "glow": 0.05, "wiggle_amp": 0.04}},
	&"trevally": {"shape": &"jack", "size": 0.7, "col": {"col_back": Color(0.3, 0.45, 0.7), "col_belly": Color(0.9, 0.93, 0.95),
		"col_fin": Color(0.2, 0.4, 0.85), "fin_mix": 0.7, "col_tail": Color(0.2, 0.4, 0.85), "tail_u": 0.86, "metal": 0.6, "glow": 0.06, "wiggle_amp": 0.06}},
}

const FISH_SHADER := preload("res://scripts/sea/shaders/reef_fish.gdshader")

static func make_material(look: Dictionary, mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FISH_SHADER
	m.set_shader_parameter(&"mode", mode)
	for k: String in look:
		m.set_shader_parameter(StringName(k), look[k])
	return m

## Одиночная рыба (mode 2) — для сценок: узел, которым двигает скрипт.
static func actor_node(id: StringName, look_from_fish: bool = false) -> MeshInstance3D:
	var d: Dictionary = FISH[id] if look_from_fish else ACTORS[id]
	var mi := MeshInstance3D.new()
	mi.mesh = ReefMeshes.fish(d["shape"])
	var look: Dictionary = (d["col"] as Dictionary).duplicate()
	var m := make_material(look, 2)
	mi.material_override = m
	var s: float = (d["size"][1] if look_from_fish else d["size"])
	mi.scale = Vector3.ONE * s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
