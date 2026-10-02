# Dungeon Prototype (Godot 4.3+)

Protótipo 2D estilo Enter the Gungeon, todo desenhado por código e com sons sintetizados por código (sem assets).

Desde a v0.4 o conteúdo do jogo é **dados editáveis no Inspector** (arquivos `.tres`), e a cena do jogo tem os nós de verdade. Você não precisa mais abrir `.gd` para mexer em salas, objetos, monstros ou balanceamento.

## Rodar
1. Abra a pasta no Godot 4.3+ (Project Manager > Import > `project.godot`).
2. Aguarde a importação (na primeira vez o editor registra os `class_name` novos) e aperte **F5**.

## Mapa do projeto
```
scenes/
  menu.tscn            menu principal
  game.tscn            cena do jogo: Dungeon, Fx, Monsters, Player, Camera, HudLayer/Hud
  monster.tscn         molde de cada monstro
  rooms/*.tscn         AS SALAS PREDEFINIDAS (uma cena por sala, editadas visualmente)
  rooms/parts/*.tscn   as peças para montar salas: estante, pilar, mesa, barril, caixa, vaso, livros, tapete, buraco
data/
  dungeon_settings.tres     painel de controle da geração (salas, portas, fog, listas)
  objects/*.tres            um tipo de objeto por arquivo (ObjectDef)
  monsters/*.tres           um tipo de monstro por arquivo (MonsterDef)
resources/                  as classes dos recursos (ObjectDef, DungeonSettings, MonsterDef)
scripts/rooms/              scripts das peças e da raiz de sala (RoomLayout, RoomObject, RoomRug, RoomHole)
scripts/                    lógica e desenho (dungeon, player, monster, fx, hud, sfx...)
```

## Editar uma sala (visualmente)
1. Dê dois cliques numa cena de `scenes/rooms/` (ex.: `library_hall.tscn`). Ela abre no editor 2D com chão, paredes, objetos e tapetes desenhados.
2. **Mover**: clique numa peça e arraste. Tudo gruda na grade de 32 px sozinho.
3. **Apagar / duplicar**: `Delete` e `Ctrl+D`, como em qualquer cena.
4. **Adicionar**: selecione o nó `Objetos` (ou `Tapetes` / `Buracos`) na árvore e arraste um arquivo de `scenes/rooms/parts/` para o viewport.
5. **Tamanho da sala**: clique no nó raiz e puxe as alças. Ela sempre fica em tiles inteiros.
6. **Tapete / buraco**: selecione e puxe as alças para cobrir a área que quiser. Um *buraco* tira o chão daquele pedaço (salas em L, em U, com pátio).
7. **Dados da sala**: selecione o nó raiz e use o Inspector: nome, tag (`library` conta como biblioteca), peso no sorteio, tom do piso, se pode espelhar/girar, e `Enabled` para tirar do sorteio sem apagar.
8. As marcas **verdes na parede** mostram onde a porta consegue entrar. O texto laranja abaixo da sala e o triângulo amarelo no nó raiz avisam de problemas (chão dividido por objetos, sem lugar para porta, objeto fora do chão ou empilhado).

Legenda das peças no editor: faixa clara no topo = objeto alto (bloqueia a visão) · bolinha branca = quebra com a espada · a letra é a inicial do nome do objeto. No jogo cada objeto é desenhado pelo código, com o visual de sempre.

## Criar uma sala nova
1. **Scene > New Scene**, escolha *Other Node* e procure por **RoomLayout**. Salve em `scenes/rooms/` (ou duplique uma sala existente no FileSystem e renomeie).
2. Dentro dela crie três nós `Node2D` chamados `Buracos`, `Tapetes` e `Objetos` (só organização; qualquer nome serve).
3. Defina o tamanho puxando as alças e arraste as peças de `scenes/rooms/parts/`.
4. Arraste o `.tscn` para a lista **Room Scenes** em `data/dungeon_settings.tres`. Pronto, ela entra no sorteio.

## Objetos
- Cada objeto é um `ObjectDef` em `data/objects/`: **Tall** (bloqueia a visão e faz sombra), **Destructible** + **Hp**, cor e se aparece sozinho nas salas aleatórias (**Scatter**: nos cantos / no miolo, com peso).
- Para criar um novo: duplique um `.tres`, troque o **Id**, adicione em `dungeon_settings.tres > Object Defs`, e duplique `scenes/rooms/parts/shelf.tscn` trocando o campo **Def** para poder usá-lo nas salas. Tipos novos são desenhados no jogo com uma caixa na cor escolhida (os 7 originais têm desenho próprio no código).

## Monstros
- `data/monsters/*.tres`: raio, vida, velocidade, dano de contato e **Spawn Weight** (chance de nascer). **Kind** escolhe o desenho/comportamento (slime, morcego, ogro, esqueleto).
- Selecione o nó **Game** em `scenes/game.tscn` para trocar a lista de monstros, quantos nascem por sala e a câmera.

## Ajustes rápidos (tudo no Inspector)
- **Dungeon > Settings** (`dungeon_settings.tres`): quantidade de salas, tamanho das salas aleatórias, chance de sala predefinida, formatos aleatórios permitidos, vida das portas, fog e sombra, tom da madeira.
- **Player**: velocidade, vida, alcance e dano da espada.
- **Game**: foco da câmera na sala, antecipação do mouse, monstros por sala.
- Sons: `scripts/sfx.gd` (autoload `Sfx`). Desenho de objetos/monstros: funções `_draw_*` nos scripts.

## Controles
WASD mover · Mouse mirar · Botão esquerdo atacar · ESC menu · R (após morrer) nova dungeon

## Salas e objetos do jogo
- Chão e paredes de madeira. Além das salas aleatórias, há 9 salas predefinidas: 4 bibliotecas (Salão das Estantes, Sala de Leitura, Arquivo, Biblioteca em Ruínas), Corredor, Corredor em L, Armazém, Salão de Pilares e Refeitório. Cada uma aparece espelhada/rotacionada aleatoriamente.
- Objetos **bloqueadores** (não dá para andar por cima): estante e pilar (também escondem parcialmente o que está atrás, com fog) e mesa (só bloqueia o caminho).
- Objetos **destrutíveis** (quebram com a espada; também bloqueiam até quebrar): barril (2 golpes), caixa (3), vaso (1) e pilha de livros (1).

## Exportar para o GitHub Pages
1. Editor > Manage Export Templates > baixe os templates da sua versão.
2. Project > Export > preset **Web** (já incluso). Mantenha **Thread Support desligado**.
3. Export Project para `docs/index.html`.
4. Crie o arquivo vazio `docs/.nojekyll`.
5. No GitHub: repositório > Settings > Pages > Branch `main`, pasta `/docs`.
6. O jogo ficará em `https://SEU_USUARIO.github.io/NOME_DO_REPO/`.
