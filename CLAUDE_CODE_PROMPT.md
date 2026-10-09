# Claude Code Prompt — WH40KINGS продолжение

---

## КОНТЕКСТ ПРОЕКТА

**WH40KINGS** — 2D изометрический roguelite auto-battler, Godot 4, сеттинг Warhammer 40K.

**Что уже работает:**
- FSM солдата: все 9 состояний (IDLE/MOVE/CHASE/ATTACK/CASTING/STUNNED/KNOCKBACK/RETREATING/DEAD)
- Экономика по TDD: `10 + wave×2 + min(bonuses, 8)`, старт 12 Req
- Юниты: все 10 Marines из TDD (Tactical, Assault, Scout, Devastator, Terminator, Librarian, Chaplain, Land Speeder, Dreadnought, Chapter Master) + Apothecary (не из TDD) + Chaos Marine; UnitFactory.create(id)
- Способности данными в UnitData: on_hit_stun (Librarian), on_hit_knockback (Dreadnought), aura_* (Chaplain), commander_damage_bonus (Chapter Master)
- CardFactory: 16 карт, все в пуле магазина; здания — Building.gd (турель, стена)
- SynergyManager: 3 MVP синергии, income_bonus, epic_discount_pending
- Salvage API (без источников — P1)
- Поле как в 9 Kings: общая платформа, королевство сверху слева, враг приходит по диагонали снизу справа; отряды стоят шеренгами вдоль осей изометрии и маршируют строем (MOVE держит formation_offset)
- UI: тема `scripts/ui/UITheme.gd`, вёрстка кодом, stretch canvas_items; спрайты нормализованы по высоте, HP-бары, y-sort
- occupied_tiles_player / occupied_tiles_enemy (раздельные словари)
- Лимита армии нет, только рука ≤ 10 карт
- Королевство 3×3 → 4×4: каждую 3-ю волну (3, 6, 9, 12, 15) при расстановке соседние клетки покупаются кликом (6 + 2×куплено Req); BattleManager.kingdom_tiles
- Враги скрыты до «В БОЙ»
- Цитадель (Citadel.gd): HP 1000 на забег; при гибели армии — штурм: враги бьют её атаками, она стреляет по площади; отбилась — победа, 0 HP — новый забег
- Поле из пиксельного тайлсета assets/sprites/map_sprite (TerrainTiles.gd)
- Забег линейный (RunManager autoload, ShopScene — главная сцена): магазин → бой × 15 волн, игрок путь не выбирает; мини-босс Hellbrute + элита на 5 и 10, главный босс Chaos Lord на 15; победа над боссом / гибель цитадели → экран конца забега → новый забег. Враги — данными в EnemyWaves. Старая карта с выбором пути и события — в docs/archive/run-map-and-events.md

**Критические правила кода:**
1. Боевая логика — только через `tick(delta)` из BattleManager (FIXED_TICK=0.1), НЕ в `_process`
2. IsoGridRenderer: `occupied_tiles_player` и `occupied_tiles_enemy` — не `occupied_tiles`
3. `_is_tile_occupied()` проверяет только `occupied_tiles_player`
4. Спавн: сначала `_place_enemy_squads()`, потом `_place_player_squads()`
5. В конце боя: `SquadRegistry.clear()` и `SoldierRegistry.clear()`
6. Runtime-поля солдата: `max_hp`, `current_damage`, `current_move_speed`, `current_attack_range`, `current_attack_speed`, `current_heal_per_second` — не трогать `data.*` напрямую
7. При расхождении агента с TDD (`WH40K_TDD.docx`) — приоритет у TDD; дальности и скорости в пикселях, не в тайлах

---

## ШАГ 0 — АНАЛИЗ ПРОЕКТА (выполнить ПЕРВЫМ в каждой сессии)

Прочитай CLAUDE.md и ключевые файлы:

```
CLAUDE.md                               ← начни здесь
scripts/autoload/BattleManager.gd
scripts/autoload/EconomyManager.gd
scripts/autoload/SynergyManager.gd
scripts/battle/Soldier.gd
scripts/data/UnitFactory.gd
scripts/data/CardFactory.gd
scenes/battle/BattleScene.gd
scenes/shop/ShopScene.gd
```

Выведи отчёт:

```
=== АНАЛИЗ ПРОЕКТА ===
FSM состояния: [enum State из Soldier.gd]
Юниты в UnitFactory: [список create() ID]
Карты в CardFactory: [список]
EconomyManager.give_round_income: [формула]
Salvage источники: [есть / нет]
Синергии в SynergyManager: [список]
agents/ в проекте: [список файлов]
TODO/pass в коде: [список]
Известные баги: [список]
```

