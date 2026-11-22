class_name UserClipRig
extends RefCounted
## Существа пака пользователя с готовыми клипами (модели чата моделирования, 2026-11-22):
## змеи (зелёная и синяя куфии, королевский и ковровый питоны), комодский варан, зелёная игуана,
## огненная саламандра, гигантская сколопендра, бурый рак-отшельник, попугаи (синеголовый пионус, кеа).
## У каждой модели в GLB свой скелет и запечённые клипы автора (idle / crawl / walk / run / strike /
## tongue / death …) — их и играем: AnimationPlayer модели с плавным переходом между клипами.
##  • клип выбирается по состоянию Animal (стоит / идёт / бежит / плывёт / угроза / атака / укрытие /
##    сидит / летит / планирует) и событиям (attack / hurt / eat / die → strike, hit, death …);
##  • скорость шага клипа подстраивается под скорость животного (скорость клипа в м/с — по заданиям
##    автора: «шаг за полцикла»), с ограничением, чтобы лапы не «мелькали»;
##  • в покое — случайные вставки автора: язык, моргание, кивки, чистка перьев, «нюханье» …;
##  • смерть — клип death с удержанием последнего кадра (Animal не переворачивает модель: owns_death);
##  • плеер в ручном режиме: время клипа идёт по тикам Animal (advance(dt)); вдали (lod 2) — пауза.
## Модель лежит носом в −Z, начало координат — середина тела (змеи у автора — от кончика морды).
## Варианты вида выбираются случайно (или next_variant для витрин полигона).

const DIR := "res://assets/user_pack/animals/"

