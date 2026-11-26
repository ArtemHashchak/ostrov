class_name SeaSkel
extends Node3D
## Морские существа со скелетом и запечёнными клипами автора (модели чата моделирования,
## 2026-11-22): рифовые рыбы (клоун, хирурги, ангелы, спинорог, бабочка-пинцетник, мандаринка,
## аулонокара, дискус), барракуда, гигантский групер, мурена, хвостокол, манта, дельфин,
## красный кальмар, черепахи (зелёная, бисса), лобстер, креветка-щелкун, звёзды, голотурии,
## сардина (стая — VAT, см. SeaSchool); морской конёк (3 расцветки) — у автора только .blend без
## скелета и клипов: скелет и клипы процедурные (tools/seahorse/build_seahorse.py), меш — как есть.
##
## Тело — экземпляр игрового GLB (AnimationPlayer автора). Клип выбирается по состоянию
## (стоит / плывёт / быстро / поворот) с плавным переходом; события (испуг, укус, щелчок, чернила,
## бочка, вдох у поверхности…) — разовые клипы поверх; позы (закопался, угроза, смерть) держат
## последний кадр. Скорость клипа плавания — от скорости существа (в пределах, чтобы плавники не
## «мелькали»). LOD: дальше lod_dist — облегчённый GLB (если автор дал), дальше PAUSE_DIST клипы на паузе.
## Ориентация: существо смотрит в −Z (как SeaCritter); модели с головой в +Z разворачиваются,
## тело центрируется по габариту (у донных — низ на нуле). Клипы с ходом корня (gulp, jump)
## обнуляются по корню: перемещение делает игровой код.

const DIR := "res://assets/user_pack/sea_skel/"
const BLEND := 0.22
const PAUSE_DIST := 70.0
const SPEED_MIN := 0.5
const SPEED_MAX := 2.2

## Наборы клипов (роль → клип).
const FISH_CLIPS := {"idle": "idle_hover", "swim": "swim", "fast": "swim_fast", "turn_l": "turn_L", "turn_r": "turn_R",
	"startle": "startle", "eat": "eat", "death": "death"}
## Морской конёк: зависает стоя, трепещет спинной плавник, хвост держится за траву/коралл (grip — цикл,
## пока держится; grip_eat/grip_look — действия, не отпуская), наклон головы к добыче и щелчок рылом (eat),
## глаза ходят независимо (look).
const SEAHORSE_CLIPS := {"idle": "idle_hover", "swim": "swim", "fast": "swim_fast", "startle": "startle", "eat": "eat",
	"look": "look", "grip": "grip", "grip_eat": "grip_eat", "grip_look": "grip_look", "death": "death"}
const CRUST_CLIPS := {"idle": "idle", "swim": "walk", "fast": "swim", "flip": "tail_flip", "hit": "hit", "death": "death"}

