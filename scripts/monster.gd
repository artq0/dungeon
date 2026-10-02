extends Node2D
## Monstros: 0 = slime, 1 = morcego, 2 = ogro, 3 = esqueleto.
## Só ficam visíveis na sala do jogador ou quando há linha de visão (porta aberta).

signal died(m)

var dungeon
var game
var player

var kind: int = 0
var radius: float = 11.0
var max_hp: float = 3.0
var hp: float = 3.0
var speed: float = 62.0
var contact_damage: float = 10.0

var vel := Vector2.ZERO
var knock := Vector2.ZERO
var flash: float = 0.0
var vis: float = 0.0
var phase: float = 0.0
var wander_dir := Vector2.ZERO
var wander_t: float = 0.0
var aggro: bool = false


func setup(k: int) -> void:
	kind = k
	phase = randf() * TAU
	match k:
		0:
			radius = 11.0
			max_hp = 3.0
			speed = 62.0
			contact_damage = 10.0
		1:
			radius = 8.0
			max_hp = 2.0
			speed = 105.0
			contact_damage = 7.0
		2:
			radius = 14.0
			max_hp = 6.0
			speed = 48.0
			contact_damage = 16.0
		3:
			radius = 10.0
			max_hp = 3.0
			speed = 80.0
			contact_damage = 9.0
	hp = max_hp


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	phase += delta * (10.0 if kind == 1 else (6.0 if kind == 3 else 4.0))
	flash = maxf(0.0, flash - delta)

	var to_p: Vector2 = player.position - position
	var dist: float = to_p.length()
	var my_room: int = dungeon.room_at(position)
	var same_room: bool = my_room != -1 and my_room == game.current_room
	var los: bool = dist < 420.0 and dungeon.has_los(player.position, position)

	# fog: objetos de outras salas ficam escondidos
	var seen: bool = same_room or los
	vis = move_toward(vis, 1.0 if seen else 0.0, delta * 5.0)
	visible = vis > 0.02
	modulate.a = vis * (1.0 if same_room else 0.78)

	aggro = (same_room or (los and dist < 360.0)) and not player.dead

	var desired := Vector2.ZERO
	if aggro and dist > 1.0:
		var dir: Vector2 = to_p / dist
		if kind == 1:
			dir = (dir + dir.orthogonal() * sin(phase * 0.5) * 0.9).normalized()
		desired = dir * speed
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(0.8, 2.0)
			wander_dir = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
		desired = wander_dir * speed * 0.3
	vel = vel.move_toward(desired, 600.0 * delta)

	var push := Vector2.ZERO
	if aggro:
		for o in game.monsters:
			if o == self or not is_instance_valid(o):
				continue
			var dv: Vector2 = position - o.position
			var l: float = dv.length()
			var min_d: float = radius + o.radius
			if l < min_d and l > 0.01:
				push += dv / l * (min_d - l) * 8.0

	knock = knock.move_toward(Vector2.ZERO, 900.0 * delta)
	position = dungeon.move_circle(position, (vel + knock + push) * delta, radius)

	if aggro and dist < radius + 10.0:
		player.take_damage(contact_damage, to_p.normalized())

	queue_redraw()


func take_damage(amount: float, from_dir: Vector2) -> void:
	hp -= amount
	flash = 0.15
	knock = from_dir * 300.0
	game.add_shake(2.5)
	if hp <= 0.0:
		died.emit(self)
		queue_free()
	else:
		Sfx.play("hit", -2.0, 1.0, 0.1)
		game.fx.hit_sparks(position, from_dir, Color(1.0, 0.95, 0.7), 6)


# ---------------------------------------------------------------- desenho

func _tint(c: Color) -> Color:
	if flash > 0.0:
		return c.lerp(Color.WHITE, 0.85)
	return c


