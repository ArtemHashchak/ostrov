class_name GraphicsQuality
extends RefCounted
## Пресеты графики (0 низкое, 1 среднее, 2 высокое, 3 ультра) — единое место,
## где решается цена кадра: масштаб 3D и апскейлер, тени, эффекты окружения,
## небо, дальность травы/кустов (detail). Применяет Settings.apply_graphics();
## окружение и солнце перенастраиваются по сигналу Settings.graphics_changed.
##
## Цены (Forward+, грубо, от дорогого к дешёвому): SDFGI > объёмный туман >
## SSIL > SSR > тени 4 каскада 4096 > SSAO > свечение. Поэтому SDFGI/SSIL/
## объёмный туман — только «ультра»; «высокое» держит SSAO, тени 4 каскада,
## свечение, туман Sky3D и масштаб 3D с временным апскейлером (MetalFX/FSR2).

const NAMES: Array[String] = ["низкое", "среднее", "высокое", "ультра"]

## Пресеты. scale — доля разрешения 3D при «авто» (умножается на поправку
## для экранов с большим числом пикселей, см. auto_scale()).
const PRESETS: Array[Dictionary] = [
	{ # низкое — встроенная графика, старые ноутбуки
		"scale": 0.6, "upscaler": "spatial",
		"shadow_atlas": 1024, "shadow_splits": 2, "shadow_dist": 60.0, "soft_shadows": 0, "shadow_blur": 0.6,
		"pos_shadow_atlas": 1024,
		"ssao": false, "ssil": false, "sdfgi": false, "vol_fog": false, "glow": false, "ssr": false,
		"radiance": Sky.RADIANCE_SIZE_32, "sky_fog": false,
		"detail": 0.5, "lod_threshold": 4.0, "aniso": 1,
	},
	{ # среднее
		"scale": 0.75, "upscaler": "temporal",
		"shadow_atlas": 2048, "shadow_splits": 2, "shadow_dist": 90.0, "soft_shadows": 1, "shadow_blur": 1.0,
		"pos_shadow_atlas": 2048,
		"ssao": true, "ssil": false, "sdfgi": false, "vol_fog": false, "glow": true, "ssr": false,
		"radiance": Sky.RADIANCE_SIZE_64, "sky_fog": true,
		"detail": 0.75, "lod_threshold": 2.0, "aniso": 2,
	},
	{ # высокое — цель 60 FPS на современных ноутбуках (M-серия, RTX 3050+)
		"scale": 0.85, "upscaler": "temporal",
		"shadow_atlas": 4096, "shadow_splits": 4, "shadow_dist": 130.0, "soft_shadows": 2, "shadow_blur": 1.2,
		"pos_shadow_atlas": 2048,
		"ssao": true, "ssil": false, "sdfgi": false, "vol_fog": false, "glow": true, "ssr": false,
		"radiance": Sky.RADIANCE_SIZE_128, "sky_fog": true,
		"detail": 1.0, "lod_threshold": 1.0, "aniso": 3,
	},
	{ # ультра — сильные видеокарты
		"scale": 1.0, "upscaler": "temporal",
		"shadow_atlas": 8192, "shadow_splits": 4, "shadow_dist": 180.0, "soft_shadows": 3, "shadow_blur": 1.3,
		"pos_shadow_atlas": 4096,
		"ssao": true, "ssil": true, "sdfgi": true, "vol_fog": true, "glow": true, "ssr": false,
		"radiance": Sky.RADIANCE_SIZE_256, "sky_fog": true,
		"detail": 1.25, "lod_threshold": 1.0, "aniso": 4,
	},
]

static func preset(q: int = -1) -> Dictionary:
	if q < 0:
		q = Settings.graphics_quality
	return PRESETS[clampi(q, 0, 3)]

static func is_compat() -> bool:
	return RenderingServer.get_rendering_device() == null

static func is_metal() -> bool:
	return OS.get_name() == "macOS" and not is_compat() \
		and RenderingServer.get_current_rendering_driver_name().to_lower().contains("metal")

## Множитель дальности мелкой растительности/декора (трава, кусты, камни).
static func detail() -> float:
	return float(preset().get("detail", 1.0))

## Масштаб 3D: ручной (Settings.render_scale > 0) или авто по пресету и
## размеру окна — на 4K/Retina-экранах рендерим меньшую долю пикселей.
static func auto_scale(vp: Viewport) -> float:
	if Settings.render_scale > 0.0:
		return clampf(Settings.render_scale, 0.25, 1.0)
	var s := float(preset().get("scale", 1.0))
	var px := float(vp.get_visible_rect().size.x * vp.get_visible_rect().size.y)
	if vp is Window:
		var w := vp as Window
		px = float(w.size.x * w.size.y)
	# опорно ~1920×1080; на 2560×1600 (Retina-ноутбук) ≈ ×0.82, на 4K ≈ ×0.71
	var ref := 1920.0 * 1080.0
	if px > ref * 1.15:
		s *= clampf(sqrt(ref / px) * 1.03, 0.62, 1.0)
	return clampf(s, 0.4, 1.0)

