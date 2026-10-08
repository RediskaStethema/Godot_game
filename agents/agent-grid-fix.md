# SUB-AGENT: Fix Isometric Grid Positioning

## Роль
Ты — разработчик Godot 4 / GDScript. Твоя задача: исправить позиционирование обеих изометрических сеток (игрок + враги) так чтобы обе полностью влезали в viewport.

## Контекст
Игра WH40KINGS использует псевдо-изометрическую сетку (diamond layout):
- TILE_WIDTH = 128, TILE_HEIGHT = 64
- Две отдельные сетки: player (левый верхний квадрант) и enemy (правый нижний квадрант)
- Проблема: вражеская сетка частично уходит за правый/нижний край экрана

## Файлы для чтения
1. `scripts/battle/IsoGrid.gd` — `setup(viewport_size)`, `tile_to_screen()`, `player_origin`, `enemy_origin`
2. `scripts/battle/IsoGridRenderer.gd` — как рисуется сетка
3. `scenes/battle/BattleScene.gd` — `iso_grid.setup(get_viewport_rect().size)`

## Изометрическая математика

В diamond (pseudo-iso) layout тайл (col, row) → экран:
```gdscript
# Стандартная iso формула:
screen_x = origin_x + (col - row) * (TILE_WIDTH / 2)
screen_y = origin_y + (col + row) * (TILE_HEIGHT / 2)
```

Размер всей сетки W×H тайлов:
- Ширина в пикселях: `(W + H) * TILE_WIDTH / 2`
- Высота в пикселях: `(W + H) * TILE_HEIGHT / 2`

Для сетки 3×3: ширина = 384px, высота = 192px.

## Требуемое расположение

Viewport по умолчанию 1152×648 (или другой — читай `get_viewport_rect().size`).

Разбить viewport на два квадранта:
```
+------------------+------------------+
|                  |                  |
|   ИГРОК (лево)   |   ВРАГИ (право)  |
|                  |                  |
+------------------+------------------+
```

Или диагональное расположение (игрок слева-снизу, враги справа-сверху):
```
+------------------------------------+
|              ВРАГИ                 |
|                                    |
|   ИГРОК                            |
+------------------------------------+
```

## Алгоритм правильного позиционирования

В `IsoGrid.setup(viewport_size: Vector2)`:

```gdscript
func setup(viewport_size: Vector2) -> void:
    var grid_pixel_w = (grid_width + grid_height) * TILE_WIDTH / 2.0
    var grid_pixel_h = (grid_width + grid_height) * TILE_HEIGHT / 2.0
    
    var margin = 40.0  # отступ от края экрана
    
    # Игрок — левый квадрант, по центру вертикально
    player_origin = Vector2(
        margin + grid_pixel_w / 2.0,
        viewport_size.y / 2.0
    )
    
    # Враги — правый квадрант, зеркально
    enemy_origin = Vector2(
        viewport_size.x - margin - grid_pixel_w / 2.0,
        viewport_size.y / 2.0
    )
```

## Проверка

После изменения:
1. Запусти BattleScene
2. Обе сетки должны быть видны целиком
3. Сетка игрока слева, врагов справа, с заметным зазором между ними
4. При drop карты тайлы должны корректно определяться (screen_to_tile работает)

## Отладка screen_to_tile

Если после изменения origin drop перестал работать, добавь временный print:
```gdscript
func _on_card_dropped(card, screen_pos):
    print("screen_pos: ", screen_pos)
    print("player_origin: ", iso_grid.player_origin)
    var tile = iso_grid.screen_to_tile(screen_pos, false)
    print("tile: ", tile, " valid: ", iso_grid.is_valid_tile(tile))
```

`screen_to_tile` должна быть точной инверсией `tile_to_screen` — если нет, проверь формулу в IsoGrid.gd.

## Что НЕ трогать
- TILE_WIDTH и TILE_HEIGHT — 128/64 это стандарт
- occupied_tiles_player / occupied_tiles_enemy — не трогать
- expand_grid(stage) — логику размеров не менять
