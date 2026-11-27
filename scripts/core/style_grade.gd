class_name StyleGrade
extends RefCounted
## Единая цветокоррекция кадра (LUT) и мягкая автоэкспозиция — общий «киношный» ряд,
## который склеивает модели разных авторов. Мягко: лёгкая S-кривая, тени чуть в бирюзу,
## света чуть тёплые, живее зелень и вода, кожа/песок не трогаются.
## LUT строится в коде (без файла), 32³, применяется после тонмаппинга (Environment.adjustment_*).
## StyleGrade.enabled — переключатель «до/после» (полка стиля на полигоне).

const SIZE := 32
const STRENGTH := 1.0

static var enabled := true
static var _lut: ImageTexture3D
static var _envs: Array[Environment] = []


static func lut() -> ImageTexture3D:
	if _lut == null:
		_lut = _build()
	return _lut


## Подключить к окружению. world_env — узел WorldEnvironment (для автоэкспозиции; можно null).
static func apply(env: Environment, world_env: Node = null) -> void:
	if env == null:
		return
	if not _envs.has(env):
		_envs.append(env)
	env.adjustment_color_correction = lut() if enabled else null
	if enabled:
		env.adjustment_enabled = true
	if world_env is WorldEnvironment and not RenderProfile.is_compat():
		var we := world_env as WorldEnvironment
		var ca := we.camera_attributes as CameraAttributesPractical
		if ca == null:
			ca = CameraAttributesPractical.new()
			we.camera_attributes = ca
		# узкий диапазон (≈ ±0.8 EV): яркий пляж чуть темнее, тень джунглей и пещеры чуть светлее
		ca.auto_exposure_enabled = enabled
		# v5: глаз привыкает к свету — выход из тени джунглей на пляж слепит ~1 с, обратно —
		# темно ~2 с (диапазон ≈ ±1 EV, скорость выше прежней)
		# v5.1: мерцание — автоэкспозиция «качала» кадр при повороте камеры (небо ↔ земля, листва):
		# диапазон уже (≈ ±0,7 EV) и привыкание медленнее (~2–3 с), без резких рывков
		ca.auto_exposure_min_sensitivity = 80.0
		ca.auto_exposure_max_sensitivity = 220.0
		ca.auto_exposure_scale = 0.4
		ca.auto_exposure_speed = 0.45


static func set_enabled(on: bool) -> void:
	enabled = on
	for e in _envs:
		if is_instance_valid(e):
			e.adjustment_color_correction = lut() if on else null


## Нужна ли коррекция всегда (а не только в дождь/шторм).
static func active(env: Environment) -> bool:
	return env != null and env.adjustment_color_correction != null


static func grade(c: Color) -> Color:
	var r := c.r
	var g := c.g
	var b := c.b
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	# 1) мягкая S-кривая вокруг 0.45 (+4% контраста в середине, концы на месте)
	var t := clampf(y, 0.0, 1.0)
	var s := t + 0.045 * sin((t - 0.45) * PI / 0.55) * (1.0 - absf(t - 0.45) / 0.55) if absf(t - 0.45) < 0.55 else t
	var k := s / maxf(y, 1e-4) if y > 1e-4 else 1.0
	r *= k
	g *= k
	b *= k
	y = s
	# 2) сплит-тон: тени — бирюза, света — тёплый (слабо)
	var sh := pow(1.0 - clampf(y, 0.0, 1.0), 2.0) * 0.55
	var hi := pow(clampf(y, 0.0, 1.0), 2.0)
	r += -0.010 * sh + 0.018 * hi
	g += 0.006 * sh + 0.006 * hi
	b += 0.016 * sh - 0.014 * hi
	# 3) «вибранс»: тусклое чуть насыщеннее, зелень/бирюза +6%, оранж (кожа, песок) не трогаем
	var col := Color(clampf(r, 0, 1), clampf(g, 0, 1), clampf(b, 0, 1))
	var h := col.h
	var sat := col.s
	var vib := 0.08 * (1.0 - sat)
	var green_cyan := clampf(1.0 - absf(h - 0.42) / 0.16, 0.0, 1.0)   # 0.26…0.58 — зелень и бирюза
	var orange := clampf(1.0 - absf(h - 0.08) / 0.06, 0.0, 1.0)
	var add := (vib + 0.06 * green_cyan) * (1.0 - orange)
	col.s = clampf(sat * (1.0 + add), 0.0, 1.0)
	return Color(c.r, c.g, c.b).lerp(col, STRENGTH)


static func _build() -> ImageTexture3D:
	var imgs: Array[Image] = []
	for zi in SIZE:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for yi in SIZE:
			for xi in SIZE:
				var c := Color(xi / float(SIZE - 1), yi / float(SIZE - 1), zi / float(SIZE - 1))
				img.set_pixel(xi, yi, grade(c))
		imgs.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, imgs)
	return tex
