@tool
class_name RoomRug
extends RoomPart
## Tapete. Puxe as alças no viewport para ele cobrir quantos tiles quiser.
## Só enfeita o chão: não bloqueia nada.

const RUG_COLOR := Color(0.5, 0.13, 0.15)
const EDGE_COLOR := Color(0.85, 0.65, 0.25)
const DARK_COLOR := Color(0.32, 0.08, 0.1)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, RUG_COLOR)
	draw_rect(rect.grow(-3), EDGE_COLOR, false, 2.0)
	draw_rect(rect.grow(-8), DARK_COLOR, false, 2.0)
