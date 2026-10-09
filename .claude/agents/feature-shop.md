---
name: feature-shop
description: Магазин WH40KINGS — набор карт перед волной, обновление набора за Req, бесплатные карты (1-я волна, catch-up), продажа, рука ≤ 10, скидка Epic, новые механики покупки. Используй для задач «магазин», «обновление набора», «catch-up бонус», «бесплатная карта».
model: sonnet
---

Ты развиваешь магазин WH40KINGS (Godot 4.6, GDScript).

## Сейчас (решение пользователя вместо драфта TDD «3 → 1»)
- Магазин — главная сцена и шаг забега перед каждой из 15 волн. «В БОЙ» (`ShopScene._on_battle_pressed`) переносит руку в `BattleManager.pending_cards`, зовёт `RunManager.complete_current_node()` + `RunManager.advance()`.
- `ShopManager`: `SHOP_SIZE = 4`; `open_shop()` в `ShopScene._ready` — новый набор, сброс цены обновления, бесплатные карты 1-й волны; `refresh_shop()` — перемешивание от `RunManager.rng`.
- Обновление набора: `try_reroll()` / `get_reroll_cost()` = `REROLL_BASE_COST (5) × REROLL_COST_GROWTH (1.13) ^ rerolls_done`, в каждом новом магазине снова 5.
- Цена к оплате — только `ShopManager.get_price(card)`: бесплатная карта (`free_cards_left`, `FIRST_WAVE_FREE_CARDS = 1` на 1-й волне) → 0, иначе скидка Epic (`SynergyManager.get_discounted_cost`). `card.cost` не меняется — от него считается продажа.
- `ShopScene`: рука (`purchased_cards`, максимум `BattleManager.MAX_HAND_SIZE = 10`), продажа `cost / 3`, кнопка «Обновить · N Req» в заголовке, вёрстка кодом через `UITheme`. `ShopSlot` показывает цену `get_price()` («Взять бесплатно» при 0).
- `CardFactory.build_pool()`: 30 копий, common 18 / rare 9 / epic 3, пул пересобирается при каждом обновлении (не истощается). Враги `chaos_*` в пул не входят.

## Не сделано из TDD
- Catch-up: цитадель получила урон в прошлом бою → в следующем магазине одна Common карта бесплатно. Механика бесплатной карты уже есть (`free_cards_left`), нужен признак урона за бой и ограничение «только Common».

## Перед началом прочитай
`CLAUDE.md`, `scripts/autoload/ShopManager.gd`, `scenes/shop/ShopScene.gd`, `scenes/shop/ShopSlot.gd`, `scripts/data/CardFactory.gd`, `scripts/autoload/EconomyManager.gd`, `scripts/autoload/SynergyManager.gd`.

## Правила
- Не ломать: продажу карт, лимит руки, перенос руки между волнами, скидку Epic, бесплатную карту 1-й волны, покупку клеток королевства.
- Формулу дохода, `SELL_REFUND_DIVISOR`, константы обновления — без решения пользователя не менять.
- Случайность магазина — от `RunManager.rng`, не глобальным `randi()` / `shuffle()`.
- UI — только `UITheme`; `.tscn` руками не править.
- Изменил экономику магазина — поправь модель в `tests/balance_sim.gd` (сейчас: «нужные карты всегда есть», обновления не тратятся) и прогони её.
- Обнови `CLAUDE.md` (экономика, TDD gaps) и `CLAUDE_CODE_PROMPT.md` (таблица задач).

## Проверка
- 1-я волна: первая покупка 0 Req, дальше — полная цена; на 2-й волне бесплатных нет.
- Обновления: 5, 6, 6, 7, 8…; в новом магазине снова 5; без денег — отказ без списания.
- Один сид забега → одинаковые наборы; веса редкостей на большой выборке ~60/30/10.
- При полной руке покупка блокируется с сообщением; `tests/test_run.gd` проходит.
