extends Control
## HUD: barra de vida no topo, crosshair, dica de porta e tela de game over.

var game
var player
var shown_hp: float = 100.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shown_hp = player.hp


func _process(delta: float) -> void:
	shown_hp = move_toward(shown_hp, player.hp, 45.0 * delta)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vs: Vector2 = get_viewport_rect().size

	# barra de vida
	var bw: float = 420.0
	var bar := Rect2((vs.x - bw) * 0.5, 18.0, bw, 24.0)
	draw_rect(Rect2(bar.position - Vector2(3, 3), bar.size + Vector2(6, 6)), Color(0, 0, 0, 0.65))
	draw_rect(bar, Color(0.18, 0.05, 0.07))
	var maxhp: float = player.MAX_HP
	draw_rect(Rect2(bar.position, Vector2(bw * clampf(shown_hp / maxhp, 0.0, 1.0), bar.size.y)), Color(0.96, 0.85, 0.85, 0.9))
	draw_rect(Rect2(bar.position, Vector2(bw * clampf(player.hp / maxhp, 0.0, 1.0), bar.size.y)), Color(0.85, 0.15, 0.2))
	draw_rect(bar, Color(0, 0, 0, 0.8), false, 2.0)
	draw_string(font, Vector2(bar.position.x, bar.position.y + 18.0), "VIDA  %d / %d" % [int(ceil(player.hp)), int(maxhp)], HORIZONTAL_ALIGNMENT_CENTER, bw, 16, Color.WHITE)

	# dica de porta
	if game.hint != "":
		draw_string(font, Vector2(0, vs.y - 90.0), game.hint, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, Color(1, 0.9, 0.6))

	draw_string(font, Vector2(0, vs.y - 16.0), "WASD mover  •  Mouse mirar  •  Clique esquerdo atacar  •  ESC menu", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 14, Color(1, 1, 1, 0.4))

	if game.over:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, vs.y * 0.45), "VOCÊ MORREU", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 64, Color(0.9, 0.2, 0.25))
		draw_string(font, Vector2(0, vs.y * 0.45 + 50.0), "R  -  nova dungeon        ESC  -  menu", HORIZONTAL_ALIGNMENT_CENTER, vs.x, 24, Color(0.9, 0.9, 0.9))
		return

	# crosshair
	var m: Vector2 = get_local_mouse_position()
	var col := Color(1, 1, 1, 0.95)
	draw_arc(m, 9.0, 0.0, TAU, 24, col, 1.5)
	for dv in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(m + dv * 13.0, m + dv * 20.0, col, 2.0)
	draw_circle(m, 1.8, Color(1, 0.3, 0.3))
