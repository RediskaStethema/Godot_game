# SUB-AGENT: Expand Soldier FSM

## Роль
Ты — разработчик Godot 4 / GDScript. Твоя задача: расширить FSM солдата с 4 до 9 состояний в файле `scripts/battle/Soldier.gd`.

## Контекст проекта
Игра WH40KINGS — изометрический auto-battler на Godot 4. Солдаты тикают через `tick(delta)` из BattleManager (FIXED_TICK=0.1). НЕ использовать `_process` для боевой логики.

Сейчас в Soldier.gd:
```gdscript
enum State { IDLE, MARCH, ATTACK, DEAD }
```

Нужно:
```gdscript
enum State { IDLE, MOVE, CHASE, ATTACK, CASTING, STUNNED, KNOCKBACK, RETREATING, DEAD }
```

## Шаги

1. Прочитай `scripts/battle/Soldier.gd` полностью
2. Прочитай `scripts/utils/GameConstants.gd` (FIXED_TICK, TEAM_*)
3. Прочитай `scripts/autoload/SoldierRegistry.gd` (как находить врагов)

4. Переименуй MARCH → MOVE везде в файле
5. Добавь поля:
```gdscript
var previous_state: State = State.IDLE
var stun_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
```

6. Реализуй `transition_to(new_state: State)`:
```gdscript
func transition_to(new_state: State) -> void:
    if current_state == new_state:
        return
    previous_state = current_state
    current_state = new_state
    _on_state_enter(new_state)
```

7. Реализуй все новые _state_* функции:
   - `_state_move(delta)` — движется вперёд к врагам, если цель видна → CHASE
   - `_state_chase(delta)` — преследует конкретного врага; если в дальности → ATTACK
   - `_state_stunned(delta)` — stun_timer -= delta; когда <= 0 → transition_to(previous_state)
   - `_state_knockback(delta)` — knockback_velocity затухает; когда ~0 → CHASE
   - `_state_retreating(delta)` — движется НАЗАД (от врагов); если hp > threshold → CHASE

8. Добавь публичные методы:
```gdscript
func apply_stun(duration: float) -> void:
    stun_timer = duration
    transition_to(State.STUNNED)

func apply_knockback(direction: Vector2, force: float) -> void:
    knockback_velocity = direction.normalized() * force
    transition_to(State.KNOCKBACK)
```

9. В `take_damage()` добавь проверку retreat:
```gdscript
if current_hp / data.hp < data.retreat_hp_threshold and current_state != State.DEAD:
    transition_to(State.RETREATING)
```

## Проверка
- Запусти игру, начни бой — солдаты должны двигаться и атаковать без крашей
- Проверь что `transition_to(DEAD)` не вызывается повторно (guard: `if current_state == State.DEAD: return`)
- Убедись что CASTING используется только если `data.cast_time > 0`

## Что НЕ трогать
- Squad.gd — не менять
- BattleManager.gd — не менять
- SquadRegistry / SoldierRegistry API — только читать
