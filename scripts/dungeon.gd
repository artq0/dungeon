class_name Dungeon
extends Node2D
## Dungeon procedural de madeira: salas aleatórias + salas predefinidas (bibliotecas, corredores...)
## ligadas por portas quebráveis.
## TUDO que dá para ajustar (quantidade de salas, portas, fog, lista de salas predefinidas, lista de
## objetos) fica em `settings` (res://data/dungeon_settings.tres) e pode ser editado pelo Inspector.
## Objetos nas salas: BLOQUEADORES (estante, mesa, pilar - não dá para andar por cima; estante e pilar
## também projetam sombra de fog parcial atrás deles) e DESTRUTÍVEIS (barril, caixa, vaso, pilha de livros).
## Fog é por sala: só afeta objetos/chão da sala, e salas ainda não abertas mostram só o formato.

const DEFAULT_SETTINGS_PATH: String = "res://data/dungeon_settings.tres"

const TILE: int = RoomPart.TILE   # 32 px (definido em scripts/rooms/room_part.gd)
const VOID: int = 0
const FLOOR: int = 1
const WALL: int = 2
const DOOR: int = 3

## Configuração da geração. Se ficar vazio, usa res://data/dungeon_settings.tres.
@export var settings: DungeonSettings


const BOOK_COLORS: Array = [
	Color(0.62, 0.18, 0.18), Color(0.2, 0.35, 0.55), Color(0.25, 0.5, 0.3),
	Color(0.7, 0.55, 0.2), Color(0.45, 0.25, 0.5), Color(0.75, 0.7, 0.55),
]

var rng := RandomNumberGenerator.new()
var grid: Dictionary = {}        # Vector2i -> tipo
var room_of: Dictionary = {}     # Vector2i (chão) -> índice da sala
var wall_rooms: Dictionary = {}  # Vector2i (parede) -> salas vizinhas
var rooms: Array = []
var doors: Array = []
var door_at: Dictionary = {}     # Vector2i -> índice da porta
var objects: Dictionary = {}     # Vector2i -> objeto (dicionário)
var shade: Dictionary = {}       # Vector2i -> 0..1 sombra atrás de objetos altos (sala atual)
var shade_goal: Dictionary = {}
var shade_tick: int = 0
var template_use: Dictionary = {}
var library_count: int = 0
var time: float = 0.0



# valores copiados de `settings` no início de cada geração (leitura rápida no desenho)
var fog_color := Color(0.17, 0.19, 0.26)
var fog_unseen: float = 0.9
var fog_peek: float = 0.7
var fog_visited: float = 0.5
var fog_shade: float = 0.55
var door_hp: float = 8.0
var template_chance: float = 0.5

var _defs: Dictionary = {}       # id do objeto (String) -> ObjectDef
var _scatter: Dictionary = {}    # ObjectDef.SCATTER_* -> [[id, peso], ...]
var _templates: Array = []       # salas predefinidas ativas (dados lidos de RoomLayout.extract())


# ---------------------------------------------------------------- configuração

## Copia os valores de `settings` e monta as tabelas de objetos e de salas predefinidas.
func apply_settings() -> void:
	if settings == null and ResourceLoader.exists(DEFAULT_SETTINGS_PATH):
		settings = load(DEFAULT_SETTINGS_PATH) as DungeonSettings
	if settings == null:
		push_warning("Dungeon: %s não encontrado, usando valores padrão (sem salas predefinidas nem objetos)." % DEFAULT_SETTINGS_PATH)
		settings = DungeonSettings.new()
	fog_color = settings.fog_color
	fog_unseen = settings.fog_unseen
	fog_peek = settings.fog_peek
	fog_visited = settings.fog_visited
	fog_shade = settings.fog_shade
	door_hp = settings.door_hp
	template_chance = settings.template_chance

	_defs.clear()
	_scatter = {ObjectDef.SCATTER_CORNER: [], ObjectDef.SCATTER_INTERIOR: []}
	for d in settings.object_defs:
		if d == null:
			continue
		var oid: String = str(d.id)
		_defs[oid] = d
		if d.scatter != ObjectDef.SCATTER_NONE and d.scatter_weight > 0.0:
			_scatter[d.scatter].append([oid, d.scatter_weight])

	_load_room_scenes()


## Lê cada cena de sala (settings.room_scenes) uma vez e guarda só os dados que a geração precisa.
func _load_room_scenes() -> void:
	_templates.clear()
	for scene in settings.room_scenes:
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		var layout := node as RoomLayout
		if layout == null:
			push_warning("Dungeon: %s não tem um RoomLayout na raiz, sala ignorada." % scene.resource_path)
			node.free()
			continue
		var data: Dictionary = layout.extract()
		layout.free()
		for message in data.warnings:
			push_warning("Sala '%s': %s" % [data.name, message])
		if not data.enabled or data.weight <= 0.0 or data.cells.is_empty():
			continue
		# objetos usados na sala entram na tabela mesmo que não estejam em settings.object_defs
		for def in data.defs:
			var oid: String = str(def.id)
			if not _defs.has(oid):
				_defs[oid] = def
		_templates.append(data)


