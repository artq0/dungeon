class_name Player
extends Node2D
## Jogador (cavaleiro): WASD, mira no mouse, espada com swing (botão esquerdo).
## Os números abaixo aparecem no Inspector quando você seleciona o nó Player em scenes/game.tscn.

signal died

@export_group("Movimento")
@export var speed: float = 215.0
@export var accel: float = 2200.0
## Raio de colisão com paredes e objetos.
@export var radius: float = 10.0

@export_group("Vida")
@export var max_hp: float = 100.0

@export_group("Espada")
@export var swing_time: float = 0.22
@export var swing_cooldown: float = 0.10
## Abertura do golpe em radianos.
@export var swing_arc: float = 2.9
@export var reach: float = 58.0
@export var sword_damage: float = 1.0

var dungeon
var game

var hp: float = 100.0
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
var hit_objects: Array = []
var walk: float = 0.0
var step_idx: int = 0


func _ready() -> void:
	hp = max_hp


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
	vel = vel.move_toward(input * speed, accel * delta)
	position = dungeon.move_circle(position, vel * delta, radius)

	# passos
	if vel.length() > 40.0 and not dead:
		walk += vel.length() * delta * 0.09
		var si: int = int(floor(walk / PI))
		if si != step_idx:
			step_idx = si
			Sfx.play("step", -22.0, 1.0, 0.2)

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
	swing_offset = -swing_arc * 0.5 * swing_dir
	hit_monsters.clear()
	hit_doors.clear()
	hit_objects.clear()
	vel += aim * 170.0
	Sfx.play("swing", -3.0, 1.0, 0.1)


func _update_swing(delta: float) -> void:
	swing_t += delta
	var k: float = clampf(swing_t / swing_time, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0)
	swing_offset = lerpf(-swing_arc * 0.5, swing_arc * 0.5, e) * swing_dir
	var blade_angle: float = swing_base + swing_offset

	# monstros
	var cur: float = swing_offset * swing_dir
	for m in game.monsters:
		if not is_instance_valid(m) or hit_monsters.has(m):
			continue
		var rel: Vector2 = m.position - position
		if rel.length() > reach + m.radius:
			continue
		var off: float = angle_difference(swing_base, rel.angle()) * swing_dir
		if off >= -swing_arc * 0.5 - 0.2 and off <= cur + 0.2:
			if dungeon.has_los(position, m.position):
				hit_monsters.append(m)
				m.take_damage(sword_damage, rel.normalized())

	# portas
	for dist in [22.0, 38.0, 54.0]:
		var p: Vector2 = position + Vector2.from_angle(blade_angle) * float(dist)
		var cell: Vector2i = dungeon.pos_to_cell(p)
		if dungeon.door_at.has(cell):
			var di: int = dungeon.door_at[cell]
			if not hit_doors.has(di) and not dungeon.doors[di].open:
				hit_doors.append(di)
				var dmg: float = sword_damage
				if game.room_cleared(game.current_room):
					dmg = 9999.0  # sala limpa: a porta quebra instantaneamente
				var opened: bool = dungeon.damage_door(di, dmg)
				game.on_door_hit(di, aim, opened)
		# objetos destrutíveis (barril, caixa, vaso, livros): 1 dano por golpe
		if dungeon.objects.has(cell) and not hit_objects.has(cell):
			var ob: Dictionary = dungeon.objects[cell]
			if ob.destructible:
				hit_objects.append(cell)
				var otype: String = ob.type
				var broken: bool = dungeon.damage_object(cell, sword_damage)
				game.on_object_hit(cell, otype, aim, broken)

	if k >= 1.0:
		swinging = false
		cooldown = swing_cooldown
		swing_dir = -swing_dir


func take_damage(amount: float, from_dir: Vector2) -> void:
	if invuln > 0.0 or dead:
		return
	hp = maxf(0.0, hp - amount)
	invuln = 0.8
	vel = from_dir * 260.0
	game.add_shake(7.0)
	game.fx.hit_sparks(position, from_dir, Color(0.95, 0.25, 0.25), 8)
	if hp <= 0.0:
		dead = true
		swinging = false
		Sfx.play("pdie", 0.0, 1.0, 0.0)
		died.emit()
	else:
		Sfx.play("hurt", 0.0, 1.0, 0.06)


# ---------------------------------------------------------------- desenho

