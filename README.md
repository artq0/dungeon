# Dungeon Prototype (Godot 4.3+)

Protótipo 2D estilo Enter the Gungeon, todo desenhado por código e com sons sintetizados por código (sem assets).

## Ajustes rápidos
- Durabilidade das portas: `DOOR_HP` em `scripts/dungeon.gd`
- Tamanho das salas: `_random_size()` em `scripts/dungeon.gd`
- Foco da câmera na sala: `ROOM_FOCUS` em `scripts/game.gd`
- Sons: `scripts/sfx.gd` (autoload `Sfx`)

## Rodar
1. Abra a pasta no Godot 4.3+ (Project Manager > Import > `project.godot`).
2. Aguarde a importação e aperte **F5**.

## Controles
WASD mover · Mouse mirar · Botão esquerdo atacar · ESC menu · R (após morrer) nova dungeon

## Exportar para o GitHub Pages
1. Editor > Manage Export Templates > baixe os templates da sua versão.
2. Project > Export > preset **Web** (já incluso). Mantenha **Thread Support desligado**.
3. Export Project para `docs/index.html`.
4. Crie o arquivo vazio `docs/.nojekyll`.
5. No GitHub: repositório > Settings > Pages > Branch `main`, pasta `/docs`.
6. O jogo ficará em `https://SEU_USUARIO.github.io/NOME_DO_REPO/`.
