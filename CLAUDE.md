# WH40KINGS — Claude Code Project Context

## Что это
2D изометрический roguelite auto-battler в сеттинге Warhammer 40K на Godot 4.
Вдохновлён игрой 9 Kings. Одиночная разработка.

## Технологии
- **Engine**: Godot 4.x / GDScript
- **Renderer**: Forward+ (D3D12 на Windows)
- **Архитектура**: Autoload-синглтоны + Resource-based данные + FSM для юнитов

## Структура проекта
```
scenes/
  battle/
	BattleScene.tscn / BattleScene.gd   — основная боевая сцена
	Bench.tscn / Bench.gd               — скамейка карт (drag & drop на тайл)
	Squad.tscn / Squad.gd               — отряд (группа солдат на тайле)
  shop/
	ShopScene.tscn / ShopScene.gd       — магазин между боями
scripts/
  autoload/
	BattleManager.gd    — управляет боем, хранит player_units, pending_cards
	EconomyManager.gd   — requisition, round_number, доход
	ShopManager.gd      — генерация офферов магазина
	SquadRegistry.gd    — реестр всех Squad на сцене
	SoldierRegistry.gd  — реестр всех Soldier на сцене
	SynergyManager.gd   — синергии по тегам (TDD MVP: marine x3/x6, elite x2), доход +2 за 3 marine
  battle/
	IsoGrid.gd          — раскладка как в 9 Kings: королевство (открытые клетки `unlocked` в рамке 4×4, сверху слева) и зона врага на одной изометрической оси col, между ними gap_tiles «ничьей земли»; setup(screen, play_area) центрирует всю раскладку
	IsoGridRenderer.gd  — платформа из блоков лунного тайлсета (кэш в дочернем узле, перерисовка refresh_floor()), техно-плиты королевства, тёмные плиты зоны врага, декор; подсветка клеток; occupied_tiles_player/enemy
	TerrainTiles.gd     — тайлсет assets/sprites/map_sprite (32×32 пиксель-арт, масштаб 128/30, TEXTURE_FILTER_NEAREST): draw_block / draw_decoration, списки Slice по назначению
	Building.gd         — здание на клетке королевства: вид из блоков (BLOCKS по building_type), турель (tick), аура замедления стены
	Citadel.gd          — цитадель: крепость из блоков в полклетки на IsoGrid.citadel_tile (0,5), HP-бар, орудие для штурма (tick / take_hit)
	Soldier.gd          — FSM юнита (9 состояний, transition_to / apply_stun / apply_knockback)
	Squad.gd            — контейнер солдат на одном тайле
  data/
	UnitData.gd         — Resource: hp, damage, speed, tags, faction...
	CardData.gd         — Resource: card_type, unit_count, unit_factory_id...
	UnitFactory.gd      — фабрика: create(id) + tactical/assault/scout/devastator/terminator/apothecary/librarian/chaplain/land_speeder/dreadnought/chapter_master/chaos_marine
	CardFactory.gd      — карты и пул магазина (30 копий: common 18 / rare 9 / epic 3)
  ui/
	UITheme.gd          — палитра, Theme, стили карт по редкости, портреты юнитов, фон
  utils/
	GameConstants.gd    — FIXED_TICK=0.1, TEAM_PLAYER=0, TEAM_ENEMY=1, PRIORITY_*
```

## Autoload-синглтоны (глобальные)
| Синглтон | Ключевые поля |
|---|---|
| BattleManager | player_units: Array[UnitData], pending_cards: Array[CardData], player_placements: Dictionary |
| EconomyManager | requisition: int, round_number: int |
| ShopManager | — |
| SquadRegistry | register(squad), get_all_alive_squads(), get_alive_squads_of_team(team) |
| SoldierRegistry | register(soldier), get_alive_soldiers_of_team(team) |
| SynergyManager | calculate_synergies(soldiers), apply_synergies_to_soldiers(soldiers), income_bonus, epic_discount_pending |

