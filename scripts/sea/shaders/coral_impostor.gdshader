shader_type spatial;
render_mode cull_disabled;
// Импостор («заранее снятый» коралл): квадрат, повёрнутый к камере, показывает снимки модели высокой
// детализации из атласа N×N направлений верхней полусферы (полу-октаэдр). Смешиваются 4 ближайших
// снимка, нормаль снимка (координаты модели) освещается как обычная поверхность — свет, время суток,
// каустика и поглощение воды как у мешей кораллов (coral_pack.gdshader). Запекание:
// tools/model_gen/corals/bake_impostors.gd. Меш — квадрат 2×2 (вершины ±1).

#include "res://scripts/sea/shaders/coral_common.gdshaderinc"

uniform sampler2D imp_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D imp_normal : filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform vec3 imp_center = vec3(0.0, 0.5, 0.0);
uniform float imp_radius = 1.0;
uniform float water_level = 0.0;
uniform float caustic_strength = 0.75;
uniform float rough = 0.75;
uniform float wet_spec = 0.3;
uniform float lod_begin = 0.0;
uniform float lod_end = 0.0;
uniform float lod_fade = 3.0;
uniform float alpha_cut = 0.45;

varying vec3 wpos;
varying vec3 tint;
varying float hue_k;
varying vec3 p_l;          // точка квадрата в координатах модели
varying vec2 cell;         // нижний левый снимок блока 2×2
varying vec2 wgt;          // веса билинейного смешивания снимков
varying float vis;

vec3 hemi_decode(vec2 o) {
	vec2 p = vec2(o.x + o.y, o.x - o.y) * 0.5;
	float y = 1.0 - abs(p.x) - abs(p.y);
	return normalize(vec3(p.x, max(y, 0.0), p.y));
}

vec2 hemi_encode(vec3 d) {
	d.y = max(d.y, 0.0);
	vec3 a = abs(d);
	vec2 p = d.xz / max(a.x + a.y + a.z, 0.0001);
	return vec2(p.x + p.y, p.x - p.y);
}

void frame_basis(vec3 d, out vec3 bx, out vec3 by) {
	if (abs(d.y) > 0.999) {
		bx = vec3(1.0, 0.0, 0.0);
	} else {
		bx = normalize(cross(vec3(0.0, 1.0, 0.0), d));
	}
	by = normalize(cross(d, bx));
}

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	if (dot(tint, tint) < 0.0001) {
		tint = vec3(1.0);
	}
	hue_k = fract(INSTANCE_CUSTOM.a * 7.13) - 0.5;
	float idist = length(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	vis = coral_lod_vis(idist, lod_begin, lod_end, lod_fade);
	vec3 cam_l = coral_cam_local(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	vec3 d = normalize(cam_l - imp_center);
	d.y = max(d.y, 0.03);
	d = normalize(d);
	vec3 bx;
	vec3 by;
	frame_basis(d, bx, by);
	p_l = imp_center + (bx * VERTEX.x + by * VERTEX.y) * imp_radius;
	VERTEX = p_l;
	NORMAL = d;
	vec2 g = (hemi_encode(d) * 0.5 + 0.5) * frames - 0.5;
	g = clamp(g, vec2(0.0), vec2(frames - 1.0));
	cell = min(floor(g), vec2(frames - 2.0));
	wgt = clamp(g - cell, vec2(0.0), vec2(1.0));
	if (vis <= 0.0) {
		VERTEX = vec3(0.0);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Снимок (i, j): uv точки p_l на его плоскости → координаты атласа.
vec2 frame_uv(vec2 ij, out bool inside) {
	vec2 o = (ij + 0.5) / frames * 2.0 - 1.0;
	vec3 fd = hemi_decode(o);
	vec3 bx;
	vec3 by;
	frame_basis(fd, bx, by);
	vec3 q = p_l - imp_center;
	vec2 uv = vec2(dot(q, bx), -dot(q, by)) / (2.0 * imp_radius) + 0.5;
	inside = all(greaterThan(uv, vec2(0.002))) && all(lessThan(uv, vec2(0.998)));
	return (ij + clamp(uv, vec2(0.002), vec2(0.998))) / frames;
}

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	float c = 1.0 - abs(a + b) * 0.5;
	return pow(clamp(c, 0.0, 1.0), 7.0);
}

void fragment() {
	if (vis < 0.999 && vis <= coral_dither(FRAGCOORD.xy)) {
		discard;
	}
	vec4 acc = vec4(0.0);
	vec3 nacc = vec3(0.0);
	float wsum = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 off = vec2(float(k % 2), float(k / 2));
		float w = (off.x > 0.5 ? wgt.x : 1.0 - wgt.x) * (off.y > 0.5 ? wgt.y : 1.0 - wgt.y);
		if (w < 0.001) {
			continue;
		}
		bool inside;
		vec2 auv = frame_uv(cell + off, inside);
		if (!inside) {
			continue;
		}
		vec4 a = texture(imp_albedo, auv);
		vec3 n = texture(imp_normal, auv).rgb * 2.0 - 1.0;
		acc.rgb += a.rgb * a.a * w;
		acc.a += a.a * w;
		nacc += n * a.a * w;
		wsum += w;
	}
	float alpha = wsum > 0.0 ? acc.a / wsum : 0.0;
	if (alpha < alpha_cut) {
		discard;
	}
	vec3 col = acc.rgb / max(acc.a, 0.0001) * tint;
	col = mix(col, col.gbr, hue_k * 0.10);
	vec3 n_l = normalize(nacc);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n_l, 0.0))).xyz);
	float depth = water_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 11.0, 0.0, 1.0) * under;
	float c = caus(wpos.xz * 0.85, TIME * 0.9) + 0.6 * caus(wpos.xz * 1.9 + 3.1, TIME * 1.15);
	vec3 absorb = mix(vec3(1.0), vec3(0.6, 0.86, 0.95), clamp(depth / 10.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + c * k);
	EMISSION = col * c * k * 0.10;
	ROUGHNESS = rough;
	SPECULAR = wet_spec;
	BACKLIGHT = col * 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += col * rim * 0.08 * (1.0 - clamp(depth / 14.0, 0.0, 1.0) * under);
}
