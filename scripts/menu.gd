extends Control
## Menu principal.

var t: float = 0.0
var embers: Array = []
var controls_panel: PanelContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in 45:
		embers.append({
			"p": Vector2(randf(), randf()),
			"s": randf_range(0.02, 0.07),
			"r": randf_range(1.0, 3.0),
			"ph": randf() * TAU,
		})

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "DUNGEON ABISSAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", Color(0.92, 0.82, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.1))
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "protótipo v0.1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	var play := _make_button("JOGAR", _on_play)
	box.add_child(play)
	box.add_child(_make_button("CONTROLES", _on_controls))
	if not OS.has_feature("web"):
		box.add_child(_make_button("SAIR", _on_quit))

	controls_panel = PanelContainer.new()
	controls_panel.visible = false
	controls_panel.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.08, 0.12)))
	var lbl := Label.new()
	lbl.text = "WASD  -  mover\nMouse  -  mirar\nBotão esquerdo  -  atacar com a espada\nPortas fechadas: ataque até quebrar\nESC  -  voltar ao menu"
	lbl.add_theme_font_size_override("font_size", 18)
	controls_panel.add_child(lbl)
	box.add_child(controls_panel)

	play.grab_focus()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.07))
	for e in embers:
		var y: float = fposmod(e.p.y - t * e.s, 1.0)
		var x: float = e.p.x + sin(t * 0.7 + e.ph) * 0.01
		var a: float = 0.25 + 0.2 * sin(t * 2.0 + e.ph)
		draw_circle(Vector2(x * size.x, y * size.y), e.r, Color(1.0, 0.55, 0.25, a))


func _sb(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = Color(0.45, 0.4, 0.7)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _sb(Color(0.14, 0.13, 0.2)))
	b.add_theme_stylebox_override("hover", _sb(Color(0.24, 0.2, 0.34)))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.34, 0.24, 0.3)))
	b.add_theme_stylebox_override("focus", _sb(Color(0.2, 0.18, 0.3)))
	b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.97))
	b.pressed.connect(cb)
	return b


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_controls() -> void:
	controls_panel.visible = not controls_panel.visible


func _on_quit() -> void:
	get_tree().quit()
