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
	ShopScene.tscn / ShopScene.gd       — магазин перед каждой волной; главная сцена
scripts/
  autoload/
	BattleManager.gd    — управляет боем, хранит player_units, pending_cards
	EconomyManager.gd   — requisition, round_number, доход
	ShopManager.gd      — набор магазина (4 карты, RunManager.rng), обновление за Req, бесплатная карта 1-й волны, цена к оплате get_price()
	SquadRegistry.gd    — реестр всех Squad на сцене
	SoldierRegistry.gd  — реестр всех Soldier на сцене
	SynergyManager.gd   — синергии по тегам (TDD MVP: marine x3/x6, elite x2), доход +2 за 3 marine
	RunManager.gd       — забег: линейная цепочка шагов (RunMapData), текущий шаг, advance() — переход к следующему
  battle/
	IsoGrid.gd          — раскладка как в 9 Kings: королевство (открытые клетки `unlocked` в рамке 4×4, сверху слева) и зона врага на одной изометрической оси col, между ними `gap_tiles = 5` «ничьей земли»; раскладка в мировых координатах (`setup()`), `get_world_bounds()` — что должно быть видно (с цитаделью и запасом под спрайты)
	IsoGridRenderer.gd  — платформа из блоков лунного тайлсета (кэш в дочернем узле, перерисовка refresh_floor()), техно-плиты королевства, тёмные плиты зоны врага, декор; подсветка клеток; occupied_tiles_player/enemy
	TerrainTiles.gd     — тайлсет assets/sprites/map_sprite (32×32 пиксель-арт, масштаб IsoGrid.TILE_WIDTH/30 (клетка 140×70), TEXTURE_FILTER_NEAREST): draw_block / draw_decoration, списки Slice по назначению
	Building.gd         — здание на клетке королевства: вид из блоков (BLOCKS по building_type), турель (tick), аура замедления стены
	Citadel.gd          — цитадель: крепость из блоков в полклетки на IsoGrid.citadel_tile (0,5), HP-бар, орудие для штурма (tick / take_hit)
	Soldier.gd          — FSM юнита (9 состояний, transition_to / apply_stun / apply_knockback)
	Squad.gd            — контейнер солдат на одном тайле
  data/
	UnitData.gd         — Resource: hp, damage, speed, tags, faction...
	CardData.gd         — Resource: card_type, unit_count, unit_factory_id...
	UnitFactory.gd      — фабрика: create(id) + tactical/assault/scout/devastator/terminator/apothecary/librarian/chaplain/land_speeder/dreadnought/chapter_master + chaos_marine/chaos_champion/chaos_hellbrute/chaos_lord
	CardFactory.gd      — карты и пул магазина (30 копий: common 18 / rare 9 / epic 3)
	RunMapNode.gd       — Resource: шаг забега (type shop/battle/miniboss/boss, wave, next)
	RunMapData.gd       — Resource: цепочка магазин→бой × TOTAL_WAVES (15), MINIBOSS_EVERY (5) + generate()
	EnemyWaves.gd       — состав врагов по волне и типу боя (обычный / мини-босс / босс) — данными
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
| ShopManager | current_offers, open_shop() (новый магазин), try_reroll() / get_reroll_cost(), get_price(card), try_purchase(slot), free_cards_left |
| SquadRegistry | register(squad), get_all_alive_squads(), get_alive_squads_of_team(team) |
| SoldierRegistry | register(soldier), get_alive_soldiers_of_team(team) |
| SynergyManager | calculate_synergies(soldiers), apply_synergies_to_soldiers(soldiers), income_bonus, epic_discount_pending |
| RunManager | map: RunMapData, current_node_id, current_completed, visited, run_won; advance(), ensure_started(), enter_node(id), complete_current_node(), get_battle_type/wave(), new_run() (зовёт BattleManager.reset_run) |

