class_name OcclusionFader
extends Node

# Постройки (здания, цитадель) становятся полупрозрачными, пока за ними стоит
# боец — иначе y-sort прячет его целиком. Боец «за» постройкой: он выше на
# экране (меньше y — рисуется раньше) и его спрайт пересекает область постройки.
# Только визуал: опрос REFRESH_INTERVAL раз в секунду, альфа плавно тянется к
# цели каждый кадр. Гасится self_modulate — дочерние узлы (HP-бар цитадели) яркие.
# Новая постройка подхватывается сама, если у неё есть get_occlusion_rect().
# Только на расстановке (решение пользователя): в бою BattleScene выключает
# enabled — постройки плавно возвращаются к полной непрозрачности.

const FADE_ALPHA: float = 0.35
const FADE_SPEED: float = 4.0            # единиц альфы в секунду
const REFRESH_INTERVAL: float = 0.1
const SOLDIER_HALF_WIDTH: float = 18.0   # полуширина спрайта бойца, px мира

var enabled: bool = true
var _targets: Dictionary = {}   # постройка → целевая альфа
var _refresh_left: float = 0.0

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		_update_targets()
	_apply_fade(delta)

func _occluders() -> Array:
	var list: Array = []
	for b in BattleManager.buildings:
		if is_instance_valid(b):
			list.append(b)
	if BattleManager.has_citadel():
		list.append(BattleManager.citadel)
	return list

func _update_targets() -> void:
	_targets.clear()
	var soldiers = SoldierRegistry.get_all_alive_soldiers()
	for occ in _occluders():
		if occ.has_method("get_occlusion_rect"):
			_targets[occ] = FADE_ALPHA if enabled and _hides_anyone(occ, soldiers) else 1.0

func _hides_anyone(occ: Node2D, soldiers: Array) -> bool:
	var area: Rect2 = occ.get_occlusion_rect()
	var base_y = occ.global_position.y
	for s in soldiers:
		if s.global_position.y >= base_y or not s.is_visible_in_tree():
			continue
		var k = s.data.sprite_scale
		var h = Soldier.TARGET_SPRITE_HEIGHT * k
		var w = SOLDIER_HALF_WIDTH * k
		if area.intersects(Rect2(s.global_position - Vector2(w, h), Vector2(w * 2.0, h))):
			return true
	return false

func _apply_fade(delta: float) -> void:
	for occ in _targets:
		if not is_instance_valid(occ):
			continue
		var target: float = _targets[occ]
		if not is_equal_approx(occ.self_modulate.a, target):
			occ.self_modulate.a = move_toward(occ.self_modulate.a, target, FADE_SPEED * delta)