## Модели: file — игровой GLB, lod1 — облегчённый; len — длина модели автора, м; flip — голова в +Z;
## ground — донное (низ габарита на нуле); upright — стоит торчком (конёк: len — рост, по Y); clips — роли; ref — скорость (м/с, масштаб автора),
## при которой клип плавания идёт со скоростью 1; loops — зацикленные клипы; zero_root — клипы
## без хода корня; extras — вставки в покое [роль, вес]; tris — треугольники игрового GLB.
const DEFS := {
	"clownfish": {"name": "Рыба-клоун", "file": "animal_fish_clownfish.glb", "len": 0.10, "clips": FISH_CLIPS, "ref": 0.12,
		"extras": [["eat", 1.0]], "tris": 3960},
	"tang_blue": {"name": "Синий хирург", "file": "animal_fish_tang_blue.glb", "len": 0.25, "clips": FISH_CLIPS, "ref": 0.3,
		"extras": [["eat", 2.0]], "tris": 3968},
	"tang_yellow": {"name": "Жёлтый хирург", "file": "animal_fish_tang_yellow.glb", "len": 0.18, "clips": FISH_CLIPS, "ref": 0.22,
		"extras": [["eat", 2.0]], "tris": 3968},
	"tang_regal": {"name": "Королевский хирург", "file": "animal_fish_tang_regal.glb", "len": 0.25, "clips": FISH_CLIPS, "ref": 0.3,
		"extras": [["eat", 2.0]], "tris": 3968},
	"triggerfish_clown": {"name": "Пятнистый спинорог", "file": "animal_fish_triggerfish_clown.glb", "len": 0.30, "clips": FISH_CLIPS,
		"ref": 0.3, "extras": [["eat", 1.5]], "tris": 2708},
	"angel_emperor": {"name": "Императорский ангел", "file": "animal_fish_angel_emperor.glb", "len": 0.37, "clips": FISH_CLIPS, "ref": 0.32,
		"extras": [["eat", 1.5]], "tris": 2800},
	"angel_emperor_juv": {"name": "Императорский ангел (молодь)", "file": "animal_fish_angel_emperor_juv.glb", "len": 0.14,
		"clips": FISH_CLIPS, "ref": 0.15, "extras": [["eat", 1.5]], "tris": 2800},
	"angel_blueyellow": {"name": "Сине-жёлтый ангел", "file": "animal_fish_angel_blueyellow.glb", "len": 0.35, "clips": FISH_CLIPS,
		"ref": 0.3, "extras": [["eat", 1.5]], "tris": 2800},
	"copperband": {"name": "Пинцетник (рыба-бабочка)", "file": "animal_fish_copperband.glb", "len": 0.16, "clips": FISH_CLIPS, "ref": 0.18,
		"extras": [["eat", 2.5]], "tris": 2872},
	"mandarin": {"name": "Мандаринка", "file": "animal_fish_mandarin.glb", "len": 0.06, "clips": FISH_CLIPS, "ref": 0.06,
		"extras": [["eat", 2.0]], "tris": 3418},
	"aulonocara": {"name": "Аулонокара красная", "file": "animal_fish_aulonocara_red.glb", "len": 0.13, "clips": FISH_CLIPS, "ref": 0.15,
		"extras": [["eat", 1.0]], "tris": 3260},
	"discus": {"name": "Дискус", "file": "animal_fish_discus.glb", "len": 0.16, "clips": FISH_CLIPS, "ref": 0.15,
		"extras": [["eat", 1.0]], "tris": 3108},
	"barracuda": {"name": "Барракуда", "file": "animal_fish_barracuda.glb", "lod1": "animal_fish_barracuda_LOD1.glb", "lod_dist": 15.0,
		"len": 1.30, "ref": 0.5, "tris": 29180, "tris_lod1": 9488,
		"clips": {"idle": "idle", "swim": "swim", "fast": "dash", "turn_l": "turn", "turn_r": "turn_R", "bite": "bite", "death": "death"}},
	"giant_grouper": {"name": "Гигантский групер", "file": "animal_fish_giant_grouper.glb", "lod1": "animal_fish_giant_grouper_LOD1.glb",
		"lod_dist": 28.0, "len": 1.85, "ref": 0.45, "tris": 24190, "tris_lod1": 3510, "zero_root": ["gulp"],
		"clips": {"idle": "idle", "swim": "swim", "fast": "swim_fast", "turn_l": "turn_L", "turn_r": "turn_R", "startle": "startle",
			"gulp": "gulp", "death": "death"}},
	"moray": {"name": "Мурена", "file": "animal_moray_eel.glb", "len": 1.50, "ref": 0.35, "tris": 9196, "center": true,
		"clips": {"idle": "idle_burrow", "swim": "swim", "fast": "swim", "threat": "threat", "lunge": "lunge", "retreat": "retreat",
			"hit": "hit", "death": "death"}, "loops": ["threat"]},
	"stingray": {"name": "Хвостокол", "file": "animal_ray_stingray.glb", "len": 2.08, "ref": 0.5, "tris": 9221,
		"clips": {"idle": "glide", "swim": "swim", "fast": "flee", "bury": "bury", "bottom": "idle_bottom", "strike": "tail_strike",
			"hit": "hit", "death": "death"}},
	"manta": {"name": "Манта", "file": "animal_ray_manta.glb", "lod1": "animal_ray_manta_LOD1.glb", "lod_dist": 25.0, "len": 3.46,
		"ref": 0.8, "tris": 44071, "tris_lod1": 9579,
		"clips": {"idle": "idle_glide", "swim": "swim", "fast": "swim_fast", "turn_l": "turn_L", "turn_r": "turn_R", "feed": "feeding",
			"roll": "barrel_roll", "death": "death"}, "loops": ["feeding"]},
	"dolphin": {"name": "Афалина", "file": "animal_dolphin_bottlenose.glb", "lod1": "animal_dolphin_bottlenose_LOD1.glb", "lod_dist": 25.0,
		"len": 2.62, "flip": true, "ref": 1.6, "tris": 15210, "tris_lod1": 4282, "zero_root": ["jump"],
		"clips": {"idle": "idle", "swim": "swim", "fast": "swim_fast", "turn_l": "turn", "turn_r": "turn", "breathe": "breathe",
			"call": "click_call", "jump": "jump", "death": "death"}, "extras": [["call", 1.0]]},
	"squid_red": {"name": "Красный кальмар", "file": "animal_squid_red.glb", "lod1": "animal_squid_red_LOD1.glb", "lod_dist": 12.0,
		"len": 0.58, "flip": true, "ref": 0.35, "tris": 47576, "tris_lod1": 9480,
		"clips": {"idle": "idle_hover", "swim": "swim_slow", "fast": "swim", "turn_l": "turn", "turn_r": "turn", "ink": "ink",
			"grab": "grab", "death": "death"}},
	"turtle_green": {"name": "Зелёная черепаха", "file": "animal_turtle_green.glb", "lod1": "animal_turtle_green_LOD1.glb", "lod_dist": 20.0, "tris_lod1": 9168, "len": 1.32, "ref": 0.45, "tris": 15606,
		"clips": {"idle": "idle_water", "swim": "swim", "fast": "swim", "glide": "glide", "breathe": "breathe_surface",
			"crawl": "crawl_sand", "nest": "dig_nest", "bite": "bite", "hit": "hit", "death": "death"}, "extras": [["glide", 1.0], ["bite", 0.5]]},
	"turtle_hawksbill": {"name": "Бисса", "file": "animal_turtle_hawksbill.glb", "lod1": "animal_turtle_hawksbill_LOD1.glb", "lod_dist": 20.0, "tris_lod1": 9200, "len": 1.08, "ref": 0.4, "tris": 14540,
		"clips": {"idle": "idle_water", "swim": "swim", "fast": "swim", "glide": "glide", "breathe": "breathe_surface",
			"crawl": "crawl_sand", "nest": "dig_nest", "bite": "bite", "hit": "hit", "death": "death"}, "extras": [["glide", 1.0], ["bite", 0.5]]},
	"lobster": {"name": "Лобстер", "file": "animal_lobster.glb", "len": 0.56, "ground": true, "ref": 0.055, "tris": 8860,
		"clips": {"idle": "idle", "swim": "walk", "fast": "swim", "flip": "tail_flip", "threat": "threat", "pinch": "pinch", "hit": "hit",
			"death": "death"}, "extras": [["pinch", 1.0]]},
	"shrimp_pistol": {"name": "Креветка-щелкун", "file": "animal_shrimp_pistol.glb", "len": 0.074, "ground": true, "ref": 0.03, "tris": 10374,
		"clips": {"idle": "idle", "swim": "walk", "fast": "swim", "flip": "tail_flip", "snap": "snap", "hit": "hit", "death": "death"},
		"extras": [["snap", 1.0]]},
	"starfish_orange": {"name": "Морская звезда", "file": "animal_starfish_orange.glb", "len": 0.22, "ground": true, "ref": 0.01, "tris": 3344,
		"clips": {"idle": "idle", "swim": "crawl", "fast": "crawl", "curl": "curl", "flip": "flip", "hit": "hit", "death": "death"},
		"extras": [["curl", 0.3]]},
	"starfish_spiny": {"name": "Колючая звезда", "file": "animal_starfish_spiny.glb", "len": 0.31, "ground": true, "ref": 0.01, "tris": 3896,
		"clips": {"idle": "idle", "swim": "crawl", "fast": "crawl", "curl": "curl", "flip": "flip", "hit": "hit", "death": "death"},
		"extras": [["curl", 0.3]]},
	"seacucumber_spotted": {"name": "Голотурия пятнистая", "file": "animal_seacucumber_spotted.glb", "len": 0.27, "ground": true, "ref": 0.01,
		"tris": 2228, "clips": {"idle": "idle", "swim": "crawl", "fast": "crawl", "feed": "feed", "contract": "contract", "death": "death"},
		"loops": ["feed"], "extras": [["feed", 2.0]]},
	"seacucumber_grey": {"name": "Голотурия серая", "file": "animal_seacucumber_grey.glb", "len": 0.23, "ground": true, "ref": 0.01,
		"tris": 2228, "clips": {"idle": "idle", "swim": "crawl", "fast": "crawl", "feed": "feed", "contract": "contract", "death": "death"},
		"loops": ["feed"], "extras": [["feed", 2.0]]},
	"seahorse_yellow": {"name": "Морской конёк (жёлтый)", "file": "animal_seahorse_yellow.glb", "len": 0.158, "upright": true, "ref": 0.05,
		"tris": 14932, "clips": SEAHORSE_CLIPS, "loops": ["grip"], "extras": [["eat", 1.5], ["look", 1.0]]},
	"seahorse_lilac": {"name": "Морской конёк (сиреневый)", "file": "animal_seahorse_lilac.glb", "len": 0.158, "upright": true, "ref": 0.05,
		"tris": 14932, "clips": SEAHORSE_CLIPS, "loops": ["grip"], "extras": [["eat", 1.5], ["look", 1.0]]},
	"seahorse_red": {"name": "Морской конёк (красный)", "file": "animal_seahorse_red.glb", "len": 0.158, "upright": true, "ref": 0.05,
		"tris": 14932, "clips": SEAHORSE_CLIPS, "loops": ["grip"], "extras": [["eat", 1.5], ["look", 1.0]]},
	# v5 (агент B): тунец пользователя (готовая модель со скелетом и одним клипом «swim»)
	"tuna": {"name": "Желтопёрый тунец", "file": "animal_fish_tuna.glb", "lod1": "animal_fish_tuna_LOD1.glb", "lod_dist": 18.0,
		"len": 11.69, "flip": true, "ref": 1.2, "tris": 26996, "tris_lod1": 3179,
		"clips": {"idle": "swim", "swim": "swim", "fast": "swim", "turn_l": "swim", "turn_r": "swim"}},
	"sardine": {"name": "Сардина", "file": "animal_fish_sardine.glb", "len": 0.186, "ref": 0.25, "tris": 550,
		"clips": {"idle": "swim", "swim": "swim", "fast": "swim_fast", "turn_l": "turn_L", "turn_r": "turn_R", "startle": "startle"}},
}