## Игровой цикл
Линейный, игрок путь не выбирает: ShopScene (главная сцена) → BattleScene (волна 1) → ShopScene → BattleScene (волна 2) → … → волна 15
- Цепочка (`RunMapData.generate`): перед каждой волной магазин; волны 5 и 10 — мини-босс (`MINIBOSS_EVERY`), волна 15 — главный босс (`TOTAL_WAVES`)
- `RunMapNode.wave` боевого шага всегда равна `EconomyManager.round_number` (растёт только в `give_round_income`, 1 раз за бой)
- Магазин: кнопка «В БОЙ» переносит руку в `BattleManager.pending_cards`, завершает шаг, `RunManager.advance()`. Без армии — уход со второго нажатия. Запуск игры: `ShopScene._ready` → `RunManager.ensure_started()`
- Бой: враги по `EnemyWaves.build(wave, type)`; итог → `RunManager.complete_current_node()` → через 2 с `advance()` в магазин следующей волны
- Враги (`EnemyWaves`, константы вверху файла): обычная волна — `2 + (w−1)/2` отрядов Chaos Marine по `3 + (w−1)/3` бойцов (≤ 6), статы ×(1 + 0.10·(w−1)). Мини-босс — Hellbrute сверх волны + Chaos Champion (1 на 5-й, 2 на 10-й) вместо передних отрядов; босс — Chaos Lord вместо переднего отряда
- Регресс забега: `tests/test_run.gd` (цепочка, бои обычный/мини-босс/босс/штурм, расширение): `godot --headless --path . -s tests/test_run.gd`
- Баланс: `tests/balance_sim.gd` (headless, армия на накопленный доход по волнам 1–15): `godot --headless --path . -s tests/balance_sim.gd -- [tactical|mixed|all] [прогонов]`
- Главный босс (Chaos Lord) побеждён → экран «ПОБЕДА»; цитадель 0 HP → экран «ЦИТАДЕЛЬ ПАЛА»; кнопка «НОВЫЙ ЗАБЕГ» → `BattleManager.reset_run()` (сбрасывает и цепочку через `RunManager.new_run()`) → магазин волны 1
- Рука, королевство, здания, ветераны и HP цитадели переживают переходы между сценами

## Текущий статус FSM
**Реализовано (все 9 по TDD)**: IDLE → MOVE → CHASE → ATTACK → CASTING → STUNNED → KNOCKBACK → RETREATING → DEAD  
- CASTING только при `data.cast_time > 0`; RETREATING один раз за бой при HP < `retreat_hp_threshold` (15%), длится `retreat_duration` сек
- Таймеры сравниваются с `TIMER_EPSILON` (погрешность float при шаге 0.1)

