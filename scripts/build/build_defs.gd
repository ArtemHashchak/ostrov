class_name BuildDefs
extends RefCounted
## Описание чертежей в духе The Forest: каждая постройка — список «деталей»
## (бревно, палка, верёвка, камень) с положением. Чертёж ставится призраком,
## затем детали укладываются по одной — постройка «прорастает».
##
## Деталь: {t: &"log"|&"stick"|&"rope"|&"stone", pos: Vector3, rot: Vector3 (эйлер),
##          len: float, r: float, solid: bool, shape: &"box"|&"cyl"|&"none"}

const R := 0.17          # радиус бревна
const D := 0.34          # диаметр бревна (шаг рядов)
const WALL_LEN := 3.0
const WALL_ROWS := 7
const WALL_H := D * WALL_ROWS   # 2.38 м
const DECK_H := 1.15            # верх настила платформы над точкой постановки
const RAFT_W := 2.04
const RAFT_L := 3.0
const STAIRS_RISE := 2.38
const STAIRS_RUN := 3.0

const HP_PER: Dictionary = {&"log": 35.0, &"stick": 8.0, &"rope": 6.0, &"stone": 30.0}
const NEED_NAMES: Dictionary = {&"log": "брёвна", &"stick": "палки", &"rope": "верёвка", &"stone": "камни"}

const ORDER: Array[StringName] = [&"wall", &"wall_window", &"wall_door", &"door", &"platform",
	&"stairs", &"roof", &"shelter", &"fire_pit", &"raft"]

const INFO: Dictionary = {
	&"wall": {"name": "Стена из брёвен", "kind": &"structure", "snap": &"wall", "radius": 1.6},
	&"wall_window": {"name": "Стена с окном", "kind": &"structure", "snap": &"wall", "radius": 1.6},
	&"wall_door": {"name": "Стена с дверным проёмом", "kind": &"structure", "snap": &"wall", "radius": 1.6},
	&"door": {"name": "Дверь", "kind": &"structure", "snap": &"door", "radius": 0.6, "socket_only": true},
	&"platform": {"name": "Платформа на сваях", "kind": &"structure", "snap": &"platform", "radius": 2.0},
	&"stairs": {"name": "Лестница", "kind": &"structure", "snap": &"stairs", "radius": 1.6},
	&"roof": {"name": "Крыша", "kind": &"structure", "snap": &"roof", "radius": 2.0, "socket_only": true},
	&"shelter": {"name": "Шалаш", "kind": &"structure", "snap": &"shelter", "radius": 1.6},
	&"fire_pit": {"name": "Каменный очаг", "kind": &"structure", "snap": &"fire_pit", "radius": 0.8},
	&"raft": {"name": "Мост: связка брёвен", "kind": &"raft", "snap": &"raft", "radius": 1.6},
}

static func name_of(id: StringName) -> String:
	return String(INFO.get(id, {}).get("name", String(id)))

static func kind_of(id: StringName) -> StringName:
	return StringName(INFO.get(id, {}).get("kind", &"structure"))

static func _p(t: StringName, pos: Vector3, rot: Vector3, length: float, radius: float,
		solid: bool = true, shape: StringName = &"box") -> Dictionary:
	return {"t": t, "pos": pos, "rot": rot, "len": length, "r": radius, "solid": solid, "shape": shape}

## Горизонтальное бревно вдоль X.
static func _log_x(x: float, y: float, z: float, length: float, solid: bool = true) -> Dictionary:
	return _p(&"log", Vector3(x, y, z), Vector3(0, 0, PI * 0.5), length, R, solid, &"box")

## Горизонтальное бревно вдоль Z.
static func _log_z(x: float, y: float, z: float, length: float, solid: bool = true) -> Dictionary:
	return _p(&"log", Vector3(x, y, z), Vector3(PI * 0.5, 0, 0), length, R, solid, &"box")