## Sorteia um objeto para espalhar numa sala aleatória (ObjectDef.SCATTER_CORNER / SCATTER_INTERIOR).
## Devolve "" se nenhum objeto estiver marcado para esse grupo.
func _pick_scatter(mode: int) -> String:
	var pool: Array = _scatter.get(mode, [])
	if pool.is_empty():
		return ""
	var total: float = 0.0
	for e in pool:
		total += float(e[1])
	var roll: float = rng.randf() * total
	for e in pool:
		roll -= float(e[1])
		if roll <= 0.0:
			return str(e[0])
	return str(pool[pool.size() - 1][0])


# ---------------------------------------------------------------- geração

## Gera a dungeon. Sem argumento (ou < 1), sorteia a quantidade de salas entre
## settings.room_count_min e room_count_max.
func generate(room_count: int = -1) -> void:
	rng.randomize()
	apply_settings()
	if room_count < 1:
		room_count = rng.randi_range(mini(settings.room_count_min, settings.room_count_max), maxi(settings.room_count_min, settings.room_count_max))
	grid.clear()
	room_of.clear()
	wall_rooms.clear()
	rooms.clear()
	doors.clear()
	door_at.clear()
	objects.clear()
	shade.clear()
	shade_goal.clear()
	template_use.clear()
	library_count = 0

	var first_rect := Rect2i(Vector2i.ZERO, _random_size())
	var first_style: int = _random_style()
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
	var w0: int = mini(settings.room_width.x, settings.room_width.y)
	var w1: int = maxi(settings.room_width.x, settings.room_width.y)
	var h0: int = mini(settings.room_height.x, settings.room_height.y)
	var h1: int = maxi(settings.room_height.x, settings.room_height.y)
	return Vector2i(rng.randi_range(maxi(w0, 4), maxi(w1, 4)), rng.randi_range(maxi(h0, 4), maxi(h1, 4)))


## Sorteia um formato (0..5) entre os marcados em settings.random_styles.
func _random_style() -> int:
	var allowed: Array = []
	for s in 6:
		if (settings.random_styles & (1 << s)) != 0:
			allowed.append(s)
	if allowed.is_empty():
		return 0
	return allowed[rng.randi_range(0, allowed.size() - 1)]


func _rand_range_v(v: Vector2) -> float:
	return rng.randf_range(minf(v.x, v.y), maxf(v.x, v.y))


func _add_room(rect: Rect2i, style: int, cells: Array) -> int:
	var idx: int = rooms.size()
	for c in cells:
		grid[c] = FLOOR
		room_of[c] = idx
	rooms.append({
		"rect": rect,
		"style": style,
		"name": "",
		"cells": cells,
		"open_cells": [],
		"visited": false,
		"known": false,
		"fog": fog_unseen,
		"doors": [],
		"deco": {},
		"has_tall": false,
		# tons de madeira
		"tint": Color.from_hsv(_rand_range_v(settings.tint_hue), _rand_range_v(settings.tint_saturation), _rand_range_v(settings.tint_value)),
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


# ---- salas predefinidas (cenas de scenes/rooms)

func _want_template() -> bool:
	if _templates.is_empty():
		return false
	if settings.force_libraries and rooms.size() >= 2 and library_count == 0 and _has_library():
		return rng.randf() < 0.85
	return rng.randf() < template_chance


func _has_library() -> bool:
	for t in _templates:
		if t.tag == "library":
			return true
	return false


func _pick_template() -> Dictionary:
	# garante bibliotecas: pelo menos 1 cedo e, se couber, uma segunda
	var need_lib: bool = settings.force_libraries and _has_library() \
		and (library_count == 0 or (library_count < 2 and rooms.size() >= 4))
	var pool: Array = []
	var weights: Array = []
	var total: float = 0.0
	for t in _templates:
		if need_lib and t.tag != "library":
			continue
		var wgt: float = t.weight / (1.0 + float(template_use.get(t.id, 0)))
		pool.append(t)
		weights.append(wgt)
		total += wgt
	if pool.is_empty():
		return {}
	var roll: float = rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]



func _tpl_xf(p: Vector2i, w: int, h: int, flip_x: bool, flip_y: bool, transpose: bool) -> Vector2i:
	var x: int = w - 1 - p.x if flip_x else p.x
	var y: int = h - 1 - p.y if flip_y else p.y
	if transpose:
		return Vector2i(y, x)
	return Vector2i(x, y)


## Aplica espelhamento/rotação aleatórios à sala e devolve:
##   chars: célula local -> "" (chão livre) ou id do objeto
##   rugs : células com tapete,  dim: tamanho final,  t: dados originais da sala
func _build_template(t: Dictionary) -> Dictionary:
	var size: Vector2i = t.tiles
	var flip_x: bool = t.flip_x and rng.randf() < 0.5
	var flip_y: bool = t.flip_y and rng.randf() < 0.5
	var transpose: bool = t.rotate and rng.randf() < 0.5
	var chars: Dictionary = {}
	for cell in t.cells.keys():
		chars[_tpl_xf(cell, size.x, size.y, flip_x, flip_y, transpose)] = t.cells[cell]
	var rugs: Array = []
	for cell in t.rugs:
		rugs.append(_tpl_xf(cell, size.x, size.y, flip_x, flip_y, transpose))
	var dim: Vector2i = size
	if transpose:
		dim = Vector2i(size.y, size.x)
	return {"chars": chars, "rugs": rugs, "dim": dim, "t": t}


func _apply_template(idx: int, tpl: Dictionary, obj_map: Dictionary, rect: Rect2i) -> void:
	var t: Dictionary = tpl.t
	var room: Dictionary = rooms[idx]
	room.name = t.name
	var tone: float = t.tone
	if tone >= 0.0:
		room.tint = (room.tint as Color).darkened(tone)
	else:
		room.tint = (room.tint as Color).lightened(-tone)
	for c in obj_map.keys():
		_place_object(idx, c, obj_map[c])
	for lc in tpl.rugs:
		room.deco[rect.position + lc] = "rug"
	template_use[t.id] = int(template_use.get(t.id, 0)) + 1
	if t.tag == "library":
		library_count += 1



# ---- objetos

func _cell_hash(c: Vector2i, salt: int) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663) ^ (salt * 83492791)) % 1000