func _draw() -> void:
	draw_set_transform(Vector2(0, radius * 0.7), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var look: Vector2 = (player.position - position).normalized()
	var perp: Vector2 = look.orthogonal()

	match kind:
		0:
			_draw_slime(look, perp)
		1:
			_draw_bat(look, perp)
		2:
			_draw_ogre(look, perp)
		_:
			_draw_skeleton(look, perp)

	if hp < max_hp:
		draw_rect(Rect2(-11, -radius - 14, 22, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-10, -radius - 13, 20.0 * hp / max_hp, 2), Color(0.9, 0.2, 0.2))


func _draw_slime(look: Vector2, perp: Vector2) -> void:
	var body: Color = _tint(Color(0.32, 0.78, 0.38))
	var dark: Color = _tint(Color(0.12, 0.4, 0.2))
	var light: Color = _tint(Color(0.6, 0.95, 0.6))
	var sq: float = sin(phase) * 0.07
	var pts := PackedVector2Array()
	var n: int = 22
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var wob: float = 1.0 + 0.05 * sin(a * 3.0 + phase * 1.4)
		pts.append(Vector2(cos(a) * radius * (1.1 + sq) * wob, sin(a) * radius * (0.88 - sq) * wob + 2.0))
	draw_colored_polygon(pts, body)
	draw_circle(Vector2(-radius * 0.3, -radius * 0.2), radius * 0.38, Color(light.r, light.g, light.b, 0.55))
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, dark, 2.0)
	draw_circle(Vector2(-radius * 0.45, -radius * 0.45), 1.8, Color(1, 1, 1, 0.8))
	for s in [-1.0, 1.0]:
		var ep: Vector2 = Vector2(0, -1) + look * radius * 0.15 + perp * radius * 0.38 * float(s)
		draw_circle(ep, 3.4, Color.WHITE)
		draw_circle(ep + look * 1.6, 1.8, Color(0.05, 0.08, 0.05))
	draw_arc(look * radius * 0.35 + Vector2(0, 4), 3.0, 0.2, PI - 0.2, 8, dark, 1.5)


func _draw_bat(look: Vector2, perp: Vector2) -> void:
	var body: Color = _tint(Color(0.45, 0.25, 0.62))
	var dark: Color = _tint(Color(0.2, 0.08, 0.3))
	var wing: Color = _tint(Color(0.32, 0.15, 0.45))
	var f: float = sin(phase)
	for s in [-1.0, 1.0]:
		var sg: float = float(s)
		var root: Vector2 = perp * sg * 4.0
		var tip: Vector2 = perp * sg * (19.0 - 3.0 * absf(f)) + look * (-2.0 + 8.0 * f)
		var s1: Vector2 = perp * sg * 13.0 + look * (-10.0 + 5.0 * f)
		var s2: Vector2 = perp * sg * 7.0 + look * (-9.0 + 2.0 * f)
		draw_colored_polygon(PackedVector2Array([root + look * 3.0, tip, s1, s2, root - look * 5.0]), wing)
		draw_line(root, tip, dark, 2.0)
		draw_line(root, s1, dark, 1.2)
		draw_line(root, s2, dark, 1.2)
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, dark, 1.5)
	for s in [-1.0, 1.0]:
		var sg2: float = float(s)
		draw_colored_polygon(PackedVector2Array([
			look * 5.0 + perp * sg2 * 2.0, look * 11.0 + perp * sg2 * 4.5, look * 4.0 + perp * sg2 * 5.5]), dark)
		var ep: Vector2 = look * 3.5 + perp * sg2 * 2.8
		draw_circle(ep, 1.9, Color(1.0, 0.2, 0.2))
		draw_circle(ep + look * 0.5, 0.7, Color(1.0, 0.9, 0.7))
		draw_line(look * 7.0 + perp * sg2 * 1.6, look * 9.5 + perp * sg2 * 1.2, Color.WHITE, 1.5)


