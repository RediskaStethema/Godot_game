class_name BuildingFx
extends Node2D

# Эффекты зданий и стены владений кодом (EFFECTS_NEEDED 4.2, 4.10, 8.5, 8.6; решение пользователя 07.11.2026 —
# листы пакета не подошли, рисовать кодом, как полёт купленной карты). Только вид, логику боя не трогает.
#   wave(точка здания, сдвиги к соседям, вид) — начало боя: от здания по осям ромба к клеткам отрядов, на которых
#     сработал эффект, бегут низкие волны света и «впитываются» в клетку — кромка ромба вспыхивает и гаснет.
#     Слой — земля поля (AuraRing.layer): под бойцами и постройками
#   lifesteal(боец) — боец у Чаши крови ударил вплотную и лечится: 2–3 кровавые нити от ног к груди
#   wall_break(родитель, a, b, хаос) — звено стены разбито: камни разлетаются и падают, пыль низко по земле
#   wall_chips(родитель, a, b, хаос) — удар по звену: каменная крошка и пыль брызгами (частый — мелкий)
#   battle_start(слой, a, b, хаос) — «В БОЙ» (8.4): полоса света вдоль передней кромки королевства расходится от
#     середины и гаснет (янтарь; Хаос — огонь)
#   level_down(отряд) — отряд пал целиком и возродился уровнем ниже (2.5): шеврон уровня над ним трескается и
#     осыпается половинками
#   god_sigil(боец, бог) — павший встал бойцом бога у Святилища культа (4.9): под ногами загорается знак бога
#     (эллипс 2:1), от него до пояса — языки света, знак гаснет; он же — благословение и смена бога отряда (4.11)
#   charm(жертва, отряд) — порабощение Король Второго Акта (4.11, 09.11.2026): розовая цепь от поработившего отряда к бойцу
#     натягивается и гаснет, над головой — серп
#   squad_fall(точка, радиус, свой) — отряд пал целиком (09.11.2026): кольцо цвета стороны по земле расходится, пыль
#   rift(точка, радиус) — выход отряда Хаоса на «В БОЙ» (09.11.2026): вертикальный разлом варпа раскрывается,
#     светится и стягивается, искры; бойцы проявляются из него (BattleScene._reveal_enemies)
#   shield_break(боец) — щит бойца (Iron Halo, Кодекс-бастион) кончился (09.11.2026): голубая сфера вспыхивает
#     и разлетается осколками
#   bonus_marks(отряд, виды, задержка) — бонусы перед боем (09.11.2026): над отрядом ряд знаков — синергия,
#     передний / задний ряд, орден / бог, командир; поднимаются и гаснут

const WAVE_TIME: float = 0.55        # с — волна идёт от здания до соседней клетки
const ABSORB_TIME: float = 0.5       # с — кромка клетки соседа гаснет
const WAVE_ARC: float = 0.32         # полуширина фронта волны — доля шага до соседа (по второй оси ромба)
const WAVE_TRAIL: int = 6            # огоньков за фронтом
const TILE_INSET: float = 0.86       # ромб «впитывания» — доля клетки
# Вид волны по building_type: кромка, ядро
const WAVE_LOOKS = {
	"codex_bastion": {"edge": Palette.SHIELD_BLUE, "core": Palette.FROST_PALE},
	"blood_chalice": {"edge": Palette.BLOOD_BRIGHT, "core": Palette.HIT_RED},
	"wolf_totem": {"edge": Palette.FROST, "core": Palette.FROST_PALE},
	"vulkan_forge": {"edge": Palette.FORGE, "core": Palette.FORGE_PALE},
	"plague_cauldron": {"edge": Palette.POISON_DEEP, "core": Palette.POISON},
}

const LIFESTEAL_TIME: float = 0.45
const LIFESTEAL_GAP_MS: int = 450    # не чаще у одного бойца — удары частые
const BREAK_TIME: float = 1.2
const BREAK_STONES: int = 9
const BREAK_DUST: int = 6
const CHIPS_TIME: float = 0.4
const CHIPS_GAP_MS: int = 120        # не чаще у одного звена
const GRAVITY: float = 420.0         # px/с² — камни и крошка
const FADE_TAIL: float = 0.3         # доля времени в конце — гаснет
const DUST_ALPHA: float = 0.3        # пыль приглушённая: светлая и плотная читалась светящимися лужами

