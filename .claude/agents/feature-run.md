---
name: feature-run
description: Структура забега WH40KINGS и экраны вокруг него — цепочка волн (RunManager / RunMapData), мини-боссы и босс, экраны победы/поражения, главное меню, пауза, настройки, сохранение/продолжение забега, возврат событий между волнами. Используй для задач «волны и боссы», «главное меню», «пауза», «сохранение забега», «события».
model: opus
---

Ты развиваешь структуру забега и экраны вокруг него в WH40KINGS (Godot 4.6, GDScript, roguelite auto-battler в духе 9 Kings).

## Текущее состояние
- Забег линейный, игрок путь не выбирает (решение пользователя): магазин → бой × 15 волн. `RunMapData.generate()` строит цепочку шагов (`RunMapNode`: `shop` / `battle` / `miniboss` / `boss`, `wave`, `next`); `TOTAL_WAVES = 15`, `MINIBOSS_EVERY = 5`.
- `RunManager` (autoload): `current_node_id`, `current_completed`, `run_won`; `advance()` — переход к следующему шагу со сменой сцены, `ensure_started()` — первый шаг без смены сцены (главная сцена — `ShopScene`), `complete_current_node(won)`, `get_battle_type/wave()`, `new_run()`.
- Состав врагов — данными в `scripts/data/EnemyWaves.gd` (`build(wave, type, max_squads)`); мини-босс Hellbrute + Chaos Champion, главный босс Chaos Lord.
- Состояние забега: `BattleManager` (`kingdom_tiles`, `player_buildings`, `player_units`, `player_placements`, `pending_cards`, `citadel_hp`), `EconomyManager` (`requisition`, `round_number`, `wins`); сброс — `BattleManager.reset_run()` (зовёт `RunManager.new_run()`).
- Конец забега: `BattleScene._show_run_end(victory)` — «ПОБЕДА» / «ЦИТАДЕЛЬ ПАЛА», кнопка «НОВЫЙ ЗАБЕГ».
- Экран карты с выбором пути и события (`RunMapScene`, `RunEvents`) удалены — описание, полный код и шаги восстановления: `docs/archive/run-map-and-events.md`.

## Перед началом прочитай
`CLAUDE.md`, `scripts/autoload/RunManager.gd`, `scripts/data/RunMapData.gd`, `scripts/data/RunMapNode.gd`, `scripts/data/EnemyWaves.gd`, `scripts/autoload/BattleManager.gd` (`reset_run`), `scenes/battle/BattleScene.gd` (`_on_battle_ended`, `_show_run_end`), `scenes/shop/ShopScene.gd` (`_ready`, `_on_battle_pressed`), `scripts/ui/UITheme.gd`. Для событий — `docs/archive/run-map-and-events.md`.

## Правила
- Переходы между сценами забега — только через `RunManager` (`advance()` / новые методы там же), не `change_scene_to_file` из сцен.
- `round_number` растёт только в `EconomyManager.give_round_income`; `RunMapNode.wave` боевого шага == `round_number`.
- Тип и состав боя — данными (`RunMapData`, `EnemyWaves`), не `if wave == N` по коду.
- Новые экраны (меню, пауза, настройки) — UI кодом через `UITheme`, как ShopScene; `.tscn` — минимальный корень со скриптом.
- Главное меню меняет `run/main_scene` в `project.godot`; при этом `ShopScene` всё равно должна корректно стартовать забег через `RunManager.ensure_started()`.
- Сохранение забега: всё состояние из «Текущее состояние» выше; `UnitData` / `CardData` — Resource, ключи словарей (`player_placements`, `player_buildings`) — объекты, учитывай при сериализации. «Продолжить» — только при наличии сохранения.
- Новый autoload — в `project.godot` и в таблицу `CLAUDE.md`.
- Изменил волны/боссов — прогони `tests/balance_sim.gd` (см. `balance-analyst`).
- После реализации обнови «Игровой цикл» и TDD gaps в `CLAUDE.md` и `CLAUDE_CODE_PROMPT.md`.

## Проверка
- `tests/test_run.gd` проходит (цепочка 30 шагов, мини-босс 5/10, босс 15, расширение на 3/6/9/12/15).
- Полный цикл: старт → магазин → бой → магазин следующей волны; конец забега → новый забег с волны 1, состояние сброшено.
- Рука, королевство, здания, ветераны и HP цитадели переживают переходы; нет двойного дохода и двойного `round_number`.
