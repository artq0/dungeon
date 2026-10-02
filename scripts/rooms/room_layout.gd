@tool
class_name RoomLayout
extends Control
## Raiz de uma sala predefinida. Cada sala é uma cena (.tscn) em scenes/rooms/.
##
## Como editar, tudo com o mouse:
##  - Puxe as alças do nó raiz para mudar o tamanho da sala (sempre em tiles inteiros).
##  - Arraste peças de scenes/rooms/parts/ para o viewport: estantes, barris, tapetes, buracos...
##    (selecione antes o nó "Objetos", "Tapetes" ou "Buracos" para a peça cair dentro dele).
##  - Mova com o mouse: tudo gruda na grade de 32 px.
##  - Os avisos aparecem no triângulo amarelo do nó raiz e no texto abaixo da sala.
##  - As marcas verdes na parede mostram onde uma porta consegue entrar.
##
## Depois de criar uma sala nova, arraste a cena para a lista "Room Scenes"
## do arquivo data/dungeon_settings.tres.

const TILE: int = RoomPart.TILE

const WALL_COLOR := Color(0.27, 0.17, 0.1)
const DOOR_SPOT_COLOR := Color(0.3, 1.0, 0.4, 0.8)

## Identificador interno (usado para contar quantas vezes a sala já foi usada).
@export var id: StringName = &"nova_sala"
@export var display_name: String = "Nova sala"
## "library" conta como biblioteca (a dungeon garante pelo menos uma cedo).
@export_enum("library", "corridor", "storage", "hall", "other") var tag: String = "other"
## Desmarque para tirar a sala do sorteio sem apagar a cena.
@export var enabled: bool = true
## Peso no sorteio (a chance cai sozinha conforme a sala já foi usada na mesma dungeon).
@export_range(0.0, 5.0, 0.05) var weight: float = 1.0
## Tom do piso: positivo escurece a madeira, negativo clareia.
@export_range(-0.5, 0.5, 0.01) var tone: float = 0.0

@export_group("Variação")
## A dungeon pode espelhar/girar a sala a cada uso. Desmarque o que não fizer sentido.
@export var allow_flip_x: bool = true
@export var allow_flip_y: bool = true
## Trocar largura por altura (rotação de 90°).
@export var allow_rotate: bool = true

# resultado da última leitura da cena (só usado para desenhar no editor)
var _data: Dictionary = {}
var _signature: int = 0
var _timer: float = 0.0


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	_refresh()


func _process(delta: float) -> void:
	# a sala só existe em tiles inteiros
	var wanted: Vector2 = RoomPart.at_least_one_tile((size / TILE).round()) * TILE
	if wanted != size:
		size = wanted
	# relê a cena umas 5 vezes por segundo para o desenho acompanhar o que você mexe
	_timer += delta
	if _timer >= 0.2:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	_data = extract()
	var sig: int = hash([_data.cells, _data.rugs, _data.warnings, tone, display_name, tag, size])
	if sig != _signature:
		_signature = sig
		queue_redraw()
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	return _data.get("warnings", PackedStringArray())


# ---------------------------------------------------------------- leitura da cena

