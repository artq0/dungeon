extends Node2D
## Dungeon procedural: salas aleatórias (tamanho + estilo) ligadas por portas quebráveis.
## Fog é por sala: só afeta objetos/chão da sala, e salas ainda não abertas mostram só o formato.

const TILE: int = 32
const VOID: int = 0
const FLOOR: int = 1
const WALL: int = 2
const DOOR: int = 3

const FOG_COLOR := Color(0.17, 0.19, 0.26)
const FOG_UNSEEN: float = 0.9
const FOG_PEEK: float = 0.7
const FOG_VISITED: float = 0.5
const DOOR_HP: float = 8.0

var rng := RandomNumberGenerator.new()
var grid: Dictionary = {}        # Vector2i -> tipo
var room_of: Dictionary = {}     # Vector2i (chão) -> índice da sala
var wall_rooms: Dictionary = {}  # Vector2i (parede) -> salas vizinhas
var rooms: Array = []
var doors: Array = []
var door_at: Dictionary = {}     # Vector2i -> índice da porta
var time: float = 0.0


# ---------------------------------------------------------------- geração

func generate(room_count: int) -> void:
	rng.randomize()
	grid.clear()
	room_of.clear()
	wall_rooms.clear()
	rooms.clear()
	doors.clear()
	door_at.clear()

	var first_rect := Rect2i(Vector2i.ZERO, _random_size())
	var first_style: int = rng.randi_range(0, 5)
	_add_room(first_rect, first_style, _room_cells(first_rect, first_style))

	var attempts: int = 0
	while rooms.size() < room_count and attempts < 80:
		attempts += 1
		var parent: int = rooms.size() - 1
		if rng.randf() < 0.35:
			parent = rng.randi_range(0, rooms.size() - 1)
		_try_place(parent)
	_finalize()


func _random_size() -> Vector2i:
	return Vector2i(rng.randi_range(12, 26), rng.randi_range(10, 18))


func _add_room(rect: Rect2i, style: int, cells: Array) -> int:
	var idx: int = rooms.size()
	for c in cells:
		grid[c] = FLOOR
		room_of[c] = idx
	rooms.append({
		"rect": rect,
		"style": style,
		"cells": cells,
		"open_cells": [],
		"visited": false,
		"known": false,
		"fog": FOG_UNSEEN,
		"doors": [],
		"tint": Color.from_hsv(rng.randf(), rng.randf_range(0.12, 0.3), rng.randf_range(0.30, 0.42)),
	})
	return idx


func _room_cells(rect: Rect2i, style: int) -> Array:
	var cells: Array = []
	var w: int = rect.size.x
	var h: int = rect.size.y
	var blocked: Dictionary = {}
	if style == 4:  # obstáculos espalhados
		for lx in range(3, w - 3):
			for ly in range(3, h - 3):
				if rng.randf() < 0.07:
					var ok: bool = true
					for ox in range(-1, 2):
						for oy in range(-1, 2):
							if blocked.has(Vector2i(lx + ox, ly + oy)):
								ok = false
					if ok:
						blocked[Vector2i(lx, ly)] = true
	var corner: int = clampi(mini(w, h) / 4, 2, 5)
	for lx in w:
		for ly in h:
			var inside: bool = true
			match style:
				1:  # pilares
					if lx >= 3 and lx <= w - 4 and ly >= 3 and ly <= h - 4:
						if (lx - 3) % 5 < 2 and (ly - 3) % 5 < 2:
							inside = false
				2:  # cantos cortados
					if (lx < corner or lx >= w - corner) and (ly < corner or ly >= h - corner):
						inside = false
				3:  # elipse
					var nx: float = (lx + 0.5 - w * 0.5) / (w * 0.5)
					var ny: float = (ly + 0.5 - h * 0.5) / (h * 0.5)
					inside = nx * nx + ny * ny <= 1.0
				4:
					inside = not blocked.has(Vector2i(lx, ly))
				5:  # cruz
					inside = absf(ly + 0.5 - h * 0.5) < h * 0.28 or absf(lx + 0.5 - w * 0.5) < w * 0.22
			if inside:
				cells.append(rect.position + Vector2i(lx, ly))
	return cells