---

## ШАГ 1 — ВЫБОР АГЕНТА

Настоящие субагенты Claude Code — в `.claude/agents/` (вызываются через Agent tool, свой контекст):

| Агент | Когда |
|---|---|
| `godot-verifier` | после любого изменения кода и перед коммитом — парсинг, запуск, сценарии |
| `rules-reviewer` | перед коммитом — diff против правил проекта |
| `balance-analyst` | новые юниты/карты/волны/босс, вопросы баланса |
| `content-cards` | юниты, карты, здания, враги (задача 6) |
| `feature-run` | структура забега (15 волн, мини-боссы, босс), главное меню, пауза, сохранение, события |
| `feature-draft` | драфт 3 → 1 (задача 7) |
| `docs-keeper` | после фичи — синхронизация CLAUDE.md и этого файла |

Папка `docs/task-briefs/` — справочные инструкции по прошлым задачам (не субагенты, только для чтения).

### Правила

```
Задача совпадает с агентом     → вызови субагента из .claude/agents/ через Agent tool
Задача частично совпадает      → вызови ближайшего агента, дополни промпт под задачу
Задача не совпадает ни с кем   → создай новый .claude/agents/<тема>.md (шаблон ниже)
```

### Когда создавать нового агента

Создавай если задача:
- затрагивает 3+ файла
- может повториться в будущих сессиях
- изолирована и не ломает другие системы напрямую

НЕ создавай для hotfix одной строки, переименования, изменения одной константы.

### Шаблон нового агента

```markdown
---
name: <тема>
description: Что делает агент и когда его вызывать (по этому тексту агент выбирается автоматически).
model: sonnet
---

Одно предложение — роль агента.

## Контекст
Игра WH40KINGS, Godot 4. Что важно знать для этой задачи.

## Файлы для чтения
1. путь/к/файлу.gd — зачем читать

## Шаги
1. Конкретное действие
2. Конкретное действие с примером кода если нужно

## Проверка
- Что проверить после выполнения

## Что НЕ трогать
- Список файлов/API которые нельзя менять
```

---

## ЗАДАЧА НА ЭТУ СЕССИЮ

Если нет конкретной задачи от пользователя — выбери первую незакрытую по приоритету:

| Приоритет | Задача | Агент |
|---|---|---|
| ~~1~~ | ~~Добавить 5 оставшихся юнитов TDD (Librarian, Chaplain, Land Speeder, Dreadnought, Chapter Master)~~ ✅ | content-cards |
| ~~2~~ | ~~Реализовать bolter_turret; вернуть здания в `build_pool()`~~ ✅ (+ Fortress Wall) | content-cards |
| ~~3~~ | ~~Реализовать Цитадель с HP (враги атакуют если нет игрока)~~ ✅ | — |
| ~~4~~ | ~~Продажа карт за 1/3 цены, рука до 10 карт, карты не пропадают после боя~~ ✅ | — |
| ~~5~~ | ~~Забег: 15 волн подряд, магазин перед каждой, мини-босс на 5/10, босс на 15~~ ✅ (граф с выбором пути убран по решению пользователя) | feature-run |
| 6 | Расширить карты до 20 MVP (10 Unit + 5 Buff + 3 Building + 2 Event) | content-cards |
| 7 | Драфт по TDD: 3 карты → выбрать 1 (сейчас 4 оффера, покупка любых) | feature-draft |

---

## ШАГ 2 — ТЕСТИРОВАНИЕ (после каждого изменения)

### Статический анализ

```
[ ] Нет обращения к occupied_tiles (старое имя)
[ ] Нет боевой логики в _process / _physics_process
[ ] transition_to() защищён: if current_state == new_state: return
[ ] Нет прямых изменений data.hp / data.damage — только runtime-поля
[ ] BattleManager.player_placements очищается при поражении и ничьей
[ ] SquadRegistry.clear() и SoldierRegistry.clear() в конце боя
[ ] Все новые сигналы объявлены через signal до использования
[ ] Таймеры сравниваются через TIMER_EPSILON, не == 0
```

### Регрессионный чеклист

```
[ ] Игра запускается без ошибок в консоли
[ ] Карту можно купить в магазине
[ ] Карту можно перетащить на тайл
[ ] Бой запускается и заканчивается без зависания
[ ] После боя — переход в ShopScene
[ ] Выжившие на своих тайлах в следующем раунде
[ ] Нет дублирования отрядов на одном тайле
[ ] Нет бесконечного боя
[ ] Доход после победы = 10 + wave×2 + бонусы (проверь в консоли)
```

### Сценарий: первый раунд

