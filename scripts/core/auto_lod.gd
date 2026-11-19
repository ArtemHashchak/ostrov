class_name AutoLOD
extends RefCounted
## Автоматическая дальность видимости и тени для всей геометрии сцены, у
## которой их не задали вручную (предметы, обломки, звери, постройки, модели
## из пака пользователя). Подключается к SceneTree.node_added (Settings).
##
## Правило по размеру объекта s (наибольшая сторона AABB в метрах):
##   s < 0.4  → 45 м, без тени      (камешки, ракушки, мелкие предметы)
##   s < 1.0  → 75 м, без тени      (травы, обломки, мелкие звери)
##   s < 3    → 130 м               (кусты, ящики, звери, части построек)
##   s < 8    → 300 м               (брёвна мостов, стены, лодки)
##   s < 30   → 600 м               (крупные постройки, остовы кораблей)
##   больше   → без ограничения
## Дальность умножается на GraphicsQuality.detail() (пресет).
## Не трогаем: уже заданную дальность, геометрию в под-вьюпортах (иконки),
## руки/предметы у камеры, узлы с метой "no_auto_lod" и потомков групп
## "flag" и "no_auto_lod".

const GROUP := &"auto_lod"
const META_BASE := &"auto_lod_base"

static var _queue: Array[GeometryInstance3D] = []
static var _scheduled := false
static var _later: Array[GeometryInstance3D] = []
static var enabled := true
static var processed := 0

static func connect_tree(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)

static func _on_node_added(n: Node) -> void:
	if not enabled or not (n is GeometryInstance3D):
		return
	_queue.append(n as GeometryInstance3D)
	if not _scheduled:
		_scheduled = true
		_flush.call_deferred()

static func _flush() -> void:
	_scheduled = false
	var q := _queue
	_queue = []
	for gi in q:
		if is_instance_valid(gi) and gi.is_inside_tree():
			apply(gi)

static func _flush_later(tree: SceneTree) -> void:
	await tree.process_frame
	var q := _later
	_later = []
	for gi in q:
		if is_instance_valid(gi) and gi.is_inside_tree():
			apply(gi)

static func base_range(s: float) -> float:
	if s < 0.4: return 45.0
	if s < 1.0: return 75.0
	if s < 3.0: return 130.0
	if s < 8.0: return 300.0
	if s < 30.0: return 600.0
	return 0.0

static func _exempt(gi: GeometryInstance3D) -> bool:
	if gi.has_meta(&"no_auto_lod"):
		return true
	var tree := gi.get_tree()
	if tree == null or gi.get_viewport() != tree.root:
		return true
	var p: Node = gi.get_parent()
	while p != null:
		if p is Camera3D or p.is_in_group(&"flag") or p.is_in_group(&"no_auto_lod") or p.is_in_group(&"player"):
			return true
		p = p.get_parent()
	return false

## Размер в мировых единицах (учитывает масштаб узла).
static func world_size(gi: GeometryInstance3D) -> float:
	var ab := gi.get_aabb()
	if ab.size == Vector3.ZERO:
		return -1.0
	var sc := gi.global_transform.basis.get_scale()
	var sz := ab.size * sc.abs()
	return maxf(sz.x, maxf(sz.y, sz.z))

static func apply(gi: GeometryInstance3D) -> void:
	if _exempt(gi):
		return
	var s := world_size(gi)
	if s <= 0.0:
		# меш ещё не назначен — одна повторная попытка в следующем кадре
		if not gi.has_meta(&"auto_lod_retry"):
			gi.set_meta(&"auto_lod_retry", true)
			_later.append(gi)
			if _later.size() == 1:
				_flush_later.call_deferred(gi.get_tree())
		return
	var r := base_range(s)
	if r <= 0.0:
		return
	if gi is MultiMeshInstance3D or gi is GPUParticles3D or gi is CPUParticles3D:
		# AABB группы/частиц не равен размеру объекта
		return
	if s < 0.6:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
		return # дальность задана модулем
	gi.set_meta(META_BASE, r)
	gi.add_to_group(GROUP)
	gi.visibility_range_end = r * GraphicsQuality.detail()
	gi.visibility_range_end_margin = clampf(r * 0.12, 4.0, 30.0)
	# плавное растворение на границе (Forward+/Mobile; в Compatibility — без эффекта):
	# без него предметы «выскакивают», а граница дальности читается кругом вокруг игрока
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if s < 1.0:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	processed += 1

## Пресет изменился — пересчитать дальности.
static func rescale(tree: SceneTree) -> void:
	var k := GraphicsQuality.detail()
	for n in tree.get_nodes_in_group(GROUP):
		var gi := n as GeometryInstance3D
		if gi and gi.has_meta(META_BASE):
			gi.visibility_range_end = float(gi.get_meta(META_BASE)) * k