const FRONT_TIME: float = 0.9
const FRONT_SPREAD: float = 0.35    # с — полоса расходится от середины до концов
const LEVEL_DOWN_TIME: float = 1.1
const LEVEL_DOWN_CRACK: float = 0.35   # доля времени: шеврон целый, затем трещина и осыпается
const CHEVRON: Vector2 = Vector2(9.0, 5.0)   # полуширина, высота шеврона, px мира
const SIGIL_TIME: float = 1.1
const SIGIL_RADIUS: float = 9.0     # px мира — знак под бойцом ростом Soldier.TARGET_SPRITE_HEIGHT
const SIGIL_STAGGER: float = 0.08   # с — бойцы загораются по очереди

const CHARM_TIME: float = 0.9
const CHARM_LINKS: int = 9
const FALL_TIME: float = 0.9
const RIFT_TIME: float = 0.85
const SHIELD_TIME: float = 0.45
const SHIELD_SHARDS: int = 8
const BONUS_TIME: float = 1.6
const BONUS_GAP: float = 13.0        # px мира между знаками бонусов
# Вид знака бонуса: цвет кромки и ядра
const BONUS_LOOKS = {
	"synergy": [Palette.GOLD, Palette.AMBER_LIGHT],
	"front": [Palette.SHIELD_BLUE, Palette.FROST_PALE],
	"back": [Palette.HIT_RED, Palette.FIRE],
	"chapter": [Palette.GOLD_DIM, Palette.GOLD_BRIGHT],
	"commander": [Palette.GOLD_BRIGHT, Palette.STAR_AMBER],
}

static var _rng := RandomNumberGenerator.new()   # своя случайность: randf — общая с боем (вид не должен сдвигать
# случайность боя — lifesteal и стена зовутся из боевой логики; ревью 09.11.2026)

var kind := ""
var look: Dictionary = {}
var targets: Array = []        # волна: сдвиги к центрам соседних клеток
var follow: Node2D = null      # нити: за бойцом
var chest := 15.0
var parts: Array = []          # камни / крошка / капли: {p, v, size, col, ground, delay}
var puffs: Array = []          # пыль: {p, r0, r1, col}
var duration := 1.0
var a_pt := Vector2.ZERO       # полоса фронта: концы (свои координаты узла)
var b_pt := Vector2.ZERO
var god := ""
var delay := 0.0
var radius := 20.0             # падение отряда: радиус кольца
var _t := 0.0

# --- Создание ---

static func wave(origin: Vector2, offsets: Array, building_type: String) -> void:
	if offsets.is_empty() or not WAVE_LOOKS.has(building_type) or not is_instance_valid(AuraRing.layer):
		return
	var fx := _make("wave", AuraRing.layer, true)
	fx.global_position = origin
	fx.targets = offsets
	fx.look = WAVE_LOOKS[building_type]
	fx.duration = WAVE_TIME + ABSORB_TIME

static func lifesteal(s: Node2D, sprite_scale: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(s.get_meta("lifesteal_fx_ms", -LIFESTEAL_GAP_MS)) < LIFESTEAL_GAP_MS:
		return
	var parent: Node = s.get_parent().get_parent() if s.get_parent() else null   # мир: родитель отряда
	if parent == null:
		return
	s.set_meta("lifesteal_fx_ms", now)
	var fx := _make("lifesteal", parent, true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.follow = s
	fx.global_position = s.global_position + Vector2(0.0, Soldier.GROUND_SINK)
	fx.chest = Soldier.TARGET_SPRITE_HEIGHT * 0.55 * sprite_scale
	fx.duration = LIFESTEAL_TIME
	for i in _rng.randi_range(2, 3):
		fx.parts.append({"p": Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-1.0, 1.0)),
			"delay": i * 0.07, "sway": _rng.randf_range(-3.0, 3.0)})

