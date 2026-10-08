# SUB-AGENT: Buildings

## Роль
Добавлять и поддерживать здания: карта типа `building` выкладывается на клетку королевства и работает в бою.

## Контекст
Игра WH40KINGS, Godot 4. Здания — как в 9 Kings: занимают клетку королевства вместо отряда,
стоят между раундами (`BattleManager.player_buildings`: CardData → Vector2i), неуязвимы.
Спрайтов зданий нет — собираются из блоков лунного тайлсета (`TerrainTiles`, как `Citadel`).
TDD: Fortress Wall — Common 3–5 Req, «+20 HP базе» (при HP базы 100). У нас база = цитадель с HP 1000,
поэтому стена — щит цитадели на каждый бой. Bolter Turret в TDD нет (Rare, решение по проекту).

## Файлы для чтения
1. `scripts/battle/Building.gd` — вид (BLOCKS по building_type), tick (турель), аура замедления
2. `scripts/data/CardFactory.gd` — карты зданий (`building_type`, `building_stats`) и `build_pool()`
3. `scripts/autoload/BattleManager.gd` — `buildings` (узлы текущего боя), `player_buildings`, `citadel_shield`, тик зданий
4. `scenes/battle/BattleScene.gd` — `_on_card_dropped` ветка "building", `_place_player_buildings()`
5. `scripts/battle/Citadel.gd` — образец здания из блоков и орудия

## Шаги (новое здание)
1. Карта в `CardFactory`: `card_type = "building"`, свой `building_type`, параметры в `building_stats`.
2. Вид: блоки в `Building.BLOCKS[building_type]`.
3. Поведение: ветка в `Building.tick()` (боевая логика — только в tick, FIXED_TICK) или пассив.
4. Добавить карту в `build_pool()` с сохранением весов 60/30/10.
5. Текст карты в магазине — `ShopSlot` (ветка "building").

## Проверка
- Карта здания: drop на свободную клетку → здание стоит, клетка занята; на занятую — «Тайл занят».
- Здание остаётся на своей клетке в следующем раунде; `reset_run()` их убирает.
- Турель стреляет только во время боя; бой заканчивается.
- Стена: щит цитадели в бою = сумма `shield` стен, урон штурма сначала снимает щит.

## Что НЕ трогать
- `SquadRegistry` / `SoldierRegistry` API
- `GameConstants.FIXED_TICK`
- FSM-переходы Soldier (замедление — только множитель скорости в `_move_towards`)
