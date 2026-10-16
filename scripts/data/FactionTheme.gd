class_name FactionTheme
extends RefCounted

# Оформление поля боя и цитадели по расе ИГРОКА (решение пользователя: цитадель
# только у игрока; все плитки поля — в стиле выбранной игроком расы, раса врага
# на вид не влияет). Раса забега — RunManager.player_faction, выбирается в начале
# нового забега (RaceSelectDialog из главного меню; пока доступен только Космодесант).
#
# Плитка (floor / kingdom / enemy; необязательные edge — внешнее кольцо поля, river — линии рек через
# поле, IsoGridRenderer) — вариант для клетки, выбирается по хэшу клетки.
# ground + features (необязательно) — пол и зона врага естественной местностью вместо случайной плиты
#   в каждой клетке: ground — грунт везде, features — редкие детали поверх:
#   {"tiles": [плитки], "clusters": N, "size": [от, до]} — N групп соседних клеток (руины к руинам),
#   {"tiles": [плитки], "scatter": доля} — одиночные (кратеры);
# flags — {"tiles": [плитки], "count": N}: N клеток только на стороне игрока (не в королевстве).
# Плитка:
#   int    — номер Tiles/Slice N лунного тайлсета (блок, TerrainTiles.draw_block)
#   String — путь к PNG ромба клетки целиком (TerrainTiles.draw_tile_texture):
#            ширина картинки = ширина клетки, верхняя грань — ромб 2:1 в верхней части
#   {"texture": путь, "top": px} — то же, верхний угол ромба на top px ниже верха картинки
#            (руины, знамя торчат над плитой); плиты из листа — tools/tiles_from_sheet.py (tiles.json);
#            "axis": "u" / "v" — вдоль какой оси клеток нарисована стена / русло (edge, river):
#            на линии по другой оси плита отражается; "mirror": {"texture", "top"} — у плиты русла: она же,
#            отражённая вдоль течения (шире с другого конца) — вдоль реки идут парами плита + отражение
#   "no_decor": true — на клетке не ставится декор (туман, большой кратер); "flag": true — знамя:
#            плитка / объект только на стороне игрока (IsoGridRenderer)
#   {"frames": [{"texture", "top"}, …], "fps": кадров/с} — анимированная плита (кратер с туманом): кадры
#            по кругу, соседние плавно перетекают; у каждой клетки свой сдвиг такта (IsoGridRenderer)
# decorations — объекты {"texture", "base", "scale", "flat"} (TerrainTiles.draw_prop); flat — можно в боевой полосе
#
# citadel — вид цитадели:
#   {}                — башня из блоков тайлсета (Citadel.BLOCKS)
#   {"sheet": путь к PNG-листу кадров, "frame_size": Vector2i, "anchor": Vector2
#    (точка основания башни в кадре, px), "scale": float, "fps": float,
#    "rows": {"idle": [ряд, кадров], "attack": [...], "hit": [...], "fall": [...]}}
#    idle — по кругу; attack (выстрел), hit (попадание) — один раз и снова idle;
#    fall — при 0 HP, остаётся на последнем кадре. "tint" — тон спрайта (ближе к грунту).
# Новая раса — запись в THEMES; чистые спрайты рас — сюда же (пути к PNG).

const DEFAULT_FACTION: String = "space_marines"

# Расы в окне выбора нового забега (RaceSelectDialog), по порядку.
# available = false — видна, но закрыта («Скоро»); открыть расу — true + тема и юниты
const FACTIONS = [
	{"id": "space_marines", "name": "Космодесант", "available": true,
		"desc": "Ангелы Смерти: стойкие отряды и цитадель-бастион."},
	{"id": "chaos", "name": "Хаос", "available": false,
		"desc": "Предатели и демонические машины."},
	{"id": "tyranids", "name": "Тираниды", "available": false,
		"desc": "Рой, пожирающий миры."},
]

static func get_faction_info(faction: String) -> Dictionary:
	for f in FACTIONS:
		if f["id"] == faction:
			return f
	return {}

static func is_available(faction: String) -> bool:
	return get_faction_info(faction).get("available", false)