func _draw_ogre(look: Vector2, perp: Vector2) -> void:
	var skin: Color = _tint(Color(0.78, 0.34, 0.27))
	var dark: Color = _tint(Color(0.35, 0.1, 0.1))
	var light: Color = _tint(Color(0.9, 0.5, 0.4))
	var bone: Color = _tint(Color(0.93, 0.9, 0.78))
	var sw: float = sin(phase) * 3.0
	for s in [-1.0, 1.0]:
		var sg: float = float(s)
		var fist: Vector2 = perp * sg * 16.0 + look * (2.0 + sw * sg)
		draw_line(perp * sg * 9.0, fist, skin, 7.0)
		draw_circle(fist, 5.8, dark)
		draw_circle(fist, 4.8, skin)
	draw_circle(Vector2.ZERO, 13.5, dark)
	draw_circle(Vector2.ZERO, 12.2, skin)
	draw_circle(Vector2(-3, -2), 5.0, Color(light.r, light.g, light.b, 0.35))
	# cinto com fivela
	draw_line(perp * -12.0 - look * 3.0, perp * 12.0 - look * 3.0, _tint(Color(0.3, 0.18, 0.08)), 4.5)
	draw_circle(-look * 3.0, 2.6, _tint(Color(0.9, 0.75, 0.25)))
	# cabeça
	var hc: Vector2 = look * 8.0
	for s in [-1.0, 1.0]:
		var sg2: float = float(s)
		draw_colored_polygon(PackedVector2Array([
			hc + perp * sg2 * 5.5 - look * 1.0, hc + perp * sg2 * 13.0 + look * 6.0, hc + perp * sg2 * 7.5 + look * 3.0]), bone)
	draw_circle(hc, 8.6, dark)
	draw_circle(hc, 7.6, light)
	for s in [-1.0, 1.0]:
		var sg3: float = float(s)
		var e: Vector2 = hc + look * 2.8 + perp * sg3 * 3.2
		draw_circle(e, 2.0, Color(1.0, 0.9, 0.2))
		draw_circle(e + look * 0.8, 0.9, Color(0.05, 0.02, 0.02))
		draw_line(hc + look * 5.4 + perp * sg3 * 0.8, hc + look * 4.2 + perp * sg3 * 5.2, dark, 1.8)
		draw_colored_polygon(PackedVector2Array([
			hc + look * 6.4 + perp * sg3 * 1.6, hc + look * 10.8 + perp * sg3 * 2.6, hc + look * 6.8 + perp * sg3 * 3.6]), bone)


func _draw_skeleton(look: Vector2, perp: Vector2) -> void:
	var bone: Color = _tint(Color(0.88, 0.86, 0.76))
	var shade: Color = _tint(Color(0.55, 0.52, 0.45))
	var dark := Color(0.1, 0.08, 0.1)
	var sw: float = sin(phase) * 3.0
	for s in [-1.0, 1.0]:
		var sg: float = float(s)
		var hand: Vector2 = perp * sg * 11.0 + look * (3.0 + sw * sg)
		draw_line(perp * sg * 6.0, hand, bone, 3.0)
		draw_circle(hand, 2.4, bone)
	# espada enferrujada
	var h0: Vector2 = perp * 11.0 + look * (3.0 + sw)
	draw_line(h0, h0 + look * 16.0, _tint(Color(0.55, 0.5, 0.45)), 3.0)
	draw_line(h0 + perp * 3.5, h0 - perp * 3.5, _tint(Color(0.4, 0.25, 0.12)), 2.5)
	# costelas
	draw_circle(Vector2.ZERO, 8.4, shade)
	draw_circle(Vector2.ZERO, 7.4, bone)
	for k in 3:
		var o: float = -4.0 + float(k) * 4.0
		draw_line(look * o + perp * -6.0, look * o + perp * 6.0, shade, 1.6)
	draw_line(look * -6.0, look * 6.0, shade, 2.0)
	# crânio
	var hc: Vector2 = look * 6.0
	draw_circle(hc, 6.4, shade)
	draw_circle(hc, 5.5, bone)
	for s in [-1.0, 1.0]:
		var sg2: float = float(s)
		var e: Vector2 = hc + look * 1.6 + perp * sg2 * 2.5
		draw_circle(e, 1.9, dark)
		draw_circle(e, 0.8, Color(1.0, 0.25, 0.2))
	draw_circle(hc + look * 3.6, 0.9, dark)
	draw_line(hc + look * 5.0 + perp * -2.5, hc + look * 5.0 + perp * 2.5, shade, 1.2)