static func wall_break(parent: Node, a: Vector2, b: Vector2, chaos: bool) -> void:
	WorldGrade.pulse(0.35)   # пролом стены — короткая аберрация
	if parent == null:
		return
	var fx := _make("stones", parent, false)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.position = (a + b) / 2.0
	fx.duration = BREAK_TIME
	var half := (b - a) / 2.0
	var out := Vector2(-half.y, half.x).normalized()   # поперёк звена — камни летят на обе стороны
	var cols := _stone_colors(chaos)
	for i in BREAK_STONES:
		var along := half * _rng.randf_range(-0.9, 0.9)
		var side := 1.0 if i % 2 == 0 else -1.0
		fx.parts.append({"p": along - Vector2(0.0, _rng.randf_range(6.0, KingdomWall.HEIGHT)), "ground": along.y + _rng.randf_range(-3.0, 4.0),
			"v": out * side * _rng.randf_range(25.0, 70.0) + half.normalized() * _rng.randf_range(-40.0, 40.0) + Vector2(0.0, _rng.randf_range(-150.0, -60.0)),
			"size": _rng.randf_range(2.0, 4.0), "col": cols[i % cols.size()], "delay": 0.0})
	for i in BREAK_DUST:
		var along := half * lerpf(-0.9, 0.9, float(i) / (BREAK_DUST - 1))
		fx.puffs.append({"p": along + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 1.0)),
			"r0": _rng.randf_range(4.0, 7.0), "r1": _rng.randf_range(13.0, 20.0), "col": Palette.DUST_PALE if i % 3 == 1 else Palette.DUST})

static func wall_chips(parent: Node, seg: Node2D, a: Vector2, b: Vector2, chaos: bool) -> void:
	var now := Time.get_ticks_msec()
	if parent == null or now - int(seg.get_meta("chips_fx_ms", -CHIPS_GAP_MS)) < CHIPS_GAP_MS:
		return
	seg.set_meta("chips_fx_ms", now)
	var fx := _make("stones", parent, false)
	fx.z_index = Vfx.Z_INDEX_WORLD
	var hit := a.lerp(b, _rng.randf_range(0.2, 0.8))
	fx.position = hit - Vector2(0.0, _rng.randf_range(5.0, KingdomWall.HEIGHT))
	fx.duration = CHIPS_TIME
	var cols := _stone_colors(chaos)
	var ground := hit.y - fx.position.y
	for i in _rng.randi_range(4, 6):
		var ang := _rng.randf_range(PI * 1.05, PI * 1.95)   # брызги вверх и в стороны
		fx.parts.append({"p": Vector2.ZERO, "ground": ground + _rng.randf_range(-2.0, 3.0),
			"v": Vector2(cos(ang), sin(ang)) * _rng.randf_range(35.0, 85.0), "size": _rng.randf_range(1.2, 2.2),
			"col": cols[i % cols.size()], "delay": 0.0})
	fx.puffs.append({"p": Vector2.ZERO, "r0": 2.0, "r1": 7.0, "col": Palette.DUST_PALE})

static func battle_start(layer: Node, a: Vector2, b: Vector2, chaos: bool) -> void:
	if not is_instance_valid(layer):
		return
	var fx := _make("front", layer, true)
	fx.global_position = (a + b) / 2.0
	fx.a_pt = a - fx.global_position
	fx.b_pt = b - fx.global_position
	fx.look = {"edge": Palette.RED_BRIGHT, "core": Palette.FIRE} if chaos 		else {"edge": Palette.GOLD, "core": Palette.AMBER_LIGHT}
	fx.duration = FRONT_TIME

static func level_down(squad: Node2D) -> void:
	if not is_instance_valid(squad) or squad.get_parent() == null:
		return
	var fx := _make("level_down", squad.get_parent(), false)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.global_position = squad.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 2.6)   # над полоской HP отряда
	fx.duration = LEVEL_DOWN_TIME

static func god_sigil(s: Node2D, god_id: String, order: int = 0) -> void:
	if not Palette.GOD_COLORS.has(god_id) or not is_instance_valid(AuraRing.layer):
		return
	var fx := _make("sigil", AuraRing.layer, true)
	fx.follow = s
	fx.global_position = s.global_position
	fx.god = god_id
	fx.delay = order * SIGIL_STAGGER
	fx.duration = SIGIL_TIME + fx.delay