func _place_object(room_idx: int, cell: Vector2i, otype: String) -> void:
	if not _defs.has(otype):
		return
	var def: ObjectDef = _defs[otype]
	var hp: float = def.hp if def.destructible else 0.0
	objects[cell] = {
		"type": otype, "room": room_idx, "tall": def.tall, "destructible": def.destructible,
		"hp": hp, "max_hp": hp, "shake": 0.0, "v": _cell_hash(cell, 7),
	}
	if def.tall:
		rooms[room_idx].has_tall = true



## Todas as células livres da sala continuam conectadas (4 direções) com os objetos no lugar?
func _room_connected(i: int) -> bool:
	var free: Dictionary = {}
	for c in rooms[i].cells:
		if not objects.has(c):
			free[c] = true
	if free.is_empty():
		return false
	var start: Vector2i = free.keys()[0]
	var seen: Dictionary = {}
	seen[start] = true
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + dv
			if free.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == free.size()


## Decoração das salas aleatórias: objetos "nos cantos" (ObjectDef.scatter = Nos cantos) e alguns
## "no miolo" (bloqueadores soltos). Quais objetos entram e com que peso: res://data/objects/*.tres.
func _decorate_room(i: int) -> void:
	var room: Dictionary = rooms[i]
	var near_door: Dictionary = {}
	for di in room.doors:
		for t in doors[di].tiles:
			for ox in range(-2, 3):
				for oy in range(-2, 3):
					near_door[t + Vector2i(ox, oy)] = true
	var cellset: Dictionary = {}
	for c in room.cells:
		cellset[c] = true

	# objetos de canto (e um vizinho junto à parede)
	if _pick_scatter(ObjectDef.SCATTER_CORNER) != "":
		var corners: Array = []
		for c in room.cells:
			if near_door.has(c):
				continue
			var wall_x: bool = not cellset.has(c + Vector2i(1, 0)) or not cellset.has(c + Vector2i(-1, 0))
			var wall_y: bool = not cellset.has(c + Vector2i(0, 1)) or not cellset.has(c + Vector2i(0, -1))
			if wall_x and wall_y:
				corners.append(c)
		corners.shuffle()
		var want: int = rng.randi_range(1, 4)
		for c in corners:
			if want <= 0:
				break
			if objects.has(c) or rng.randf() < 0.3:
				continue
			_place_object(i, c, _pick_scatter(ObjectDef.SCATTER_CORNER))
			if not _room_connected(i):
				objects.erase(c)
				continue
			want -= 1
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + dv
				if cellset.has(n) and not near_door.has(n) and not objects.has(n) and rng.randf() < 0.4:
					_place_object(i, n, _pick_scatter(ObjectDef.SCATTER_CORNER))
					if not _room_connected(i):
						objects.erase(n)
					break

	if i == 0:
		return  # a sala inicial fica sem bloqueadores (spawn do jogador)
	if _pick_scatter(ObjectDef.SCATTER_INTERIOR) == "":
		return

	# bloqueadores soltos (pilar de madeira / mesa) no miolo da sala
	var open: Array = []
	for c in room.open_cells:
		if not near_door.has(c) and not objects.has(c):
			open.append(c)
	open.shuffle()
	var wanted: int = rng.randi_range(0, 3)
	var placed: Array = []
	for c in open:
		if wanted <= 0:
			break
		var cell: Vector2i = c
		var ok: bool = true
		for p in placed:
			if maxi(absi(cell.x - p.x), absi(cell.y - p.y)) < 3:
				ok = false
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				if objects.has(cell + Vector2i(ox, oy)):
					ok = false
		if not ok:
			continue
		_place_object(i, cell, _pick_scatter(ObjectDef.SCATTER_INTERIOR))
		if not _room_connected(i):
			objects.erase(cell)
			continue
		placed.append(cell)
		wanted -= 1



