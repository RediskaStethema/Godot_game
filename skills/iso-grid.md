# SKILL: Изометрическая сетка (IsoGrid + IsoGridRenderer)

## Когда использовать
Когда нужно изменить размер сетки, исправить позиционирование, добавить новые типы тайлов, отлаживать drop-зоны.

## Архитектура

### IsoGrid.gd
```gdscript
const TILE_WIDTH = 128
const TILE_HEIGHT = 64

var grid_width: int
var grid_height: int
var player_origin: Vector2   # верхний-левый угол игрока
var enemy_origin: Vector2    # верхний-левый угол врага

# expand_grid(stage) определяет размер:
# stage 1 → 3×3
# stage 2 → 4×3
# stage 3 → 4×4

func tile_to_screen(tile: Vector2i, is_enemy: bool) -> Vector2
func screen_to_tile(screen: Vector2, is_enemy: bool) -> Vector2i
func is_valid_tile(tile: Vector2i) -> bool
func get_all_tiles() -> Array[Vector2i]
```

### IsoGridRenderer.gd
```gdscript
var occupied_tiles_player: Dictionary  # Vector2i → bool
var occupied_tiles_enemy: Dictionary   # Vector2i → bool

func set_occupied(tile: Vector2i, occupied: bool, is_enemy: bool = false) -> void
func update_hover(tile: Vector2i) -> void
```

**ВАЖНО**: Никогда не используй `occupied_tiles` (старое имя). Всегда `occupied_tiles_player` или `occupied_tiles_enemy`.

## Две отдельные сетки

Игрок и враг используют разные системы координат:
- `tile_to_screen(tile, false)` → экранная позиция для игрока
- `tile_to_screen(tile, true)` → экранная позиция для врага

При спавне:
```gdscript
squad.global_position = iso_grid.tile_to_screen(tile, team == GameConstants.TEAM_ENEMY)
```

## Drop карт с bench на тайл

```gdscript
func _on_card_dropped(card: CardData, screen_pos: Vector2) -> void:
    var tile = iso_grid.screen_to_tile(screen_pos, false)  # is_enemy=false для игрока
    
    if not iso_grid.is_valid_tile(tile):
        return
    
    if _is_tile_occupied(tile):  # проверяет occupied_tiles_player
        return
    
    _spawn_squad(...)

func _is_tile_occupied(tile: Vector2i) -> bool:
    var renderer = grid_renderer.get_child(0) as IsoGridRenderer
    if renderer:
        return renderer.occupied_tiles_player.has(tile)
    return false
```

## Инициализация в BattleScene._ready()

```gdscript
var renderer = IsoGridRenderer.new()
renderer.occupied_tiles_player.clear()  # обязательно в начале каждого раунда
renderer.occupied_tiles_enemy.clear()
renderer.setup(iso_grid)
grid_renderer.add_child(renderer)

# Сначала враги (они занимают тайлы врагов), потом игрок
_place_enemy_squads()
_place_player_squads()
```

## Порядок спавна (критически важен)
1. `_place_enemy_squads()` — заполняет `occupied_tiles_enemy`
2. `_place_player_squads()` — заполняет `occupied_tiles_player` (выжившие на их старых тайлах)
3. Bench отображает купленные карты — игрок вручную drag & drop на `occupied_tiles_player`

## Проблема: враги вне экрана

Если поле или враги уходят за край экрана — проверить `IsoGrid.get_world_bounds()` (что входит в видимую область) и `BattleScene._fit_camera()` / `_get_play_area()`; раскладка сама в экран не вписывается, это делает камера.  
Формула: `enemy_origin` должна быть в пределах viewport с учётом TILE_WIDTH * grid_width.

## Отладка тайлов
```gdscript
print("Занятые тайлы (игрок): ", renderer.occupied_tiles_player)
print("Занятые тайлы (враг): ", renderer.occupied_tiles_enemy)
print("Тайл под курсором: ", iso_grid.screen_to_tile(get_viewport().get_mouse_position(), false))
```
