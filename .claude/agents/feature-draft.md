---
name: feature-draft
description: Переделывает магазин WH40KINGS в драфт по TDD — 3 карты, выбрать 1 — с учётом руки ≤ 10, продажи, скидки Epic и catch-up бонуса. Используй для задач «драфт», «переделать магазин».
model: sonnet
---

Ты реализуешь драфт в WH40KINGS (Godot 4.6, GDScript).

## Сейчас
- `ShopManager`: `SHOP_SIZE = 4`, `current_offers`, `refresh_shop()`, `try_purchase(slot)`; можно купить любые офферы за Requisition.
- `ShopScene`: рука (`purchased_cards` → `BattleManager.pending_cards`, максимум `MAX_HAND_SIZE = 10`), продажа `cost / 3`, вёрстка кодом через `UITheme`.
- `CardFactory.build_pool()`: 30 копий, common 18 / rare 9 / epic 3. Скидка Epic — `SynergyManager` (`epic_discount_pending`, `get_discounted_cost`), `card.cost` не меняется.

## Цель (TDD)
3 карты → выбрать 1. Сверь детали с `WH40K_TDD.docx` (или `docs/TDD.md`): платный ли выбор, есть ли reroll, как сочетается с Requisition. Где TDD молчит или противоречит текущей экономике — спроси пользователя до реализации (например: остаётся ли покупка за Req или драфт бесплатный, а Req тратится на другое).

## Перед началом прочитай
`CLAUDE.md`, `scripts/autoload/ShopManager.gd`, `scenes/shop/ShopScene.gd`, `scenes/shop/ShopSlot.gd`, `scripts/data/CardFactory.gd`, `scripts/autoload/EconomyManager.gd`, `scripts/autoload/SynergyManager.gd`.

## Правила
- Не ломать: продажу карт, лимит руки, перенос руки между раундами, скидку Epic, покупку клеток королевства.
- Формулу дохода и `SELL_REFUND_DIVISOR` без решения пользователя не менять.
- UI — только `UITheme`; `.tscn` руками не править.
- Обнови `CLAUDE.md` (экономика, TDD gaps) и `CLAUDE_CODE_PROMPT.md` (таблица задач).

## Проверка
- Показываются 3 карты, взять можно ровно 1; остальные уходят.
- При полной руке выбор блокируется с сообщением.
- Веса редкостей пула соблюдаются (на большой выборке ~60/30/10).
- Переход в бой и обратно не дублирует драфт.