## Lê a sala e devolve um dicionário simples, que a Dungeon usa para gerar o mapa:
##   cells    : Vector2i -> String   ("" = chão livre, senão o id do objeto naquela célula)
##   rugs     : Array[Vector2i]      células com tapete
##   defs     : Array[ObjectDef]     objetos usados
##   tiles    : Vector2i             tamanho em tiles
##   warnings : PackedStringArray    problemas encontrados
##   door_spots : Array              lugares onde uma porta de 2 tiles cabe
## mais id, name, tag, weight, tone, enabled, flip_x, flip_y, rotate.
func extract() -> Dictionary:
	var tiles := Vector2i((_own_size() / TILE).round())
	var warnings := PackedStringArray()

	# 1) quais células são buraco
	var holes: Dictionary = {}
	var parts: Array = []
	_collect_parts(self, parts)
	for part in parts:
		if part is RoomHole:
			for cell in _cells_of(part):
				holes[cell] = true

	# 2) chão = retângulo da sala menos os buracos
	var cells: Dictionary = {}
	for x in tiles.x:
		for y in tiles.y:
			var cell := Vector2i(x, y)
			if not holes.has(cell):
				cells[cell] = ""

	# 3) objetos e tapetes
	var defs: Array = []
	var rug_cells: Dictionary = {}
	var outside: int = 0
	var stacked: int = 0
	for part in parts:
		if part is RoomObject:
			var obj := part as RoomObject
			if obj.def == null:
				warnings.append("O objeto '%s' está sem Def." % obj.name)
				continue
			var cell: Vector2i = _cells_of(obj)[0]
			if not cells.has(cell):
				outside += 1
			elif cells[cell] != "":
				stacked += 1
			else:
				cells[cell] = str(obj.def.id)
				if not defs.has(obj.def):
					defs.append(obj.def)
		elif part is RoomRug:
			for cell in _cells_of(part):
				if cells.has(cell):
					rug_cells[cell] = true
	if outside > 0:
		warnings.append("%d objeto(s) fora do chão da sala (ignorados)." % outside)
	if stacked > 0:
		warnings.append("%d objeto(s) empilhados na mesma célula (só um vale)." % stacked)

	# 4) checagens
	var spots: Array = _find_door_spots(cells, tiles)
	if cells.is_empty():
		warnings.append("A sala não tem nenhuma célula de chão.")
	else:
		if not _free_floor_connected(cells):
			warnings.append("O chão livre está dividido: algum objeto fecha a passagem.")
		if spots.is_empty():
			warnings.append("Nenhuma borda tem 2 tiles livres seguidos: a sala não consegue receber porta.")

	return {
		"id": id, "name": display_name, "tag": tag, "weight": weight, "tone": tone,
		"enabled": enabled, "flip_x": allow_flip_x, "flip_y": allow_flip_y, "rotate": allow_rotate,
		"tiles": tiles, "cells": cells, "rugs": rug_cells.keys(), "defs": defs,
		"warnings": warnings, "door_spots": spots,
	}


## Tamanho da sala em pixels, lido dos offsets (funciona também fora da árvore de nós).
func _own_size() -> Vector2:
	return Vector2(offset_right - offset_left, offset_bottom - offset_top)


## Junta todas as peças (RoomPart) da cena, em qualquer nível de aninhamento.
func _collect_parts(node: Node, found: Array) -> void:
	for child in node.get_children():
		if child is RoomPart:
			found.append(child)
		else:
			_collect_parts(child, found)


## Retângulo da peça em pixels, relativo à raiz da sala.
func _rect_in_room(part: RoomPart) -> Rect2:
	var top_left := Vector2(part.offset_left, part.offset_top)
	var part_size := Vector2(part.offset_right - part.offset_left, part.offset_bottom - part.offset_top)
	# soma as posições dos nós "pasta" (Objetos, Tapetes...) entre a peça e a raiz
	var parent: Node = part.get_parent()
	while parent != null and parent != self:
		if parent is Control:
			top_left += Vector2((parent as Control).offset_left, (parent as Control).offset_top)
		elif parent is Node2D:
			top_left += (parent as Node2D).position
		parent = parent.get_parent()
	return Rect2(top_left, part_size)


## Todas as células (em tiles) que a peça cobre.
func _cells_of(part: RoomPart) -> Array:
	var rect: Rect2 = _rect_in_room(part)
	var first := Vector2i((rect.position / TILE).round())
	var count := Vector2i(RoomPart.at_least_one_tile((rect.size / TILE).round()))
	var result: Array = []
	for x in count.x:
		for y in count.y:
			result.append(first + Vector2i(x, y))
	return result


func _is_free(cells: Dictionary, cell: Vector2i) -> bool:
	return cells.has(cell) and cells[cell] == ""


