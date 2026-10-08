# SKILL: Soldier FSM (расширенная)

## Когда использовать
Когда нужно добавить/изменить состояния FSM солдата, реализовать новое состояние, добавить статус-эффекты.

## Архитектура FSM

### Enum состояний (TDD-целевой)
```gdscript
enum State {
    IDLE, MOVE, CHASE, ATTACK,
    CASTING, STUNNED, KNOCKBACK, RETREATING, DEAD
}
```

### Текущая реализация (Soldier.gd)
Сейчас: IDLE / MARCH / ATTACK / DEAD  
MARCH нужно переименовать в MOVE, добавить CHASE (цель есть, но далеко), CASTING, STUNNED, KNOCKBACK, RETREATING.

### Правила перехода состояний
```
IDLE → MOVE         нет цели, есть путь вперёд
MOVE → CHASE        цель видна, но вне дальности атаки
MOVE → IDLE         достигнут конец пути, цели нет
CHASE → ATTACK      цель в дальности атаки (data.attack_range тайлов)
ATTACK → CHASE      цель вышла из дальности
ATTACK → CASTING    есть способность, cast_time > 0
CASTING → ATTACK    cast_time истёк
ANY → STUNNED       apply_stun(duration) вызван извне
STUNNED → prev      stun_timer <= 0
ANY → KNOCKBACK     apply_knockback(direction, force) вызван
KNOCKBACK → CHASE   скорость затухла до 0
ANY → RETREATING    current_hp / data.hp < data.retreat_hp_threshold
RETREATING → DEAD   hp <= 0
ANY → DEAD          hp <= 0 (из любого состояния через take_damage)
```

### Обязательные поля в Soldier.gd
```gdscript
var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var stun_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var status_effects: Dictionary = {
    "poisoned": false,
    "burning": false,
    "empowered": false,
    "marked_chaos": false,
    "in_synapse": false,
}
```

### Паттерн transition_to
```gdscript
func transition_to(new_state: State) -> void:
    previous_state = current_state
    current_state = new_state
    _on_state_enter(new_state)

func _on_state_enter(state: State) -> void:
    match state:
        State.DEAD:
            emit_signal("died")
            # остановить анимации, спрятать спрайт или проиграть death anim
        State.STUNNED:
            pass  # visual stun effect
        State.RETREATING:
            pass  # flip sprite direction
```

### Использование FIXED_TICK
FSM тикает через `tick(delta: float)` — вызывается из BattleManager._battle_tick().  
НЕ использовать `_process` или `_physics_process` для боевой логики.

```gdscript
func tick(delta: float) -> void:
    _apply_status_effects(delta)
    match current_state:
        State.IDLE:       _state_idle(delta)
        State.MOVE:       _state_move(delta)
        State.CHASE:      _state_chase(delta)
        State.ATTACK:     _state_attack(delta)
        State.CASTING:    _state_casting(delta)
        State.STUNNED:    _state_stunned(delta)
        State.KNOCKBACK:  _state_knockback(delta)
        State.RETREATING: _state_retreating(delta)
        State.DEAD:       pass
```

### Статус-эффекты
Применяются поверх FSM, не заменяют его:
```gdscript
func _apply_status_effects(delta: float) -> void:
    if status_effects["poisoned"]:
        _poison_timer -= delta
        if _poison_timer <= 0.0:
            take_damage(data.hp * 0.02)  # 2% hp per tick
            _poison_timer = 0.5
    if status_effects["burning"]:
        take_damage(data.damage * 0.1 * delta)
```

## Что НЕ делать
- Не добавлять боевую логику в `_process()` — только в `tick()`
- Не читать `delta` из `_physics_process` для урона/движения
- Не вызывать `transition_to(DEAD)` без проверки `current_state != State.DEAD`
