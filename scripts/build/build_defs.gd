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

const TOWER_H := 3.6            # верх настила вышки
const FOUND_H := 0.48           # верх каменного фундамента
const PAL_R := 0.21             # радиус кольев частокола
const PAL_N := 7

const ORDER: Array[StringName] = [&"wall", &"wall_window", &"wall_door", &"door", &"platform",
	&"stairs", &"roof", &"shelter", &"fire_pit",
	&"palisade", &"gate", &"spikes", &"watchtower", &"foundation",
	&"chest", &"log_holder", &"workbench",
	&"raft", &"raft_gate", &"raft_pile"]

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
	&"palisade": {"name": "Частокол", "kind": &"structure", "snap": &"palisade", "radius": 1.6},
	&"gate": {"name": "Ворота в частоколе", "kind": &"structure", "snap": &"palisade", "radius": 1.6},
	&"spikes": {"name": "Колья (ловушка)", "kind": &"structure", "snap": &"spikes", "radius": 1.5},
	&"watchtower": {"name": "Сторожевая вышка", "kind": &"structure", "snap": &"watchtower", "radius": 1.9},
	&"foundation": {"name": "Каменный фундамент", "kind": &"structure", "snap": &"foundation", "radius": 1.9},
	&"chest": {"name": "Сундук", "kind": &"structure", "snap": &"chest", "radius": 0.8},
	&"log_holder": {"name": "Поленница (10 брёвен)", "kind": &"structure", "snap": &"log_holder", "radius": 1.2},
	&"workbench": {"name": "Верстак", "kind": &"structure", "snap": &"workbench", "radius": 1.2},
	&"raft_gate": {"name": "Мост: секция с воротами", "kind": &"raft", "snap": &"raft", "radius": 1.6},
	&"raft_pile": {"name": "Мост: секция на сваях", "kind": &"raft", "snap": &"raft", "radius": 1.6},
}

## Створка (ворота, крышка сундука): детали с "leaf" вращаются вокруг оси.
## box — коллизия закрытой створки (локально, в координатах постройки).
const LEAVES: Dictionary = {
	&"gate": {"pivot": Vector3(-1.16, 0, 0), "axis": Vector3.UP, "angle": -1.75,
		"box_size": Vector3(2.3, 2.62, 0.36), "box_pos": Vector3(0, 1.39, 0)},
	&"raft_gate": {"pivot": Vector3(-0.88, 0, 0), "axis": Vector3.UP, "angle": -1.7,
		"box_size": Vector3(1.75, 1.95, 0.2), "box_pos": Vector3(0, R + 1.06, 0)},
	&"chest": {"pivot": Vector3(0, 0.69, -0.3), "axis": Vector3.RIGHT, "angle": -1.45},
}

static func leaf(id: StringName) -> Dictionary:
	return LEAVES.get(id, {})

## Высота настила, к которому цепляется лестница.
static func deck_h(id: StringName) -> float:
	return TOWER_H if id == &"watchtower" else DECK_H

static func name_of(id: StringName) -> String:
	return String(INFO.get(id, {}).get("name", String(id)))

static func kind_of(id: StringName) -> StringName:
	return StringName(INFO.get(id, {}).get("kind", &"structure"))

static func _p(t: StringName, pos: Vector3, rot: Vector3, length: float, radius: float,
		solid: bool = true, shape: StringName = &"box") -> Dictionary:
	return {"t": t, "pos": pos, "rot": rot, "len": length, "r": radius, "solid": solid, "shape": shape}

## Деталь с флагами: sharp — заострённый конец (+Y), leaf — часть створки.
static func _pf(t: StringName, pos: Vector3, rot: Vector3, length: float, radius: float,
		solid: bool, shape: StringName, flags: Dictionary) -> Dictionary:
	var d := _p(t, pos, rot, length, radius, solid, shape)
	d.merge(flags)
	return d