## Детали чертежа. ctx: {"ground": Callable(lx, lz) -> локальная высота земли} — для свай.
static func parts(id: StringName, ctx: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match id:
		&"wall", &"wall_window", &"wall_door":
			for row in WALL_ROWS:
				var y := R + row * D
				var split := false
				var gap := 0.0
				if id == &"wall_window" and (row == 3 or row == 4):
					split = true
					gap = 1.0
				elif id == &"wall_door" and row <= 5:
					split = true
					gap = 1.1
				if split:
					var seg := (WALL_LEN - gap) * 0.5 + 0.05
					var cx := gap * 0.5 + seg * 0.5 - 0.025
					out.append(_log_x(-cx, y, 0.0, seg))
					out.append(_log_x(cx, y, 0.0, seg))
				else:
					out.append(_log_x(0.0, y, 0.0, WALL_LEN + 0.1))
			# стойки-скрепы по краям (палки) и перевязь
			for sx in [-1.56, 1.56]:
				out.append(_p(&"stick", Vector3(sx, WALL_H * 0.5 + 0.05, 0.22), Vector3.ZERO, WALL_H + 0.2, 0.05, false, &"none"))
				out.append(_p(&"stick", Vector3(sx, WALL_H * 0.5 + 0.05, -0.22), Vector3.ZERO, WALL_H + 0.2, 0.05, false, &"none"))
			if id == &"wall_window":
				out.append(_p(&"stick", Vector3(0, R + 3 * D - R - 0.02, 0.0), Vector3(0, 0, PI * 0.5), 1.1, 0.045, false, &"none"))
		&"door":
			# дверь: петля в начале координат, полотно вдоль +X (ширина 1.06)
			for i in 3:
				out.append(_p(&"log", Vector3(0.18 + i * 0.35, 1.0, 0.0), Vector3.ZERO, 2.0, 0.165, true, &"box"))
			out.append(_p(&"stick", Vector3(0.53, 0.45, 0.2), Vector3(0, 0, PI * 0.5), 1.1, 0.05, false, &"none"))
			out.append(_p(&"stick", Vector3(0.53, 1.55, 0.2), Vector3(0, 0, PI * 0.5), 1.1, 0.05, false, &"none"))
			out.append(_p(&"rope", Vector3(0.05, 1.0, 0.0), Vector3.ZERO, 0.0, 0.2, false, &"none"))
		&"platform":
			var g: Callable = ctx.get("ground", Callable())
			var bottom := DECK_H - D * 2.0
			for c in [Vector2(-1.3, -1.3), Vector2(1.3, -1.3), Vector2(-1.3, 1.3), Vector2(1.3, 1.3)]:
				var gy := -0.4
				if g.is_valid():
					gy = float(g.call(c.x, c.y)) - 0.35
				var length := maxf(0.4, bottom - gy)
				out.append(_p(&"log", Vector3(c.x, gy + length * 0.5, c.y), Vector3.ZERO, length, R, true, &"cyl"))
			out.append(_log_x(0.0, DECK_H - D - R, -1.3, 3.1))
			out.append(_log_x(0.0, DECK_H - D - R, 1.3, 3.1))
			for i in 9:
				out.append(_log_z(-1.36 + i * D, DECK_H - R, 0.0, 3.1))
			for c in [Vector2(-1.3, -1.3), Vector2(1.3, 1.3)]:
				out.append(_p(&"rope", Vector3(c.x, DECK_H - D - R, c.y), Vector3.ZERO, 0.0, 0.24, false, &"none"))
		&"stairs":
			var dims := stairs_dims(ctx)
			var rise := dims.x
			var run := dims.y
			var slope := sqrt(rise * rise + run * run)
			for sx in [-0.62, 0.62]:
				out.append(_p(&"log", Vector3(sx, rise * 0.5, 0.0), Vector3(atan2(-run, rise), 0, 0), slope + 0.2, R, false, &"none"))
			var steps := maxi(3, int(round(rise / 0.3)))
			for i in steps:
				var f := (i + 0.5) / float(steps)
				out.append(_p(&"stick", Vector3(0.0, rise * f + 0.12, run * 0.5 - run * f),
					Vector3(0, 0, PI * 0.5), 1.45, 0.06, false, &"none"))
		&"roof":
			# двускатная крыша над комнатой 3×3; конёк вдоль X
			var ridge_y := 1.35
			var eave := 1.75
			out.append(_log_x(0.0, ridge_y + 0.05, 0.0, 3.4))
			for side in [-1.0, 1.0]:
				for i in 5:
					var f := (i + 0.5) / 5.0
					out.append(_log_x(0.0, ridge_y * (1.0 - f) + R, side * eave * f, 3.4, false))
			var rafter := sqrt(ridge_y * ridge_y + eave * eave)
			for sx in [-1.5, 1.5]:
				for side in [-1.0, 1.0]:
					var th := atan2(-side * eave, ridge_y)
					out.append(_p(&"stick", Vector3(sx, ridge_y * 0.5 + 0.05, side * eave * 0.5), Vector3(th, 0, 0), rafter + 0.2, 0.05, false, &"none"))
		&"shelter":
			for sx in [-1.15, 1.15]:
				out.append(_p(&"stick", Vector3(sx, 0.7, 0.0), Vector3.ZERO, 1.5, 0.06, false, &"none"))
			out.append(_log_x(0.0, 1.42, 0.0, 2.7, false))
			out.append(_p(&"rope", Vector3(-1.15, 1.42, 0.0), Vector3(0, 0, PI * 0.5), 0.0, 0.2, false, &"none"))
			for i in 12:
				var x := -1.1 + i * 0.2
				out.append(_p(&"stick", Vector3(x, 0.71, 0.85), Vector3(atan2(-1.7, 1.42), 0, 0), 2.25, 0.045, false, &"none"))
		&"fire_pit":
			for i in 8:
				var a := TAU * i / 8.0
				out.append(_p(&"stone", Vector3(cos(a) * 0.6, 0.1, sin(a) * 0.6), Vector3(0, a, 0), 0.0, 0.22, false, &"none"))
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				out.append(_p(&"stick", Vector3(cos(a) * 0.14, 0.35, sin(a) * 0.14), Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35), 0.8, 0.035, false, &"none"))
		&"raft":
			for i in 6:
				out.append(_log_z(-0.85 + i * D, 0.0, 0.0, RAFT_L))
			for z in [-1.12, 1.12]:
				out.append(_p(&"stick", Vector3(0.0, R + 0.03, z), Vector3(0, 0, PI * 0.5), 2.2, 0.05, false, &"none"))
			for z in [-1.12, 1.12]:
				out.append(_p(&"rope", Vector3(0.0, 0.0, z), Vector3(0, 0, PI * 0.5), 2.1, 0.035, false, &"none"))
	return out