## Варианты по видам Animal.
##   path, name — файл и подпись; scale — масштаб к модели автора; z — сдвиг модели по Z (центр тела);
##   clips: роль → клип; loop: какие клипы зациклены; ref: скорость клипа в м/с при speed_scale = 1
##   (в масштабе автора); extras: вставки в покое [клип, вес]; extra_every: пауза между ними (с).
const VARIANTS := {
	&"snake": [
		{"id": "green_pit_viper", "name": "Зелёная куфия", "path": "snakes/snake_green_pit_viper.glb", "scale": 1.0, "len": 0.9,
			"clips": {"idle": "idle", "move": "crawl", "warn": "stance", "attack": "strike", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.27}, "extras": [["tongue", 3.0], ["sniff", 1.0]], "extra_every": [2.5, 6.0]},
		{"id": "blue_pit_viper", "name": "Синяя куфия", "path": "snakes/snake_blue_pit_viper.glb", "scale": 1.0, "len": 0.75,
			"clips": {"idle": "idle", "move": "crawl", "warn": "coil", "warn2": "stance", "attack": "strike", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.22}, "extras": [["tongue_flick", 3.0], ["sniff", 1.0]], "extra_every": [2.5, 6.0]},
	],
	&"python": [
		{"id": "ball_python", "name": "Королевский питон", "path": "snakes/snake_ball_python.glb", "scale": 1.0, "len": 1.3,
			"clips": {"idle": "idle", "move": "crawl", "warn": "stance", "attack": "strike", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.39}, "extras": [["tongue", 3.0], ["sniff", 1.0]], "extra_every": [3.0, 7.0]},
		{"id": "carpet_python", "name": "Ковровый питон", "path": "snakes/snake_carpet_python.glb", "scale": 1.0, "len": 1.8,
			"clips": {"idle": "idle", "move": "crawl", "warn": "stance", "attack": "strike", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.54}, "extras": [["tongue", 3.0], ["sniff", 1.0]], "extra_every": [3.0, 7.0]},
	],
	&"monitor": [
		{"id": "varan_komodo", "name": "Комодский варан", "path": "varan/varan_komodo.glb", "scale": 1.0, "len": 2.6,
			"clips": {"idle": "idle", "move": "walk", "run": "run", "swim": "swim", "turn": "turn", "warn": "tongue_flick",
				"attack": "bite", "lunge": "attack_lunge", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.52, "run": 1.6, "swim": 0.6}, "extras": [["tongue_flick", 3.0], ["blink", 1.0]], "extra_every": [3.0, 8.0]},
	],
	&"iguana": [
		{"id": "iguana_green", "name": "Зелёная игуана", "path": "iguana/iguana_green.glb", "scale": 1.0, "len": 1.5,
			"clips": {"idle": "idle", "move": "walk", "run": "run", "warn": "head_bob", "attack": "bite", "hurt": "tail_whip",
				"eat": "bite", "death": "death", "rest": "bask"},
			"ref": {"move": 0.28, "run": 0.9}, "extras": [["head_bob", 2.0], ["blink", 2.0], ["bask", 1.0]], "extra_every": [3.0, 8.0]},
	],
	&"salamander": [
		{"id": "salamander_fire", "name": "Огненная саламандра", "path": "salamander/salamander_fire.glb", "scale": 1.0, "len": 0.2,
			"clips": {"idle": "idle", "move": "walk", "run": "run", "turn": "turn", "warn": "defend", "attack": "defend",
				"eat": "eat", "hurt": "hit", "death": "death"},
			"ref": {"move": 0.06, "run": 0.16}, "extras": [["eat", 1.0], ["turn", 0.5]], "extra_every": [4.0, 9.0]},
	],
	&"centipede": [
		{"id": "centipede_giant", "name": "Гигантская сколопендра", "path": "centipede/centipede_giant.glb", "scale": 2.0, "len": 0.28,
			"clips": {"idle": "idle", "move": "crawl", "run": "crawl_fast", "turn": "turn", "warn": "rear_up", "attack": "bite",
				"hurt": "rear_up", "death": "death"},
			"ref": {"move": 0.08, "run": 0.2}, "extras": [["turn", 1.0]], "extra_every": [4.0, 9.0]},
	],
	&"hermit_crab": [
		{"id": "hermit_crab_brown", "name": "Рак-отшельник", "path": "hermit_crab/hermit_crab_brown.glb", "scale": 1.8, "len": 0.15, "z": 0.03,
			"clips": {"idle": "idle", "move": "walk", "hide": "hide_in_shell", "peek": "peek_out", "warn": "pinch", "attack": "pinch",
				"hurt": "hide_in_shell", "death": "death"},
			"ref": {"move": 0.035}, "extras": [["pinch", 1.0]], "extra_every": [5.0, 11.0]},
	],
	&"parrot": [
		{"id": "pionus_bluehead", "name": "Синеголовый попугай", "path": "parrots/parrot_pionus_bluehead.glb", "scale": 1.0, "len": 0.27, "z": 0.13,
			"clips": {"idle": "idle_perch", "fly": "fly", "glide": "glide", "takeoff": "takeoff", "land": "land", "eat": "peck",
				"hurt": "hit", "death": "death", "move": "hop"},
			"ref": {"move": 0.25}, "extras": [["preen", 2.0], ["call", 1.5], ["peck", 1.0], ["hop", 0.7]], "extra_every": [2.0, 5.0]},
		{"id": "kea", "name": "Попугай кеа", "path": "parrots/parrot_kea.glb", "scale": 1.0, "len": 0.37,
			"clips": {"idle": "idle_perch", "fly": "fly", "glide": "glide", "takeoff": "takeoff", "land": "land", "eat": "peck",
				"hurt": "hit", "death": "death", "move": "walk"},
			"ref": {"move": 0.3}, "extras": [["preen", 2.0], ["call", 1.5], ["peck", 1.0], ["hop", 0.7]], "extra_every": [2.0, 5.0]},
	],
}

## Клипы, которые крутятся по кругу (остальные — один раз).
const LOOPS := ["idle", "crawl", "walk", "run", "swim", "crawl_fast", "idle_perch", "fly", "glide", "bask"]
## Клипы-позы: доиграв, держат последний кадр (пока длится состояние). Стойка змеи — поза
## (тело поднимается S-образно за 1.5 с и замирает), в цикле она бы каждые 1.5 с падала на землю.
const HOLDS := ["coil", "stance", "rear_up", "hide_in_shell", "defend", "death"]
## Позы, у которых пик — в середине клипа (дальше автор возвращает в покой): держим кадр пика.
const HOLD_AT := {"rear_up": 0.55}

const BLEND := 0.25
const SPEED_MIN := 0.45
const SPEED_MAX := 2.3