func _compute_open_cells(i: int) -> void:
	var room: Dictionary = rooms[i]
	room.open_cells = []
	for c in room.cells:
		var ok: bool = true
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var n: Vector2i = c + Vector2i(ox, oy)
				if room_of.get(n, -1) != i or objects.has(n):
					ok = false
		if ok:
			room.open_cells.append(c)


## Células onde dá para nascer algo (sem objetos); prefere as bem no miolo da sala.
func free_cells(i: int) -> Array:
	var room: Dictionary = rooms[i]
	if not room.open_cells.is_empty():
		return room.open_cells.duplicate()
	var out: Array = []
	for c in room.cells:
		if not objects.has(c):
			out.append(c)
	return out


# ---- colocação das salas

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
			var tpl: Dictionary = {}
			if _want_template():
				var picked: Dictionary = _pick_template()
				if not picked.is_empty():
					tpl = _build_template(picked)
			var size: Vector2i = _random_size()
			if not tpl.is_empty():
				size = tpl.dim
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
			var style: int = _random_style()
			var cells: Array = []
			var obj_map: Dictionary = {}
			if tpl.is_empty():
				cells = _room_cells(rect, style)
			else:
				style = 6
				for lc in tpl.chars.keys():
					var ac: Vector2i = rect.position + lc
					cells.append(ac)
					var object_id: String = tpl.chars[lc]
					if object_id != "":
						obj_map[ac] = object_id
			# a porta só pode ficar onde o chão está livre (sem objetos) dos dois lados
			var cellset: Dictionary = {}
			for c in cells:
				if not obj_map.has(c):
					cellset[c] = true
			var door_tiles: Array = _find_door(pidx, rect, cellset, d)
			if door_tiles.is_empty():
				continue
			var idx: int = _add_room(rect, style, cells)
			if not tpl.is_empty():
				_apply_template(idx, tpl, obj_map, rect)
			var di: int = doors.size()
			doors.append({
				"tiles": door_tiles, "hp": door_hp, "max_hp": door_hp,
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
	var c := Vector2i(x, y)
	return room_of.get(c, -1) == pidx and not objects.has(c)


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
	# células "abertas" (todas as vizinhas são chão da mesma sala, sem objetos) para spawn
	for i in rooms.size():
		_compute_open_cells(i)
	# decoração das salas aleatórias (as predefinidas já vêm com seus objetos)
	for i in rooms.size():
		if rooms[i].name == "":
			_decorate_room(i)
	for i in rooms.size():
		_compute_open_cells(i)


# ---------------------------------------------------------------- consultas

func pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


func room_at(p: Vector2) -> int:
	return room_of.get(pos_to_cell(p), -1)


## Bloqueia movimento: parede, porta fechada ou qualquer objeto (bloqueador ou destrutível).
func is_solid_cell(cell: Vector2i) -> bool:
	var t: int = grid.get(cell, VOID)
	if t == FLOOR:
		return objects.has(cell)
	if t == DOOR:
		var d: Dictionary = doors[door_at[cell]]
		return not d.open
	return true


func is_solid_pos(p: Vector2) -> bool:
	return is_solid_cell(pos_to_cell(p))


## Bloqueia a visão: parede, porta fechada ou objeto alto (estante, pilar).
func blocks_sight_cell(cell: Vector2i) -> bool:
	var t: int = grid.get(cell, VOID)
	if t == FLOOR:
		if objects.has(cell):
			var o: Dictionary = objects[cell]
			return o.tall
		return false
	if t == DOOR:
		var d: Dictionary = doors[door_at[cell]]
		return not d.open
	return true


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
		if blocks_sight_cell(pos_to_cell(p)):
			return false
	return true


func room_center(i: int) -> Vector2:
	var rect: Rect2i = rooms[i].rect
	return (Vector2(rect.position) + Vector2(rect.size) * 0.5) * TILE


func center_open_cell(i: int) -> Vector2i:
	var room: Dictionary = rooms[i]
	var pool: Array = free_cells(i)
	if pool.is_empty():
		pool = room.cells
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


# ---------------------------------------------------------------- portas, objetos e fog

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


## Dá dano num objeto destrutível. Devolve true se ele quebrou (e some do mapa).
func damage_object(cell: Vector2i, amount: float) -> bool:
	if not objects.has(cell):
		return false
	var o: Dictionary = objects[cell]
	if not o.destructible:
		return false
	o.hp -= amount
	o.shake = 0.25
	if o.hp <= 0.0:
		objects.erase(cell)
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


func update_fog(current: int, delta: float, viewer: Vector2 = Vector2.ZERO) -> void:
	time += delta
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var target: float = fog_unseen
		if i == current:
			target = 0.0
		elif r.visited:
			target = fog_visited
		else:
			for di in r.doors:
				if doors[di].open:
					target = fog_peek
		r.fog = lerpf(r.fog, target, 1.0 - exp(-5.0 * delta))
	for d in doors:
		d.shake = maxf(0.0, d.shake - delta)
	for c in objects.keys():
		var o: Dictionary = objects[c]
		if o.shake > 0.0:
			o.shake = maxf(0.0, o.shake - delta)
	_update_shade(current, viewer, delta)
	queue_redraw()


## Sombra parcial: células da sala atual que o jogador não enxerga por causa de objetos altos.
## Os alvos são recalculados em rodízio (1/4 das células por frame) e suavizados.
func _update_shade(current: int, viewer: Vector2, delta: float) -> void:
	var k: float = 1.0 - exp(-9.0 * delta)
	var active: bool = current >= 0 and rooms[current].has_tall
	var stale: Array = []
	for c in shade.keys():
		if active and room_of.get(c, -1) == current:
			continue
		var v: float = lerpf(shade[c], 0.0, k)
		if v < 0.01:
			stale.append(c)
		else:
			shade[c] = v
	for c in stale:
		shade.erase(c)
		shade_goal.erase(c)
	if not active:
		return
	shade_tick += 1
	var idx: int = 0
	for c in rooms[current].cells:
		if (idx + shade_tick) % 4 == 0 or not shade_goal.has(c):
			shade_goal[c] = _shade_target(c, viewer)
		var cur: float = shade.get(c, 0.0)
		shade[c] = lerpf(cur, shade_goal[c], k)
		idx += 1


func _shade_target(c: Vector2i, viewer: Vector2) -> float:
	var target: Vector2 = cell_center(c)
	var steps: int = int(viewer.distance_to(target) / 16.0)
	for i in range(1, steps + 1):
		var p: Vector2 = viewer.lerp(target, float(i) / float(steps + 1))
		var cell: Vector2i = pos_to_cell(p)
		if cell == c:
			continue
		if blocks_sight_cell(cell):
			return 1.0
	return 0.0


# ---------------------------------------------------------------- desenho

func _fc(col: Color, fog: float) -> Color:
	return col.lerp(fog_color, fog)


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


## Piso de tábuas de madeira (4 tábuas por tile, emendas e variação de tom por tile).
func _draw_planks(c: Vector2i, r: Rect2, base: Color, fog: float) -> void:
	var seam: Color = _fc(base.darkened(0.45), fog)
	draw_rect(r, seam)
	for j in 4:
		var vary: float = (float(_cell_hash(c, 10 + j)) / 1000.0 - 0.5) * 0.16
		var col: Color = base
		if vary >= 0.0:
			col = base.lightened(vary)
		else:
			col = base.darkened(-vary)
		draw_rect(Rect2(r.position.x, r.position.y + float(j) * 8.0, TILE, 7.0), _fc(col, fog))
	if fog < 0.8:
		for j in 4:
			var jx: float = float(_cell_hash(c, 20 + j) % 26) + 3.0
			draw_rect(Rect2(r.position.x + jx, r.position.y + float(j) * 8.0, 1.0, 7.0), seam)


func _draw_floor(c: Vector2i, r: Rect2) -> void:
	var room: Dictionary = rooms[room_of[c]]
	if not room.known:
		return
	var sh: float = shade.get(c, 0.0)
	var fog: float = maxf(room.fog, sh * fog_shade)
	_draw_planks(c, r, room.tint, fog)
	if room.deco.has(c):
		_draw_rug(c, r, room, fog)
	if fog > 0.05:
		var wob: float = sin(time * 0.7 + c.x * 0.35) * sin(time * 0.5 + c.y * 0.3)
		var a: float = maxf(0.0, fog * (0.06 + 0.07 * wob))
		draw_rect(r, Color(0.8, 0.85, 1.0, a))
	if objects.has(c):
		_draw_object(c, r, fog)


func _draw_rug(c: Vector2i, r: Rect2, room: Dictionary, fog: float) -> void:
	var deco: Dictionary = room.deco
	var base: Color = _fc(Color(0.5, 0.13, 0.15), fog)
	var edge: Color = _fc(Color(0.85, 0.65, 0.25), fog)
	var dark: Color = _fc(Color(0.32, 0.08, 0.1), fog)
	draw_rect(r, base)
	draw_rect(Rect2(r.position + Vector2(9, 9), Vector2(14, 14)), dark, false, 2.0)
	if (c.x + c.y) % 2 == 0:
		draw_rect(Rect2(r.position + Vector2(14, 14), Vector2(4, 4)), edge)
	if not deco.has(c + Vector2i(0, -1)):
		draw_rect(Rect2(r.position.x, r.position.y, TILE, 3.0), edge)
	if not deco.has(c + Vector2i(0, 1)):
		draw_rect(Rect2(r.position.x, r.end.y - 3.0, TILE, 3.0), edge)
	if not deco.has(c + Vector2i(-1, 0)):
		draw_rect(Rect2(r.position.x, r.position.y, 3.0, TILE), edge)
	if not deco.has(c + Vector2i(1, 0)):
		draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, TILE), edge)