## Клипы-циклы (кроме перечисленных в def.loops).
const LOOPS := ["idle", "idle_hover", "swim", "swim_fast", "swim_slow", "walk", "crawl", "glide", "idle_glide", "idle_water",
	"idle_bottom", "idle_burrow", "dash", "feed"]
## Позы: доиграв, держат последний кадр, пока не сменится состояние.
const HOLDS := ["death", "bury", "idle_bottom", "threat", "contract", "curl"]

static var _scenes: Dictionary = {}
static var _bounds: Dictionary = {}
static var next_variant := -1

static func has(id: String) -> bool:
	return DEFS.has(id) and ResourceLoader.exists(DIR + String(DEFS[id]["file"]))

static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func clear_cache() -> void:
	_scenes.clear()
	_bounds.clear()

## Сцена GLB (клипы зациклены/обнулены по корню один раз на ресурс).
static func scene(file: String, d: Dictionary) -> PackedScene:
	if _scenes.has(file):
		return _scenes[file]
	var ps := load(DIR + file) as PackedScene
	if ps:
		var probe := ps.instantiate()
		var extra_loops: Array = d.get("loops", [])
		var zero: Array = d.get("zero_root", [])
		for ap: AnimationPlayer in probe.find_children("*", "AnimationPlayer", true, false):
			for lib_name in ap.get_animation_library_list():
				var lib := ap.get_animation_library(lib_name)
				for an_name in lib.get_animation_list():
					var an := lib.get_animation(an_name)
					var nm := String(an_name)
					an.loop_mode = Animation.LOOP_LINEAR if (nm in LOOPS or nm in extra_loops) else Animation.LOOP_NONE
					if nm in zero:
						_zero_root(an, probe)
		# габарит в позе покоя (для центровки)
		var ab := AABB()
		var first := true
		for mi: MeshInstance3D in probe.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var a := _xform_to(probe, mi) * mi.get_aabb()
			ab = a if first else ab.merge(a)
			first = false
		_bounds[file] = ab
		probe.free()
	_scenes[file] = ps
	return ps