func _overlaps_others(rect: Rect2i, pidx: int) -> bool:
	for j in rooms.size():
		if j == pidx:
			continue
		var other: Rect2i = rooms[j].rect
		if other.grow(2).intersects(rect):
			return true
	return false


func _try_place(pidx: int) -> bool:
	var P: Rect2i = rooms[pidx].rect
	var dirs: Array = [0, 1, 2, 3]  # 0 direita, 1 esquerda, 2 baixo, 3 cima
	dirs.shuffle()
	for d in dirs:
		for attempt in 6:
			var size: Vector2i = _random_size()
			var pos := Vector2i.ZERO
			if d == 0 or d == 1:
				pos.y = rng.randi_range(P.position.y - size.y + 4, P.end.y - 4)
				pos.x = P.end.x + 1 if d == 0 else P.position.x - 1 - size.x
			else:
				pos.x = rng.randi_range(P.position.x - size.x + 4, P.end.x - 4)
				pos.y = P.end.y + 1 if d == 2 else P.position.y - 1 - size.y
			var rect := Rect2i(pos, size)
			if _overlaps_others(rect, pidx):
				continue
			var style: int = rng.randi_range(0, 5)
			var cells: Array = _room_cells(rect, style)
			var cellset: Dictionary = {}
			for c in cells:
				cellset[c] = true
			var door_tiles: Array = _find_door(pidx, rect, cellset, d)
			if door_tiles.is_empty():
				continue
			var idx: int = _add_room(rect, style, cells)
			var di: int = doors.size()
			doors.append({
				"tiles": door_tiles, "hp": DOOR_HP, "max_hp": DOOR_HP,
				"open": false, "a": pidx, "b": idx, "shake": 0.0,
			})
			for t in door_tiles:
				grid[t] = DOOR
				door_at[t] = di
			rooms[pidx].doors.append(di)
			rooms[idx].doors.append(di)
			return true
	return false


func _pf(x: int, y: int, pidx: int) -> bool:
	return room_of.get(Vector2i(x, y), -1) == pidx


func _find_door(pidx: int, rect: Rect2i, cellset: Dictionary, d: int) -> Array:
	var P: Rect2i = rooms[pidx].rect
	var cands: Array = []
	if d == 0 or d == 1:
		var gx: int = P.end.x if d == 0 else P.position.x - 1
		var ax: int = gx - 1 if d == 0 else gx + 1
		var bx: int = gx + 1 if d == 0 else gx - 1
		var y0: int = maxi(P.position.y, rect.position.y)
		var y1: int = mini(P.end.y, rect.end.y) - 1
		for y in range(y0, y1):
			if _pf(ax, y, pidx) and _pf(ax, y + 1, pidx) and cellset.has(Vector2i(bx, y)) and cellset.has(Vector2i(bx, y + 1)):
				cands.append([Vector2i(gx, y), Vector2i(gx, y + 1)])
	else:
		var gy: int = P.end.y if d == 2 else P.position.y - 1
		var ay: int = gy - 1 if d == 2 else gy + 1
		var by: int = gy + 1 if d == 2 else gy - 1
		var x0: int = maxi(P.position.x, rect.position.x)
		var x1: int = mini(P.end.x, rect.end.x) - 1
		for x in range(x0, x1):
			if _pf(x, ay, pidx) and _pf(x + 1, ay, pidx) and cellset.has(Vector2i(x, by)) and cellset.has(Vector2i(x + 1, by)):
				cands.append([Vector2i(x, gy), Vector2i(x + 1, gy)])
	if cands.is_empty():
		return []
	return cands[rng.randi_range(0, cands.size() - 1)]


func _finalize() -> void:
	# paredes ao redor de chão e portas
	var anchors: Array = room_of.keys()
	anchors.append_array(door_at.keys())
	for c in anchors:
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var n: Vector2i = c + Vector2i(ox, oy)
				if not grid.has(n):
					grid[n] = WALL
	# quais salas "enxergam" cada parede (para a fog)
	for c in grid.keys():
		if grid[c] != WALL:
			continue
		var lst: Array = []
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var n: Vector2i = c + Vector2i(ox, oy)
				if room_of.has(n):
					var ri: int = room_of[n]
					if not lst.has(ri):
						lst.append(ri)
				elif door_at.has(n):
					var dd: Dictionary = doors[door_at[n]]
					if not lst.has(dd.a):
						lst.append(dd.a)
					if not lst.has(dd.b):
						lst.append(dd.b)
		wall_rooms[c] = lst
	# células "abertas" (todas as vizinhas são chão da mesma sala) para spawn
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		for c in room.cells:
			var ok: bool = true
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					if room_of.get(c + Vector2i(ox, oy), -1) != i:
						ok = false
			if ok:
				room.open_cells.append(c)


