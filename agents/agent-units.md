# SUB-AGENT: Add Unit Types

## Роль
Добавить оставшиеся юниты Space Marines из TDD (юниты + карты + способности) так, чтобы они появлялись в магазине и работали в бою.

## Контекст
Игра WH40KINGS, Godot 4. Уже есть (НЕ добавлять повторно):
`tactical_marine`, `assault_marine`, `scout_marine`, `devastator`, `terminator`, `apothecary`, `chaos_marine`.

Нужно добавить 5 юнитов TDD: **Librarian, Chaplain, Land Speeder, Dreadnought, Chapter Master**.

Важно:
- Статы и цены — из TDD (`WH40K_TDD.docx`, «Юниты MVP»). При расхождении с этим файлом прав TDD.
- `attack_range`, `move_speed`, `heal_radius`, `vision_range` — в **пикселях** (melee ≈ 60, ranged 200–320).
- Редкость по цене (TDD): Common 3–5, Rare 7–10, Epic 12–16.
- В бою меняются только runtime-поля Soldier (`max_hp`, `current_damage`, ...). `data.*` не трогать.
- Спрайтов для новых юнитов нет → `sprite_path = "res://assets/sprites/space_marine"` + свой `tint` / `sprite_scale` + `# TODO: свой спрайт`.

## Файлы для чтения
1. `scripts/data/UnitData.gd` — все поля (heal_*, cast_time, tint, sprite_scale, retreat_*)
2. `scripts/data/UnitFactory.gd` — паттерн юнита и `create(id)` с match по id
3. `scripts/data/CardFactory.gd` — паттерн карты и `build_pool()` (веса по редкости)
4. `scripts/battle/Soldier.gd` — FSM: `apply_stun()`, `apply_knockback()`, CASTING, `_tick_support()`
5. `scripts/autoload/SynergyManager.gd` — теги `marine`, `elite` участвуют в синергиях

## Юниты (TDD)

| id | Имя | HP | DMG | Скорость | Теги | Цена | Редкость | Карта: бойцов |
|---|---|---|---|---|---|---|---|---|
| `librarian` | Librarian | 110 | 15 | 75 | marine, psyker, elite | 10 | rare | 1 |
| `chaplain` | Chaplain | 120 | 14 | 75 | marine, melee, support | 8 | rare | 1 |
| `land_speeder` | Land Speeder | 70 | 16 | 160 | marine, vehicle, fast | 9 | rare | 1 |
| `dreadnought` | Dreadnought | 300 | 28 | 45 | marine, vehicle, elite | 14 | epic | 1 |
| `chapter_master` | Chapter Master | 180 | 20 | 70 | marine, elite, commander | 16 | epic | 1 |

Предлагаемые остальные статы (подбирай по балансу):
- Librarian: ranged 220 px, attack_speed 0.6, `cast_time = 0.8`
- Chaplain: melee 60 px, attack_speed 1.0
- Land Speeder: ranged 200 px, attack_speed 1.0, priority `farthest` (налетает на тыл), `retreat_hp_threshold = 0`
- Dreadnought: melee 70 px, attack_speed 0.6, `retreat_hp_threshold = 0`, `sprite_scale ≈ 1.6`
- Chapter Master: melee 60 px, attack_speed 1.0, `retreat_hp_threshold = 0`, `sprite_scale ≈ 1.3`

## Способности (используют уже готовые состояния FSM)
- **Librarian** — псайкер: удар через CASTING (`cast_time > 0`), попадание оглушает цель: `target.apply_stun(1.0)`.
- **Dreadnought** — удар отбрасывает: `target.apply_knockback(target.global_position - global_position, 300.0)`.
- **Chaplain** — аура: союзные `melee` в радиусе получают +урон. Делать как пассив в `Soldier._tick_support()`-подобном методе или через SynergyManager — без изменения `data.*`.
- **Chapter Master** — commander: +10% урона всем союзникам на старте боя (применять к runtime-полям, как синергии).

Способности описывай данными в UnitData (например `on_hit_stun: float`, `on_hit_knockback: float`, `aura_*`), а не через проверки `unit_name` в Soldier.

## Шаги
1. В `UnitFactory.gd` добавь 5 статических методов и 5 веток в `create(id)`.
2. В `CardFactory.gd` добавь 5 карт (`card_type = "squad"`, `unit_factory_id = id`, цена/редкость из таблицы).
3. Добавь карты в `build_pool()`, сохраняя веса TDD: common ~60%, rare ~30%, epic ~10%.
4. Добавь нужные поля способностей в `UnitData.gd` (с дефолтом «выключено»).
5. Реализуй способности в `Soldier.gd` (в `_do_attack()` для on-hit эффектов).
6. Проверь, что Epic-карты получают скидку `SynergyManager.get_discounted_cost()` (elite x2).

## Проверка
- `UnitFactory.create(id)` для каждого id возвращает юнит с правильным `unit_name` (не fallback Tactical).
- Карта каждого юнита: drop на тайл → отряд с нужным числом бойцов.
- Librarian: цель после удара в STUNNED. Dreadnought: цель в KNOCKBACK.
- Бой с новыми юнитами заканчивается (нет вечного боя); Dreadnought/Chapter Master не отступают.
- Лимит юнитов в магазине учитывает новые карты.
- Тест удобно гонять: `Godot_v4.6.2-stable_win64_console.exe --path . -s res://_test.gd` (скрипт `extends SceneTree`, autoload'ы брать через `root.get_node("...")`, тестовый файл удалить после). Для проверок с сеткой — без `--headless` (в headless окно 64×64).

## Что НЕ трогать
- Существующие юниты и их статы
- `SquadRegistry` / `SoldierRegistry` API
- `GameConstants.FIXED_TICK`
- Логику FSM-переходов (только вызывать `apply_stun` / `apply_knockback`)