```
1. Запуск → ShopScene, баланс 12 Req
2. Купить Tactical Squad (5 Req) + Scout Squad (3 Req) → обе на bench
   (одной карты на 1-ю волну не хватает: 0/5 побед; две карты — 5/5)
3. Drag на тайл → отряд заспавнен, тайл занят
4. Drag на тот же тайл → "тайл занят", нет дублирования
5. Start Battle → солдаты двигаются (MOVE → CHASE → ATTACK)
6. Победа → доход = 12 + min(бонусы, 8)
   бонусы: +5 без потерь, +2 за каждые 3 marine (Tactical 3 + Scout 4 = 7 marine → +4)
   пример: Tactical + Scout без потерь → 12 + min(5+4, 8) = 20 Req
   только Tactical (3 marine) без потерь → 12 + 5 + 2 = 19 Req
7. ShopScene → выжившие на тайлах
```

### Сценарий: FSM переходы

```
1. Солдат создан → IDLE
2. start_march() → MOVE
3. Враг в зоне видимости → CHASE
4. Враг в дальности атаки → ATTACK
5. Враг убит → CHASE или MOVE
6. apply_stun(1.0) → STUNNED → через 1с → previous_state
7. HP < 15% → RETREATING (один раз за бой)
8. HP = 0 → DEAD, сигнал died ровно один раз
```

### Отладочные принты

```gdscript
# Drop карты:
print("Drop: ", screen_pos, " → тайл ", tile, " valid=", iso_grid.is_valid_tile(tile))
print("Занятые (игрок): ", renderer.occupied_tiles_player)

# FSM переходы:
print("[%s] %s → %s" % [data.unit_name, State.keys()[previous_state], State.keys()[new_state]])

# Экономика:
print("Доход волна %d: %d Req (бонусы: %d)" % [round_number, income, bonuses])

# Синергии:
print("Активные синергии: ", SynergyManager.get_active_synergy_names())
```

---

## ЧТО НЕ ТРОГАТЬ

- `SquadRegistry.gd` и `SoldierRegistry.gd` — API стабилен
- `GameConstants.gd` — FIXED_TICK=0.1 неприкосновенно
- `CardData.gd` и `UnitData.gd` — поля не менять без необходимости
- `.tscn` файлы — только через код, не вручную
- `SynergyManager` — только читать income_bonus, не пересчитывать вручную

---

## TDD GAPS (текущие)

| Система | TDD цель | Статус |
|---|---|---|
| FSM | 9 состояний | ✅ |
| Юниты Marines | 10 типов | ✅ 10/10 + Apothecary; у новых юнитов placeholder-спрайты |
| Юниты Chaos | Chaos Marine + variants | Chaos Marine + Champion (элита) + Hellbrute (мини-босс) + Lord (босс) — масштаб статов/тинт, без своих спрайтов |
| Экономика | 10+wave×2+bonuses | ✅ (+3 за элитного врага); catch-up бонус — нет |
| Продажа карт | стоимость × 0.5 Requisition | ✅ 1/3 цены (решение пользователя), рука ≤ 10 карт |
| Salvage | P1: Tier 3 и реликвии | API есть, источников нет (P1 — не MVP) |
| Синергии | TDD MVP пороги | ✅ 3 базовых |
| Здания | Fortress Wall, Plasma Generatorium, Apothecarion | ✅ Fortress Wall (щит цитадели + замедление), Bolter Turret (не из TDD); нет Plasma Generatorium |
| Цитадель | База с HP | ✅ HP 1000, при гибели армии — бой цитадели с врагами, 0 HP — новый забег |
| Карта забега | Node-граф | Линейный забег по решению пользователя (магазин → бой); граф и события — в архиве |
| Карты | 20 MVP карт | 16 (12 squad, 2 building, 2 upgrade); Epic: Dreadnought, Chapter Master |
| Драфт | 3 карты → выбрать 1 | 4 оффера, покупка любых |
| Grid | 8×4 слота | 3×3 → 4×4 покупкой клеток каждую 3-ю волну |
| Волны | 5 + босс на 5-й | 15 волн (решение пользователя): мини-босс на 5/10, Chaos Lord на 15, экраны победы/поражения; баланс черновой |

## ИЗВЕСТНЫЕ БАГИ

- Свои спрайты есть только у space_marine и chaos — остальные юниты различаются тинтом/размером
- Баланс мини-босса/босса (EnemyWaves, UnitFactory.chaos_hellbrute / chaos_lord) не выверен: мини-босс 10 почти сносит цитадель, босс 15 сильнее армии из 36 Tactical — задача для balance-analyst
- Агенты `agent-fsm.md`, `agent-grid-fix.md`, `agent-synergy.md` — выполнены, использовать только как справку
