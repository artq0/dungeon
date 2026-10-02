extends Node2D
## Cena principal do jogo: monta dungeon, jogador, monstros, câmera, efeitos e HUD.

const DungeonScr = preload("res://scripts/dungeon.gd")
const PlayerScr = preload("res://scripts/player.gd")
const MonsterScr = preload("res://scripts/monster.gd")
const HudScr = preload("res://scripts/hud.gd")
const FxScr = preload("res://scripts/fx.gd")

## quanto a câmera é puxada para o centro da sala atual (0 = nada, 1 = fixa na sala)
const ROOM_FOCUS: float = 0.3

var dungeon
var player
var hud
var fx
var camera: Camera2D
var monster_layer: Node2D
var monsters: Array = []
var current_room: int = -1
var over: bool = false
var shake: float = 0.0
var hint: String = ""


func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color(0.03, 0.03, 0.05))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	dungeon = DungeonScr.new()
	add_child(dungeon)
	dungeon.generate(randi_range(6, 9))

	fx = FxScr.new()
	fx.dungeon = dungeon
	add_child(fx)

	monster_layer = Node2D.new()
	add_child(monster_layer)

	player = PlayerScr.new()
	player.dungeon = dungeon
	player.game = self
	add_child(player)
	player.died.connect(_on_player_died)

	var start: Vector2 = dungeon.cell_center(dungeon.center_open_cell(0))
	player.position = start

	camera = Camera2D.new()
	camera.zoom = Vector2(1.5, 1.5)
	add_child(camera)
	camera.position = start
	camera.make_current()

	_spawn_monsters()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HudScr.new()
	hud.game = self
	hud.player = player
	layer.add_child(hud)

	current_room = dungeon.room_at(start)
	dungeon.enter_room(current_room)


func _spawn_monsters() -> void:
	for i in dungeon.rooms.size():
		var room: Dictionary = dungeon.rooms[i]
		var pool: Array = room.cells.duplicate()
		if not room.open_cells.is_empty():
			pool = room.open_cells.duplicate()
		var n: int = clampi(room.cells.size() / 60, 2, 6) + randi_range(0, 1)
		if i == 0:
			n = 2
			var far: Array = []
			for c in pool:
				if dungeon.cell_center(c).distance_to(player.position) > 130.0:
					far.append(c)
			pool = far
		pool.shuffle()
		for k in mini(n, pool.size()):
			var roll: float = randf()
			var kind: int = 2          # ogro
			if roll < 0.35:
				kind = 0               # slime
			elif roll < 0.58:
				kind = 3               # esqueleto
			elif roll < 0.84:
				kind = 1               # morcego
			var m = MonsterScr.new()
			m.dungeon = dungeon
			m.game = self
			m.player = player
			m.setup(kind)
			m.position = dungeon.cell_center(pool[k])
			monster_layer.add_child(m)
			monsters.append(m)
			m.died.connect(_on_monster_died)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)

	var r: int = dungeon.room_at(player.position)
	if r != -1 and r != current_room:
		current_room = r
		dungeon.enter_room(r)
	dungeon.update_fog(current_room, delta)

	# câmera: segue levemente o mouse + é puxada para o centro da sala atual
	var mouse: Vector2 = get_global_mouse_position()
	var off: Vector2 = (mouse - player.position) * 0.16
	if off.length() > 100.0:
		off = off.normalized() * 100.0
	var focus: Vector2 = player.position + off
	if current_room >= 0:
		focus = focus.lerp(dungeon.room_center(current_room), ROOM_FOCUS)
	camera.position = camera.position.lerp(focus, 1.0 - exp(-6.0 * delta))
	shake = maxf(0.0, shake - delta * 28.0)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake

	# dica ao chegar perto de uma porta fechada
	hint = ""
	var cleared: bool = room_cleared(current_room)
	if not over:
		for d in dungeon.doors:
			if d.open:
				continue
			for t in d.tiles:
				if dungeon.cell_center(t).distance_to(player.position) < 64.0:
					if cleared:
						hint = "Sala limpa! Um golpe quebra a porta"
					else:
						hint = "Ataque a porta para abri-la  (%d%%)" % int(100.0 * d.hp / d.max_hp)


## Sala sem monstros vivos dentro dela.
func room_cleared(room: int) -> bool:
	for m in monsters:
		if is_instance_valid(m) and dungeon.room_at(m.position) == room:
			return false
	return true


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Chamado pelo jogador quando a espada acerta uma porta.
func on_door_hit(di: int, dir: Vector2, opened: bool) -> void:
	var d: Dictionary = dungeon.doors[di]
	var centers: Array = []
	for t in d.tiles:
		centers.append(dungeon.cell_center(t))
	var mid: Vector2 = (centers[0] + centers[centers.size() - 1]) * 0.5
	if opened:
		add_shake(16.0)
		Sfx.play("door_break", 2.0, randf_range(0.82, 1.18), 0.0)
		fx.door_break(centers, dir)
	else:
		var dmg: float = 1.0 - float(d.hp) / float(d.max_hp)
		add_shake(3.0 + dmg * 3.0)
		Sfx.play("door_hit", 0.0, lerpf(1.15, 0.8, dmg), 0.04)
		fx.door_chips(mid - dir * 16.0, -dir)


func _on_monster_died(m) -> void:
	monsters.erase(m)
	fx.death_burst(m.position, m.kind)
	Sfx.play("die%d" % m.kind, 0.0, 1.0, 0.08)
	add_shake(5.0)


func _on_player_died() -> void:
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		elif event.keycode == KEY_R and over:
			get_tree().reload_current_scene()