## Parede de madeira: topo de tábuas verticais + face frontal (quando há chão embaixo).
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
	var top: Color = Color(0.27, 0.17, 0.1).lerp(fog_color.lightened(0.08), fog)
	draw_rect(r, top)
	var seam: Color = Color(0.14, 0.08, 0.04).lerp(fog_color, fog)
	for k in range(1, 4):
		draw_rect(Rect2(r.position.x + float(k) * 8.0, r.position.y, 1.0, TILE), seam)
	var below: int = grid.get(Vector2i(c.x, c.y + 1), VOID)
	if below == FLOOR or below == DOOR:
		var fy: float = r.end.y - 14.0
		draw_rect(Rect2(r.position.x, fy, TILE, 14.0), _fc(Color(0.4, 0.26, 0.15), fog))
		for k in range(1, 4):
			draw_rect(Rect2(r.position.x + float(k) * 8.0, fy, 1.0, 14.0), _fc(Color(0.25, 0.15, 0.08), fog))
		draw_rect(Rect2(r.position.x, fy, TILE, 2.0), _fc(Color(0.58, 0.4, 0.23), fog))
		draw_rect(Rect2(r.position.x, r.end.y - 2.0, TILE, 2.0), seam)


func _draw_door(c: Vector2i, r: Rect2) -> void:
	var d: Dictionary = doors[door_at[c]]
	var ra: Dictionary = rooms[d.a]
	var rb: Dictionary = rooms[d.b]
	if not (ra.known or rb.known):
		return
	var fog: float = minf(ra.fog, rb.fog)
	if d.open:
		var fc: Color = (ra.tint as Color).lerp(rb.tint, 0.5)
		_draw_planks(c, r, fc, fog)
		for k in 3:
			var ox: float = float((c.x * 13 + c.y * 7 + k * 11) % 24) + 2.0
			var oy: float = float((c.x * 5 + c.y * 17 + k * 9) % 24) + 2.0
			draw_rect(Rect2(r.position + Vector2(ox, oy), Vector2(4, 3)), Color(0.4, 0.26, 0.14).lerp(fog_color, fog))
		return
	var off := Vector2(sin(time * 70.0) * d.shake * 14.0, 0.0)
	var rr := Rect2(r.position + off, r.size)
	var wood: Color = Color(0.58, 0.38, 0.2).lerp(fog_color, fog * 0.75)
	draw_rect(rr, wood)
	var dark: Color = wood.darkened(0.4)
	draw_line(rr.position + Vector2(10, 0), rr.position + Vector2(10, TILE), dark, 1.5)
	draw_line(rr.position + Vector2(21, 0), rr.position + Vector2(21, TILE), dark, 1.5)
	var iron: Color = Color(0.32, 0.34, 0.4).lerp(fog_color, fog * 0.75)
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