## Применить к корневому вьюпорту: масштаб 3D, апскейлер, сглаживание, тени.
static func apply_viewport(vp: Viewport) -> void:
	var q := clampi(Settings.graphics_quality, 0, 3)
	var p := preset(q)
	var scale := auto_scale(vp)
	if Settings.dynamic_resolution and DynamicResolution.current_scale > 0.0:
		scale = DynamicResolution.current_scale
	if is_compat():
		# gl_compatibility — автотесты и запасной режим: прежняя простая схема
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = Settings.render_scale if Settings.render_scale > 0.0 else [0.67, 0.8, 1.0, 1.0][q]
		vp.msaa_3d = Viewport.MSAA_DISABLED if q < 2 else Viewport.MSAA_2X
		vp.mesh_lod_threshold = float(p.lod_threshold)
		return
	var temporal := String(p.upscaler) == "temporal"
	if scale >= 0.999:
		# Родное разрешение: TAA при временном режиме, иначе FXAA.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.use_taa = temporal
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if temporal else Viewport.SCREEN_SPACE_AA_FXAA
	elif temporal:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if is_metal() else Viewport.SCALING_3D_MODE_FSR2
		vp.use_taa = false # временной апскейлер сам сглаживает
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL if is_metal() else Viewport.SCALING_3D_MODE_FSR
		vp.use_taa = false
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.35
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.mesh_lod_threshold = float(p.lod_threshold)
	vp.anisotropic_filtering_level = int(p.aniso) as Viewport.AnisotropicFiltering
	vp.positional_shadow_atlas_size = int(p.pos_shadow_atlas)
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_atlas), true)
	var sq := int(p.soft_shadows) as RenderingServer.ShadowQuality
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)
	# SSAO/SSIL в половинном разрешении — основная экономия без видимой потери.
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_LOW if q < 2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if q >= 3 else 48, 64 if q >= 3 else 48)
	RenderingServer.environment_set_volumetric_fog_filter_active(q >= 3)
	RenderingServer.gi_set_use_half_resolution(q < 3)

## Эффекты окружения (Forward+). Базовый туман/тонмаппинг не трогаем.
static func apply_environment(env: Environment) -> void:
	if env == null or is_compat():
		return
	var p := preset()
	env.ssao_enabled = bool(p.ssao)
	env.ssil_enabled = bool(p.ssil)
	env.sdfgi_enabled = bool(p.sdfgi)
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	env.volumetric_fog_enabled = bool(p.vol_fog)
	if env.volumetric_fog_enabled:
		# По умолчанию объёмный туман кончается в 64 м — граница видна «полусферой»
		# вокруг игрока (дальше туман резко пропадает). Растягиваем объём на 240 м
		# (дальние срезы грубее — detail_spread) и гасим его плотность к краю: дальше
		# работает обычный глубинный туман, который продолжается без шва.
		env.volumetric_fog_length = 240.0
		env.volumetric_fog_detail_spread = 2.5
		env.volumetric_fog_temporal_reprojection_enabled = true
	env.glow_enabled = bool(p.glow)
	env.ssr_enabled = bool(p.ssr)
	if env.sky:
		env.sky.radiance_size = int(p.radiance) as Sky.RadianceSize
		# Небо Sky3D анимировано (облака, TIME): пересчёт отражений по частям
		# за несколько кадров вместо полного пересчёта каждый кадр.
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

## Солнце: каскады, дальность, мягкость.
static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	var p := preset()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p.shadow_splits) >= 4 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = float(p.shadow_dist)
	sun.shadow_blur = float(p.shadow_blur)
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_blend_splits = int(p.shadow_splits) >= 4 and Settings.graphics_quality >= 3

## Предлагаемый пресет для первого запуска — по видеокарте и экрану.
static func detect_default() -> int:
	if is_compat():
		return 0
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var dtype := -1
	var rd := RenderingServer.get_rendering_device()
	if rd:
		dtype = rd.get_device_type()
	var screen := DisplayServer.screen_get_size()
	var px := screen.x * screen.y
	var q := 2
	if dtype == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		q = 1
		if adapter.contains("apple"):
			# Apple M: базовые чипы — «среднее», Pro/Max/Ultra — «высокое».
			q = 2 if (adapter.contains("pro") or adapter.contains("max") or adapter.contains("ultra")) else 1
		elif adapter.contains("intel") and not adapter.contains("arc"):
			q = 0
	elif dtype == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		q = 2
		for hi in ["rtx 40", "rtx 50", "rtx 308", "rtx 309", "rx 79", "rx 78", "rx 69", "rx 68"]:
			if adapter.contains(hi):
				q = 3
		for lo in ["gtx 9", "gtx 10", "gt ", "mx", "rx 5", "rx 4"]:
			if adapter.contains(lo):
				q = 1
	elif dtype == RenderingDevice.DEVICE_TYPE_CPU or dtype == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
		q = 0
	if px > 3840 * 2000 and q > 1 and not vendor.contains("nvidia"):
		q -= 1 # 4K без сильной карты
	return q