## Для витрин: следующий build() возьмёт этот вариант (затем −1 — случайный).
static var next_variant := -1
static var use_pack := true
static var _scenes: Dictionary = {}

static func available(species: StringName) -> bool:
	if not use_pack or not VARIANTS.has(species):
		return false
	for v: Dictionary in VARIANTS[species]:
		if ResourceLoader.exists(DIR + String(v["path"])):
			return true
	return false

static func variants(species: StringName) -> Array:
	return VARIANTS.get(species, [])

## Регистрация в FaunaAnim (вызывается из FaunaAnim._ensure).
static func register_all() -> void:
	for sp: StringName in VARIANTS:
		if available(sp):
			FaunaAnim.register_builder(sp, build.bind(sp))

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var ps := load(DIR + path) as PackedScene
		if ps:
			# зациклить клипы движения/покоя один раз на ресурс
			var probe := ps.instantiate()
			for ap: AnimationPlayer in probe.find_children("*", "AnimationPlayer", true, false):
				for lib_name in ap.get_animation_library_list():
					var lib := ap.get_animation_library(lib_name)
					for an_name in lib.get_animation_list():
						var an := lib.get_animation(an_name)
						an.loop_mode = Animation.LOOP_LINEAR if String(an_name) in LOOPS else Animation.LOOP_NONE
			probe.free()
		_scenes[path] = ps
	return _scenes[path]

## Модель с контроллером (meta "anim"). Корень — как у AnimalModels._root (mat = null: свои материалы GLB).
static func build(species: StringName) -> Node3D:
	var vs: Array = VARIANTS[species]
	var idx := next_variant if next_variant >= 0 and next_variant < vs.size() else randi() % vs.size()
	next_variant = -1
	return build_variant(species, idx)

static func build_variant(species: StringName, idx: int) -> Node3D:
	var v: Dictionary = VARIANTS[species][idx]
	var root := Node3D.new()
	root.name = "Model_" + String(species)
	root.set_meta(&"mat", null)
	root.set_meta(&"legs", [])
	root.set_meta(&"wings", [])
	root.set_meta(&"tail", null)
	root.set_meta(&"jaw", null)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var ps := _scene(String(v["path"]))
	var inst := ps.instantiate() as Node3D
	inst.name = String(v["id"])
	body.add_child(inst)
	var k := float(v.get("scale", 1.0))
	body.scale = Vector3.ONE * k
	# змеи у автора — от кончика морды (z = 0) назад к хвосту: центр тела в начало координат
	var dz := float(v.get("z", 0.0))
	if species in [&"snake", &"python"]:
		dz = -float(v["len"]) * 0.5
	body.position = Vector3(0.0, 0.0, dz * k)
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k * float(v["len"]) > 0.3 \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := UserClipRig.new()
	c.species = species
	c.variant = v
	c.scale_k = k
	c.root = root
	c.body = body
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	c.player = aps[0] if not aps.is_empty() else null
	if c.player:
		c.player.playback_default_blend_time = BLEND
		# время клипов — по тикам животного (Animal.tick → animate → advance): вдали не считается вовсе
		c.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		c._has = {}
		for a in c.player.get_animation_list():
			c._has[String(a)] = true
		c._play(c._clip(&"idle"), 0.0)
		c.player.seek(randf() * 1.5, true)
	root.set_meta(&"anim", c)
	root.set_meta(&"variant", String(v["id"]))
	root.set_meta(&"display_name", String(v["name"]))
	root.set_meta(&"length", float(v["len"]) * k)
	return root

# ============================== контроллер (на экземпляр) ==============================

## Animal не переворачивает модель после смерти — клип death делает это сам.
var owns_death := true
var species: StringName
var variant: Dictionary
var scale_k := 1.0
var root: Node3D
var body: Node3D
var player: AnimationPlayer
var _has: Dictionary = {}
var _cur := ""
var _oneshot := ""          # играющий клип-событие (attack/hurt/eat…): база ждёт его конца
var _extra_cd := 3.0
var _prev_heading := 0.0
var _turn_rate := 0.0
var _st_prev: StringName = &""
var _bird_phase := 0.0
var _vy := 0.0
var _py := 0.0
var _dead_started := false

var _started := false