## Pontos da borda onde uma porta de 2 tiles consegue entrar.
## Cada item: {"side": "top|bottom|left|right", "cells": [Vector2i, Vector2i]}
func _find_door_spots(cells: Dictionary, tiles: Vector2i) -> Array:
	var spots: Array = []
	for x in range(0, tiles.x - 1):
		var top := [Vector2i(x, 0), Vector2i(x + 1, 0)]
		var bottom := [Vector2i(x, tiles.y - 1), Vector2i(x + 1, tiles.y - 1)]
		if _is_free(cells, top[0]) and _is_free(cells, top[1]):
			spots.append({"side": "top", "cells": top})
		if _is_free(cells, bottom[0]) and _is_free(cells, bottom[1]):
			spots.append({"side": "bottom", "cells": bottom})
	for y in range(0, tiles.y - 1):
		var left := [Vector2i(0, y), Vector2i(0, y + 1)]
		var right := [Vector2i(tiles.x - 1, y), Vector2i(tiles.x - 1, y + 1)]
		if _is_free(cells, left[0]) and _is_free(cells, left[1]):
			spots.append({"side": "left", "cells": left})
		if _is_free(cells, right[0]) and _is_free(cells, right[1]):
			spots.append({"side": "right", "cells": right})
	return spots


## O chão livre (sem objetos) forma uma região só? Senão o jogador poderia ficar preso.
func _free_floor_connected(cells: Dictionary) -> bool:
	var free: Dictionary = {}
	for cell in cells.keys():
		if cells[cell] == "":
			free[cell] = true
	if free.is_empty():
		return false
	var start: Vector2i = free.keys()[0]
	var seen: Dictionary = {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + step
			if free.has(next) and not seen.has(next):
				seen[next] = true
				stack.append(next)
	return seen.size() == free.size()


# ---------------------------------------------------------------- desenho no editor

func _draw() -> void:
	var cells: Dictionary = _data.get("cells", {})
	var font: Font = ThemeDB.fallback_font

	# paredes em volta de todo o chão
	var walls: Dictionary = {}
	for cell in cells.keys():
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var near: Vector2i = cell + Vector2i(ox, oy)
				if not cells.has(near):
					walls[near] = true
	for cell in walls.keys():
		draw_rect(_tile_rect(cell), WALL_COLOR)

	# chão de madeira (o tom segue o campo Tone)
	var floor_color := Color.from_hsv(0.075, 0.5, 0.39)
	if tone >= 0.0:
		floor_color = floor_color.darkened(tone)
	else:
		floor_color = floor_color.lightened(-tone)
	for cell in cells.keys():
		var rect: Rect2 = _tile_rect(cell)
		draw_rect(rect, floor_color)
		for k in range(1, 4):
			draw_rect(Rect2(rect.position.x, rect.position.y + k * 8.0 - 1.0, TILE, 1.0), floor_color.darkened(0.3))

	# marcas verdes na parede: onde a porta pode entrar
	for spot in _data.get("door_spots", []):
		draw_rect(_door_marker(spot), DOOR_SPOT_COLOR)

	# título em cima e avisos embaixo
	var tiles: Vector2i = _data.get("tiles", Vector2i.ONE)
	var title: String = "%s   (%dx%d tiles, %s)" % [display_name, tiles.x, tiles.y, tag]
	draw_string(font, Vector2(0, -TILE - 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.92, 0.6))
	var text_y: float = tiles.y * TILE + TILE + 22.0
	var warnings: PackedStringArray = _data.get("warnings", PackedStringArray())
	if warnings.is_empty():
		draw_string(font, Vector2(0, text_y), "Sala OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 1.0, 0.6))
	for message in warnings:
		draw_string(font, Vector2(0, text_y), "! " + message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.65, 0.3))
		text_y += 18.0


func _tile_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))


## Faixa verde desenhada no tile de parede ao lado do lugar onde a porta entraria.
func _door_marker(spot: Dictionary) -> Rect2:
	var first: Vector2i = spot.cells[0]
	match spot.side:
		"top":
			return Rect2(first.x * TILE, first.y * TILE - 6, TILE * 2, 6)
		"bottom":
			return Rect2(first.x * TILE, (first.y + 1) * TILE, TILE * 2, 6)
		"left":
			return Rect2(first.x * TILE - 6, first.y * TILE, 6, TILE * 2)
		_:
			return Rect2((first.x + 1) * TILE, first.y * TILE, 6, TILE * 2)