## Игровой цикл
ShopScene → (купить карты, drag на скамейку) → BattleScene → (расставить карты на тайлы, запустить бой) → ShopScene

## Текущий статус FSM
**Реализовано (все 9 по TDD)**: IDLE → MOVE → CHASE → ATTACK → CASTING → STUNNED → KNOCKBACK → RETREATING → DEAD  
- CASTING только при `data.cast_time > 0`; RETREATING один раз за бой при HP < `retreat_hp_threshold` (15%), длится `retreat_duration` сек
- Таймеры сравниваются с `TIMER_EPSILON` (погрешность float при шаге 0.1)

## Текущий статус экономики
- Старт: `STARTING_REQUISITION = 12` (по таблице TDD волна 1 = 2–3 Common)
- Доход за победу: `10 + wave×2 + min(bonuses, 8)`; поражение/ничья — половина базы без бонусов
- Бонусы: «без потерь» (+5), синергия (+2 за 3 marine); элитных врагов (+3) нет
- Рука: `BattleManager.pending_cards`, максимум `BattleManager.MAX_HAND_SIZE = 10`; переносится между раундами (после боя не очищается)
- Продажа карт в магазине: `EconomyManager.sell_card()` = `cost / 3` (округление вниз) — решение пользователя, в TDD было ×0.5. Цена Epic со скидкой не меняет `card.cost`
- Salvage: API есть (`add_salvage`, кап 5, `try_spend(req, sal)`), источников нет — P1 по TDD
- Лимита армии нет — ограничена только рука (`MAX_HAND_SIZE = 10`)
- Королевство: `BattleManager.kingdom_tiles` (старт 3×3, рамка `IsoGrid.MAX_KINGDOM_SIZE` 4×4), живёт весь забег. Каждую 3-ю волну (`round_number % 3 == 0`) во время расстановки соседние клетки продаются кликом: `6 + 2×куплено` Req. `IsoGrid.is_valid_tile` = клетка открыта; зона врага — отдельно `enemy_width/height` 3×3
- Враги скрыты (`squad.visible = false`) до нажатия «В БОЙ»

## Критические правила кодирования
1. Всегда использовать `FIXED_TICK = 0.1` — не `delta` в боевой логике
2. `occupied_tiles_player` и `occupied_tiles_enemy` — два отдельных словаря в IsoGridRenderer
3. При вызове `_is_tile_occupied()` проверять только `occupied_tiles_player`
4. `BattleManager.player_placements` — Dictionary[UnitData → Vector2i], очищать при поражении
5. `SquadRegistry.clear()` и `SoldierRegistry.clear()` вызывать в конце каждого боя

