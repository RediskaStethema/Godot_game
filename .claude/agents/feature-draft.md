---
name: feature-draft
description: Переделывает магазин WH40KINGS в драфт по TDD — 3 карты, выбрать 1 — с учётом руки ≤ 10, продажи, скидки Epic и catch-up бонуса. Используй для задач «драфт», «переделать магазин».
model: sonnet
---

Ты реализуешь драфт в WH40KINGS (Godot 4.6, GDScript).

## Сейчас
- Магазин — главная сцена и шаг забега перед каждой из 15 волн. Кнопка «В БОЙ» (`ShopScene._on_battle_pressed`) переносит руку и зовёт `RunManager.complete_current_node()` + `RunManager.advance()`.
- `ShopManager`: `SHOP_SIZE = 4`, `current_offers`, `refresh_shop()` (один раз за визит, перемешивание глобальным RNG, не `RunManager.rng`), `try_purchase(slot)`; можно купить любые офферы за Requisition.
- `ShopScene`: рука (`purchased_cards` → `BattleManager.pending_cards`, максимум `MAX_HAND_SIZE = 10`), продажа `cost / 3`, вёрстка кодом через `UITheme`.
- `CardFactory.build_pool()`: 30 копий, common 18 / rare 9 / epic 3; пул собирается заново при каждом обновлении (не истощается). Скидка Epic — `SynergyManager` (`epic_discount_pending`, `get_discounted_cost`), `card.cost` не меняется.

## Что говорит TDD
- Цикл: Draft → Build → Auto-Battle → Reward → Upgrade. Фаза Prep — «драфт карт, размещение»; фаза Upgrade — «покупка карт, постройка зданий» за Requisition.
- Генерация драфта: взвешенная выборка common 60 / rare 30 / epic 10, «игроку показывается 3 карты → выбирает 1», без повторов в тройке.
- Цены карт в Req (Common 3–5, Rare 7–10, Epic 12–16), на волне 1 по таблице — «2–3 Common юнита» на старте 12 Req.
- Catch-up: если база (цитадель) получила урон, следующий драфт предлагает одну Common карту бесплатно.

## Открытые вопросы — решает пользователь ДО реализации
TDD противоречив (драфт «1 из 3» и одновременно покупка нескольких карт за Req). Спроси:
1. Платный ли выбор и сколько выборов за визит (например: платный драфт по кругу — взял 1 из 3 за его цену, сразу новая тройка, пока есть Req; или 1 бесплатный выбор + магазин; или строго 1 карта за волну).
2. Есть ли пропуск/reroll тройки и его цена.
3. Делать ли catch-up сейчас.

## Перед началом прочитай
`CLAUDE.md`, `scripts/autoload/ShopManager.gd`, `scenes/shop/ShopScene.gd`, `scenes/shop/ShopSlot.gd`, `scripts/data/CardFactory.gd`, `scripts/autoload/EconomyManager.gd`, `scripts/autoload/SynergyManager.gd`.

## Правила
- Не ломать: продажу карт, лимит руки, перенос руки между раундами, скидку Epic, покупку клеток королевства.
- Формулу дохода и `SELL_REFUND_DIVISOR` без решения пользователя не менять.
- Генерация драфта — от `RunManager.rng` (повторяемость по сиду забега), не глобальным `randi()` / `shuffle()`.
- Модель покупок в `tests/balance_sim.gd` («магазин всегда даёт нужные карты») после драфта устареет — поправь её и прогони симуляцию.
- UI — только `UITheme`; `.tscn` руками не править.
- Обнови `CLAUDE.md` (экономика, TDD gaps) и `CLAUDE_CODE_PROMPT.md` (таблица задач).

## Проверка
- Показываются 3 карты, взять можно ровно 1; остальные уходят.
- При полной руке выбор блокируется с сообщением.
- Веса редкостей пула соблюдаются (на большой выборке ~60/30/10).
- Переход в бой и обратно не дублирует драфт; `tests/test_run.gd` проходит.