# ---- objetos

func _shelf_at(c: Vector2i) -> bool:
	return objects.has(c) and objects[c].type == "shelf"


func _table_at(c: Vector2i) -> bool:
	return objects.has(c) and objects[c].type == "table"


func _draw_object(c: Vector2i, r: Rect2, fog: float) -> void:
	var o: Dictionary = objects[c]
	var off := Vector2(sin(time * 70.0) * float(o.shake) * 10.0, 0.0)
	var cr := Rect2(r.position + off, r.size)
	var otype: String = o.type
	match otype:
		"shelf":
			_draw_shelf(c, cr, o, fog)
		"pillar":
			_draw_pillar(cr, fog)
		"table":
			_draw_table(c, cr, o, fog)
		"barrel":
			_draw_barrel(cr, o, fog)
		"crate":
			_draw_crate(cr, o, fog)
		"vase":
			_draw_vase(cr, o, fog)
		"books":
			_draw_books(cr, o, fog)
		_:
			_draw_generic(cr, o, fog)


func _draw_cracks(center: Vector2, o: Dictionary, fog: float, spread: float) -> void:
	if o.hp >= o.max_hp:
		return
	var col: Color = _fc(Color(0.06, 0.03, 0.02), fog)
	draw_line(center + Vector2(-spread, -spread), center + Vector2(1.0, 0.0), col, 1.5)
	draw_line(center + Vector2(1.0, 0.0), center + Vector2(spread * 0.8, spread), col, 1.5)
	if o.hp <= o.max_hp * 0.5:
		draw_line(center + Vector2(spread, -spread * 0.6), center + Vector2(-2.0, 3.0), col, 1.5)