static func _xform_to(root: Node, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

## Ход корня → на месте: ключи позиции корневых костей приравниваются первому.
static func _zero_root(an: Animation, probe: Node) -> void:
	var roots := {}
	for sk: Skeleton3D in probe.find_children("*", "Skeleton3D", true, false):
		for b in sk.get_bone_count():
			if sk.get_bone_parent(b) < 0:
				roots[sk.get_bone_name(b)] = true
	for t in an.get_track_count():
		if an.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var sub := String(an.track_get_path(t).get_concatenated_subnames())
		if not roots.has(sub) or an.track_get_key_count(t) == 0:
			continue
		var p0: Vector3 = an.track_get_key_value(t, 0)
		for k in an.track_get_key_count(t):
			an.track_set_key_value(t, k, p0)

## Габарит модели автора (после scene()).
static func bounds(id: String) -> AABB:
	var d := def(id)
	scene(String(d.get("file", "")), d)
	return _bounds.get(String(d.get("file", "")), AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2)))

# ============================== экземпляр ==============================

var id := ""
var d: Dictionary = {}
var game_len := 0.3
var scale_k := 1.0
var pivot: Node3D               # центровка/разворот
var lods: Array[Node3D] = []    # 0 — игровой GLB, 1 — облегчённый
var players: Array[AnimationPlayer] = []
var lod := 0
var _has := {}
var _cur := ""
var _oneshot := ""
var _oneshot_t := 0.0
var _pose := ""                 # удерживаемая поза (bury/threat/death…)
var _extra_cd := 4.0
var _rng := RandomNumberGenerator.new()
var _paused := false
var _lod_cd := 0.0
var on_event: Callable          # (имя события, существо) — щелчок креветки, укус, чернила…
var rest_pose := ""             # роль-поза, в которую существо возвращается после действий (конёк: grip)