## Текущий статус экономики
- Старт: `STARTING_REQUISITION = 12` (по таблице TDD волна 1 = 2–3 Common)
- Доход за победу: `10 + wave×2 + min(bonuses, 8)`; поражение/ничья — половина базы без бонусов
- Бонусы: «без потерь» (+5), синергия (+2 за 3 marine), +3 за каждого элитного врага (тег `elite`: Hellbrute, Champion, Chaos Lord)
- `EconomyManager.add_requisition()` и `BattleManager.heal_citadel()` — разовые награды вне боя (раньше — события), round_number не трогают
- Рука: `BattleManager.pending_cards`, максимум `BattleManager.MAX_HAND_SIZE = 10`; переносится между раундами (после боя не очищается)
- Магазин (решение пользователя вместо драфта TDD «3 → 1»): 4 карты, каждый магазин — новый набор (`ShopManager.open_shop()`). Обновить набор — `REROLL_BASE_COST = 5` Req, каждое следующее в этом магазине ×`REROLL_COST_GROWTH = 1.13` (5, 6, 6, 7, 8, 9, 10, 12…), в новом магазине снова 5. В магазине 1-й волны первая карта бесплатно (`FIRST_WAVE_FREE_CARDS = 1`). Цену к оплате считает `ShopManager.get_price()` (бесплатная → 0, иначе скидка Epic)
- Продажа карт в магазине: `EconomyManager.sell_card()` = `cost / 3` (округление вниз) — решение пользователя, в TDD было ×0.5. Цена Epic со скидкой не меняет `card.cost`
- Salvage: API есть (`add_salvage`, кап 5, `try_spend(req, sal)`), источников нет — P1 по TDD
- Лимита армии нет — ограничена только рука (`MAX_HAND_SIZE = 10`)
- Королевство: `BattleManager.kingdom_tiles` (старт 3×3, рамка `IsoGrid.MAX_KINGDOM_SIZE` 4×4), живёт весь забег. Каждую 3-ю волну (`round_number % BattleManager.EXPANSION_EVERY == 0`, волны 3, 6, 9, 12, 15) во время расстановки соседние клетки продаются кликом: `6 + 2×куплено` Req. `IsoGrid.is_valid_tile` = клетка открыта; зона врага — отдельно `enemy_width/height` 3×3
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
- Экономика: ✅ формула TDD, продажа карт (1/3), рука ≤ 10, +3 за элитного врага; Salvage без источников (P1); catch-up бонус — нет
- Здания: ✅ `Building.gd` (агент `docs/task-briefs/agent-buildings.md`). Занимают клетку королевства, неуязвимы, стоят между раундами (`BattleManager.player_buildings`: CardData → Vector2i), тикают от BattleManager. Bolter Turret (Rare 7, в TDD нет) — 15 урона, 1.5/с, 300 px. Fortress Wall (Common 5) — щит цитадели +200 на каждый бой (`BattleManager.citadel_shield`, TDD «+20 HP базе» ×10) и замедление врагов ×0.6 в 130 px (`Building.slow_mult_at` в `Soldier._move_towards`). Plasma Generatorium — нет
- Цитадель: ✅ HP 1000 на весь забег (`BattleManager.citadel_hp`, float). Армия пала → `siege_started` → штурм: бой цитадели с врагами. Враги идут к ней и бьют обычными атаками в ATTACK (`Soldier._is_sieging / _attack_citadel`, дальность + `Citadel.HIT_RADIUS`); цитадель тикает от BattleManager и бьёт по площади ближайшего врага (`Citadel.DAMAGE/ATTACK_SPEED/ATTACK_RANGE/SPLASH_RADIUS`). Враги перебиты → победа («Цитадель выстояла», доход за победу); HP 0 → `BattleManager.reset_run()` и новый забег. Catch-up бонус TDD — нет
- Синергии: ✅ 3 MVP из TDD (frontline/backline позиции — нет)
- Карты: 15 из 20 MVP (11 squad, 2 building, 2 upgrade); пул магазина 30 копий: common 18 (Tactical 7, Assault 5, Scout 4, Wall 2) / rare 9 / epic 3. Враги (`chaos_*`) в пул не входят
- Баланс карт (решение пользователя, статы отличаются от TDD): Rare/Epic подобраны по паритету HP×DPS за Req с Tactical (карта вдвое дороже ≈ вдвое больше HP и урона), способности — сверху; Scout 4 Req ×3; улучшения 7 Req (+25% HP / +20% урона)
- Забег: ✅ линейная цепочка из 15 волн, магазин перед каждой, мини-босс на 5/10, главный босс на 15, экраны победы и поражения. Chaos: `chaos_marine` + `chaos_champion` (элита) + `chaos_hellbrute` (мини-босс) + `chaos_lord` (босс) — масштаб статов/размера/тинта, без своих спрайтов; кривая волн и карты подобраны симуляцией `tests/balance_sim.gd` (идеальный игрок проходит 1–14, босс 15 — пик: Tactical 3/4, Rare/Epic 1/4). Экран карты с выбором пути (`RunMapScene`) и события (`RunEvents`) удалены — описание и полный код в `docs/archive/run-map-and-events.md`

