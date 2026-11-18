class_name DynamicResolution
extends RefCounted
## Динамическое разрешение 3D: держит время кадра в бюджете (по умолчанию
## 60 FPS или лимит кадров), снижая/повышая scaling_3d_scale шагами по 5 %
## между 50 % и масштабом пресета. Интерфейс не затрагивается.
## Время кадра берём из GPU-замера вьюпорта (если есть), иначе из delta.

static var current_scale: float = 0.0
static var _avg_ms: float = 0.0
static var _hold: float = 0.0
const STEP := 0.05
const MIN_SCALE := 0.5

static func target_ms() -> float:
	var fps := Settings.fps_cap if Settings.fps_cap > 0 else 60
	return 1000.0 / float(fps)

static func tick(vp: Viewport, delta: float) -> void:
	if GraphicsQuality.is_compat():
		return
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) \
		+ (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var ms := maxf(gpu, cpu) if gpu > 0.0 else delta * 1000.0
	_avg_ms = ms if _avg_ms <= 0.0 else lerpf(_avg_ms, ms, 0.08)
	var top := GraphicsQuality.auto_scale(vp)
	if current_scale <= 0.0:
		current_scale = top
	var t := target_ms()
	_hold -= delta
	if _hold > 0.0:
		return
	var ns := current_scale
	if _avg_ms > t * 0.95:
		ns = maxf(MIN_SCALE, current_scale - STEP)
		_hold = 0.6
	elif _avg_ms < t * 0.72:
		ns = minf(top, current_scale + STEP)
		_hold = 2.5
	if absf(ns - current_scale) > 0.001:
		current_scale = ns
		vp.scaling_3d_scale = ns

static func reset() -> void:
	current_scale = 0.0
	_avg_ms = 0.0