static func charm(victim: Node2D, by: Node2D) -> void:
	if not is_instance_valid(victim) or not is_instance_valid(by) or victim.get_parent() == null \
			or victim.get_parent().get_parent() == null:
		return
	var fx := _make("charm", victim.get_parent().get_parent(), true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.follow = victim
	fx.global_position = victim.global_position
	fx.a_pt = by.global_position   # глобально: откуда цепь (центр поработившего отряда)
	fx.duration = CHARM_TIME

static func squad_fall(at: Vector2, r: float, own: bool) -> void:
	if not is_instance_valid(AuraRing.layer):
		return
	var fx := _make("fall", AuraRing.layer, true)
	fx.global_position = at
	fx.radius = r
	fx.look = {"edge": Palette.PLAYER_SIDE if own else Palette.ENEMY_SIDE}
	fx.duration = FALL_TIME
	DustLayer.puff(at, r * 0.3, 7, r * 0.6)

static func rift(at: Vector2, r: float, wait: float = 0.0) -> void:
	if not is_instance_valid(AuraRing.layer):
		return
	var fx := _make("rift", AuraRing.layer.get_parent() if AuraRing.layer.get_parent() else AuraRing.layer, true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.global_position = at
	fx.radius = r
	fx.delay = wait
	fx.duration = RIFT_TIME + wait
	for i in 10:   # искры варпа
		fx.parts.append({"p": Vector2(_rng.randf_range(-0.4, 0.4) * r, _rng.randf_range(-1.6, -0.2) * r),
			"v": Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-50.0, -10.0)), "size": _rng.randf_range(0.8, 1.8)})

