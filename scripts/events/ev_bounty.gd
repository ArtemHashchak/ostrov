extends SeasonEvent
## Награда за голову лидера: компания помечает участника с наибольшими очками шоу (ShowBus).
## Над ним — красный луч «эфира» (виден издалека), метка на карте. Убийца получает очки
## (ShowBus «bounty_kill»). Боты-соперники в радиусе bot_hunt_r идут на лидера.

var target: Node3D = null
var _beam: MeshInstance3D

func begin() -> void:
	target = _leader()
	if target == null:
		done = true
		return
	_beam = MeshInstance3D.new()
	_beam.name = "BountyBeam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.35
	cm.height = 40.0
	_beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.15, 0.1, 0.38)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	Events.character_died.connect(_on_died)
	say(host_line("bounty", [Game.display_name(target)]), true)
	if target.is_in_group(&"player"):
		Events.toast.emit("За твою голову назначена награда. Все знают, где ты.")

func _leader() -> Node3D:
	if cfg.has("target") and cfg.target is Node3D:
		return cfg.target
	var best: Node3D = null
	var bp := -1.0
	for c in characters():
		var pts := ShowBus.points_of(c)
		if pts > bp:
			bp = pts
			best = c
	return best

func target_node() -> Node3D:
	return target if alive(target) else null

func step(_dt: float) -> void:
	if not alive(target):
		done = true
		return
	_beam.global_position = target.global_position + Vector3.UP * 21.0

func _on_died(ch: Node, killer: Node) -> void:
	if ch != target:
		return
	if killer and is_instance_valid(killer) and killer != ch and killer.is_in_group(&"characters"):
		var pts := ShowBus.score_for(&"bounty_kill", [])
		director.call(&"award", killer, &"bounty_kill", pts, [], {"target": ch})
		say(host_line("bounty_done", [Game.display_name(killer)]), true)
	done = true

func finish() -> void:
	if Events.character_died.is_connected(_on_died):
		Events.character_died.disconnect(_on_died)
	super.finish()

## Боту стоит охотиться на лидера (не своя команда, близко).
func bot_hunt(bot: Node3D) -> Node3D:
	if not alive(target) or target == bot:
		return null
	if target.get(&"team") != null and bot.get(&"team") != null and int(target.get(&"team")) == int(bot.get(&"team")):
		return null
	return target if bot.global_position.distance_to(target.global_position) < float(cfg.get("bot_hunt_r", 140.0)) else null

func hud_line() -> String:
	if not alive(target):
		return ""
	var nm := Game.display_name(target)
	if target.is_in_group(&"player"):
		return "Награда за ТВОЮ голову (%s)" % left_text()
	return "Награда за голову: %s — %s (%s)" % [nm, where(target.global_position), left_text()]

func markers(_viewer: Node) -> Array[Dictionary]:
	if not alive(target):
		return []
	return [{"pos": target.global_position, "color": Color(1.0, 0.2, 0.1), "kind": &"event", "label": "Награда"}]