# ---------------------------------------------------------------- consultas

func pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


func room_at(p: Vector2) -> int:
	return room_of.get(pos_to_cell(p), -1)


func is_solid_cell(cell: Vector2i) -> bool:
	var t: int = grid.get(cell, VOID)
	if t == FLOOR:
		return false
	if t == DOOR:
		var d: Dictionary = doors[door_at[cell]]
		return not d.open
	return true


func is_solid_pos(p: Vector2) -> bool:
	return is_solid_cell(pos_to_cell(p))


func box_blocked(p: Vector2, r: float) -> bool:
	var q: float = r * 0.9
	return is_solid_pos(p + Vector2(-q, -q)) or is_solid_pos(p + Vector2(q, -q)) \
		or is_solid_pos(p + Vector2(-q, q)) or is_solid_pos(p + Vector2(q, q))


func move_circle(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var p: Vector2 = pos
	p.x += motion.x
	if box_blocked(p, r):
		p.x = pos.x
	var q: Vector2 = p
	q.y += motion.y
	if box_blocked(q, r):
		q.y = p.y
	return q


func has_los(a: Vector2, b: Vector2) -> bool:
	var dist: float = a.distance_to(b)
	var steps: int = int(dist / 8.0)
	for i in range(1, steps):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		if is_solid_pos(p):
			return false
	return true


func center_open_cell(i: int) -> Vector2i:
	var room: Dictionary = rooms[i]
	var pool: Array = room.cells
	if not room.open_cells.is_empty():
		pool = room.open_cells
	var rect: Rect2i = room.rect
	var center: Vector2 = Vector2(rect.position) + Vector2(rect.size) * 0.5
	var best: Vector2i = pool[0]
	var bd: float = INF
	for c in pool:
		var dd: float = (Vector2(c) + Vector2(0.5, 0.5)).distance_to(center)
		if dd < bd:
			bd = dd
			best = c
	return best


# ---------------------------------------------------------------- portas e fog

func damage_door(di: int, amount: float) -> bool:
	var d: Dictionary = doors[di]
	if d.open:
		return false
	d.hp -= amount
	d.shake = 0.25
	if d.hp <= 0.0:
		d.open = true
		rooms[d.a].known = true
		rooms[d.b].known = true
		return true
	return false


func enter_room(i: int) -> void:
	var room: Dictionary = rooms[i]
	room.visited = true
	room.known = true
	for di in room.doors:
		var d: Dictionary = doors[di]
		var other: int = d.a if d.b == i else d.b
		rooms[other].known = true


func update_fog(current: int, delta: float) -> void:
	time += delta
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var target: float = FOG_UNSEEN
		if i == current:
			target = 0.0
		elif r.visited:
			target = FOG_VISITED
		else:
			for di in r.doors:
				if doors[di].open:
					target = FOG_PEEK
		r.fog = lerpf(r.fog, target, 1.0 - exp(-5.0 * delta))
	for d in doors:
		d.shake = maxf(0.0, d.shake - delta)
	queue_redraw()


# ---------------------------------------------------------------- desenho

func _draw() -> void:
	var vr: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x0: int = int(floor(vr.position.x / TILE)) - 1
	var y0: int = int(floor(vr.position.y / TILE)) - 1
	var x1: int = int(ceil(vr.end.x / TILE)) + 1
	var y1: int = int(ceil(vr.end.y / TILE)) + 1
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var c := Vector2i(x, y)
			var t: int = grid.get(c, VOID)
			if t == VOID:
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if t == FLOOR:
				_draw_floor(c, r)
			elif t == WALL:
				_draw_wall(c, r)
			else:
				_draw_door(c, r)


func _draw_floor(c: Vector2i, r: Rect2) -> void:
	var room: Dictionary = rooms[room_of[c]]
	if not room.known:
		return
	var fog: float = room.fog
	var base: Color = room.tint
	if (c.x + c.y) % 2 == 0:
		base = base.lightened(0.05)
	draw_rect(r, base.lerp(FOG_COLOR, fog))
	if fog > 0.05:
		var wob: float = sin(time * 0.7 + c.x * 0.35) * sin(time * 0.5 + c.y * 0.3)
		var a: float = maxf(0.0, fog * (0.06 + 0.07 * wob))
		draw_rect(r, Color(0.8, 0.85, 1.0, a))


func _draw_wall(c: Vector2i, r: Rect2) -> void:
	var known: bool = false
	var fog: float = 1.0
	for ri in wall_rooms.get(c, []):
		var room: Dictionary = rooms[ri]
		if room.known:
			known = true
			fog = minf(fog, room.fog)
	if not known:
		return
	var top: Color = Color(0.36, 0.33, 0.43).lerp(FOG_COLOR.lightened(0.08), fog)
	draw_rect(r, top)
	var below: int = grid.get(Vector2i(c.x, c.y + 1), VOID)
	if below == FLOOR or below == DOOR:
		draw_rect(Rect2(r.position.x, r.end.y - 12.0, TILE, 12.0), Color(0.2, 0.18, 0.27).lerp(FOG_COLOR, fog))
		draw_rect(Rect2(r.position.x, r.end.y - 12.0, TILE, 2.0), top.lightened(0.12))


func _draw_door(c: Vector2i, r: Rect2) -> void:
	var d: Dictionary = doors[door_at[c]]
	var ra: Dictionary = rooms[d.a]
	var rb: Dictionary = rooms[d.b]
	if not (ra.known or rb.known):
		return
	var fog: float = minf(ra.fog, rb.fog)
	if d.open:
		var fc: Color = (ra.tint as Color).lerp(rb.tint, 0.5).lerp(FOG_COLOR, fog)
		draw_rect(r, fc)
		for k in 3:
			var ox: float = float((c.x * 13 + c.y * 7 + k * 11) % 24) + 2.0
			var oy: float = float((c.x * 5 + c.y * 17 + k * 9) % 24) + 2.0
			draw_rect(Rect2(r.position + Vector2(ox, oy), Vector2(4, 3)), Color(0.4, 0.26, 0.14).lerp(FOG_COLOR, fog))
		return
	var off := Vector2(sin(time * 70.0) * d.shake * 14.0, 0.0)
	var rr := Rect2(r.position + off, r.size)
	var wood: Color = Color(0.46, 0.29, 0.15).lerp(FOG_COLOR, fog * 0.75)
	draw_rect(rr, wood)
	var dark: Color = wood.darkened(0.35)
	draw_line(rr.position + Vector2(10, 0), rr.position + Vector2(10, TILE), dark, 1.5)
	draw_line(rr.position + Vector2(21, 0), rr.position + Vector2(21, TILE), dark, 1.5)
	var iron: Color = Color(0.4, 0.42, 0.48).lerp(FOG_COLOR, fog * 0.75)
	draw_rect(Rect2(rr.position + Vector2(0, 6), Vector2(TILE, 4)), iron)
	draw_rect(Rect2(rr.position + Vector2(0, 22), Vector2(TILE, 4)), iron)
	draw_rect(rr, dark, false, 2.0)
	# rachaduras conforme o dano
	var dmg: float = 1.0 - float(d.hp) / float(d.max_hp)
	var n: int = int(dmg * 6.0)
	for k in n:
		var sx: float = float((k * 37 + c.x * 11 + c.y * 7) % 26) + 3.0
		var sy: float = float((k * 13) % 10) + 2.0
		var s: Vector2 = rr.position + Vector2(sx, sy)
		var mid: Vector2 = s + Vector2(float((k * 5) % 9) - 4.0, 8.0)
		var e: Vector2 = mid + Vector2(float((k * 7) % 7) - 3.0, 9.0)
		draw_line(s, mid, Color(0.08, 0.04, 0.02), 2.0)
		draw_line(mid, e, Color(0.08, 0.04, 0.02), 2.0)
