# SKILL: Система экономики (EconomyManager)

## Когда использовать
Когда нужно изменить формулу дохода, добавить Salvage, настроить стоимость карт, реализовать catch-up механику.

## TDD-спецификация экономики

### Ресурсы
- **Requisition (Req)** — основная валюта, тратится в магазине
- **Salvage** — вторичная валюта (из разобранных/проданных карт), кап = 5

### Формула дохода за раунд
```gdscript
func calculate_wave_income(wave: int, bonuses: int) -> int:
    var base = INCOME_BASE + (wave * INCOME_PER_WAVE)  # 10 + wave*2
    return base + min(bonuses, INCOME_CAP_BONUS)       # bonuses cap = 8
```

Пример: волна 3 = 10 + 6 = 16 Req базово. С синергиями максимум +8 = 24 Req.

### Константы (EconomyManager.gd)
```gdscript
const SALVAGE_CAP: int = 5
const INCOME_BASE: int = 10
const INCOME_PER_WAVE: int = 2
const INCOME_CAP_BONUS: int = 8
```

### Текущее состояние (НЕ соответствует TDD)
Сейчас в `give_round_income(won: bool)` используется фиксированный доход 6 Req.  
Нужно заменить на `calculate_wave_income(round_number, synergy_bonuses)`.

### Стоимость карт по редкости
| Редкость | Стоимость |
|---|---|
| Common | 3–5 Req |
| Rare | 7–10 Req |
| Epic | 12–16 Req |

### Лимит юнитов
```gdscript
# В ShopScene.gd — уже реализовано корректно
max_units = 9 + (EconomyManager.round_number / 3) * 3
max_units = min(max_units, 18)
```

### Catch-up механика (TODO)
Если цитадель получила урон в прошлом раунде → следующий драфт предлагает одну Common карту бесплатно.
Реализовать через флаг `BattleManager.citadel_took_damage: bool`.

### Salvage
```gdscript
func add_salvage(amount: int) -> void:
    salvage = min(salvage + amount, SALVAGE_CAP)

func can_afford(req_cost: int, sal_cost: int = 0) -> bool:
    return requisition >= req_cost and salvage >= sal_cost

func spend(req_cost: int, sal_cost: int = 0) -> void:
    assert(can_afford(req_cost, sal_cost))
    requisition -= req_cost
    salvage -= sal_cost
```

## Порядок обновления
1. Добавить `salvage: int = 0` в EconomyManager
2. Заменить `give_round_income` на вызов `calculate_wave_income`
3. Передавать `synergy_bonuses` из SynergyManager (или 0 если не реализовано)
4. Добавить `sell_card(card: CardData)` → `add_salvage(1)` в ShopScene