# Плиты Космодесанта: PNG assets/FightFleed/Assets_cosmodesant → tools/tiles_from_png.py.
# Окопа, бункера и развалин в новом стиле нет (старые плиты другой палитры убраны) — ASSETS_NEEDED.
# Решение пользователя: королевство — seamless terrain (осыпь), край карты — debris wall (стена),
# ядовитый ручей — только линиями рек через поле, остальное (ничья земля, зона врага) — как реальная
# местность: грунт (та же осыпь) и редкие детали — группы руин, одиночные кратеры и воронки;
# знамёна — немного и только на стороне игрока
const SM_TILES = "res://assets/sprites/tiles/space_marines/"
const SM_TERRAIN = [{"texture": SM_TILES + "terrain.png", "top": 10}]      # каменная осыпь
const SM_DEBRIS_WALL = [{"texture": SM_TILES + "wall.png", "top": 67, "axis": "u"}]   # стена с обломками
# Ядовитый ручей: плиты русла (к юго-западу шире) и их отражения вдоль течения (tools/river_mirror.py) —
# IsoGridRenderer чередует плиту и отражение одной плиты на всю реку: стыки совпадают пиксель в пиксель.
# River1 (river_0) не берём: на узком конце русло перегорожено обломками — грунтовая перемычка на стыке
const SM_RIVER = [
	{"texture": SM_TILES + "river_1.png", "top": 17, "axis": "v",
		"mirror": {"texture": SM_TILES + "river_1_mirror.png", "top": 17}},
	{"texture": SM_TILES + "river_2.png", "top": 22, "axis": "v",
		"mirror": {"texture": SM_TILES + "river_2_mirror.png", "top": 22}},
]
const SM_RUINS = [{"texture": SM_TILES + "ruins_bunker.png", "top": 48}]   # руины с бункером
const SM_CRATER = [{"texture": SM_TILES + "crater.png", "top": 20, "no_decor": true}]   # большой кратер
const SM_SMALL_CRATERS = [{"texture": SM_TILES + "terrain_craters.png", "top": 10}]   # осыпь с воронками
# Воронки в тумане: туман густеет и редеет — кадры плавно перетекают (TerrainTiles.draw_theme_tile),
# по туманной местности — волной (IsoGridRenderer._cell_time). Туман — из ScatteredDebrisTilecrator1/2
# на плите SM_SMALL_CRATERS (tools/fog_overlay.py: у кадров чужая палитра)
const SM_FOG_CRATERS = [{"fps": 0.4, "no_decor": true, "frames": [
	{"texture": SM_TILES + "fog_crater_0.png", "top": 10},   # лёгкий туман
	{"texture": SM_TILES + "fog_crater_1.png", "top": 10},   # густой туман
]}]
const SM_FLAG = [{"texture": SM_TILES + "flag.png", "top": 120, "flag": true}]     # обломки и знамя
# Готика Империума: лист assets/FightFleed/Assets_cosmodesant/goticImperial.png → tools/props_from_sheet.py
# (assets/sprites/props/space_marines/gothic_NN.png, base — точка земли под объектом). Решение пользователя:
# руины на поле, декор вместо лунных камней, цитадель (gothic_09); лист заменён пользователем 15.10.2026 (30 объектов)
const SM_PROPS = "res://assets/sprites/props/space_marines/"
const GOTHIC_SCALE: float = 0.35        # руины: площадка плазы (gothic_13) ≈ клетка
const GOTHIC_DECOR_SCALE: float = 0.22  # мелкий декор
# Готика светлее и теплее грунта (средний цвет 44,40,34 против 19,27,37) — темнее и холоднее, но не
# до цвета грунта, чтобы читалась (решение пользователя: ближе к грунту); цитадель — чуть светлее
const GOTHIC_TINT = Color(0.62, 0.70, 0.85)
const GOTHIC_CITADEL_TINT = Color(0.7, 0.76, 0.88)
# Руины — объект на плите осыпи; "tall" — выше бойца, только вне боевой полосы (IsoGridRenderer._put_feature)
const SM_GOTHIC_RUINS = [
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "flag": true, "prop": {"texture": SM_PROPS + "gothic_00.png", "base": Vector2(123, 186), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # shrine
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_01.png", "base": Vector2(156, 165), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # wall_towers
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_02.png", "base": Vector2(188, 146), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # cathedral
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_03.png", "base": Vector2(134, 136), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # ruin_block
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_04.png", "base": Vector2(122, 102), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # ruin_colonnade
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_06.png", "base": Vector2(194, 164), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # hangar
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "flag": true, "prop": {"texture": SM_PROPS + "gothic_07.png", "base": Vector2(82, 218), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # watchtower
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_08.png", "base": Vector2(161, 130), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # gothic_wall
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_10.png", "base": Vector2(110, 133), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # bunker
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_12.png", "base": Vector2(92, 140), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # golden_shrine
	{"texture": SM_TILES + "terrain.png", "top": 10, "tall": true, "prop": {"texture": SM_PROPS + "gothic_16.png", "base": Vector2(98, 236), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # eagle_statue
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_11.png", "base": Vector2(190, 73), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # aquila_plaza
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_13.png", "base": Vector2(204, 77), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # plaza
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_14.png", "base": Vector2(170, 85), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # plaza_grid
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_15.png", "base": Vector2(186, 111), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # broken_stairs
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_17.png", "base": Vector2(106, 65), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # spiky_rubble
	{"texture": SM_TILES + "terrain.png", "top": 10, "prop": {"texture": SM_PROPS + "gothic_22.png", "base": Vector2(152, 72), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # rubble
	{"texture": SM_TILES + "terrain.png", "top": 10, "flag": true, "prop": {"texture": SM_PROPS + "gothic_23.png", "base": Vector2(135, 84), "scale": GOTHIC_SCALE, "tint": GOTHIC_TINT}},   # fallen_banner
]
const SM_GOTHIC_DECOR = [
	{"texture": SM_PROPS + "gothic_05.png", "base": Vector2(56, 155), "scale": GOTHIC_DECOR_SCALE, "flag": true, "tint": GOTHIC_TINT},   # eagle_pillar
	{"texture": SM_PROPS + "gothic_18.png", "base": Vector2(48, 140), "scale": GOTHIC_DECOR_SCALE, "flag": true, "tint": GOTHIC_TINT},   # banner
	{"texture": SM_PROPS + "gothic_19.png", "base": Vector2(61, 86), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # red_chest
	{"texture": SM_PROPS + "gothic_20.png", "base": Vector2(47, 102), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # barrel
	{"texture": SM_PROPS + "gothic_21.png", "base": Vector2(128, 55), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # sarcophagus
	{"texture": SM_PROPS + "gothic_24.png", "base": Vector2(58, 84), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # crate
	{"texture": SM_PROPS + "gothic_25.png", "base": Vector2(100, 105), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # blue_shrine
	{"texture": SM_PROPS + "gothic_26.png", "base": Vector2(40, 112), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # lamp
	{"texture": SM_PROPS + "gothic_27.png", "base": Vector2(75, 96), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # strongbox
	{"texture": SM_PROPS + "gothic_28.png", "base": Vector2(50, 76), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # dome
	{"texture": SM_PROPS + "gothic_29.png", "base": Vector2(118, 57), "scale": GOTHIC_DECOR_SCALE, "tint": GOTHIC_TINT},   # parapet
]
const SM_FEATURES = [
	{"tiles": SM_RUINS + SM_GOTHIC_RUINS, "clusters": 5, "size": [2, 4]},
	{"tiles": SM_CRATER, "scatter": 0.04},
	{"tiles": SM_SMALL_CRATERS, "scatter": 0.06},
	{"tiles": SM_FOG_CRATERS, "clusters": 4, "size": [5, 9]},   # туманные местности
]

const THEMES = {
	"space_marines": {
		"floor": SM_RUINS + SM_CRATER + SM_SMALL_CRATERS,
		"kingdom": SM_TERRAIN,
		"enemy": SM_RUINS + SM_CRATER + SM_SMALL_CRATERS,
		"ground": SM_TERRAIN,
		"features": SM_FEATURES,
		"flags": {"tiles": SM_FLAG, "count": 2},
		# Карта одна во всех забегах (решение пользователя): seed подобран перебором — 4 туманные
		# местности по 8–9 клеток (у королевства, внизу посередине, справа), 5 групп руин,
		# центр боевой полосы чистый
		"map_seed": 131,
		"edge": SM_DEBRIS_WALL,
		"river": SM_RIVER,
		"decorations": SM_GOTHIC_DECOR,
		# Крепость из листа готики — лист из одного кадра (стрельба / попадание / падение — без анимации)
		"citadel": {"sheet": SM_PROPS + "gothic_09.png", "frame_size": Vector2i(264, 244),
			"anchor": Vector2(132, 178), "scale": 0.6, "fps": 1.0, "rows": {"idle": [0, 1]},
			"tint": GOTHIC_CITADEL_TINT},
	},
}

static func get_theme(faction: String) -> Dictionary:
	return THEMES.get(faction, THEMES[DEFAULT_FACTION])

# Тема текущего забега
static func current() -> Dictionary:
	return get_theme(RunManager.player_faction)

# Текстура по пути: из ресурсов проекта или файлом (тесты, user://). Кэш обязателен:
# пол рисуется в _draw — текстура, созданная на вызов, освободилась бы до отрисовки
static var _textures: Dictionary = {}

static func load_texture(path: String) -> Texture2D:
	if not _textures.has(path):
		var tex: Texture2D = null
		if path.begins_with("res://"):
			tex = load(path) if ResourceLoader.exists(path) else null
		else:
			var img = Image.load_from_file(ProjectSettings.globalize_path(path))
			tex = ImageTexture.create_from_image(img) if img else null
		_textures[path] = tex
	return _textures[path]
