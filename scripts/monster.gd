extends Node2D
## Monstros simples: 0 = slime, 1 = morcego, 2 = bruto.
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
	hp = max_hp


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	phase += delta * (10.0 if kind == 1 else 4.0)
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


func _draw() -> void:
	var body: Color
	var outline: Color
	match kind:
		0:
			body = Color(0.3, 0.75, 0.35)
			outline = Color(0.1, 0.35, 0.15)
		1:
			body = Color(0.6, 0.35, 0.75)
			outline = Color(0.25, 0.1, 0.35)
		_:
			body = Color(0.8, 0.3, 0.25)
			outline = Color(0.35, 0.08, 0.08)
	if flash > 0.0:
		body = Color.WHITE

	draw_set_transform(Vector2(0, radius * 0.7), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var look: Vector2 = (player.position - position).normalized()
	var perp: Vector2 = look.orthogonal()

	if kind == 0:
		var sq: float = sin(phase) * 0.08
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0 + sq, 1.0 - sq))
		draw_circle(Vector2.ZERO, radius, body)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, outline, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == 1:
		var w: float = sin(phase) * 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 0), Vector2(-17, -6 + w), Vector2(-10, 5)]), outline)
		draw_colored_polygon(PackedVector2Array([Vector2(2, 0), Vector2(10, 5), Vector2(17, -6 + w)]), outline)
		draw_circle(Vector2.ZERO, radius, body)
	else:
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), body)
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), outline, false, 2.5)
		draw_colored_polygon(PackedVector2Array([Vector2(-radius, -radius), Vector2(-radius - 3, -radius - 9), Vector2(-radius + 6, -radius)]), Color(0.9, 0.9, 0.8))
		draw_colored_polygon(PackedVector2Array([Vector2(radius - 6, -radius), Vector2(radius + 3, -radius - 9), Vector2(radius, -radius)]), Color(0.9, 0.9, 0.8))

	for s in [-1.0, 1.0]:
		var ep: Vector2 = look * radius * 0.35 + perp * radius * 0.38 * float(s)
		draw_circle(ep, 2.6, Color.WHITE)
		draw_circle(ep + look * 1.0, 1.3, Color(0.05, 0.05, 0.05))

	if hp < max_hp:
		draw_rect(Rect2(-11, -radius - 12, 22, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-10, -radius - 11, 20.0 * hp / max_hp, 2), Color(0.9, 0.2, 0.2))
