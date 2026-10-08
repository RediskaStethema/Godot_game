# SKILL: UnitFactory — добавление новых юнитов

## Когда использовать
Когда нужно добавить нового юнита, изменить статы существующего, добавить новую фракцию.

## MVP юниты по TDD (Space Marines)

| ID | Имя | HP | Damage | Speed | Range | Rarity | Tags |
|---|---|---|---|---|---|---|---|
| tactical_marine | Tactical Marine | 100 | 10 | 80 | 1.5 | common | [marine, ranged] |
| assault_marine | Assault Marine | 80 | 18 | 120 | 0.8 | common | [marine, melee, jump] |
| devastator | Devastator | 120 | 25 | 50 | 3.0 | rare | [marine, ranged, heavy] |
| scout_marine | Scout Marine | 60 | 8 | 140 | 1.5 | common | [marine, ranged, scout] |
| terminator | Terminator | 250 | 30 | 40 | 1.0 | epic | [marine, melee, elite] |
| apothecary | Apothecary | 80 | 5 | 80 | 0.5 | rare | [marine, support, heal] |
| librarian | Librarian | 90 | 20 | 70 | 2.0 | epic | [marine, psyker, ranged] |
| chaplain | Chaplain | 120 | 15 | 80 | 1.0 | rare | [marine, melee, inspire] |
| dreadnought | Dreadnought | 400 | 40 | 30 | 1.5 | epic | [marine, melee, vehicle] |
| land_speeder | Land Speeder | 150 | 20 | 160 | 2.0 | rare | [marine, ranged, vehicle] |

| Chaos | Chaos Marine | 110 | 12 | 75 | 1.5 | common | [chaos, ranged] |

## Паттерн добавления юнита

```gdscript
# В UnitFactory.gd — добавить статический метод:
static func devastator() -> UnitData:
    var data = UnitData.new()
    data.unit_name = "Devastator"
    data.faction = "space_marines"
    data.tags = ["marine", "ranged", "heavy"]
    data.hp = 120.0
    data.damage = 25.0
    data.attack_speed = 0.6    # медленнее стреляет
    data.attack_range = 3.0    # но дальше достаёт
    data.move_speed = 50.0
    data.cost = 8
    data.rarity = "rare"
    data.sprite_path = "res://assets/sprites/units/devastator/"
    return data
```

## Паттерн добавления карты (CardData)

```gdscript
# В CardFactory.gd или как Resource .tres файл:
var card = CardData.new()
card.card_name = "Devastator Squad"
card.card_type = "squad"
card.unit_factory_id = "devastator"
card.unit_count = 3
card.cost = 8
card.rarity = "rare"
card.description = "Тяжёлая поддержка. Дальность 3 тайла."
```

## UnitData — полный список полей (TDD)
```gdscript
@export var unit_name: String = ""
@export var faction: String = ""
@export var tags: Array[String] = []
@export var hp: float = 100.0
@export var damage: float = 10.0
@export var attack_speed: float = 1.0
@export var attack_range: float = 1.5
@export var move_speed: float = 80.0
@export var cast_time: float = 0.0          # > 0 → юнит использует CASTING
@export var is_interruptible: bool = true
@export var retreat_hp_threshold: float = 0.15  # < 15% HP → RETREATING
@export var has_reanimation: bool = false   # Necron mechanic
@export var reanimation_chance: float = 0.0
@export var synapse_dependent: bool = false # Tyranid mechanic
@export var cost: int = 5
@export var rarity: String = "common"
@export var sprite_path: String = ""
# Runtime (не @export):
var current_hp_saved: float = 0.0          # для передачи выживших между раундами
```

## Приоритеты добавления
1. scout_marine (common, быстрый — хорошо для обучения игрока)
2. devastator (rare — сразу даёт тактическую глубину)
3. terminator (epic — rare endgame unit)
4. apothecary (support, heal — учит синергиям)

## Что НЕ делать
- Не хардкодить статы прямо в BattleScene или Squad — только через UnitFactory
- Не создавать UnitData в `_ready()` сцены — только в UnitFactory
- Sprite path должен указывать на папку (для динамической загрузки анимаций)