## Правила данных юнитов
- `UnitData` — шаблон; в бою меняются только runtime-поля Soldier: `max_hp`, `current_damage`, `current_move_speed`, `current_attack_range`, `current_attack_speed`, `current_heal_per_second`
- Карты-улучшения (upgrade) лежат на скамейке; игрок бросает карту НА свой отряд → `Squad.apply_upgrade(card)` → `UnitData.apply_upgrade()` (множители `hp_multiplier` / `damage_multiplier` этого отряда, живут с отрядом между раундами) + `Soldier.refresh_stats_from_data()`; тег отряда должен совпадать с `affects_tag`
- Карта отряда, брошенная на свой отряд того же типа (`UnitData.factory_id == CardData.unit_factory_id`) → меню в BattleScene: **улучшить** (`Squad.merge_upgrade()`, до `UnitFactory.MAX_SQUAD_LEVEL = 3`, уровень — `UnitData.squad_level`, множители hp/damage/attack_speed копятся умножением) или **вылечить** (`Squad.heal_by_ratio`, без лимита: живым +доля max HP, павшие до полного состава `UnitData.squad_size` возвращаются с той же долей HP). Бонусы по фракциям — `UnitFactory.SQUAD_MERGE_BONUSES` (space_marines: +20% урона, +20% HP, +15% скорострельности; лечение 35% max HP)
- Множители `UnitData` — только улучшения отряда и масштабирование врагов по волнам; синергии — только runtime-поля Soldier
- Один UnitData = один отряд; `saved_hp` — **доли** HP (0..1] выживших бойцов между раундами (не абсолют — иначе баффы обрезаются)
- Отряд пал целиком, но бой выигран (в т.ч. «Цитадель выстояла») → `UnitData.respawn_after_wipe()` в `BattleScene._save_survivors`: полный состав `squad_size` с полным HP на свою клетку, уровень −1 (с базового — просто возрождается), карты-улучшения сбрасываются (решение пользователя). Поражение / ничья — армия теряется, как раньше
- Дальности и скорости — в пикселях (melee ≈ 60, ranged 200–320)

## UI и ассеты
- UI собирается кодом поверх .tscn (`_build_layout` в ShopScene, `_build_ui` в BattleScene, `_ready` в Bench); стили — только из `UITheme` (вариации: HeaderLabel, TitleLabel, ValueLabel, DimLabel, SmallLabel, HudPanel, PrimaryButton)
- Окно: 1152×648, `stretch = canvas_items / expand` — всё масштабируется под размер окна; минимальная высота 648 — под неё подобраны панели магазина (`ShopScene.BOTTOM_BAR_HEIGHT / HAND_PANEL_HEIGHT`, `ShopSlot.CARD_SIZE`) и карта скамейки (`BenchCard`, текст ≤ 3 строк)
- Бой: `Camera2D` в BattleScene (`_fit_camera`) вписывает `IsoGrid.get_world_bounds()` в свободную от UI область — при расстановке между HUD и скамейкой с приближением `PLACEMENT_ZOOM = 1.15` (якорь — левый верхний угол мира: королевство и цитадель, зона врага может обрезаться), после «В БОЙ» скамейка и синергии прячутся, камера плавно отъезжает. Ввод с экрана → мир: `_screen_to_world()` (UI — в CanvasLayer, камера на него не влияет)
- Подпись отряда: курсор на бойце дольше `BattleScene.HOVER_NAME_DELAY` (0.5 с) → имя ×бойцов (· ур.N у своих), свои золотом, враги красным; скрытые до боя враги не подписываются (`_squad_at`, `_show_hover`)
- Справка по отряду: клик по своему отряду (`_unhandled_input` — клики по UI не доходят) → панель рядом: уровень, живые бойцы / `squad_size`, текущее / макс. HP, бонусы множителей `UnitData` в %, карты-улучшения, синергии отряда; обновляется каждый кадр (`_update_info_panel`), повторный клик или клик мимо — закрыть
- Спрайты юнитов нормализуются к `Soldier.TARGET_SPRITE_HEIGHT` (62 px) по кадру idle, ноги — в точке бойца; размер юнита — `UnitData.sprite_scale`, окраска — `UnitData.tint`
- Импорт спрайтов: mipmaps включены; `premult_alpha` / `normal_map_invert_y` должны быть false (иначе зелёные силуэты)
- Units и Squad — `y_sort_enabled`; полоска HP рисуется в `Soldier._draw()`