func _draw_shelf(c: Vector2i, r: Rect2, o: Dictionary, fog: float) -> void:
	var wood: Color = _fc(Color(0.36, 0.22, 0.12), fog)
	var dark: Color = _fc(Color(0.16, 0.09, 0.05), fog)
	var light: Color = _fc(Color(0.52, 0.35, 0.2), fog)
	var front: bool = not _shelf_at(c + Vector2i(0, 1))
	var left_open: bool = not _shelf_at(c + Vector2i(-1, 0))
	var right_open: bool = not _shelf_at(c + Vector2i(1, 0))
	if not front:
		# parte de cima/meio de uma pilha vertical: só o tampo de madeira
		draw_rect(r, light)
		for k in range(1, 4):
			draw_rect(Rect2(r.position.x, r.position.y + float(k) * 8.0, TILE, 1.0), wood)
	else:
		var top_h: float = 11.0
		draw_rect(Rect2(r.position, Vector2(TILE, top_h)), light)
		draw_rect(Rect2(r.position.x, r.position.y + top_h - 2.0, TILE, 2.0), wood)
		draw_rect(Rect2(r.position.x, r.position.y + top_h, TILE, r.size.y - top_h), dark)
		var x: float = r.position.x + 2.0
		var i: int = 0
		var v: int = int(o.v)
		while x < r.end.x - 3.0:
			var hv: int = _cell_hash(c, 40 + i)
			var bw: float = 3.0 + float(hv % 3)
			var bh: float = 10.0 + float(hv % 7)
			var col: Color = BOOK_COLORS[(hv + v) % BOOK_COLORS.size()]
			draw_rect(Rect2(x, r.end.y - 3.0 - bh, bw, bh), _fc(col, fog))
			draw_rect(Rect2(x, r.end.y - 3.0 - bh, 1.0, bh), _fc(col.lightened(0.25), fog))
			x += bw + 0.5
			i += 1
		draw_rect(Rect2(r.position.x, r.end.y - 3.0, TILE, 3.0), wood)
	if left_open:
		draw_rect(Rect2(r.position.x, r.position.y, 2.0, TILE), dark)
	if right_open:
		draw_rect(Rect2(r.end.x - 2.0, r.position.y, 2.0, TILE), dark)


func _draw_pillar(r: Rect2, fog: float) -> void:
	var wood: Color = _fc(Color(0.42, 0.27, 0.15), fog)
	var dark: Color = _fc(Color(0.17, 0.09, 0.05), fog)
	var light: Color = _fc(Color(0.58, 0.4, 0.23), fog)
	var bx: float = r.position.x + 3.0
	var by: float = r.position.y + 2.0
	var bs: float = TILE - 6.0
	draw_rect(Rect2(bx, by + 6.0, bs, bs - 2.0), dark)           # lateral/frente
	draw_rect(Rect2(bx, by, bs, bs - 4.0), wood)                 # viga
	draw_rect(Rect2(bx + 3.0, by + 3.0, bs - 6.0, bs - 10.0), light)
	draw_line(Vector2(bx + 6.0, by + 4.0), Vector2(bx + 6.0, by + bs - 8.0), wood, 1.0)
	draw_line(Vector2(bx + bs - 7.0, by + 4.0), Vector2(bx + bs - 7.0, by + bs - 8.0), wood, 1.0)
	draw_rect(Rect2(bx, by, bs, bs - 4.0), dark, false, 1.5)


func _draw_table(c: Vector2i, r: Rect2, o: Dictionary, fog: float) -> void:
	var wood: Color = _fc(Color(0.52, 0.35, 0.19), fog)
	var edge: Color = _fc(Color(0.25, 0.14, 0.07), fog)
	var lf: float = 0.0 if _table_at(c + Vector2i(-1, 0)) else 2.0
	var rt: float = 0.0 if _table_at(c + Vector2i(1, 0)) else 2.0
	var tp: float = 0.0 if _table_at(c + Vector2i(0, -1)) else 2.0
	var has_below: bool = _table_at(c + Vector2i(0, 1))
	var bt: float = 0.0 if has_below else 7.0
	var area := Rect2(r.position.x + lf, r.position.y + tp, TILE - lf - rt, TILE - tp - bt)
	draw_rect(area, wood)
	for k in range(1, 3):
		draw_rect(Rect2(area.position.x, area.position.y + area.size.y * float(k) / 3.0, area.size.x, 1.0), edge)
	if not has_below:
		draw_rect(Rect2(area.position.x, area.end.y, area.size.x, 5.0), edge)
	if lf > 0.0:
		draw_rect(Rect2(area.position.x, area.position.y, 1.5, area.size.y), edge)
	if rt > 0.0:
		draw_rect(Rect2(area.end.x - 1.5, area.position.y, 1.5, area.size.y), edge)
	if tp > 0.0:
		draw_rect(Rect2(area.position.x, area.position.y, area.size.x, 1.5), edge)
	# itens em cima da mesa
	var h: int = int(o.v) % 5
	var mid: Vector2 = area.position + area.size * 0.5
	if h == 0:
		draw_rect(Rect2(mid + Vector2(-2, -3), Vector2(4, 6)), _fc(Color(0.9, 0.85, 0.7), fog))
		draw_circle(mid + Vector2(0, -5), 2.0, _fc(Color(1.0, 0.8, 0.3), fog))
	elif h == 1:
		draw_rect(Rect2(mid + Vector2(-6, -3), Vector2(6, 7)), _fc(Color(0.85, 0.82, 0.7), fog))
		draw_rect(Rect2(mid + Vector2(0, -3), Vector2(6, 7)), _fc(Color(0.75, 0.72, 0.6), fog))
		draw_line(mid + Vector2(0, -3), mid + Vector2(0, 4), edge, 1.0)