func setup(an: Animal) -> void:
	_prev_heading = an.heading
	_py = an.global_position.y if an.is_inside_tree() else 0.0
	_extra_cd = randf_range(1.0, 4.0)
	_bird_phase = randf() * 10.0

func _clip(role: StringName) -> String:
	var clips: Dictionary = variant["clips"]
	return String(clips.get(String(role), ""))

func _ok(c: String) -> bool:
	return c != "" and _has.has(c)

func _play(c: String, blend: float = BLEND, spd: float = 1.0) -> void:
	if player == null or not _ok(c):
		return
	if c != _cur or not player.is_playing():
		player.play(c, blend, 1.0)
		_cur = c
	player.speed_scale = spd

## Клип-событие поверх базы: доигрывает до конца, потом база возвращается.
func _shot(c: String, blend: float = 0.12) -> void:
	if player == null or not _ok(c):
		return
	player.play(c, blend, 1.0)
	player.speed_scale = 1.0
	_cur = c
	_oneshot = c

func on_event(_an: Animal, ev: StringName) -> void:
	match ev:
		&"attack":
			var c := _clip(&"attack")
			if _ok(_clip(&"lunge")) and _an.state_t < 0.35:
				c = _clip(&"lunge")   # бросок с места — выпад, вблизи — укус
			_shot(c)
		&"hurt":
			if _oneshot == "" or not (_oneshot in [_clip(&"attack"), _clip(&"lunge")]):
				_shot(_clip(&"hurt"))
		&"eat":
			_shot(_clip(&"eat") if _ok(_clip(&"eat")) else _clip(&"attack"))
		&"threat":
			_shot(_clip(&"warn"))
		&"die":
			_die()

func _die() -> void:
	if _dead_started or player == null:
		return
	_dead_started = true
	_oneshot = ""
	player.speed_scale = 1.0
	player.play(_clip(&"death"), 0.15, 1.0)
	_cur = _clip(&"death")

func animate_dead(an: Animal, dt: float) -> void:
	if not _dead_started:
		_die()
	if player and player.is_playing() and FaunaAnim.lod_of(an) < 2:
		player.speed_scale = 1.0
		player.advance(dt)

func animate(an: Animal, dt: float) -> void:
	if player == null:
		return
	var lod := FaunaAnim.lod_of(an)
	if lod >= 2:
		return   # вдали поза замирает (плеер не продвигается)
	_update(an, dt)
	player.advance(dt)

func _update(an: Animal, dt: float) -> void:
	if not _started:
		_started = true
		_prev_heading = an.heading
		_py = an.global_position.y
	# скорость поворота (для клипа turn на месте)
	var dh := wrapf(an.heading - _prev_heading, -PI, PI)
	_prev_heading = an.heading
	_turn_rate = FaunaAnim.damp(_turn_rate, absf(dh) / maxf(dt, 0.001), 8.0, dt)
	var y := an.global_position.y
	_vy = FaunaAnim.damp(_vy, clampf((y - _py) / maxf(dt, 0.001), -8.0, 8.0), 5.0, dt)
	_py = y
	# клип-событие доигрывает до конца
	if _oneshot != "":
		if player.current_animation == _oneshot and player.is_playing():
			return
		_oneshot = ""
	if an.cfg.get("fly", false):
		_bird(an, dt)
	else:
		_ground(an, dt)
	_st_prev = an.state

func _locomotion(an: Animal, role: StringName, ref_key: String) -> bool:
	var c := _clip(role)
	if not _ok(c):
		return false
	var refs: Dictionary = variant.get("ref", {})
	var ref := float(refs.get(ref_key, refs.get("move", 0.3))) * scale_k * maxf(an.growth, 0.3)
	_play(c, BLEND, clampf(an.speed / maxf(ref, 0.01), SPEED_MIN, SPEED_MAX))
	return true