## Палка от точки a до b (ось Y детали смотрит a→b).
static func _stick_ab(t: StringName, a: Vector3, b: Vector3, r: float, flags: Dictionary = {}) -> Dictionary:
	var d := b - a
	var ln := d.length()
	var y := d / ln
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.2:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var bas := Basis(x, y, x.cross(y).normalized())
	return _pf(t, (a + b) * 0.5, bas.get_euler(), ln, r, false, &"none", flags)

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
		&"raft_gate":
			out = parts(&"raft", ctx)
			for sx in [-0.95, 0.95]:
				out.append(_pf(&"log", Vector3(sx, R + 1.15, 0.0), Vector3.ZERO, 2.3, 0.12, true, &"cyl", {"sharp": true}))
			out.append(_p(&"stick", Vector3(0.0, R + 2.12, 0.0), Vector3(0, 0, PI * 0.5), 2.15, 0.06, false, &"none"))
			for i in 5:
				var x := -0.72 + i * 0.36
				out.append(_pf(&"stick", Vector3(x, R + 1.06, 0.0), Vector3.ZERO, 1.85 + 0.06 * sin(i * 2.3), 0.08, false, &"none",
					{"sharp": true, "leaf": true}))
			for y in [R + 0.45, R + 1.55]:
				out.append(_pf(&"stick", Vector3(0.0, y, -0.12), Vector3(0, 0, PI * 0.5), 1.75, 0.05, false, &"none", {"leaf": true}))
		&"raft_pile":
			out = parts(&"raft", ctx)
			var gp: Callable = ctx.get("ground", Callable())
			for c in [Vector2(-0.85, -1.2), Vector2(0.85, -1.2), Vector2(-0.85, 1.2), Vector2(0.85, 1.2)]:
				var gy2 := -3.0
				if gp.is_valid():
					gy2 = float(gp.call(c.x, c.y)) - 0.4
				var top := R + 0.5
				var length2 := maxf(0.8, top - gy2)
				out.append(_pf(&"log", Vector3(c.x, top - length2 * 0.5, c.y), Vector3.ZERO, length2, 0.15, true, &"cyl", {"sharp": true}))
		&"palisade":
			var step := 3.0 / PAL_N
			for i in PAL_N:
				var length3 := 3.25 + 0.2 * sin(i * 2.71 + 0.6)
				out.append(_pf(&"log", Vector3(-1.5 + step * (i + 0.5), length3 * 0.5 - 0.35, 0.0), Vector3(0, i * 1.3, 0),
					length3, PAL_R, true, &"box", {"sharp": true}))
			for y in [0.75, 2.05]:
				out.append(_p(&"stick", Vector3(0.0, y, -PAL_R - 0.05), Vector3(0, 0, PI * 0.5), 3.1, 0.055, false, &"none"))
			for y in [0.75, 2.05]:
				out.append(_p(&"rope", Vector3(0.0, y + 0.07, -PAL_R - 0.02), Vector3(0, 0, PI * 0.5), 3.0, 0.028, false, &"none"))
		&"gate":
			for sx in [-1.32, 1.32]:
				out.append(_pf(&"log", Vector3(sx, 3.75 * 0.5 - 0.45, 0.0), Vector3.ZERO, 3.75, 0.2, true, &"box", {"sharp": true}))
			out.append(_log_x(0.0, 3.02, 0.0, 3.2))
			for i in 6:
				var length4 := 2.62 + 0.14 * sin(i * 1.9 + 0.3)
				out.append(_pf(&"log", Vector3(-1.0 + i * 0.4, 0.08 + length4 * 0.5, 0.0), Vector3(0, i * 0.9, 0), length4, 0.17,
					false, &"none", {"sharp": true, "leaf": true}))
			for y in [0.6, 2.1]:
				out.append(_pf(&"stick", Vector3(0.0, y, -0.22), Vector3(0, 0, PI * 0.5), 2.3, 0.055, false, &"none", {"leaf": true}))
			out.append(_stick_ab(&"stick", Vector3(-1.0, 0.6, -0.23), Vector3(1.0, 2.1, -0.23), 0.05, {"leaf": true}))
			for y in [0.6, 2.1]:
				out.append(_p(&"rope", Vector3(-1.2, y, 0.0), Vector3.ZERO, 0.0, 0.17, false, &"none"))
		&"spikes":
			out.append(_log_x(0.0, R, 0.0, 3.0))
			out.append(_log_x(0.0, R, -0.45, 3.0))
			for i in 8:
				var x := -1.3 + i * (2.6 / 7.0)
				var tilt := 0.82 + (0.14 if i % 2 == 0 else -0.06)
				var dir := Vector3(0.08 * sin(i * 2.1), cos(tilt), sin(tilt))
				var a := Vector3(x, 0.12, -0.55)
				out.append(_stick_ab(&"stick", a, a + dir.normalized() * 1.75, 0.055, {"sharp": true}))
			out.append(_p(&"rope", Vector3(0.0, 0.5, 0.0), Vector3(0, 0, PI * 0.5), 2.8, 0.03, false, &"none"))
		&"watchtower":
			var g2: Callable = ctx.get("ground", Callable())
			var H := TOWER_H
			var bottom2 := H - D * 2.0
			for c in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
				var gy := -0.4
				if g2.is_valid():
					gy = float(g2.call(c.x, c.y)) - 0.35
				var length5 := maxf(0.4, bottom2 - gy)
				out.append(_p(&"log", Vector3(c.x, gy + length5 * 0.5, c.y), Vector3.ZERO, length5, R, true, &"cyl"))
			out.append(_log_x(0.0, H - D - R, -1.2, 2.9))
			out.append(_log_x(0.0, H - D - R, 1.2, 2.9))
			for i in 8:
				out.append(_log_z(-1.19 + i * D, H - R, 0.0, 2.9))
			# раскосы по бокам
			for sx in [-1.2, 1.2]:
				out.append(_stick_ab(&"stick", Vector3(sx + signf(sx) * 0.2, 0.25, -1.2), Vector3(sx + signf(sx) * 0.2, H - 0.75, 1.2), 0.06))
				out.append(_stick_ab(&"stick", Vector3(sx + signf(sx) * 0.2, 0.25, 1.2), Vector3(sx + signf(sx) * 0.2, H - 0.75, -1.2), 0.06))
			# перила: стойки и жерди (сторона +Z — проход к лестнице)
			for c in [Vector2(-1.3, -1.3), Vector2(1.3, -1.3), Vector2(-1.3, 1.3), Vector2(1.3, 1.3)]:
				out.append(_p(&"stick", Vector3(c.x, H + 0.55, c.y), Vector3.ZERO, 1.15, 0.06, false, &"none"))
			for y in [H + 0.5, H + 1.05]:
				out.append(_p(&"stick", Vector3(0.0, y, -1.3), Vector3(0, 0, PI * 0.5), 2.7, 0.05, false, &"none"))
				out.append(_p(&"stick", Vector3(-1.3, y, 0.0), Vector3(PI * 0.5, 0, 0), 2.7, 0.05, false, &"none"))
				out.append(_p(&"stick", Vector3(1.3, y, 0.0), Vector3(PI * 0.5, 0, 0), 2.7, 0.05, false, &"none"))
			for c in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
				out.append(_p(&"rope", Vector3(c.x, H - D - R, c.y), Vector3.ZERO, 0.0, 0.24, false, &"none"))
		&"foundation":
			for ix in 4:
				for iz in 4:
					var jx := 0.06 * sin(ix * 3.1 + iz * 1.7)
					var jz := 0.06 * cos(ix * 1.3 + iz * 2.9)
					out.append(_p(&"stone", Vector3(-1.125 + ix * 0.75 + jx, 0.27, -1.125 + iz * 0.75 + jz),
						Vector3(0, ix * 1.1 + iz * 0.7, 0), 0.0, 0.44, false, &"none"))
		&"chest":
			for z in [-0.24, 0.24]:
				out.append(_p(&"log", Vector3(0.0, 0.1, z), Vector3(0, 0, PI * 0.5), 1.2, 0.1, false, &"none"))
			for z in [-0.3, 0.3]:
				for y in [0.27, 0.41, 0.55]:
					out.append(_p(&"stick", Vector3(0.0, y, z), Vector3(0, 0, PI * 0.5), 1.2, 0.07, false, &"none"))
			for x in [-0.57, 0.57]:
				for y in [0.34, 0.48]:
					out.append(_p(&"stick", Vector3(x, y, 0.0), Vector3(PI * 0.5, 0, 0), 0.66, 0.07, false, &"none"))
			for z in [-0.225, -0.075, 0.075, 0.225]:
				out.append(_pf(&"stick", Vector3(0.0, 0.69, z), Vector3(0, 0, PI * 0.5), 1.24, 0.075, false, &"none", {"leaf": true}))
			out.append(_p(&"rope", Vector3(0.0, 0.6, 0.34), Vector3(PI * 0.5, 0, 0), 0.0, 0.07, false, &"none"))
		&"log_holder":
			for x in [-0.95, 0.95]:
				out.append(_log_z(x, R, 0.0, 1.45))
			for x in [-0.95, 0.95]:
				for z in [-0.6, 0.6]:
					out.append(_p(&"stick", Vector3(x, 0.72, z), Vector3.ZERO, 1.3, 0.06, false, &"none"))
			for x in [-0.95, 0.95]:
				out.append(_p(&"rope", Vector3(x, 1.25, 0.0), Vector3(PI * 0.5, 0, 0), 1.2, 0.03, false, &"none"))
		&"workbench":
			for z in [-0.17, 0.17]:
				out.append(_log_x(0.0, 0.82, z, 2.0, false))
			for x in [-0.82, 0.82]:
				for z in [-0.2, 0.2]:
					out.append(_p(&"stick", Vector3(x, 0.36, z), Vector3(0, 0, 0.06 * signf(x)), 0.78, 0.075, false, &"none"))
			for z in [-0.2, 0.2]:
				out.append(_p(&"stick", Vector3(0.0, 0.3, z), Vector3(0, 0, PI * 0.5), 1.75, 0.05, false, &"none"))
			out.append(_p(&"rope", Vector3(-0.7, 1.0, 0.0), Vector3(PI * 0.5, 0, 0), 0.0, 0.11, false, &"none"))
			out.append(_p(&"stone", Vector3(0.6, 1.08, 0.05), Vector3(0, 0.4, 0), 0.0, 0.16, false, &"none"))
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
		&"watchtower":
			var run2 := stairs_dims({"rise": TOWER_H}).y
			s.append({"tags": [&"stairs"], "xform": Transform3D(Basis(), Vector3(0, 0, 1.4 + run2 * 0.5)), "ctx": {"rise": TOWER_H}})
		&"palisade", &"gate":
			# частокол тянется линией, ворота встают в линию; углы — под 90° и 45°
			for sx in [-3.0, 3.0]:
				s.append({"tags": [&"palisade"], "xform": Transform3D(Basis(), Vector3(sx, 0, 0))})
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					s.append({"tags": [&"palisade"], "xform": Transform3D(rot90, Vector3(sx * 1.5, 0, sz * 1.5))})
					var b45 := Basis(Vector3.UP, sx * sz * PI * 0.25)
					var c45 := Vector3(sx * 1.5, 0, 0) + b45 * Vector3(sx * 1.5, 0, 0)
					s.append({"tags": [&"palisade"], "xform": Transform3D(b45, c45)})
		&"foundation":
			var h := FOUND_H
			for d in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
				s.append({"tags": [&"foundation"], "xform": Transform3D(Basis(), d)})
			for sz in [-1.5, 1.5]:
				s.append({"tags": [&"wall", &"palisade"], "xform": Transform3D(Basis(), Vector3(0, h, sz))})
			for sx in [-1.5, 1.5]:
				s.append({"tags": [&"wall", &"palisade"], "xform": Transform3D(rot90, Vector3(sx, h, 0))})
			s.append({"tags": [&"fire_pit", &"shelter", &"chest", &"workbench", &"log_holder"], "xform": Transform3D(Basis(), Vector3(0, h, 0))})
	return s

## Каталог для ботов и UI: {id: {name, kind, cost, radius, size: Vector3, snap}}.
static var _catalog: Dictionary = {}
static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	for id: StringName in ORDER:
		var box := AABB()
		var first := true
		for p: Dictionary in parts(id, {}):
			var e := maxf(float(p.len) * 0.5, float(p.r))
			var pb := AABB(Vector3(p.pos) - Vector3.ONE * e, Vector3.ONE * e * 2.0)
			box = pb if first else box.merge(pb)
			first = false
		var info: Dictionary = INFO.get(id, {})
		_catalog[id] = {"name": name_of(id), "kind": kind_of(id), "cost": cost(id),
			"radius": float(info.get("radius", 1.5)), "size": box.size, "snap": info.get("snap", &""),
			"socket_only": bool(info.get("socket_only", false))}
	return _catalog
