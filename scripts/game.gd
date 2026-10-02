extends Node2D
## Cena principal do jogo (scenes/game.tscn). Os nós Dungeon, Fx, Monsters, Player, Camera e Hud
## já estão na cena: selecione cada um e ajuste os valores pelo Inspector.
## Este script liga as peças, nasce os monstros e cuida de câmera, dicas e game over.

@export_group("Câmera")
## Quanto a câmera é puxada para o centro da sala atual (0 = nada, 1 = fixa na sala).
@export_range(0.0, 1.0, 0.01) var room_focus: float = 0.3
## Fração da distância até o mouse que a câmera avança.
@export_range(0.0, 0.5, 0.01) var look_ahead: float = 0.16
## Limite desse avanço em pixels.
@export var look_ahead_max: float = 100.0

@export_group("Monstros")
## Cena usada para cada monstro (scenes/monster.tscn).
@export var monster_scene: PackedScene
## Tipos de monstro que podem nascer (res://data/monsters/*.tres). O peso de cada um define a chance.
@export var monster_defs: Array[MonsterDef] = []
## Monstros por sala = células da sala / este valor, entre o mínimo e o máximo abaixo (+ extras).
@export var cells_per_monster: int = 60
@export var monsters_min: int = 2
@export var monsters_max: int = 6
## Sorteia de 0 até este valor monstros extras por sala.
@export var extra_monsters_max: int = 1
## A sala inicial tem sempre esta quantidade, longe do jogador.
@export var first_room_monsters: int = 2
@export var first_room_min_distance: float = 130.0

@onready var dungeon: Dungeon = $Dungeon
@onready var fx: Fx = $Fx
@onready var monster_layer: Node2D = $Monsters
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera
@onready var hud: Hud = $HudLayer/Hud

var monsters: Array = []
var current_room: int = -1
var over: bool = false
var shake: float = 0.0
var hint: String = ""


func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color(0.03, 0.03, 0.05))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	dungeon.generate()  # quantidade de salas vem de Dungeon > Settings
	fx.dungeon = dungeon

	player.dungeon = dungeon
	player.game = self
	player.died.connect(_on_player_died)

	var start: Vector2 = dungeon.cell_center(dungeon.center_open_cell(0))
	player.position = start
	camera.position = start
	camera.make_current()

	_spawn_monsters()
	hud.setup(self, player)

	current_room = dungeon.room_at(start)
	dungeon.enter_room(current_room)


func _pick_monster_def() -> MonsterDef:
	var total: float = 0.0
	for d in monster_defs:
		if d != null:
			total += d.spawn_weight
	if total <= 0.0:
		return null
	var roll: float = randf() * total
	var last: MonsterDef = null
	for d in monster_defs:
		if d == null:
			continue
		last = d
		roll -= d.spawn_weight
		if roll <= 0.0:
			return d
	return last


func _spawn_monsters() -> void:
	if monster_scene == null or monster_defs.is_empty():
		push_warning("Game: monster_scene/monster_defs vazios, a dungeon ficará sem monstros.")
		return
	for i in dungeon.rooms.size():
		var room: Dictionary = dungeon.rooms[i]
		var pool: Array = dungeon.free_cells(i)
		var n: int = clampi(room.cells.size() / maxi(cells_per_monster, 1), monsters_min, monsters_max) + randi_range(0, extra_monsters_max)
		if i == 0:
			n = first_room_monsters
			var far: Array = []
			for c in pool:
				if dungeon.cell_center(c).distance_to(player.position) > first_room_min_distance:
					far.append(c)
			pool = far
		pool.shuffle()
		for k in mini(n, pool.size()):
			var def: MonsterDef = _pick_monster_def()
			if def == null:
				return
			var m: Monster = monster_scene.instantiate()
			m.dungeon = dungeon
			m.game = self
			m.player = player
			m.setup(def)
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
	dungeon.update_fog(current_room, delta, player.position)

	# câmera: segue levemente o mouse + é puxada para o centro da sala atual
	var mouse: Vector2 = get_global_mouse_position()
	var off: Vector2 = (mouse - player.position) * look_ahead
	if off.length() > look_ahead_max:
		off = off.normalized() * look_ahead_max
	var focus: Vector2 = player.position + off
	if current_room >= 0:
		focus = focus.lerp(dungeon.room_center(current_room), room_focus)
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


## Chamado pelo jogador quando a espada acerta um objeto destrutível (barril, caixa, vaso, livros).
func on_object_hit(cell: Vector2i, otype: String, dir: Vector2, broken: bool) -> void:
	var pos: Vector2 = dungeon.cell_center(cell)
	if broken:
		add_shake(5.0)
		Sfx.play("door_break", -8.0, randf_range(1.2, 1.6), 0.08)
		fx.object_break(pos, otype, dir)
	else:
		add_shake(1.5)
		Sfx.play("door_hit", -4.0, randf_range(1.2, 1.5), 0.06)
		fx.object_chips(pos, otype, dir)


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
