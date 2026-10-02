class_name MonsterDef
extends Resource
## Tipo de monstro. Arquivos em res://data/monsters/*.tres, listados no nó Game (Monster Defs).

@export var id: StringName = &"slime"
@export var display_name: String = "Slime"
## Qual desenho/comportamento usar (feito em código): o morcego voa em zigue-zague.
@export_enum("Slime", "Morcego", "Ogro", "Esqueleto") var kind: int = 0
@export_group("Atributos")
@export_range(2.0, 40.0, 0.5) var radius: float = 11.0
@export_range(0.5, 100.0, 0.5) var max_hp: float = 3.0
@export_range(0.0, 400.0, 1.0) var speed: float = 62.0
@export_range(0.0, 100.0, 0.5) var contact_damage: float = 10.0
@export_group("Nascimento")
## Peso no sorteio de quem nasce nas salas (0 = nunca nasce).
@export_range(0.0, 100.0, 0.5) var spawn_weight: float = 25.0
