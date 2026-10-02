@tool
class_name RoomHole
extends RoomPart
## Buraco no formato da sala: essa área vira parede/vazio em vez de chão.
## Use para fazer salas em L, em U, com pátio no meio etc.
## Puxe as alças no viewport para ajustar o tamanho.

const FILL_COLOR := Color(0, 0, 0, 0.35)
const LINE_COLOR := Color(1, 1, 1, 0.35)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, FILL_COLOR)
	# listras na diagonal para dar a ideia de "vazio"
	var step: float = 16.0
	var offset: float = step
	while offset < size.x + size.y:
		var a := Vector2(minf(offset, size.x), maxf(0.0, offset - size.x))
		var b := Vector2(maxf(0.0, offset - size.y), minf(offset, size.y))
		draw_line(a, b, LINE_COLOR, 1.0)
		offset += step
	draw_rect(rect, LINE_COLOR, false, 2.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(6, 18), "buraco", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
