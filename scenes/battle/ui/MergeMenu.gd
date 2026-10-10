class_name MergeMenu
extends PanelContainer

# Карта отряда брошена на свой отряд того же типа: выбор «улучшить» (до
# UnitFactory.MAX_SQUAD_LEVEL) или «вылечить». Само действие делает BattleScene
# по сигналу chosen; меню закрывается при выборе или отмене.

signal chosen(card: CardData, squad: Squad, upgrade: bool)
signal closed

var card: CardData
var squad: Squad

# Можно ли что-то сделать картой с этим отрядом (иначе меню не открываем)
static func has_options(target: Squad) -> bool:
	return target.data.can_merge_upgrade() or target.is_wounded()

func setup(merge_card: CardData, target: Squad) -> void:
	card = merge_card
	squad = target
	theme = UITheme.get_theme()
	theme_type_variation = "HudPanel"
	var b = UnitFactory.get_merge_bonuses(squad.data.faction)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(UITheme.make_label("%s — уровень %d/%d" % [squad.data.unit_name,
		squad.data.squad_level, UnitFactory.MAX_SQUAD_LEVEL], "HeaderLabel"))

	var can_upgrade = squad.data.can_merge_upgrade()
	var up_text = "Улучшить: +%d%% урона, +%d%% HP, +%d%% скорострельности" % [
		roundi(b["damage"] * 100), roundi(b["hp"] * 100), roundi(b["attack_speed"] * 100)]
	var up = UITheme.make_button(up_text if can_upgrade else "Улучшить: достигнут максимум", "",
		_choose.bind(true))
	up.disabled = not can_upgrade
	col.add_child(up)

	var wounded = squad.is_wounded()
	var heal_text = "Вылечить: +%d%% HP каждому бойцу" % roundi(b["heal"] * 100)
	if squad.get_missing_count() > 0:
		heal_text += ", вернуть павших: %d" % squad.get_missing_count()
	var heal = UITheme.make_button(heal_text if wounded else "Вылечить: отряд здоров", "",
		_choose.bind(false))
	heal.disabled = not wounded
	col.add_child(heal)

	col.add_child(UITheme.make_button("Отмена", "", close))

# Рядом с точкой экрана (под отрядом), в пределах экрана
func place_near(screen_pos: Vector2) -> void:
	reset_size()
	var pos = screen_pos + Vector2(-size.x / 2.0, 20)
	position = pos.clamp(Vector2.ZERO, get_viewport_rect().size - size)

func close() -> void:
	emit_signal("closed")
	queue_free()

func _choose(upgrade: bool) -> void:
	emit_signal("chosen", card, squad, upgrade)
	close()