static func shield_break(s: Node2D, sprite_scale: float = 1.0) -> void:
	var parent: Node = s.get_parent().get_parent() if s.get_parent() else null
	if parent == null:
		return
	var fx := _make("shield", parent, true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.global_position = s.global_position + Vector2(0.0, Soldier.GROUND_SINK)
	fx.radius = Soldier.TARGET_SPRITE_HEIGHT * 0.55 * sprite_scale
	fx.duration = SHIELD_TIME
	for i in SHIELD_SHARDS:
		var a := TAU * (i + _rng.randf() * 0.6) / SHIELD_SHARDS
		fx.parts.append({"dir": Vector2.from_angle(a), "speed": _rng.randf_range(28.0, 46.0), "rot": _rng.randf() * TAU})

static func bonus_marks(squad: Node2D, kinds: Array, wait: float = 0.0) -> void:
	if kinds.is_empty() or not is_instance_valid(squad) or squad.get_parent() == null:
		return
	var fx := _make("bonus", squad.get_parent(), true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.global_position = squad.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 2.0)
	fx.parts = kinds.duplicate()
	fx.delay = wait
	fx.duration = BONUS_TIME + wait

static func _stone_colors(chaos: bool) -> Array:
	return [Palette.CHAOS_WALL_STONE, Palette.CHAOS_WALL_TOP, Palette.CHAOS_WALL_SPIKE] if chaos \
		else [Palette.WALL_STONE, Palette.WALL_STONE_TOP, Palette.WALL_TRIM]

static func _make(k: String, parent: Node, additive: bool) -> BuildingFx:
	var fx := BuildingFx.new()
	fx.kind = k
	if additive:
		fx.material = Vfx.add_material()   # пиксельный ADD
	parent.add_child(fx)
	return fx

# --- Ход и отрисовка ---

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	if kind == "stones":
		for p in parts:
			if p["v"] == Vector2.ZERO:
				continue
			p["v"].y += GRAVITY * delta
			p["p"] += p["v"] * delta
			if p["v"].y > 0.0 and p["p"].y >= p["ground"]:   # упал на землю — лежит
				p["p"].y = p["ground"]
				p["v"] = Vector2.ZERO
	elif (kind == "lifesteal" or kind == "sigil" or kind == "charm") and is_instance_valid(follow):
		global_position = follow.global_position
	queue_redraw()

func _fade() -> float:
	return clampf((duration - _t) / (duration * FADE_TAIL), 0.0, 1.0)

func _draw() -> void:
	match kind:
		"wave":
			_draw_wave()
		"lifesteal":
			_draw_lifesteal()
		"stones":
			_draw_stones()
		"front":
			_draw_front()
		"level_down":
			_draw_level_down()
		"sigil":
			_draw_sigil()
		"charm":
			_draw_charm()
		"fall":
			_draw_fall()
		"rift":
			_draw_rift()
		"shield":
			_draw_shield()
		"bonus":
			_draw_bonus()

func _draw_wave() -> void:
	var edge: Color = look["edge"]
	var core: Color = look["core"]
	var k := clampf(_t / WAVE_TIME, 0.0, 1.0)
	var run := 1.0 - pow(1.0 - k, 2.0)   # быстро от здания, мягко к соседу
	var hw := IsoGrid.TILE_WIDTH / 2.0 * TILE_INSET
	var hh := IsoGrid.TILE_HEIGHT / 2.0 * TILE_INSET
	for d in targets:
		var off: Vector2 = d
		var across := Vector2(-off.x, off.y) * WAVE_ARC   # вторая ось ромба (клетка: x ↔ y)
		if k < 1.0:
			var a := sin(k * PI) * 0.6 + 0.4
			var front := off * run
			var arc := PackedVector2Array([front - across - off * 0.08, front, front + across - off * 0.08])
			draw_polyline(arc, Color(edge, 0.12 * a), 9.0, true)
			draw_polyline(arc, Color(edge, 0.55 * a), 3.0, true)
			draw_polyline(arc, Color(core, 0.9 * a), 1.2, true)
			for i in WAVE_TRAIL:   # огоньки за фронтом
				var f := run - (i + 1) * 0.06
				if f <= 0.0:
					break
				var side := (fmod(i * 0.618 + _t * 3.0, 1.0) - 0.5) * 1.4
				draw_circle(off * f + across * side, 1.6 - i * 0.18, Color(core, a * (1.0 - float(i) / WAVE_TRAIL)), true, -1.0, true)
		if _t >= WAVE_TIME * 0.85:   # клетка соседа «впитала» волну
			var e := clampf(1.0 - (_t - WAVE_TIME * 0.85) / (ABSORB_TIME + WAVE_TIME * 0.15), 0.0, 1.0)
			var r := PackedVector2Array([off + Vector2(0.0, -hh), off + Vector2(hw, 0.0), off + Vector2(0.0, hh),
				off + Vector2(-hw, 0.0), off + Vector2(0.0, -hh)])
			draw_colored_polygon(r.slice(0, 4), Color(edge, 0.1 * e))
			draw_polyline(r, Color(edge, 0.18 * e), 8.0, true)
			draw_polyline(r, Color(core, 0.75 * e), 1.5, true)

func _draw_lifesteal() -> void:
	for d in parts:
		var k := clampf((_t - d["delay"]) / (LIFESTEAL_TIME - 0.14), 0.0, 1.0)
		if k <= 0.0 or k >= 1.0:
			continue
		var e := 1.0 - pow(1.0 - k, 2.0)
		var base: Vector2 = d["p"]
		var head := base.lerp(Vector2(0.0, -chest), e) + Vector2(sin(k * PI) * d["sway"], 0.0)
		var tail := base.lerp(Vector2(0.0, -chest), maxf(e - 0.35, 0.0))
		var a := sin(k * PI)
		draw_line(tail, head, Color(Palette.BLOOD, 0.8 * a), 2.0, true)
		draw_line(tail.lerp(head, 0.5), head, Color(Palette.BLOOD_BRIGHT, a), 1.2, true)
		if k > 0.75:   # впиталась — искра у груди
			draw_circle(head, 1.4, Color(Palette.HIT_RED, (1.0 - k) * 4.0), true, -1.0, true)

func _draw_stones() -> void:
	var f := _fade()
	var k := clampf(_t / duration, 0.0, 1.0)
	for p in puffs:   # пыль — низко, расползается и оседает
		var r := lerpf(p["r0"], p["r1"], 1.0 - pow(1.0 - k, 2.0))
		var c: Color = p["col"]
		var a := DUST_ALPHA * (1.0 - k) * minf(k * 8.0, 1.0)   # пыль поднимается, не вспыхивает
		var at: Vector2 = p["p"] - Vector2(0.0, 4.0 * k)
		draw_set_transform(at, 0.0, Vector2(1.0, 0.5))   # эллипс 2:1 — по земле
		draw_circle(Vector2.ZERO, r, Color(c, a * 0.45), true, -1.0, true)
		draw_circle(Vector2.ZERO, r * 0.55, Color(c, a * 0.8), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	for p in parts:
		var s: float = p["size"]
		var c: Color = p["col"]
		draw_rect(Rect2(p["p"] - Vector2(s, s) * 0.5, Vector2(s, s)), Color(c, f))
		draw_rect(Rect2(p["p"] - Vector2(s, s) * 0.5, Vector2(s, s)), Color(Palette.WALL_STONE_DARK, f * 0.8), false, 0.6)

func _draw_front() -> void:
	var edge: Color = look["edge"]
	var core: Color = look["core"]
	var open := 1.0 - pow(1.0 - clampf(_t / FRONT_SPREAD, 0.0, 1.0), 3.0)   # расходится от середины
	var a := clampf((duration - _t) / (duration - FRONT_SPREAD), 0.0, 1.0)
	if a <= 0.0:
		return
	var p := a_pt * open
	var q := b_pt * open
	for g in [[26.0, 0.06], [12.0, 0.14], [5.0, 0.35]]:
		draw_line(p, q, Color(edge, g[1] * a), g[0], true)
	draw_line(p, q, Color(core, 0.9 * a), 1.6, true)
	for i in 10:   # искры вдоль полосы
		var k := fmod(i * 0.618 + _t * 0.7, 1.0)
		var at := p.lerp(q, k) + Vector2(0.0, -6.0 * fmod(_t * 2.0 + i * 0.37, 1.0))
		draw_circle(at, 1.3, Color(core, a * 0.8), true, -1.0, true)

func _draw_level_down() -> void:
	var t := _t / duration
	var f := _fade()
	var steel := Palette.GOLD_DIM.lightened(0.35)
	var w := CHEVRON.x
	var h := CHEVRON.y
	if t < LEVEL_DOWN_CRACK:   # целый шеврон «^», к концу этой доли — трещина
		var crack := smoothstep(LEVEL_DOWN_CRACK * 0.5, LEVEL_DOWN_CRACK, t)
		draw_polyline(PackedVector2Array([Vector2(-w, h), Vector2(0.0, -h), Vector2(w, h)]), steel, 3.0, true)
		draw_polyline(PackedVector2Array([Vector2(-w, h), Vector2(0.0, -h), Vector2(w, h)]), Palette.OUTLINE, 1.0, true)
		if crack > 0.0:
			draw_line(Vector2(0.0, -h), Vector2(1.5, -h + 7.0 * crack), Palette.RED, 1.4, true)
		return
	var k := (t - LEVEL_DOWN_CRACK) / (1.0 - LEVEL_DOWN_CRACK)   # половинки расходятся и падают, крошка
	for side in [-1.0, 1.0]:
		var drop: Vector2 = Vector2(side * 6.0 * k, 26.0 * k * k)
		var rot: float = side * 0.9 * k
		draw_set_transform(drop, rot, Vector2.ONE)
		draw_line(Vector2(0.0, -h), Vector2(side * w, h), Color(steel, f), 3.0, true)
		draw_line(Vector2(0.0, -h), Vector2(side * w, h), Color(Palette.RED, f * 0.8), 1.0, true)
	draw_set_transform(Vector2.ZERO)
	for i in 5:
		var at := Vector2((i - 2) * 3.0, -h + 34.0 * k * k * (0.7 + i * 0.1))
		draw_rect(Rect2(at, Vector2(1.5, 1.5)), Color(steel, f * 0.8))

func _draw_sigil() -> void:
	var t := (_t - delay) / SIGIL_TIME
	if t <= 0.0:
		return
	var cols: Array = Palette.GOD_COLORS[god]
	var deep: Color = cols[0]
	var bright: Color = cols[1]
	var a := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.6, 1.0, t))
	var r := SIGIL_RADIUS * (0.7 + 0.3 * smoothstep(0.0, 0.3, t))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))   # знак лежит на земле
	draw_circle(Vector2.ZERO, r * 1.3, Color(deep, 0.25 * a), true, -1.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(bright, 0.9 * a), 1.2, true)
	var c := Color(bright, a)
	match god:
		"khorne":   # руна-череп: крест с перекладиной
			draw_line(Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.6, r * 0.6), c, 1.4, true)
			draw_line(Vector2(r * 0.6, -r * 0.6), Vector2(-r * 0.6, r * 0.6), c, 1.4, true)
			draw_line(Vector2(-r * 0.6, -r * 0.1), Vector2(r * 0.6, -r * 0.1), c, 1.4, true)
		"nurgle":   # три круга
			for i in 3:
				var ang := TAU * i / 3.0 - PI / 2.0
				draw_arc(Vector2(cos(ang), sin(ang)) * r * 0.35, r * 0.32, 0.0, TAU, 16, c, 1.2, true)
		"tzeentch":   # спираль
			var pts := PackedVector2Array()
			for i in 24:
				var u := float(i) / 23.0
				pts.append(Vector2(cos(u * TAU * 1.5), sin(u * TAU * 1.5)) * r * 0.75 * u)
			draw_polyline(pts, c, 1.2, true)
		"slaanesh":   # серп
			draw_arc(Vector2.ZERO, r * 0.6, PI * 0.15, PI * 0.85, 12, c, 1.6, true)
			draw_arc(Vector2(0.0, r * 0.15), r * 0.45, PI * 0.2, PI * 0.8, 12, Color(deep, a), 1.2, true)
	draw_set_transform(Vector2.ZERO)
	var rise := smoothstep(0.1, 0.7, t)   # языки света — от знака до пояса
	for i in 5:
		var x := (i - 2) * r * 0.35 + sin(_t * 9.0 + i) * 1.0
		var top := -Soldier.TARGET_SPRITE_HEIGHT * 0.5 * rise * (0.6 + 0.4 * fmod(i * 0.618, 1.0))
		draw_line(Vector2(x, 0.0), Vector2(x, top), Color(bright, 0.55 * a), 1.4, true)
		draw_line(Vector2(x, 0.0), Vector2(x, top * 0.6), Color(deep, 0.5 * a), 3.0, true)

