# SUB-AGENT: Economy

## Роль
Развивать экономику WH40KINGS поверх уже готового EconomyManager (бонусы дохода, Salvage, баланс цен).

## Контекст — уже реализовано, НЕ переписывать
```gdscript
# scripts/autoload/EconomyManager.gd
STARTING_REQUISITION = 12          # не 0: иначе в 1-м раунде нечего купить
calculate_wave_income(wave, bonuses) = 10 + wave*2 + clamp(bonuses, 0, 8)
give_round_income(won, bonuses) -> int   # поражение/ничья: половина базы без бонусов (LOSS_INCOME_MULT)
                                          # единственное место, где растёт round_number
try_spend(req, sal = 0) -> bool, can_afford(req, sal = 0) -> bool
get_sell_price(card) = card.cost / 3     # SELL_REFUND_DIVISOR = 3 — решение пользователя (TDD: ×0.5)
sell_card(card) -> int                   # начисляет выручку; убрать карту из руки — дело вызывающего
add_salvage(amount)                      # кап 5; Salvage — P1, источников нет
сигналы: requisition_changed, salvage_changed, income_received
```

Рука и магазин:
- Рука = `BattleManager.pending_cards` (в магазине — `ShopScene.purchased_cards`), максимум `BattleManager.MAX_HAND_SIZE = 10`.
- Невыложенные карты переносятся между раундами (после боя рука не очищается).
- Продажа — кнопка «Продать +N» на каждой карте руки в магазине (`ShopScene._sell_card`). Продавать можно любые карты, включая улучшения (они применяются только при броске на отряд).
- Скидка Epic (elite x2) списывается при покупке, но `card.cost` остаётся изначальной — от неё считается цена продажи.

Бонусы к доходу (`BattleScene._calculate_victory_bonuses()`):
- +5 победа без потерь (`BONUS_FLAWLESS`)
- +2 за каждые 3 marine (`SynergyManager.income_bonus`)
- +3 за элитного врага (`BONUS_ELITE_KILL`) — константа есть, элитных врагов пока нет
- Кап +8 применяет EconomyManager.

## Возможные следующие задачи
1. **Элитные враги** → бонус +3 Req за убийство (нужен флаг элиты в UnitData врага и подсчёт в бою).
2. **Plasma Generatorium** (здание TDD): +2 Req/волна — добавить в бонусы.
3. **Catch-up бонус TDD**: если база получила урон — следующий драфт предлагает одну Common карту бесплатно (после Цитадели).
4. **Salvage (P1)**: источники и траты для Tier 3 / реликвий.

## Файлы для чтения
1. `scripts/autoload/EconomyManager.gd`
2. `scripts/autoload/ShopManager.gd` — `try_purchase(slot)`, `current_offers`
3. `scenes/shop/ShopScene.gd` — рука, продажа, лимит руки (лимита армии нет)
4. `scenes/battle/BattleScene.gd` — `_on_battle_ended`, `_calculate_victory_bonuses`

## Проверка
- Доход после победы в 1-й волне = `12 + min(бонусы, 8)`.
- `round_number` растёт ровно на 1 за бой.
- Лимит руки 10 не обходится (купил → продал → купил).
- Продажа: Tactical (5) → +1, Terminator (10) → +3.

## Что НЕ трогать
- Формулу дохода, `STARTING_REQUISITION`, `LOSS_INCOME_MULT`, `SELL_REFUND_DIVISOR` — без явного решения пользователя
- `round_number` — меняется только в `give_round_income`
- Логику генерации офферов в ShopManager
- `SynergyManager` — только читать `income_bonus`
