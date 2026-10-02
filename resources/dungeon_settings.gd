@tool
class_name DungeonSettings
extends Resource
## Painel de controle da geração da dungeon. Arquivo padrão: res://data/dungeon_settings.tres
## Tudo aqui pode ser mexido pelo Inspector (inclusive a lista de salas e de objetos).

@export_group("Geração")
## Quantidade de salas por partida (sorteada entre mínimo e máximo).
@export_range(1, 40) var room_count_min: int = 6
@export_range(1, 40) var room_count_max: int = 9
## Tamanho das salas aleatórias em tiles: x = mínimo, y = máximo.
@export var room_width: Vector2i = Vector2i(10, 18)
@export var room_height: Vector2i = Vector2i(8, 13)
## Chance de uma sala nova ser uma sala predefinida (res://data/rooms).
@export_range(0.0, 1.0, 0.01) var template_chance: float = 0.5
## Garante bibliotecas cedo: a 1ª assim que existirem 2 salas e uma 2ª a partir de 4 salas.
@export var force_libraries: bool = true
## Formatos permitidos para as salas aleatórias.
@export_flags("Retângulo", "Pilares", "Cantos cortados", "Elipse", "Buracos", "Cruz") var random_styles: int = 63

@export_group("Portas")
## Golpes necessários para quebrar uma porta.
@export var door_hp: float = 8.0

@export_group("Fog of war")
@export var fog_color: Color = Color(0.17, 0.19, 0.26)
## Sala ainda não vista.
@export_range(0.0, 1.0, 0.01) var fog_unseen: float = 0.9
## Sala vista por uma porta aberta.
@export_range(0.0, 1.0, 0.01) var fog_peek: float = 0.7
## Sala já visitada.
@export_range(0.0, 1.0, 0.01) var fog_visited: float = 0.5
## Força da sombra atrás de estantes/pilares.
@export_range(0.0, 1.0, 0.01) var fog_shade: float = 0.55

@export_group("Madeira das salas aleatórias")
## Cada faixa: x = mínimo, y = máximo (HSV).
@export var tint_hue: Vector2 = Vector2(0.055, 0.095)
@export var tint_saturation: Vector2 = Vector2(0.42, 0.58)
@export var tint_value: Vector2 = Vector2(0.34, 0.44)

@export_group("Conteúdo")
## Salas predefinidas disponíveis (cenas de scenes/rooms/). Para criar uma sala nova:
## monte a cena e arraste o arquivo .tscn para esta lista.
@export var room_scenes: Array[PackedScene] = []
## Objetos que podem aparecer nas salas.
@export var object_defs: Array[ObjectDef] = []
