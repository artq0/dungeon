extends Node2D
## Partículas: estilhaços de porta, poeira, faíscas e pedaços de monstros.
## Peças "caem" com altura (z) fingida, quicam, ficam no chão e depois somem.

const MAX_ITEMS: int = 450
const GRAVITY: float = 950.0

var dungeon
var items: Array = []


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var i: int = items.size() - 1
	while i >= 0:
		var p: Dictionary = items[i]
		p.age += delta
		var remove: bool = false
		var k: String = p.kind
		if k == "debris":
			remove = _step_debris(p, delta)
		elif k == "puff":
			p.pos += p.vel * delta
			p.vel = p.vel.move_toward(Vector2.ZERO, 120.0 * delta)
			p.z += 24.0 * delta
			remove = p.age >= p.life
		elif k == "spark":
			p.pos += p.vel * delta
			p.vel = p.vel * maxf(0.0, 1.0 - 6.0 * delta)
			remove = p.age >= p.life
		else:
			remove = p.age >= p.life
		if remove:
			items.remove_at(i)
		i -= 1
	queue_redraw()


func _move(p: Dictionary, delta: float) -> void:
	var np: Vector2 = p.pos + p.vel * delta
	if dungeon != null and dungeon.is_solid_pos(np):
		p.vel = -p.vel * 0.35
	else:
		p.pos = np


func _step_debris(p: Dictionary, delta: float) -> bool:
	if not p.grounded:
		p.vz -= GRAVITY * delta
		p.z += p.vz * delta
		p.rot += p.spin * delta
		_move(p, delta)
		if p.z <= 0.0:
			p.z = 0.0
			if p.bounces < 2 and absf(p.vz) > 70.0:
				p.vz = -p.vz * 0.4
				p.vel *= 0.6
				p.spin *= 0.55
				p.bounces += 1
			else:
				p.grounded = true
				p.vz = 0.0
	else:
		p.vel = p.vel.move_toward(Vector2.ZERO, 600.0 * delta)
		_move(p, delta)
		p.spin = move_toward(p.spin, 0.0, 40.0 * delta)
		p.rot += p.spin * delta
	if p.age > p.life:
		p.alpha = 1.0 - (p.age - p.life) / p.fade
		if p.alpha <= 0.0:
			return true
	return false


# ---------------------------------------------------------------- criação

func _debris(pos: Vector2, vel: Vector2, vz: float, size: Vector2, color: Color, shape: int, life: float, fade: float = 0.9) -> void:
	if items.size() >= MAX_ITEMS:
		return
	items.append({
		"kind": "debris", "pos": pos, "vel": vel, "z": randf_range(4.0, 14.0), "vz": vz,
		"rot": randf() * TAU, "spin": randf_range(-12.0, 12.0), "size": size, "color": color,
		"shape": shape, "age": 0.0, "life": life, "fade": fade, "alpha": 1.0,
		"bounces": 0, "grounded": false,
	})


func _puff(pos: Vector2, vel: Vector2, r0: float, r1: float, color: Color, life: float) -> void:
	if items.size() >= MAX_ITEMS:
		return
	items.append({"kind": "puff", "pos": pos, "vel": vel, "z": 0.0, "r0": r0, "r1": r1,
		"color": color, "age": 0.0, "life": life})


func flash(pos: Vector2, r: float, life: float) -> void:
	items.append({"kind": "flash", "pos": pos, "r": r, "age": 0.0, "life": life})


func ring(pos: Vector2, r: float, life: float) -> void:
	items.append({"kind": "ring", "pos": pos, "r": r, "age": 0.0, "life": life})


func sparks(pos: Vector2, dir: Vector2, color: Color, count: int) -> void:
	for k in count:
		if items.size() >= MAX_ITEMS:
			return
		var v: Vector2 = dir.rotated(randf_range(-0.9, 0.9)) * randf_range(120.0, 320.0)
		items.append({"kind": "spark", "pos": pos, "vel": v, "color": color,
			"age": 0.0, "life": randf_range(0.12, 0.28)})


func dust(pos: Vector2, count: int, color: Color, size: float = 10.0) -> void:
	for k in count:
		var v: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(10.0, 60.0)
		_puff(pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)), v, size * 0.5, size * randf_range(1.4, 2.2), color, randf_range(0.5, 0.9))


## Porta estilhaçando: tábuas, lascas, ferragens, poeira, flash e onda de choque.
func door_break(centers: Array, dir: Vector2) -> void:
	var mid := Vector2.ZERO
	for c in centers:
		mid += c
	mid /= float(centers.size())
	flash(mid, 50.0, 0.2)
	ring(mid, 80.0, 0.4)
	ring(mid, 45.0, 0.28)
	var woods: Array = [Color(0.46, 0.29, 0.15), Color(0.55, 0.35, 0.18), Color(0.38, 0.23, 0.11)]
	var perp: Vector2 = dir.orthogonal()
	for c in centers:
		for k in 8:  # tábuas grandes
			var v: Vector2 = dir * randf_range(80.0, 300.0) + perp * randf_range(-180.0, 180.0) + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 80.0)
			_debris(c + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)), v, randf_range(200.0, 420.0),
				Vector2(randf_range(11.0, 22.0), randf_range(4.5, 7.0)), woods[randi() % 3], 0, randf_range(2.2, 3.4))
		for k in 10:  # lascas
			var v2: Vector2 = dir * randf_range(60.0, 320.0) + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 180.0)
			_debris(c, v2, randf_range(180.0, 460.0), Vector2(randf_range(4.0, 8.0), randf_range(3.0, 5.0)),
				woods[randi() % 3].darkened(randf_range(0.0, 0.25)), 1, randf_range(1.6, 2.6), 0.7)
		for k in 2:  # ferragens
			var v3: Vector2 = dir * randf_range(100.0, 260.0) + perp * randf_range(-140.0, 140.0)
			_debris(c, v3, randf_range(220.0, 380.0), Vector2(randf_range(8.0, 12.0), 3.5), Color(0.45, 0.47, 0.52), 0, randf_range(2.4, 3.2))
		dust(c, 4, Color(0.75, 0.65, 0.5, 0.55), 14.0)
		sparks(c, dir, Color(0.95, 0.75, 0.45), 8)