func _draw_charm() -> void:
	var t := _t / duration
	var a := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.65, 1.0, t))
	var from := a_pt - global_position   # от поработившего отряда
	var chest := Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 0.5)
	var reach := smoothstep(0.0, 0.4, t)   # цепь дотягивается до жертвы, потом натягивается
	var slack := (1.0 - smoothstep(0.3, 0.7, t)) * 10.0
	var normal := (chest - from).orthogonal().normalized()
	for i in CHARM_LINKS:
		var u := float(i) / (CHARM_LINKS - 1) * reach
		var p := from.lerp(chest, u) + normal * sin(u * PI) * slack
		var rot := (chest - from).angle() + (PI * 0.5 if i % 2 == 1 else 0.0)
		draw_set_transform(p, rot, Vector2(1.0, 0.6))
		draw_arc(Vector2.ZERO, 2.4, 0.0, TAU, 10, Color(Palette.SLAANESH, 0.9 * a), 1.3, true)
		draw_arc(Vector2.ZERO, 2.4, PI, TAU, 6, Color(Palette.SLAANESH_PALE, 0.7 * a), 0.8, true)
	draw_set_transform(Vector2.ZERO)
	# серп Король Второго Акта над головой
	var head := Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 1.25 - 4.0 * t)
	draw_circle(head, 6.0, Color(Palette.SLAANESH, 0.18 * a), true, -1.0, true)
	draw_arc(head, 4.0, PI * 0.15, PI * 0.85, 12, Color(Palette.SLAANESH_PALE, a), 1.6, true)
	draw_arc(head + Vector2(0.0, 0.9), 3.0, PI * 0.2, PI * 0.8, 12, Color(Palette.SLAANESH, a), 1.1, true)