## Существо вида id длиной game_len (м).
static func create(p_id: String, p_len: float = -1.0, seed_i: int = 0) -> SeaSkel:
	if not has(p_id):
		return null
	var s := SeaSkel.new()
	s._build(p_id, p_len, seed_i)
	return s

func _build(p_id: String, p_len: float, seed_i: int) -> void:
	id = p_id
	d = DEFS[p_id]
	name = "Skel_" + p_id
	_rng.seed = seed_i if seed_i != 0 else randi()
	game_len = p_len if p_len > 0.0 else float(d["len"])
	scale_k = game_len / float(d["len"])
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	pivot.scale = Vector3.ONE * scale_k
	var ab := bounds(p_id)
	var c := ab.get_center()
	var off := Vector3(-c.x, -c.y, -c.z)
	if bool(d.get("ground", false)):
		off.y = -ab.position.y
	if bool(d.get("flip", false)):
		pivot.rotation.y = PI
		off = Vector3(-off.x, off.y, -off.z)   # разворот вокруг Y: смещение тоже
	pivot.position = off * scale_k
	_add_lod(0)
	if d.has("lod1") and ResourceLoader.exists(DIR + String(d["lod1"])):
		lods.append(null)               # облегчённый — создаётся при первом удалении (память)
		players.append(null)
	if players[0]:
		for a in players[0].get_animation_list():
			_has[String(a)] = true
		_play(clip("idle"), 0.0)
		players[0].seek(_rng.randf() * 1.5, true)
	_extra_cd = _rng.randf_range(3.0, 8.0)
	set_meta(&"display_name", String(d.get("name", id)))

