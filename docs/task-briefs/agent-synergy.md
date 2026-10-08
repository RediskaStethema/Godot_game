# SUB-AGENT: Implement Synergy System

## Роль
Ты — разработчик Godot 4 / GDScript. Твоя задача: реализовать систему синергий на основе тегов юнитов.

## Контекст
Каждый UnitData имеет `tags: Array[String]`. Когда в армии игрока накапливается достаточно юнитов с одинаковым тегом — активируется синергия (бонус к урону, скорости, HP).

## Файлы для чтения
1. `scripts/data/UnitData.gd` — поле tags
2. `scripts/autoload/BattleManager.gd` — `player_units: Array[UnitData]`
3. `scripts/autoload/SoldierRegistry.gd` — активные солдаты

## Архитектура

### Новый файл: `scripts/autoload/SynergyManager.gd`
Добавить как Autoload синглтон.

```gdscript
class_name SynergyManager
extends Node

# Определения синергий: тег → [порог, бонус]
const SYNERGY_DEFINITIONS = {
    "marine": [
        {"threshold": 3, "bonus": {"damage_mult": 1.10}, "name": "Brothers in Arms"},
        {"threshold": 6, "bonus": {"damage_mult": 1.25, "hp_mult": 1.15}, "name": "For the Emperor"},
    ],
    "ranged": [
        {"threshold": 2, "bonus": {"attack_range": 0.5}, "name": "Fire Support"},
        {"threshold": 4, "bonus": {"attack_range": 1.0, "attack_speed_mult": 1.15}, "name": "Volley Fire"},
    ],
    "melee": [
        {"threshold": 2, "bonus": {"damage_mult": 1.15}, "name": "Charge!"},
        {"threshold": 4, "bonus": {"damage_mult": 1.30, "move_speed_mult": 1.20}, "name": "Slaughter"},
    ],
    "elite": [
        {"threshold": 1, "bonus": {"hp_mult": 1.20}, "name": "Veteran"},
    ],
    "support": [
        {"threshold": 1, "bonus": {"heal_per_tick": 0.5}, "name": "Combat Medic"},
    ],
}

# Активные синергии (вычисляются перед боем)
var active_synergies: Array[Dictionary] = []
var total_income_bonus: int = 0

func calculate_synergies(player_units: Array) -> void:
    active_synergies.clear()
    total_income_bonus = 0
    
    # Считаем теги
    var tag_counts: Dictionary = {}
    for unit_data in player_units:
        for tag in unit_data.tags:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
    
    # Проверяем пороги
    for tag in SYNERGY_DEFINITIONS.keys():
        if not tag_counts.has(tag):
            continue
        var count = tag_counts[tag]
        for synergy_def in SYNERGY_DEFINITIONS[tag]:
            if count >= synergy_def["threshold"]:
                active_synergies.append({
                    "tag": tag,
                    "name": synergy_def["name"],
                    "bonus": synergy_def["bonus"],
                    "count": count,
                    "threshold": synergy_def["threshold"],
                })
                total_income_bonus += 2  # каждая синергия даёт +2 Req дохода

func apply_synergies_to_soldiers() -> void:
    # Вызывается после спавна всех солдат, перед боем
    for synergy in active_synergies:
        var bonus = synergy["bonus"]
        for soldier in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER):
            if synergy["tag"] in soldier.data.tags:
                _apply_bonus(soldier, bonus)

func _apply_bonus(soldier, bonus: Dictionary) -> void:
    if bonus.has("damage_mult"):
        soldier.current_damage *= bonus["damage_mult"]
    if bonus.has("hp_mult"):
        soldier.current_max_hp *= bonus["hp_mult"]
        soldier.current_hp = soldier.current_max_hp
    if bonus.has("move_speed_mult"):
        soldier.current_move_speed *= bonus["move_speed_mult"]
    if bonus.has("attack_range"):
        soldier.current_attack_range += bonus["attack_range"]
    if bonus.has("attack_speed_mult"):
        soldier.current_attack_speed *= bonus["attack_speed_mult"]

func get_active_synergy_names() -> Array[String]:
    var names: Array[String] = []
    for s in active_synergies:
        names.append("%s (%d/%d)" % [s["name"], s["count"], s["threshold"]])
    return names
```

## Интеграция в Soldier.gd

Добавь runtime-поля (не из UnitData, а вычисляемые):
```gdscript
var current_damage: float
var current_max_hp: float
var current_hp: float
var current_move_speed: float
var current_attack_range: float
var current_attack_speed: float

func setup(unit_data, team_id, squad, offset):
    data = unit_data
    # Инициализируем из data
    current_damage = data.damage
    current_max_hp = data.hp
    current_hp = data.current_hp_saved if data.current_hp_saved > 0 else data.hp
    current_move_speed = data.move_speed
    current_attack_range = data.attack_range
    current_attack_speed = data.attack_speed
```

## Интеграция в BattleScene.gd

В `_on_start_pressed()` — ПЕРЕД `BattleManager.start_battle()`:
```gdscript
func _on_start_pressed() -> void:
    is_placement_phase = false
    start_button.disabled = true
    
    # Вычислить и применить синергии
    var all_units = BattleManager.player_units.duplicate()
    # Добавить pending_cards единицы тоже
    SynergyManager.calculate_synergies(all_units)
    SynergyManager.apply_synergies_to_soldiers()
    
    for squad in SquadRegistry.get_all_alive_squads():
        squad.start_march()
    
    BattleManager.start_battle()
```

## Интеграция в экономику

В `EconomyManager.give_round_income()`:
```gdscript
func give_round_income(won: bool) -> void:
    var income = calculate_wave_income(round_number, SynergyManager.total_income_bonus)
    ...
```

## UI синергий (опционально, добавить позже)

В BattleScene — Label показывающий активные синергии:
```gdscript
$UI/SynergyLabel.text = "\n".join(SynergyManager.get_active_synergy_names())
```

## Порядок разработки
1. Создать SynergyManager.gd, добавить в AutoLoad
2. Добавить runtime-поля в Soldier.gd
3. Вызвать calculate + apply перед стартом боя
4. Передать total_income_bonus в EconomyManager
5. UI можно оставить на потом

## Что НЕ делать
- Не менять `data.damage` напрямую — только `current_damage`
- Синергии пересчитываются каждый раунд заново, не накапливаются