func _draw_fall() -> void:
	var t := _t / duration
	var edge: Color = look["edge"]
	var a := (1.0 - smoothstep(0.35, 1.0, t)) * smoothstep(0.0, 0.08, t)
	var r := radius * (0.5 + 0.8 * (1.0 - pow(1.0 - t, 2.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(edge, 0.14 * a), 7.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(edge, 0.75 * a), 1.4, true)
	draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 32, Color(edge, 0.3 * a), 1.0, true)
	draw_set_transform(Vector2.ZERO)

func _draw_rift() -> void:
	var t := (_t - delay) / RIFT_TIME
	if t <= 0.0:
		return
	var open := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.6, 1.0, t))   # раскрылся — постоял — стянулся
	var a := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.75, 1.0, t))
	var h := radius * 1.6
	var w := radius * 0.42 * open
	var top := Vector2(0.0, -h * 1.1)
	# разлом — вертикальная «линза»: ореол, тело, ядро
	for layer_def in [[2.4, 0.12, Palette.SLAANESH], [1.4, 0.35, Palette.RED_BRIGHT], [0.55, 0.85, Palette.SLAANESH_PALE]]:
		var lw: float = w * layer_def[0]
		var pts := PackedVector2Array()
		for i in 17:
			var u := float(i) / 16.0
			pts.append(Vector2(sin(u * PI) * lw * (1.0 + 0.15 * sin(u * 9.0 + _t * 14.0)), top.y + h * 1.1 * u))
		for i in range(16, -1, -1):
			var u := float(i) / 16.0
			pts.append(Vector2(-sin(u * PI) * lw * (1.0 + 0.15 * cos(u * 7.0 + _t * 12.0)), top.y + h * 1.1 * u))
		if lw > 0.5:
			draw_colored_polygon(pts, Color(layer_def[2], layer_def[1] * a))
	# отсвет по земле
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius * (0.6 + 0.4 * open), Color(Palette.RED_BRIGHT, 0.12 * a), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	for p in parts:   # искры поднимаются
		var at: Vector2 = p["p"] * open + p["v"] * (_t - delay)
		draw_circle(at, p["size"], Color(Palette.SLAANESH_PALE, 0.8 * a), true, -1.0, true)