func _draw() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var perp: Vector2 = aim.orthogonal()
	var moving: float = clampf(vel.length() / speed, 0.0, 1.0)
	var bob: Vector2 = Vector2(0.0, sin(walk * 2.0) * 1.0 * moving)

	var steel := Color(0.66, 0.7, 0.78)
	var steel_l := Color(0.82, 0.86, 0.93)
	var steel_d := Color(0.2, 0.22, 0.3)
	var red := Color(0.72, 0.13, 0.17)
	var gold := Color(0.92, 0.75, 0.25)

	# sombra
	draw_set_transform(Vector2(0, 9), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if dead:
		draw_circle(Vector2(0, 2), 12.0, red.darkened(0.3))
		draw_circle(Vector2.ZERO, 9.0, steel.darkened(0.3))
		draw_circle(aim * 2.0, 7.0, steel_l.darkened(0.3))
		draw_line(Vector2(-14, 10), Vector2(16, 12), Color(0.8, 0.85, 0.9), 3.0)
		return

	# botas
	for s in [-1.0, 1.0]:
		var foot := Vector2(4.5 * float(s), 8.0 + sin(walk + (0.0 if s > 0.0 else PI)) * 3.0 * moving)
		draw_circle(foot, 3.6, Color(0.25, 0.16, 0.1))
		draw_circle(foot + Vector2(-0.8, -0.8), 1.3, Color(0.45, 0.3, 0.2))

	# capa
	var wave: float = sin(t * 7.0) * 2.5 * (0.4 + moving)
	var tail: float = 15.0 + 5.0 * moving
	var cape := PackedVector2Array([
		perp * 8.0 - aim * 2.0 + bob,
		perp * 6.0 - aim * tail + perp * wave + bob,
		-perp * 6.0 - aim * tail - perp * wave + bob,
		-perp * 8.0 - aim * 2.0 + bob,
	])
	draw_colored_polygon(cape, red)
	draw_line(cape[1], cape[2], red.darkened(0.45), 2.0)
	draw_line(cape[0], cape[1], red.darkened(0.3), 1.5)
	draw_line(cape[2], cape[3], red.darkened(0.3), 1.5)

	# tronco
	draw_circle(bob, 10.5, steel_d)
	draw_circle(bob, 9.2, steel)
	draw_arc(bob, 6.5, PI * 1.1, PI * 1.7, 10, Color(1, 1, 1, 0.35), 2.0)
	# sobreveste azul com detalhe dourado
	draw_line(bob - aim * 7.5, bob + aim * 7.5, Color(0.18, 0.32, 0.72), 4.5)
	draw_line(bob - aim * 7.5, bob + aim * 7.5, gold, 1.0)

	# ombreira
	var sh_r: Vector2 = perp * 9.0 - aim * 1.0 + bob
	draw_circle(sh_r, 4.8, steel_d)
	draw_circle(sh_r, 4.0, steel_l)

	# escudo (braço esquerdo)
	var sc: Vector2 = -perp * 10.0 + aim * 3.0 + bob
	draw_circle(sc, 8.0, steel_d)
	draw_circle(sc, 7.0, Color(0.78, 0.78, 0.85))
	draw_circle(sc, 5.6, Color(0.17, 0.28, 0.65))
	draw_line(sc - Vector2(0, 5.0), sc + Vector2(0, 5.0), Color(0.95, 0.95, 1.0), 1.6)
	draw_line(sc - Vector2(5.0, 0), sc + Vector2(5.0, 0), Color(0.95, 0.95, 1.0), 1.6)
	draw_circle(sc, 2.0, gold)

	# elmo
	var hc: Vector2 = aim * 2.5 + bob + Vector2(0, -1)
	var plume_tail: Vector2 = hc - aim * (13.0 + 3.0 * moving) + perp * sin(t * 9.0) * 3.0
	draw_colored_polygon(PackedVector2Array([hc - aim * 4.0 + perp * 2.4, plume_tail, hc - aim * 4.0 - perp * 2.4]), red.lightened(0.1))
	draw_circle(hc, 8.4, steel_d)
	draw_circle(hc, 7.4, steel_l)
	draw_circle(hc + Vector2(-2.2, -2.6), 2.4, Color(1, 1, 1, 0.5))
	draw_line(hc - aim * 5.5, hc + aim * 3.5, red, 3.6)
	draw_line(hc + aim * 4.4 + perp * 4.8, hc + aim * 4.4 - perp * 4.8, Color(0.06, 0.07, 0.1), 3.2)
	for s in [-1.0, 1.0]:
		draw_circle(hc + aim * 4.6 + perp * 2.1 * float(s), 0.9, Color(0.55, 0.85, 1.0))

	# espada
	var ang: float = aim.angle() - swing_dir * 1.3
	if swinging:
		ang = swing_base + swing_offset
		var a0: float = swing_base - swing_dir * swing_arc * 0.5
		var lo: float = minf(a0, ang)
		var hi: float = maxf(a0, ang)
		if hi - lo > 0.05:
			draw_arc(Vector2.ZERO, 42.0, lo, hi, 28, Color(1, 1, 1, 0.16), 12.0)
			draw_arc(Vector2.ZERO, 50.0, lo, hi, 28, Color(1, 1, 1, 0.34), 5.0)
			var lead0: float = ang - swing_dir * 0.7
			draw_arc(Vector2.ZERO, 48.0, minf(lead0, ang), maxf(lead0, ang), 12, Color(1, 1, 1, 0.8), 3.0)
	var dir: Vector2 = Vector2.from_angle(ang)
	var sp: Vector2 = dir.orthogonal()
	draw_line(dir * 6.0, dir * 14.0, Color(0.4, 0.25, 0.12), 4.0)
	draw_circle(dir * 5.0, 2.4, gold)
	draw_line(dir * 14.5 + sp * 6.5, dir * 14.5 - sp * 6.5, gold, 3.2)
	var blade := PackedVector2Array([
		dir * 15.5 + sp * 3.2,
		dir * 50.0 + sp * 2.6,
		dir * 59.0,
		dir * 50.0 - sp * 2.6,
		dir * 15.5 - sp * 3.2,
	])
	draw_colored_polygon(blade, Color(0.82, 0.88, 0.95))
	draw_line(dir * 16.0, dir * 55.0, Color.WHITE, 1.6)
	draw_line(dir * 17.0 + sp * 2.4, dir * 50.0 + sp * 2.0, Color(0.55, 0.62, 0.72), 1.0)
	draw_circle(dir * 9.5, 3.2, steel)  # manopla