func _add_lod(i: int) -> void:
	var file := String(d["file"]) if i == 0 else String(d["lod1"])
	var inst := scene(file, d).instantiate() as Node3D
	inst.name = "LOD%d" % i
	pivot.add_child(inst)
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if game_len > 0.5 \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	if ap:
		ap.playback_default_blend_time = BLEND
	if i < lods.size():
		lods[i] = inst
		players[i] = ap
	else:
		lods.append(inst)
		players.append(ap)

func clip(role: String) -> String:
	var cl: Dictionary = d.get("clips", {})
	var c := String(cl.get(role, role))
	return c if _has.has(c) else ""

func has_role(role: String) -> bool:
	return clip(role) != ""

func player() -> AnimationPlayer:
	return players[lod] if lod < players.size() else null

func _play(c: String, blend: float = BLEND, spd: float = 1.0) -> void:
	var ap := player()
	if ap == null or c == "":
		return
	if c != _cur:
		ap.play(c, blend)
		_cur = c
	ap.speed_scale = spd

## Разовый клип роли role (укус, щелчок, чернила, бочка…). Возвращает длительность (0 — нет клипа).
func act(role: String) -> float:
	var c := clip(role)
	var ap := player()
	if c == "" or ap == null:
		return 0.0
	_pose = ""
	_oneshot = c
	var ln := ap.get_animation(c).length
	_oneshot_t = ln
	ap.play(c, 0.12)
	ap.speed_scale = 1.0
	ap.seek(0.0, true)
	_cur = c
	if role in ["snap", "bite", "ink", "lunge", "strike", "gulp", "pinch", "grab"] and on_event.is_valid():
		on_event.call(role, self)
	return ln

## Удерживаемая поза (bury → лежит в песке; threat; death). "" — снять.
func pose(role: String) -> void:
	var c := clip(role)
	if role == "":
		_pose = ""
		return
	if c == "":
		return
	_pose = c
	_oneshot = ""
	_play(c, 0.2)

func posing() -> String:
	return _pose

func busy() -> bool:
	return _oneshot != ""