func _ground(an: Animal, dt: float) -> void:
	var st := an.state
	var walk := float(an.cfg.get("walk", 0.5))
	# угроза / укрытие — позы
	if st == &"hide":
		_play_hold(_clip(&"hide"))
		return
	if st == &"peek":
		_play_hold(_clip(&"peek") if _ok(_clip(&"peek")) else _clip(&"idle"))
		return
	if st == &"warn":
		var w := _clip(&"warn")
		var w2 := _clip(&"warn2")
		if _ok(w2) and an.state_t > 1.2:
			w = w2
		if w in HOLDS or w == "stance":
			_play_hold(w)
		else:
			# не поза (язык варана, кивки игуаны) — повтор, пока длится предупреждение
			if _cur != w or not player.is_playing():
				_play(w, 0.15)
		return
	if st == &"attack" and an.speed < walk * 0.3:
		var w3 := _clip(&"warn")
		if _ok(_clip(&"warn2")):
			w3 = _clip(&"warn2")
		if w3 == "stance" or w3 in HOLDS:
			_play_hold(w3)  # между бросками — в стойке
			return
	# движение
	var swim: bool = _ok(_clip(&"swim")) and bool(an.call(&"_in_water"))
	if swim and an.speed > 0.05:
		_locomotion(an, &"swim", "swim")
		return
	if an.speed > walk * 0.12:
		var runs := an.speed > walk * 1.6 and _ok(_clip(&"run"))
		if runs:
			_locomotion(an, &"run", "run")
		else:
			_locomotion(an, &"move", "move")
		return
	# поворот на месте
	if _turn_rate > 1.2 and _ok(_clip(&"turn")):
		_play(_clip(&"turn"), 0.2, clampf(_turn_rate / 2.0, 0.7, 1.6))
		return
	# покой со вставками
	_idle(an, dt)

func _play_hold(c: String) -> void:
	if not _ok(c):
		c = _clip(&"idle")
	if _cur != c:
		var from := _cur
		_play(c, 0.18)
		# после броска/удара — сразу в конечную позу стойки (бросок начинается из неё же),
		# а не заново с земли
		if c in HOLDS and from in [_clip(&"attack"), _clip(&"lunge"), _clip(&"hurt")]:
			var an := player.get_animation(c)
			player.seek(an.length * float(HOLD_AT.get(c, 1.0)) - 0.01, true)
	elif not player.is_playing() and not (c in HOLDS):
		_play(c, 0.0)
	if HOLD_AT.has(c) and _cur == c:
		var an2 := player.get_animation(c)
		if player.current_animation_position >= an2.length * float(HOLD_AT[c]):
			player.speed_scale = 0.0   # замереть на пике позы

func _idle(an: Animal, dt: float) -> void:
	var idle := _clip(&"idle")
	if _cur != idle and (not player.is_playing() or _cur in LOOPS or _cur in HOLDS or _cur == ""):
		_play(idle, BLEND)
	elif _cur == idle:
		player.speed_scale = 1.0
	_extra_cd -= dt
	if _extra_cd <= 0.0 and FaunaAnim.lod_of(an) == 0:
		var ev: Array = variant.get("every", variant.get("extra_every", [3.0, 7.0]))
		_extra_cd = randf_range(float(ev[0]), float(ev[1]))
		var ex: Array = variant.get("extras", [])
		var tot := 0.0
		for e: Array in ex:
			tot += float(e[1])
		var r := randf() * tot
		for e: Array in ex:
			r -= float(e[1])
			if r <= 0.0:
				_shot(String(e[0]), 0.2)
				break

func _bird(an: Animal, dt: float) -> void:
	_bird_phase += dt
	var perch := an.state == &"perch" or (an.tamed and an.state != &"fly")
	if perch:
		if _st_prev == &"fly" and _ok(_clip(&"land")):
			_shot(_clip(&"land"))
			return
		_idle(an, dt)
		return
	# в воздухе
	if (_st_prev == &"perch" or _st_prev == &"") and _vy > 0.2 and _ok(_clip(&"takeoff")) and _st_prev != &"":
		_shot(_clip(&"takeoff"))
		return
	if an.alt < 1.0 and _vy < -0.3 and _ok(_clip(&"land")):
		_play(_clip(&"land"), 0.2)
		return
	# планирование: снижается или по ритму (взмахи ~3 с, парение ~1.5 с)
	var glide := _vy < -0.6 or (fmod(_bird_phase, 4.5) > 3.0 and _vy < 0.4)
	if glide:
		_play(_clip(&"glide"), 0.3)
	else:
		_play(_clip(&"fly"), 0.3, clampf(1.0 + _vy * 0.15, 0.85, 1.35))
