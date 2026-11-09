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
#   teleport(родитель, точки, рост, высадка) — Deep Strike Терминаторов (5.3, 09.11.2026): уход — боец стягивается
#     в вертикальную полосу варп-света и она гаснет, высадка — полоса раскрывается; молнии, разряд по земле
#   charm(жертва, отряд) — порабощение Слаанеш (4.11, 09.11.2026): розовая цепь от поработившего отряда к бойцу
#     натягивается и гаснет, над головой — серп
#   squad_fall(точка, радиус, свой) — отряд пал целиком (09.11.2026): кольцо цвета стороны по земле расходится, пыль

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

const TELEPORT_TIME: float = 0.55
const TELEPORT_WIDTH: float = 7.0    # px мира — полуширина полосы у бойца ростом Soldier.TARGET_SPRITE_HEIGHT
const TELEPORT_BANDS = [[2.2, 0.08], [1.3, 0.16], [0.6, 0.36], [0.22, 0.6]]   # ширина ×, яркость — мягкий край;
# приглушено (снимок 09.11.2026: белые столбы читались неоном, а неон пакета пользователь отвергал 22.10.2026)
const CHARM_TIME: float = 0.9
const CHARM_LINKS: int = 9
const FALL_TIME: float = 0.9

static var _add: CanvasItemMaterial
static var _rng := RandomNumberGenerator.new()   # своя случайность: randf — общая с боем

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
var height := 31.0             # телепорт: рост бойца
var arrive := false            # телепорт: высадка (полоса раскрывается) / уход (стягивается)
var radius := 20.0             # падение отряда: радиус кольца
var seed_i := 0                # молнии телепорта, цепь — свой рисунок у каждого
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
	fx.global_position = s.global_position
	fx.chest = Soldier.TARGET_SPRITE_HEIGHT * 0.55 * sprite_scale
	fx.duration = LIFESTEAL_TIME
	for i in randi_range(2, 3):
		fx.parts.append({"p": Vector2(randf_range(-6.0, 6.0), randf_range(-1.0, 1.0)),
			"delay": i * 0.07, "sway": randf_range(-3.0, 3.0)})

static func wall_break(parent: Node, a: Vector2, b: Vector2, chaos: bool) -> void:
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
		var along := half * randf_range(-0.9, 0.9)
		var side := 1.0 if i % 2 == 0 else -1.0
		fx.parts.append({"p": along - Vector2(0.0, randf_range(6.0, KingdomWall.HEIGHT)), "ground": along.y + randf_range(-3.0, 4.0),
			"v": out * side * randf_range(25.0, 70.0) + half.normalized() * randf_range(-40.0, 40.0) + Vector2(0.0, randf_range(-150.0, -60.0)),
			"size": randf_range(2.0, 4.0), "col": cols[i % cols.size()], "delay": 0.0})
	for i in BREAK_DUST:
		var along := half * lerpf(-0.9, 0.9, float(i) / (BREAK_DUST - 1))
		fx.puffs.append({"p": along + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 1.0)),
			"r0": randf_range(4.0, 7.0), "r1": randf_range(13.0, 20.0), "col": Palette.DUST_PALE if i % 3 == 1 else Palette.DUST})