## Тик анимации: speed — м/с, cruise — крейсерская, turn −1..1, still — держится на месте.
func drive(dt: float, speed: float, cruise: float, turn: float, still: bool) -> void:
	_update_lod(dt)
	var ap := player()
	if ap == null or _paused:
		return
	if _oneshot != "":
		_oneshot_t -= dt
		if _oneshot_t > 0.05:
			return
		_oneshot = ""
	if _pose == "" and rest_pose != "" and has_role(rest_pose):
		_pose = clip(rest_pose)
		_play(_pose, 0.3)
		return
	if _pose != "" and _pose != clip("death") and _pose in HOLDS and speed > maxf(cruise * 0.6, 0.02):
		_pose = ""                      # тронулся с места — поза снимается
	if _pose != "":
		# поза-цепочка: bury доиграл → лежит (idle_bottom)
		if _pose == clip("bury") and not ap.is_playing() and has_role("bottom"):
			_pose = clip("bottom")
			_play(_pose, 0.3)
		return
	var k := scale_k
	var ref := float(d.get("ref", 0.3)) * k
	var role := "swim"
	if still or speed < cruise * 0.2:
		role = "idle"
	elif speed > maxf(cruise * 1.8, ref * 2.5) and has_role("fast"):
		role = "fast"
	if role != "idle" and absf(turn) > 0.6 and speed < cruise * 1.5:
		var tr := "turn_l" if turn > 0.0 else "turn_r"
		if has_role(tr):
			role = tr
	var spd := 1.0
	if role == "swim" or role == "fast":
		var r := ref * (2.0 if role == "fast" else 1.0)
		spd = clampf(speed / maxf(r, 0.001), SPEED_MIN, SPEED_MAX)
	var c := clip(role)
	# поворотные клипы не зациклены: доиграв — снова ход
	if c == _cur and role.begins_with("turn") and not ap.is_playing():
		c = clip("swim")
	_play(c, BLEND, spd)
	# вставки в покое/на ходу
	_extra_cd -= dt
	if _extra_cd <= 0.0:
		_extra_cd = _rng.randf_range(4.0, 11.0)
		var ex: Array = d.get("extras", [])
		if not ex.is_empty() and (role == "idle" or role == "swim"):
			var tot := 0.0
			for e: Array in ex:
				tot += float(e[1])
			var pick := _rng.randf() * tot
			for e: Array in ex:
				pick -= float(e[1])
				if pick <= 0.0:
					act(String(e[0]))
					break

func _update_lod(dt: float) -> void:
	_lod_cd -= dt
	if _lod_cd > 0.0 or not is_inside_tree():
		return
	_lod_cd = 0.5
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var dist := cam.global_position.distance_to(global_position)
	var want := 1 if (lods.size() > 1 and dist > float(d.get("lod_dist", 20.0))) else 0
	if want != lod:
		_switch_lod(want)
	var pause := dist > PAUSE_DIST
	if pause != _paused:
		_paused = pause
		var ap := player()
		if ap:
			ap.speed_scale = 0.0 if pause else 1.0

func _switch_lod(to: int) -> void:
	var old := player()
	var t := old.current_animation_position if old and old.is_playing() else 0.0
	var spd := old.speed_scale if old else 1.0
	lods[lod].visible = false
	if old:
		old.process_mode = Node.PROCESS_MODE_DISABLED
	lod = to
	if lods[lod] == null:
		_add_lod(lod)
	lods[lod].visible = true
	var ap := player()
	if ap and _cur != "":
		ap.process_mode = Node.PROCESS_MODE_INHERIT
		ap.play(_cur, 0.0)
		ap.seek(t, true)
		ap.speed_scale = spd

## Точка кости bone (в позе текущего кадра) в координатах существа; null — нет такой кости.
## Конёк: "tail_grip" — середина завитка хвоста (там проходит стебель, за который он держится).
func bone_point(bone: String) -> Variant:
	var inst := lods[lod] if lod < lods.size() else null
	if inst == null:
		return null
	for sk: Skeleton3D in inst.find_children("*", "Skeleton3D", true, false):
		var b := sk.find_bone(bone)
		if b >= 0:
			return _xform_to(self, sk) * sk.get_bone_global_pose(b).origin
	return null

## Видимые треугольники текущего LOD (для подписей/F3).
func tris() -> int:
	return int(d.get("tris_lod1", d.get("tris", 0))) if lod == 1 else int(d.get("tris", 0))
