@tool
class_name RoomPart
extends Control
## Base de toda peça que você coloca dentro de uma sala (objeto, tapete, buraco).
##
## No editor a peça gruda sozinha na grade de 32 px: pode arrastar à vontade
## que ela se encaixa no tile mais próximo. Peças grandes (tapete, buraco)
## também têm o tamanho arredondado para tiles inteiros quando você puxa as alças.

## Tamanho de um tile em pixels. É a única definição: Dungeon e RoomLayout usam esta.
const TILE: int = 32


func _ready() -> void:
	# fora do editor (no jogo) a peça não precisa fazer nada
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_snap_to_grid()


func _snap_to_grid() -> void:
	var grid := Vector2(TILE, TILE)
	var new_pos: Vector2 = position.snapped(grid)
	if new_pos != position:
		position = new_pos
	var new_size: Vector2 = get_snapped_size()
	if new_size != size:
		size = new_size


## Tamanho permitido para a peça. Por padrão: qualquer múltiplo de tile, mínimo 1x1.
## (RoomObject sobrescreve para ficar sempre 1x1.)
func get_snapped_size() -> Vector2:
	return at_least_one_tile((size / TILE).round()) * TILE


## Garante pelo menos 1 em cada eixo (nada de peça ou sala com tamanho zero).
static func at_least_one_tile(tiles: Vector2) -> Vector2:
	return Vector2(maxf(tiles.x, 1.0), maxf(tiles.y, 1.0))