## Pancada em porta que ainda não quebrou: lascas voltam para o jogador.
func door_chips(pos: Vector2, dir: Vector2) -> void:
	var wood := Color(0.5, 0.32, 0.16)
	for k in 4:
		var v: Vector2 = dir.rotated(randf_range(-0.8, 0.8)) * randf_range(60.0, 200.0)
		_debris(pos, v, randf_range(120.0, 260.0), Vector2(randf_range(3.0, 6.0), randf_range(2.5, 4.0)),
			wood.darkened(randf_range(0.0, 0.3)), 1, randf_range(0.6, 1.2), 0.5)
	sparks(pos, dir, Color(0.95, 0.8, 0.5), 4)
	dust(pos, 1, Color(0.75, 0.65, 0.5, 0.4), 8.0)


func hit_sparks(pos: Vector2, dir: Vector2, color: Color, count: int) -> void:
	sparks(pos, dir, color, count)


func death_burst(pos: Vector2, kind: int) -> void:
	var c1: Color
	var c2: Color
	match kind:
		0:
			c1 = Color(0.32, 0.78, 0.38)
			c2 = Color(0.55, 0.92, 0.55)
		1:
			c1 = Color(0.45, 0.25, 0.62)
			c2 = Color(0.3, 0.15, 0.45)
		2:
			c1 = Color(0.78, 0.34, 0.27)
			c2 = Color(0.55, 0.2, 0.18)
		_:
			c1 = Color(0.88, 0.86, 0.76)
			c2 = Color(0.7, 0.68, 0.6)
	flash(pos, 24.0, 0.14)
	var n: int = 14 if kind == 2 else 10
	for k in n:
		var v: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 230.0)
		var col: Color = c1 if randf() < 0.6 else c2
		if kind == 3:
			_debris(pos, v, randf_range(160.0, 340.0), Vector2(randf_range(6.0, 11.0), 3.0), col, 3, randf_range(1.2, 2.0), 0.7)
		else:
			_debris(pos, v, randf_range(160.0, 340.0), Vector2.ONE * randf_range(3.5, 7.0), col, 2, randf_range(0.9, 1.6), 0.6)
	dust(pos, 3, Color(c1.r, c1.g, c1.b, 0.5), 12.0)
	sparks(pos, Vector2.UP, c2, 6)


# ---------------------------------------------------------------- desenho

func _draw() -> void:
	for p in items:
		var k: String = p.kind
		if k == "debris":
			_draw_debris(p)
		elif k == "puff":
			var t: float = p.age / p.life
			var col: Color = p.color
			col.a = col.a * (1.0 - t) * 0.8
			draw_circle(p.pos + Vector2(0, -p.z), lerpf(p.r0, p.r1, t), col)
		elif k == "spark":
			var t2: float = p.age / p.life
			var col2: Color = p.color
			col2.a = 1.0 - t2
			draw_line(p.pos, p.pos - p.vel * 0.035, col2, 2.0)
		elif k == "flash":
			var t3: float = p.age / p.life
			draw_circle(p.pos, p.r * (0.4 + 0.6 * t3), Color(1.0, 0.95, 0.8, (1.0 - t3) * 0.7))
		elif k == "ring":
			var t4: float = p.age / p.life
			var r: float = p.r * sqrt(t4)
			draw_arc(p.pos, r, 0.0, TAU, 40, Color(1.0, 0.9, 0.7, (1.0 - t4) * 0.8), 1.0 + 3.0 * (1.0 - t4))


func _draw_debris(p: Dictionary) -> void:
	var a: float = p.alpha
	var sz: Vector2 = p.size
	var sh: float = clampf(1.0 - p.z / 90.0, 0.2, 1.0)
	draw_set_transform(p.pos + Vector2(0, 1), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, maxf(sz.x, sz.y) * 0.45 * sh, Color(0, 0, 0, 0.28 * a))
	var col: Color = p.color
	col.a = a
	var dark: Color = col.darkened(0.4)
	draw_set_transform(p.pos + Vector2(0, -p.z), p.rot, Vector2.ONE)
	var shape: int = p.shape
	if shape == 0:
		var r := Rect2(-sz.x * 0.5, -sz.y * 0.5, sz.x, sz.y)
		draw_rect(r, col)
		draw_rect(r, dark, false, 1.0)
		draw_line(Vector2(-sz.x * 0.4, 0.0), Vector2(sz.x * 0.4, 0.0), dark, 1.0)
	elif shape == 1:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-sz.x * 0.5, -sz.y * 0.5), Vector2(sz.x * 0.5, 0.0), Vector2(-sz.x * 0.3, sz.y * 0.5)]), col)
	elif shape == 2:
		draw_circle(Vector2.ZERO, sz.x * 0.5, col)
		draw_circle(Vector2(-sz.x * 0.15, -sz.x * 0.15), sz.x * 0.18, Color(1, 1, 1, 0.4 * a))
	else:
		draw_rect(Rect2(-sz.x * 0.5, -sz.y * 0.5, sz.x, sz.y), col)
		draw_circle(Vector2(-sz.x * 0.5, 0.0), sz.y * 0.8, col)
		draw_circle(Vector2(sz.x * 0.5, 0.0), sz.y * 0.8, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