## Стоимость чертежа: {log: n, stick: n, ...}.
static func cost(id: StringName) -> Dictionary:
	var c: Dictionary = {}
	for p: Dictionary in parts(id, {}):
		var t: StringName = p.t
		c[t] = int(c.get(t, 0)) + 1
	return c

static func cost_text(id: StringName) -> String:
	var c := cost(id)
	var bits: PackedStringArray = []
	for t: StringName in [&"log", &"stick", &"rope", &"stone"]:
		if c.has(t):
			bits.append("%s %d" % [NEED_NAMES[t], int(c[t])])
	return ", ".join(bits)

## Сокеты привязки постройки: [{tags: [snap...], xform: Transform3D (локально)}].
## Высота и длина лестницы (ctx.rise — до настила платформы).
static func stairs_dims(ctx: Dictionary) -> Vector2:
	var rise := float(ctx.get("rise", STAIRS_RISE))
	return Vector2(rise, maxf(1.4, rise * 1.4))   # ~35°

static func sockets(id: StringName) -> Array[Dictionary]:
	var s: Array[Dictionary] = []
	var rot90 := Basis(Vector3.UP, PI * 0.5)
	match id:
		&"wall", &"wall_window", &"wall_door":
			for sx in [-WALL_LEN, WALL_LEN]:
				s.append({"tags": [&"wall"], "xform": Transform3D(Basis(), Vector3(sx, 0, 0))})
			s.append({"tags": [&"wall"], "xform": Transform3D(Basis(), Vector3(0, WALL_H, 0))})
			for sz in [-1.5, 1.5]:
				s.append({"tags": [&"roof"], "xform": Transform3D(Basis(), Vector3(0, WALL_H, sz))})
				s.append({"tags": [&"wall"], "xform": Transform3D(rot90, Vector3(-1.5, 0, sz))})
				s.append({"tags": [&"wall"], "xform": Transform3D(rot90, Vector3(1.5, 0, sz))})
			if id == &"wall_door":
				s.append({"tags": [&"door"], "xform": Transform3D(Basis(), Vector3(-0.53, 0, 0))})
		&"platform":
			for d in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
				s.append({"tags": [&"platform"], "xform": Transform3D(Basis(), d)})
			s.append({"tags": [&"wall"], "xform": Transform3D(Basis(), Vector3(0, DECK_H, -1.5))})
			s.append({"tags": [&"wall"], "xform": Transform3D(Basis(), Vector3(0, DECK_H, 1.5))})
			s.append({"tags": [&"wall"], "xform": Transform3D(rot90, Vector3(-1.5, DECK_H, 0))})
			s.append({"tags": [&"wall"], "xform": Transform3D(rot90, Vector3(1.5, DECK_H, 0))})
			s.append({"tags": [&"roof", &"shelter", &"fire_pit"], "xform": Transform3D(Basis(), Vector3(0, DECK_H, 0))})
			var run := stairs_dims({"rise": DECK_H}).y
			s.append({"tags": [&"stairs"], "xform": Transform3D(Basis(), Vector3(0, 0, 1.5 + run * 0.5 + 0.1)), "ctx": {"rise": DECK_H}})
	return s
