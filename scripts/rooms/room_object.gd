@tool
class_name RoomObject
extends RoomPart
## Um objeto da sala (estante, pilar, barril...) ocupando 1 tile.
##
## Para colocar na sala: arraste uma cena de scenes/rooms/parts/ (shelf.tscn, barrel.tscn...)
## ou adicione um nó "RoomObject" e escolha o tipo no campo Def.
## No jogo o desenho de verdade vem do Dungeon; aqui é só uma representação para você editar.

## Qual objeto é este (arquivos em res://data/objects/).
@export var def: ObjectDef:
	set(value):
		def = value
		queue_redraw()
		update_configuration_warnings()


func get_snapped_size() -> Vector2:
	return Vector2(TILE, TILE)


func _get_configuration_warnings() -> PackedStringArray:
	if def == null:
		return PackedStringArray(["Escolha um ObjectDef no campo Def."])
	return PackedStringArray()


func _draw() -> void:
	var color := Color(1, 0, 1)
	var letter := "?"
	if def != null:
		color = def.color
		letter = def.display_name.left(1).to_upper()

	var box := Rect2(3, 3, TILE - 6, TILE - 6)
	draw_rect(box, color)
	draw_rect(box, color.darkened(0.55), false, 2.0)

	if def != null:
		if def.tall:
			# faixa clara no topo = objeto alto (bloqueia a visão)
			draw_rect(Rect2(box.position, Vector2(box.size.x, 5)), color.lightened(0.35))
		if def.destructible:
			# bolinha branca = quebra com a espada
			draw_circle(Vector2(box.end.x - 5, box.position.y + 5), 2.5, Color.WHITE)

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, 21), letter, HORIZONTAL_ALIGNMENT_CENTER, TILE, 16, Color.WHITE)
