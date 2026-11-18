class_name CombatFireZone
extends Node3D
## Огненная зона (разлитый горящий спирт из коктейля Молотова, огненная стрела).
## Поджигает постройки в радиусе (Blueprint.ignite — деревянные мосты/стены дальше горят сами),
## жжёт живых (kind &"fire"). На воде — плёнка плывёт по волнам и поджигает плоты рядом.

const TICK := 0.3
const DPS := 12.0

var radius := 3.0
var duration := 10.0
var source: Node

var _t := 0.0
var _tick := 0.0
var _flames: Node3D
var _on_water := false
var _ignited: Dictionary = {}
var _snd: AudioStreamPlayer3D
var _ending := false

func _ready() -> void:
	add_to_group(&"fire_zones")
	var r := radius * 0.55
	_flames = CombatFx.flames(self, clampf(radius / 2.2, 0.3, 1.6), Vector3(r, 0.05, r))
	_snd = CombatFx.loop_on(self, "fire_loop", -2.0)
	var host := get_parent()
	_on_water = not (host is Node3D and host.is_in_group(&"buildable")) and \
		absf(global_position.y - BuildEnv.water_surface(global_position.x, global_position.z)) < 0.4
	_scorch()
	_burn_tick() # сразу поджечь то, на что попали

## Тёмное пятно копоти.
func _scorch() -> void:
	if _on_water:
		return # на воде копоти нет (раньше Decal создавался и «терялся» — утечка)
	var d := Decal.new()
	d.size = Vector3(radius * 2.0, 1.0, radius * 2.0)
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.03, 0.85))
	g.set_color(1, Color(0.05, 0.04, 0.03, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	d.texture_albedo = t
	d.cull_mask = 1
	add_child(d)

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"combat", __pt)

func _perf_process(delta: float) -> void:
	_t += delta
	if _on_water:
		var p := global_position
		p.y = BuildEnv.water_surface(p.x, p.z) + 0.04
		p += Vector3(0.12, 0.0, 0.05) * delta # дрейф
		global_position = p
	if _t > duration and not _ending:
		_ending = true
		for c in _flames.get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).emitting = false
		var l := _flames.get_node_or_null(^"Light") as OmniLight3D
		if l:
			create_tween().tween_property(l, "light_energy", 0.0, 1.5)
		if _snd:
			create_tween().tween_property(_snd, "volume_db", -40.0, 1.5)
		get_tree().create_timer(3.2).timeout.connect(queue_free)
	if _ending:
		return
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		_burn_tick()

func _burn_tick() -> void:
	var c := global_position
	var t := get_tree()
	for g: StringName in [&"characters", &"player", &"animals"]:
		for n in t.get_nodes_in_group(g):
			var n3 := n as Node3D
			if n3 == null or not n.has_method(&"apply_damage"):
				continue
			var d := n3.global_position - c
			if Vector2(d.x, d.z).length() <= radius and d.y > -1.0 and d.y < 1.6:
				n.call(&"apply_damage", DPS * TICK, source, &"fire")
	for n in t.get_nodes_in_group(&"buildable"):
		if _ignited.has(n) or not n.has_method(&"ignite"):
			continue
		var b := n as Node3D
		if b == null or not is_instance_valid(b):
			continue
		var d2 := b.global_position - c
		# секции/стены ~2-3 м — берём ближайшую точку как центр минус полразмера
		if Vector2(d2.x, d2.z).length() <= radius + 1.2 and absf(d2.y) < 2.5:
			_ignited[n] = true
			n.call(&"ignite", source)