## TDD compliance gaps (текущие)
- FSM: ✅ 9 состояний; CASTING — Librarian, STUNNED — его попадание, KNOCKBACK — удар Dreadnought
- Юниты: ✅ 10/10 Marines из TDD + Apothecary (не из TDD); у всех кроме Tactical/Assault placeholder-спрайты (тинт)
- Способности — данными в UnitData: `on_hit_stun`, `on_hit_knockback` (в `Soldier._apply_on_hit_effects`), аура `aura_damage_bonus/radius/tag` (считается в момент удара, `Soldier.get_aura_damage_bonus`), `commander_damage_bonus` (`BattleScene._apply_commander_bonus` перед боем); ауры и командиры не суммируются — берётся максимум
- Экономика: ✅ формула TDD, продажа карт (1/3), рука ≤ 10; Salvage без источников (P1); нет элитных врагов
- Здания: ✅ `Building.gd` (агент `agents/agent-buildings.md`). Занимают клетку королевства, неуязвимы, стоят между раундами (`BattleManager.player_buildings`: CardData → Vector2i), тикают от BattleManager. Bolter Turret (Rare 7, в TDD нет) — 15 урона, 1.5/с, 300 px. Fortress Wall (Common 5) — щит цитадели +200 на каждый бой (`BattleManager.citadel_shield`, TDD «+20 HP базе» ×10) и замедление врагов ×0.6 в 130 px (`Building.slow_mult_at` в `Soldier._move_towards`). Plasma Generatorium — нет
- Цитадель: ✅ HP 1000 на весь забег (`BattleManager.citadel_hp`, float). Армия пала → `siege_started` → штурм: бой цитадели с врагами. Враги идут к ней и бьют обычными атаками в ATTACK (`Soldier._is_sieging / _attack_citadel`, дальность + `Citadel.HIT_RADIUS`); цитадель тикает от BattleManager и бьёт по площади ближайшего врага (`Citadel.DAMAGE/ATTACK_SPEED/ATTACK_RANGE/SPLASH_RADIUS`). Враги перебиты → победа («Цитадель выстояла», доход за победу); HP 0 → `BattleManager.reset_run()` и новый забег. Catch-up бонус TDD — нет
- Синергии: ✅ 3 MVP из TDD (frontline/backline позиции — нет)
- Карты: 16 из 20 MVP (12 squad, 2 building, 2 upgrade); пул магазина 30 копий: common 18 / rare 9 / epic 3
- Карта забега (run map): не реализована

## Правила данных юнитов
- `UnitData` — шаблон; в бою меняются только runtime-поля Soldier: `max_hp`, `current_damage`, `current_move_speed`, `current_attack_range`, `current_attack_speed`, `current_heal_per_second`
- Карты-улучшения (upgrade) лежат на скамейке; игрок бросает карту НА свой отряд → `Squad.apply_upgrade(card)` → `UnitData.apply_upgrade()` (множители `hp_multiplier` / `damage_multiplier` этого отряда, живут с отрядом между раундами) + `Soldier.refresh_stats_from_data()`; тег отряда должен совпадать с `affects_tag`
- Карта отряда, брошенная на свой отряд того же типа (`UnitData.factory_id == CardData.unit_factory_id`) → меню в BattleScene: **улучшить** (`Squad.merge_upgrade()`, до `UnitFactory.MAX_SQUAD_LEVEL = 3`, уровень — `UnitData.squad_level`, множители hp/damage/attack_speed копятся умножением) или **вылечить** (`Squad.heal_by_ratio`, без лимита: живым +доля max HP, павшие до полного состава `UnitData.squad_size` возвращаются с той же долей HP). Бонусы по фракциям — `UnitFactory.SQUAD_MERGE_BONUSES` (space_marines: +20% урона, +20% HP, +15% скорострельности; лечение 35% max HP)
- Множители `UnitData` — только улучшения отряда и масштабирование врагов по волнам; синергии — только runtime-поля Soldier
- Один UnitData = один отряд; `saved_hp` — **доли** HP (0..1] выживших бойцов между раундами (не абсолют — иначе баффы обрезаются)
- Дальности и скорости — в пикселях (melee ≈ 60, ranged 200–320)

## UI и ассеты
- UI собирается кодом поверх .tscn (`_build_layout` в ShopScene, `_build_ui` в BattleScene, `_ready` в Bench); стили — только из `UITheme` (вариации: HeaderLabel, TitleLabel, ValueLabel, DimLabel, SmallLabel, HudPanel, PrimaryButton)
- Окно: 1152×648, `stretch = canvas_items / expand` — всё масштабируется под размер окна
- Спрайты юнитов нормализуются к `Soldier.TARGET_SPRITE_HEIGHT` (62 px) по кадру idle, ноги — в точке бойца; размер юнита — `UnitData.sprite_scale`, окраска — `UnitData.tint`
- Импорт спрайтов: mipmaps включены; `premult_alpha` / `normal_map_invert_y` должны быть false (иначе зелёные силуэты)
- Units и Squad — `y_sort_enabled`; полоска HP рисуется в `Soldier._draw()`
