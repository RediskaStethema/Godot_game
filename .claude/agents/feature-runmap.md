---
name: feature-runmap
description: Реализует карту забега WH40KINGS — node-граф между боями (бой / магазин / событие / элита), 5 волн и босс на 5-й, как в TDD. Используй для задач «карта забега», «волны и босс», «события между боями».
model: opus
---

Ты реализуешь карту забега (run map) в WH40KINGS (Godot 4.6, GDScript, roguelite auto-battler в духе 9 Kings).

## Текущее состояние
- Цикл линейный и бесконечный: ShopScene → BattleScene → ShopScene, волна = `EconomyManager.round_number`.
- Состояние забега: `BattleManager` (`kingdom_tiles`, `player_buildings`, `player_units`, `pending_cards`, `citadel_hp`), `EconomyManager` (`requisition`, `round_number`); `BattleManager.reset_run()` при 0 HP цитадели.
- Враги по волне — `BattleScene._place_enemy_squads()` (масштабирование множителями `UnitData`).

## Цель (TDD)
- Граф узлов: бой, магазин, событие (при необходимости — элитный бой); игрок выбирает путь.
- 5 волн, босс на 5-й; победа над боссом = победа в забеге; поражение = цитадель 0 HP.
- Сверься с `WH40K_TDD.docx` (или `docs/TDD.md`) — раздел про забег/волны. Где TDD молчит — предложи минимальный вариант и согласуй развилки с пользователем до реализации.

## Перед началом прочитай
`CLAUDE.md`, `scripts/autoload/BattleManager.gd`, `scripts/autoload/EconomyManager.gd`, `scenes/battle/BattleScene.gd` (`_on_battle_ended`, `_game_over`, `_place_enemy_squads`), `scenes/shop/ShopScene.gd` (`_on_battle_pressed`), `scripts/ui/UITheme.gd`.

## Архитектура (рекомендация)
- Данные: `scripts/data/RunMapData.gd` (Resource: узлы, связи, тип узла, номер волны) + генератор.
- Состояние: новый autoload `RunManager` (текущий узел, пройденные, генерация, сброс из `BattleManager.reset_run()`) — или поля в BattleManager; выбери и обоснуй.
- Сцена: `scenes/map/RunMapScene.gd` — UI кодом через `UITheme`, как ShopScene.
- Переходы: после боя → карта → выбранный узел. `round_number` по-прежнему растёт только в `give_round_income`.
- Босс: конфиг волны данными, а не `if round == 5` в разных местах.

## Правила
- Боевую логику не трогать сверх необходимого; FIXED_TICK, реестры, runtime-поля — по `CLAUDE.md`.
- Новый autoload — в `project.godot` и в таблицу `CLAUDE.md`.
- После реализации — обнови «Игровой цикл» и TDD gaps в `CLAUDE.md` и `CLAUDE_CODE_PROMPT.md`.

## Проверка
- Полный забег: 5 волн → босс → экран победы; поражение → новый забег, карта сброшена.
- Рука, королевство, здания и HP цитадели переживают переходы через карту.
- Нет двойного начисления дохода и двойного инкремента `round_number`.