func _draw_barrel(r: Rect2, o: Dictionary, fog: float) -> void:
	var cen: Vector2 = r.position + Vector2(16, 15)
	var wood: Color = _fc(Color(0.5, 0.32, 0.16), fog)
	var dark: Color = _fc(Color(0.22, 0.12, 0.06), fog)
	var iron: Color = _fc(Color(0.38, 0.4, 0.46), fog)
	draw_circle(cen + Vector2(0, 5), 12.0, Color(0, 0, 0, 0.3 * (1.0 - fog)))
	draw_circle(cen, 12.0, dark)
	draw_circle(cen, 10.5, wood)
	draw_line(cen + Vector2(-4, -9), cen + Vector2(-4, 9), dark, 1.0)
	draw_line(cen + Vector2(4, -9), cen + Vector2(4, 9), dark, 1.0)
	draw_arc(cen, 7.5, 0.0, TAU, 20, iron, 2.0)
	draw_circle(cen + Vector2(-3.5, -3.5), 2.5, Color(1, 1, 1, 0.14 * (1.0 - fog)))
	_draw_cracks(cen, o, fog, 6.0)


func _draw_crate(r: Rect2, o: Dictionary, fog: float) -> void:
	var wood: Color = _fc(Color(0.6, 0.44, 0.24), fog)
	var dark: Color = _fc(Color(0.3, 0.2, 0.1), fog)
	var box := Rect2(r.position + Vector2(4, 4), Vector2(24, 24))
	draw_rect(Rect2(box.position + Vector2(0, 3), box.size), Color(0, 0, 0, 0.28 * (1.0 - fog)))
	draw_rect(box, wood)
	draw_line(box.position + Vector2(0, 8), box.position + Vector2(24, 8), dark, 1.0)
	draw_line(box.position + Vector2(0, 16), box.position + Vector2(24, 16), dark, 1.0)
	draw_line(box.position + Vector2(2, 2), box.end - Vector2(2, 2), dark, 2.0)
	draw_line(Vector2(box.end.x - 2.0, box.position.y + 2.0), Vector2(box.position.x + 2.0, box.end.y - 2.0), dark, 2.0)
	draw_rect(box, dark, false, 2.0)
	_draw_cracks(box.position + box.size * 0.5, o, fog, 7.0)


func _draw_vase(r: Rect2, o: Dictionary, fog: float) -> void:
	var cen: Vector2 = r.position + Vector2(16, 18)
	var clay: Color = _fc(Color(0.74, 0.42, 0.27), fog)
	var dark: Color = _fc(Color(0.5, 0.25, 0.15), fog)
	draw_circle(cen + Vector2(0, 5), 9.0, Color(0, 0, 0, 0.28 * (1.0 - fog)))
	draw_circle(cen, 9.0, dark)
	draw_circle(cen, 7.8, clay)
	draw_rect(Rect2(cen + Vector2(-3.5, -12.0), Vector2(7, 6)), dark)
	draw_circle(cen + Vector2(0, -11.0), 4.2, dark)
	draw_circle(cen + Vector2(0, -11.0), 2.6, _fc(Color(0.12, 0.06, 0.04), fog))
	draw_arc(cen, 5.5, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.3 * (1.0 - fog)), 1.5)
	draw_line(cen + Vector2(-7, 0), cen + Vector2(7, 0), dark, 1.0)
	_draw_cracks(cen, o, fog, 4.0)


func _draw_books(r: Rect2, o: Dictionary, fog: float) -> void:
	var v: int = int(o.v)
	draw_rect(Rect2(r.position + Vector2(5, 20), Vector2(22, 5)), Color(0, 0, 0, 0.25 * (1.0 - fog)))
	for k in 3:
		var col: Color = BOOK_COLORS[(v + k * 2) % BOOK_COLORS.size()]
		var w: float = 20.0 - float(k) * 3.0
		var ox: float = float((v + k * 5) % 5) - 2.0
		var rc := Rect2(r.position + Vector2(6.0 + float(k) * 1.5 + ox, 18.0 - float(k) * 6.0), Vector2(w, 6.0))
		draw_rect(rc, _fc(col, fog))
		draw_rect(Rect2(rc.position.x + 1.0, rc.position.y + 1.0, rc.size.x - 2.0, 1.5), _fc(Color(0.9, 0.86, 0.72), fog))
		draw_rect(rc, _fc(col.darkened(0.45), fog), false, 1.0)


## Desenho padrão para tipos de objeto novos (sem função de desenho própria):
## caixa na cor do ObjectDef, com sombra e rachaduras quando danificada.
func _draw_generic(r: Rect2, o: Dictionary, fog: float) -> void:
	var def: ObjectDef = _defs.get(o.type)
	var base: Color = Color(0.6, 0.6, 0.6)
	if def != null:
		base = def.color
	var box := Rect2(r.position + Vector2(4, 4), Vector2(24, 24))
	draw_rect(Rect2(box.position + Vector2(0, 3), box.size), Color(0, 0, 0, 0.28 * (1.0 - fog)))
	draw_rect(box, _fc(base, fog))
	draw_rect(Rect2(box.position, Vector2(24, 5)), _fc(base.lightened(0.25), fog))
	draw_rect(box, _fc(base.darkened(0.5), fog), false, 2.0)
	_draw_cracks(box.position + box.size * 0.5, o, fog, 7.0)
