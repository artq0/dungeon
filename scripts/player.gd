extends Node2D
## Jogador: WASD, mira no mouse, espada com swing (botão esquerdo).

signal died

const SPEED: float = 215.0
const ACCEL: float = 2200.0
const RADIUS: float = 10.0
const MAX_HP: float = 100.0
const SWING_TIME: float = 0.22
const SWING_COOLDOWN: float = 0.10
const SWING_ARC: float = 2.9
const REACH: float = 58.0
const SWORD_DAMAGE: float = 1.0

var dungeon
var game

var hp: float = MAX_HP
var vel := Vector2.ZERO
var aim := Vector2.RIGHT
var invuln: float = 0.0
var dead: bool = false

var swinging: bool = false
var swing_t: float = 0.0
var swing_dir: float = 1.0
var swing_base: float = 0.0
var swing_offset: float = 0.0
var cooldown: float = 0.0
var hit_monsters: Array = []
var hit_doors: Array = []


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	invuln = maxf(0.0, invuln - delta)
	cooldown = maxf(0.0, cooldown - delta)

	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		aim = to_mouse.normalized()

	var input := Vector2.ZERO
	if not dead:
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
	input = input.normalized()
	vel = vel.move_toward(input * SPEED, ACCEL * delta)
	position = dungeon.move_circle(position, vel * delta, RADIUS)

	if not dead and not swinging and cooldown <= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_start_swing()
	if swinging:
		_update_swing(delta)

	if invuln > 0.0:
		modulate.a = 0.4 + 0.6 * float(int(invuln * 18.0) % 2)
	else:
		modulate.a = 1.0
	queue_redraw()


func _start_swing() -> void:
	swinging = true
	swing_t = 0.0
	swing_base = aim.angle()
	swing_offset = -SWING_ARC * 0.5 * swing_dir
	hit_monsters.clear()
	hit_doors.clear()
	vel += aim * 170.0


func _update_swing(delta: float) -> void:
	swing_t += delta
	var k: float = clampf(swing_t / SWING_TIME, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0)
	swing_offset = lerpf(-SWING_ARC * 0.5, SWING_ARC * 0.5, e) * swing_dir
	var blade_angle: float = swing_base + swing_offset

	# monstros
	var cur: float = swing_offset * swing_dir
	for m in game.monsters:
		if not is_instance_valid(m) or hit_monsters.has(m):
			continue
		var rel: Vector2 = m.position - position
		if rel.length() > REACH + m.radius:
			continue
		var off: float = angle_difference(swing_base, rel.angle()) * swing_dir
		if off >= -SWING_ARC * 0.5 - 0.2 and off <= cur + 0.2:
			if dungeon.has_los(position, m.position):
				hit_monsters.append(m)
				m.take_damage(SWORD_DAMAGE, rel.normalized())

	# portas
	for dist in [22.0, 38.0, 54.0]:
		var p: Vector2 = position + Vector2.from_angle(blade_angle) * float(dist)
		var cell: Vector2i = dungeon.pos_to_cell(p)
		if dungeon.door_at.has(cell):
			var di: int = dungeon.door_at[cell]
			if not hit_doors.has(di) and not dungeon.doors[di].open:
				hit_doors.append(di)
				var opened: bool = dungeon.damage_door(di, SWORD_DAMAGE)
				game.add_shake(9.0 if opened else 4.0)

	if k >= 1.0:
		swinging = false
		cooldown = SWING_COOLDOWN
		swing_dir = -swing_dir


func take_damage(amount: float, from_dir: Vector2) -> void:
	if invuln > 0.0 or dead:
		return
	hp = maxf(0.0, hp - amount)
	invuln = 0.8
	vel = from_dir * 260.0
	game.add_shake(7.0)
	if hp <= 0.0:
		dead = true
		swinging = false
		died.emit()


func _draw() -> void:
	# sombra
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if dead:
		draw_circle(Vector2.ZERO, RADIUS, Color(0.3, 0.3, 0.35))
		return

	# trilha do swing
	var ang: float = aim.angle() - swing_dir * 1.3
	if swinging:
		ang = swing_base + swing_offset
		var a0: float = swing_base - swing_dir * SWING_ARC * 0.5
		var lo: float = minf(a0, ang)
		var hi: float = maxf(a0, ang)
		if hi - lo > 0.05:
			draw_arc(Vector2.ZERO, 44.0, lo, hi, 24, Color(1, 1, 1, 0.22), 10.0)
			draw_arc(Vector2.ZERO, 50.0, lo, hi, 24, Color(1, 1, 1, 0.4), 4.0)

	# corpo
	draw_circle(Vector2.ZERO, RADIUS, Color(0.25, 0.55, 0.85))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, Color(0.1, 0.2, 0.4), 2.0)
	var perp: Vector2 = aim.orthogonal()
	for s in [-1.0, 1.0]:
		var ep: Vector2 = aim * 4.5 + perp * 3.5 * float(s)
		draw_circle(ep, 2.6, Color.WHITE)
		draw_circle(ep + aim * 1.0, 1.3, Color(0.05, 0.05, 0.1))

	# espada
	var dir: Vector2 = Vector2.from_angle(ang)
	var sp: Vector2 = dir.orthogonal()
	draw_line(dir * 6.0, dir * 15.0, Color(0.4, 0.25, 0.12), 4.0)
	draw_line(dir * 15.0 + sp * 6.0, dir * 15.0 - sp * 6.0, Color(0.85, 0.7, 0.25), 3.0)
	var blade := PackedVector2Array([
		dir * 16.0 + sp * 3.0,
		dir * 50.0 + sp * 2.5,
		dir * 58.0,
		dir * 50.0 - sp * 2.5,
		dir * 16.0 - sp * 3.0,
	])
	draw_colored_polygon(blade, Color(0.85, 0.9, 0.96))
	draw_line(dir * 17.0, dir * 54.0, Color.WHITE, 1.5)