func _draw_shield() -> void:
	var t := _t / duration
	var a := 1.0 - smoothstep(0.3, 1.0, t)
	var r := radius * (1.0 + 0.35 * t)
	var center := Vector2(0.0, -radius * 0.9)
	if t < 0.35:   # вспышка сферы
		var f := 1.0 - t / 0.35
		draw_circle(center, r, Color(Palette.SHIELD_BLUE, 0.22 * f), true, -1.0, true)
		draw_arc(center, r, 0.0, TAU, 28, Color(Palette.FROST_PALE, 0.9 * f), 1.4, true)
	for p in parts:   # осколки-дуги разлетаются и гаснут
		var d: Vector2 = p["dir"]
		var at: Vector2 = center + d * (r + p["speed"] * _t)
		var ang: float = p["rot"] + _t * 8.0
		var half := Vector2.from_angle(ang) * 2.4
		draw_line(at - half, at + half, Color(Palette.SHIELD_BLUE, 0.9 * a), 1.4, true)
		draw_line(at - half * 0.4, at + half * 0.4, Color(Palette.FROST_PALE, a), 0.8, true)

func _draw_bonus() -> void:
	var t := (_t - delay) / BONUS_TIME
	if t <= 0.0:
		return
	var a := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.6, 1.0, t))
	var rise := -8.0 * smoothstep(0.0, 1.0, t)
	var n := parts.size()
	for i in n:
		var kind: String = parts[i]
		var look: Array = BONUS_LOOKS.get(kind, BONUS_LOOKS["synergy"])
		var edge: Color = look[0]
		var core: Color = look[1]
		var c := Vector2((i - (n - 1) / 2.0) * BONUS_GAP, rise)
		var pop := 1.0 + 0.35 * (1.0 - smoothstep(0.0, 0.18, t))   # знак вспыхивает крупнее и садится
		draw_set_transform(c, 0.0, Vector2(pop, pop))
		draw_circle(Vector2.ZERO, 6.5, Color(Palette.OUTLINE, 0.7 * a), true, -1.0, true)
		draw_circle(Vector2.ZERO, 6.5, Color(edge, 0.25 * a), true, -1.0, true)
		draw_arc(Vector2.ZERO, 6.5, 0.0, TAU, 20, Color(edge, a), 1.1, true)
		var col := Color(core, a)
		match kind:
			"synergy":   # два шеврона
				for k in 2:
					var y := 1.5 - k * 3.2
					draw_polyline(PackedVector2Array([Vector2(-3.0, y + 1.5), Vector2(0.0, y - 1.5), Vector2(3.0, y + 1.5)]), col, 1.2, true)
			"front":   # щит
				draw_colored_polygon(PackedVector2Array([Vector2(-3.2, -3.2), Vector2(3.2, -3.2), Vector2(3.2, 0.5),
					Vector2(0.0, 3.8), Vector2(-3.2, 0.5)]), Color(core, 0.85 * a))
			"back":   # прицел
				draw_arc(Vector2.ZERO, 3.0, 0.0, TAU, 14, col, 1.0, true)
				draw_line(Vector2(-4.4, 0.0), Vector2(4.4, 0.0), col, 0.9, true)
				draw_line(Vector2(0.0, -4.4), Vector2(0.0, 4.4), col, 0.9, true)
			"chapter":   # ромб-знак
				draw_colored_polygon(PackedVector2Array([Vector2(0.0, -3.8), Vector2(3.0, 0.0), Vector2(0.0, 3.8),
					Vector2(-3.0, 0.0)]), Color(core, 0.85 * a))
			"commander":   # звезда
				var pts := PackedVector2Array()
				for k in 10:
					var rr := 3.8 if k % 2 == 0 else 1.6
					pts.append(Vector2.from_angle(-PI / 2.0 + TAU * k / 10.0) * rr)
				draw_colored_polygon(pts, Color(core, 0.9 * a))
	draw_set_transform(Vector2.ZERO)