static func wall_chips(parent: Node, seg: Node2D, a: Vector2, b: Vector2, chaos: bool) -> void:
	var now := Time.get_ticks_msec()
	if parent == null or now - int(seg.get_meta("chips_fx_ms", -CHIPS_GAP_MS)) < CHIPS_GAP_MS:
		return
	seg.set_meta("chips_fx_ms", now)
	var fx := _make("stones", parent, false)
	fx.z_index = Vfx.Z_INDEX_WORLD
	var hit := a.lerp(b, randf_range(0.2, 0.8))
	fx.position = hit - Vector2(0.0, randf_range(5.0, KingdomWall.HEIGHT))
	fx.duration = CHIPS_TIME
	var cols := _stone_colors(chaos)
	var ground := hit.y - fx.position.y
	for i in randi_range(4, 6):
		var ang := randf_range(PI * 1.05, PI * 1.95)   # брызги вверх и в стороны
		fx.parts.append({"p": Vector2.ZERO, "ground": ground + randf_range(-2.0, 3.0),
			"v": Vector2(cos(ang), sin(ang)) * randf_range(35.0, 85.0), "size": randf_range(1.2, 2.2),
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

# Один узел на весь отряд (точки — глобальные, у каждой своя задержка stagger): по узлу на бойца с обеих сторон —
# 24 узла в один тик
static func teleport(parent: Node, points: Array, h: float, landing: bool, stagger: Array = []) -> void:
	if parent == null or points.is_empty():
		return
	var fx := _make("teleport", parent, true)
	fx.z_index = Vfx.Z_INDEX_WORLD
	fx.global_position = points[0]
	fx.height = h
	fx.arrive = landing
	var longest := 0.0
	for i in points.size():
		var wait: float = stagger[i] if i < stagger.size() else 0.0
		longest = maxf(longest, wait)
		fx.parts.append({"p": points[i] - fx.global_position, "delay": wait, "seed": _rng.randi()})
	fx.duration = TELEPORT_TIME + longest

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

static func _stone_colors(chaos: bool) -> Array:
	return [Palette.CHAOS_WALL_STONE, Palette.CHAOS_WALL_TOP, Palette.CHAOS_WALL_SPIKE] if chaos \
		else [Palette.WALL_STONE, Palette.WALL_STONE_TOP, Palette.WALL_TRIM]

static func _make(k: String, parent: Node, additive: bool) -> BuildingFx:
	var fx := BuildingFx.new()
	fx.kind = k
	if additive:
		if _add == null:
			_add = CanvasItemMaterial.new()
			_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fx.material = _add
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
		"teleport":
			_draw_teleport()
		"charm":
			_draw_charm()
		"fall":
			_draw_fall()

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

func _draw_teleport() -> void:
	for d in parts:
		_draw_teleport_beam(d["p"], (_t - d["delay"]) / TELEPORT_TIME, d["seed"])
	draw_set_transform(Vector2.ZERO)

func _draw_teleport_beam(at: Vector2, t: float, seed_v: int) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	draw_set_transform(at)
	var k := height / Soldier.TARGET_SPRITE_HEIGHT
	# высадка: тонкая яркая нить раскрывается в полосу и гаснет; уход — полоса сжимается в нить и гаснет
	var open := smoothstep(0.0, 0.35, t) if arrive else 1.0 - smoothstep(0.25, 0.8, t)
	var a := (1.0 - smoothstep(0.55, 1.0, t)) if arrive else (1.0 - smoothstep(0.7, 1.0, t))
	a *= smoothstep(0.0, 0.08, t)
	var w := TELEPORT_WIDTH * k * maxf(open, 0.08)
	var top := -height * (1.25 if arrive else 1.15)
	for b in TELEPORT_BANDS:
		var bw: float = w * b[0]
		var col: Color = Palette.TELEPORT_DEEP if b[0] > 1.0 else (Palette.TELEPORT if b[0] > 0.3 else Palette.TELEPORT_CORE)
		draw_rect(Rect2(-bw, top, bw * 2.0, -top), Color(col, b[1] * a))
	# кольцо разряда по земле
	var ring := (TELEPORT_WIDTH * 2.2 * k) * (0.6 + 0.8 * smoothstep(0.0, 0.6, t))
	draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 32, Color(Palette.TELEPORT, 0.7 * a), 1.4, true)
	draw_arc(Vector2.ZERO, ring * 0.6, 0.0, TAU, 24, Color(Palette.TELEPORT_CORE, 0.5 * a), 1.0, true)
	draw_set_transform(at)
	# молнии: ломаные внутри полосы и по земле, рисунок меняется раз в 0.06 с
	var r := RandomNumberGenerator.new()
	r.seed = seed_v + int(_t / 0.06)
	for i in 3:
		var pts := PackedVector2Array()
		var y := 0.0
		var x := r.randf_range(-w, w)
		pts.append(Vector2(x, 0.0))
		while y > top:
			y -= r.randf_range(4.0, 8.0) * k
			x = clampf(x + r.randf_range(-4.0, 4.0) * k, -w * 1.6, w * 1.6)
			pts.append(Vector2(x, maxf(y, top)))
		draw_polyline(pts, Color(Palette.TELEPORT_CORE, 0.8 * a * r.randf_range(0.4, 1.0)), 1.0, true)
	for i in 3:   # разряд по земле
		var ang := r.randf_range(0.0, TAU)
		var p := Vector2.ZERO
		var pts := PackedVector2Array([p])
		for j in 3:
			p += Vector2.from_angle(ang + r.randf_range(-0.6, 0.6)) * ring * 0.4
			pts.append(Vector2(p.x, p.y * 0.5))
		draw_polyline(pts, Color(Palette.TELEPORT, 0.7 * a), 1.0, true)

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
	# серп Слаанеш над головой
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
