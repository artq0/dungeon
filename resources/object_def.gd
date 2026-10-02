@tool
class_name ObjectDef
extends Resource
## Tipo de objeto que pode aparecer dentro das salas (estante, barril, caixa...).
##
## Os objetos ficam em res://data/objects/*.tres e são listados em
## res://data/dungeon_settings.tres > Object Defs.
## Para criar um novo: duplique um .tres, troque o id e as propriedades, adicione na lista
## e crie uma peça para usar nas salas (duplique scenes/rooms/parts/shelf.tscn e troque o Def).
## Tipos novos usam um desenho genérico (caixa colorida com a cor abaixo);
## os 7 tipos originais têm desenho próprio em scripts/dungeon.gd.

const SCATTER_NONE: int = 0
const SCATTER_CORNER: int = 1
const SCATTER_INTERIOR: int = 2

## Nome técnico. Os ids "shelf", "pillar", "table", "barrel", "crate", "vase" e "books"
## usam o desenho especial feito em código.
@export var id: StringName = &"novo_objeto"
## Nome mostrado no editor (a inicial aparece em cima da peça nas salas).
@export var display_name: String = "Novo objeto"

@export_group("Comportamento")
## Bloqueia a visão (gera sombra/fog parcial atrás). Estante e pilar são altos.
@export var tall: bool = false
## Quebra com a espada.
@export var destructible: bool = false
## Golpes necessários para quebrar (só vale se for destrutível).
@export_range(0.0, 50.0, 0.5) var hp: float = 1.0

@export_group("Salas aleatórias")
## Onde este objeto pode ser espalhado automaticamente nas salas sem layout predefinido.
@export_enum("Não aparece", "Nos cantos", "No miolo") var scatter: int = 0
## Peso no sorteio entre os objetos do mesmo grupo.
@export_range(0.0, 10.0, 0.1) var scatter_weight: float = 1.0

@export_group("Visual")
## Cor da peça no editor de salas e do desenho genérico de tipos novos.
@export var color: Color = Color(0.5, 0.35, 0.2)
