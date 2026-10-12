class_name StatusEffects
extends RefCounted

# Статус-эффекты поверх FSM (TDD, раздел 5): не заменяют состояние бойца,
# а меняют его урон, скорость, лечение или наносят урон со временем.
# Эффект бойца — Soldier.status_effects[имя] = {stacks, power, time, duration, ...}.
# Сила (power) приходит от источника (UnitData.on_hit_status_power, стена),
# стаки множат её. Повторное попадание: +1 стак (до MAX_STACKS), время — заново.
# Ауры (стена) накладывают без стаков — держат 1 стак, пока цель в радиусе.

const POISONED: String = "poisoned"    # урон со временем, лечение по цели слабее (Nurgle)
const BURNING: String = "burning"      # урон со временем, огонь перекидывается на соседа
const EMPOWERED: String = "empowered"  # +урон на время
const SLOWED: String = "slowed"        # −скорость бега и атаки на время

const MAX_STACKS: int = 3
const DOT_TICK: float = 0.5            # урон яда и огня — раз в 0.5 с (TDD: poisoned)
const POISON_HEAL_MULT: float = 0.5    # лечение отравленного — вполовину
const BURN_SPREAD_EVERY: float = 1.0   # раз в секунду огонь ищет соседа
const BURN_SPREAD_RADIUS: float = 45.0 # сосед того же отряда/команды ближе этого
const SLOW_ATTACK_SHARE: float = 0.5   # атака замедляется вдвое слабее бега
const MIN_SPEED_MULT: float = 0.3      # ниже не замедляем, сколько бы стаков ни было

# Цвет точки эффекта под полоской HP
const COLORS = {
	POISONED: Color(0.55, 0.9, 0.3),
	BURNING: Color(1.0, 0.55, 0.15),
	EMPOWERED: Color(1.0, 0.85, 0.35),
	SLOWED: Color(0.45, 0.65, 0.95),
}
const NAMES = {
	POISONED: "Яд",
	BURNING: "Горение",
	EMPOWERED: "Усиление",
	SLOWED: "Замедление",
}

static func is_dot(effect: String) -> bool:
	return effect == POISONED or effect == BURNING
