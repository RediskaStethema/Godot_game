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
# available = false — видна, но закрыта («Скоро»); открыть расу — true + тема и юниты.
# enemy — раса волн врагов в забеге за эту расу (EnemyWaves; решение пользователя 16.10.2026:
# Хаос воюет с Космодесантом)
const FACTIONS = [
	{"id": "space_marines", "name": "Космодесант", "available": true, "enemy": "chaos",
		"desc": "Ангелы Смерти: стойкие отряды и цитадель-бастион."},
	{"id": "chaos", "name": "Хаос", "available": true, "enemy": "space_marines",
		"desc": "Предатели и демонические машины. Воюют с Космодесантом."},
	{"id": "tyranids", "name": "Тираниды", "available": false,
		"desc": "Рой, пожирающий миры."},
]

static func get_faction_info(faction: String) -> Dictionary:
	for f in FACTIONS:
		if f["id"] == faction:
			return f
	return {}

# Раса волн врагов в забеге за faction
static func enemy_of(faction: String) -> String:
	return get_faction_info(faction).get("enemy", "chaos")

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
# Воронки в тумане: плита — осыпь с воронками, туман — слой дымки над полем (IsoGridRenderer._draw_mist,
# ключ "mist"): мягкие пятна шире клетки сливаются в облако над всей туманной местностью, густеет и
# редеет волной. Решение пользователя 19.10.2026: туман, залитый в плиту (fog_crater_0/1.png), складывался
# в «шахматку» светлых ромбов. Приглушён (решение пользователя): яркий туман перетягивал внимание с бойцов
const FOG_MIST = {"color": Color(0.6, 0.67, 0.8, 0.1), "radius": 90.0}
const SM_FOG_CRATERS = [{"texture": SM_TILES + "terrain_craters.png", "top": 10, "no_decor": true, "mist": FOG_MIST}]
const SM_FLAG = [{"texture": SM_TILES + "flag.png", "top": 120, "flag": true}]     # обломки и знамя
# Готика Империума: лист assets/source_sheets/goticImperial.png → tools/props_from_sheet.py
# (assets/sprites/props/space_marines/gothic_NN.png, base — точка земли под объектом). Решение пользователя:
# руины на поле, декор вместо лунных камней, цитадель (gothic_09); лист заменён пользователем 15.10.2026 (30 объектов)
const SM_PROPS = "res://assets/sprites/props/space_marines/"
const GOTHIC_SCALE: float = 0.35        # руины: площадка плазы (gothic_13) ≈ клетка
const GOTHIC_DECOR_SCALE: float = 0.22  # мелкий декор
const WAR_BANNER_SCALE: float = 0.26    # знамёна UI_assets.png (ориентиры): ≈ 2 роста бойца
const ANIM_DECOR_SCALE: float = 1.0     # пиксельные знамёна и костёр (32–48 px) — в рост бойца
# Готика светлее и теплее грунта (средний цвет 44,40,34 против 19,27,37) — темнее и холоднее, но не
# до цвета грунта, чтобы читалась (решение пользователя: ближе к грунту); цитадель — цветокор запечён
# в лист (tools/sm_grade.py: камень — к стали грунта, золото и знамёна глуше, огни ярче остального;
# средняя яркость 0.17 — чуть светлее грунта 0.145), оттенка в теме у неё нет
# Свет на поле (IsoGridRenderer, слой свечения с ADD-смешением): ключ "glow" у плиты или объекта темы
const FIRE_GLOW = Color(1.0, 0.55, 0.2, 0.55)
const LAVA_GLOW = Color(1.0, 0.35, 0.1, 0.6)
const WARP_GLOW = Color(1.0, 0.18, 0.25, 0.45)
const GOTHIC_TINT = Color(0.62, 0.70, 0.85)
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
# Ориентиры поля (решение пользователя 17.10.2026, пока на карте Космодесанта) — анимированные объекты на
# своих клетках, не случайным декором (IsoGridRenderer._landmark_cells): 2 костра — у базы и за рекой,
# 3 знамени — одно у костра у базы и random_banners в случайных местах на стороне игрока вне боевой полосы.
# "war_banners" + "war_banner_count" — большие знамёна (UI_assets.png) на стороне игрока вне боевой полосы,
# не ближе WAR_BANNER_GAP клеток к другим ориентирам; все ключи необязательны (у Хаоса — только знамёна).
# Листы кадров в ряд (TerrainTiles.draw_prop): знамёна — GIF assets/flag/flag1–3.gif, костёр — campfire-Sheet.png
const SM_CAMPFIRE = {"texture": SM_PROPS + "campfire.png", "frames": 6, "fps": 10.0, "base": Vector2(17, 42),
	"scale": ANIM_DECOR_SCALE, "glow": FIRE_GLOW, "glow_radius": 75.0}
const SM_BANNERS = [
	{"texture": SM_PROPS + "banner_1.png", "frames": 7, "fps": 10.0, "base": Vector2(4.5, 34), "scale": ANIM_DECOR_SCALE},
	{"texture": SM_PROPS + "banner_2.png", "frames": 4, "fps": 10.0, "base": Vector2(5, 32), "scale": ANIM_DECOR_SCALE},
	{"texture": SM_PROPS + "banner_3.png", "frames": 4, "fps": 10.0, "base": Vector2(6.5, 42), "scale": ANIM_DECOR_SCALE},
]
# Знамёна листа UI_assets.png в палитре расы (tools/banners_from_sheet.py; решение пользователя 17.10.2026):
# синее с аквилой, белое с аквилой, чёрное с черепом — ориентиры "war_banners" на стороне игрока
const SM_WAR_BANNERS = [
	{"texture": SM_PROPS + "war_banner_1.png", "base": Vector2(41, 236), "scale": WAR_BANNER_SCALE, "tint": GOTHIC_TINT},
	{"texture": SM_PROPS + "war_banner_2.png", "base": Vector2(40, 240), "scale": WAR_BANNER_SCALE, "tint": GOTHIC_TINT},
	{"texture": SM_PROPS + "war_banner_3.png", "base": Vector2(41, 246), "scale": WAR_BANNER_SCALE, "tint": GOTHIC_TINT},
]
const SM_FEATURES = [
	{"tiles": SM_RUINS + SM_GOTHIC_RUINS, "clusters": 5, "size": [2, 4]},
	{"tiles": SM_CRATER, "scatter": 0.04},
	{"tiles": SM_SMALL_CRATERS, "scatter": 0.06},
	{"tiles": SM_FOG_CRATERS, "clusters": 4, "size": [5, 9]},   # туманные местности
]

# Поле Хаоса (решение пользователя 16.10.2026: как местность Космодесанта — грунт, стена и река статичны,
# анимированы только детали). Основа — плиты Космодесанта, перекрашенные в красный (red_*: камень
# приглушённо-красный, вода реки — кровь; tools/tiles_recolor_red.py), top — как у исходных плит.
# Детали Хаоса — с листа assets/source_sheets/Chaos_assets2png.png: окопы — варианты без анимации, знамёна и кристаллы —
# анимация 12 кадров; обелиски (assets/chaos_assets/obelisk1–4.png) — 3 группы, кристаллы разгораются.
# top деталей — от нижнего угла плиты (толщина ≈ 0.18 ширины)
const CH_TILES = "res://assets/sprites/tiles/chaos/"
const CH_PROPS = "res://assets/sprites/props/chaos/"
# Палитра (решение пользователя 17.10.2026: ассеты Хаоса — к одной палитре): детали с листа Хаоса (кристаллы,
# окопы, знамёна, обелиски), цитадель и объекты крепости приведены к тону и яркости красного грунта
# tools/palette_match.py (кадры одной анимации — с --group); оригиналы — листы в assets/
const CH_TERRAIN = [{"texture": CH_TILES + "red_terrain.png", "top": 10}]      # красная осыпь
const CH_DEBRIS_WALL = [{"texture": CH_TILES + "red_wall.png", "top": 67, "axis": "u"}]
# Реки на поле Хаоса нет (решение пользователя 17.10.2026; плиты red_river_* остались в папке темы)
const CH_RUINS = [{"texture": CH_TILES + "red_ruins_bunker.png", "top": 48}]
const CH_CRATER = [{"texture": CH_TILES + "red_crater.png", "top": 20, "no_decor": true}]
const CH_SMALL_CRATERS = [{"texture": CH_TILES + "red_terrain_craters.png", "top": 10}]
# Осыпь с кристаллами варпа — редкие одиночные клетки. Кристаллы — лист terrain_sheet_assets.png (решение пользователя 17.10.2026, вместо прежних 12 кадров):
# 5 кадров, свечение разгорается; tools/tile_frames_from_sheet.py (одно окно по плите — top общий),
# палитра — tools/palette_match.py --group. Кадры 0→4→1 по кругу: разгорается и гаснет без скачка
const CH_CRYSTALS = [{"fps": 1.5, "glow": WARP_GLOW, "glow_radius": 55.0, "frames": [
	{"texture": CH_TILES + "terrain_0.png", "top": 214},
	{"texture": CH_TILES + "terrain_1.png", "top": 214},
	{"texture": CH_TILES + "terrain_2.png", "top": 214},
	{"texture": CH_TILES + "terrain_3.png", "top": 214},
	{"texture": CH_TILES + "terrain_4.png", "top": 214},
	{"texture": CH_TILES + "terrain_3.png", "top": 214},
	{"texture": CH_TILES + "terrain_2.png", "top": 214},
	{"texture": CH_TILES + "terrain_1.png", "top": 214},
]}]
# Обломки и знамя Хаоса — только на стороне игрока; знамя колышется (12 кадров листа)
const CH_FLAG = [{"fps": 1.0, "flag": true, "frames": [
	{"texture": CH_TILES + "flag_0.png", "top": 35},
	{"texture": CH_TILES + "flag_1.png", "top": 38},
	{"texture": CH_TILES + "flag_2.png", "top": 38},
	{"texture": CH_TILES + "flag_3.png", "top": 34},
	{"texture": CH_TILES + "flag_4.png", "top": 41},
	{"texture": CH_TILES + "flag_5.png", "top": 39},
	{"texture": CH_TILES + "flag_6.png", "top": 34},
	{"texture": CH_TILES + "flag_7.png", "top": 21},
	{"texture": CH_TILES + "flag_8.png", "top": 28},
	{"texture": CH_TILES + "flag_9.png", "top": 26},
	{"texture": CH_TILES + "flag_10.png", "top": 27},
	{"texture": CH_TILES + "flag_11.png", "top": 25},
]}]
const CH_TRENCH = [  # окопы
	{"texture": CH_TILES + "trench_0.png", "top": 13},
	{"texture": CH_TILES + "trench_1.png", "top": 17},
	{"texture": CH_TILES + "trench_2.png", "top": 18},
	{"texture": CH_TILES + "trench_3.png", "top": 27},
	{"texture": CH_TILES + "trench_4.png", "top": 23},
	{"texture": CH_TILES + "trench_5.png", "top": 35},
	{"texture": CH_TILES + "trench_6.png", "top": 37},
	{"texture": CH_TILES + "trench_7.png", "top": 32},
	{"texture": CH_TILES + "trench_8.png", "top": 41},
	{"texture": CH_TILES + "trench_9.png", "top": 35},
	{"texture": CH_TILES + "trench_10.png", "top": 37},
	{"texture": CH_TILES + "trench_11.png", "top": 48},
]
const CH_OBELISK = [{"fps": 1.2, "no_decor": true, "frames": [   # кристаллы разгораются
	{"texture": CH_TILES + "obelisk_0.png", "top": 53},
	{"texture": CH_TILES + "obelisk_1.png", "top": 53},
	{"texture": CH_TILES + "obelisk_2.png", "top": 53},
	{"texture": CH_TILES + "obelisk_3.png", "top": 53},
]}]
# Извержение (решение пользователя 17.10.2026: была вспышка при ударах игрока — стала обычной анимированной
# клеткой): лист assets/Spritesheets/Chaos Tile Blast-Sheet.png, 7 кадров по кругу — трещины → выброс камней →
# выжженная земля; кадр — ширина грани 232 по центру 127, палитра — tools/palette_match.py --group
const CH_BLAST = [{"fps": 2.0, "no_decor": true, "glow": LAVA_GLOW, "glow_radius": 85.0, "frames": [
	{"texture": CH_TILES + "blast_0.png", "top": 92},
	{"texture": CH_TILES + "blast_1.png", "top": 92},
	{"texture": CH_TILES + "blast_2.png", "top": 92},
	{"texture": CH_TILES + "blast_3.png", "top": 92},
	{"texture": CH_TILES + "blast_4.png", "top": 92},
	{"texture": CH_TILES + "blast_5.png", "top": 92},
	{"texture": CH_TILES + "blast_6.png", "top": 92},
]}]
# Руины и декор Хаоса — объекты листа assets/source_sheets/Изометрический набор демонической крепости.png (белый фон вырезан,
# нарезка tools/props_from_sheet.py, номер объекта — в имени; base — с нарезки), как готика у Космодесанта:
# руины — объект на плите красной осыпи ("tall" — выше бойца, только вне боевой полосы), декор — мелкие
const CH_PROPS_SCALE: float = 0.36    # руины: площадка (12) ≈ клетка
const CH_DECOR_SCALE: float = 0.22    # мелкий декор
const CH_CHAOS_RUINS = [
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "tall": true, "prop": {"texture": CH_PROPS + "chaos_03.png", "base": Vector2(108, 136), "scale": CH_PROPS_SCALE}},   # ruined_towers
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "tall": true, "prop": {"texture": CH_PROPS + "chaos_07.png", "base": Vector2(117, 166), "scale": CH_PROPS_SCALE}},   # skull_wall
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_04.png", "base": Vector2(128, 117), "scale": CH_PROPS_SCALE}},   # broken_wall
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_12.png", "base": Vector2(188, 102), "scale": CH_PROPS_SCALE}},   # star_plaza
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_13.png", "base": Vector2(185, 102), "scale": CH_PROPS_SCALE}},   # warp_crack_plaza
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_14.png", "base": Vector2(166, 101), "scale": CH_PROPS_SCALE}},   # grate_plaza
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_15.png", "base": Vector2(192, 128), "scale": CH_PROPS_SCALE}},   # broken_stairs
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_17.png", "base": Vector2(100, 87), "scale": CH_PROPS_SCALE}},   # skull_pile
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_20.png", "base": Vector2(133, 74), "scale": CH_PROPS_SCALE}},   # rubble
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_21.png", "base": Vector2(136, 98), "scale": CH_PROPS_SCALE}},   # wrecked_gun
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "flag": true, "prop": {"texture": CH_PROPS + "chaos_22.png", "base": Vector2(138, 104), "scale": CH_PROPS_SCALE}},   # fallen_banner
	{"texture": CH_TILES + "red_terrain.png", "top": 10, "prop": {"texture": CH_PROPS + "chaos_30.png", "base": Vector2(112, 71), "scale": CH_PROPS_SCALE}},   # spiked_wall
]
const CH_DECOR = [
	{"texture": CH_PROPS + "chaos_05.png", "base": Vector2(62, 253), "scale": CH_DECOR_SCALE},   # star_obelisk
	{"texture": CH_PROPS + "chaos_16.png", "base": Vector2(91, 240), "scale": CH_DECOR_SCALE},   # horned_shrine
	{"texture": CH_PROPS + "chaos_18.png", "base": Vector2(46, 134), "scale": CH_DECOR_SCALE, "flag": true},   # banner
	{"texture": CH_PROPS + "chaos_19.png", "base": Vector2(95, 150), "scale": CH_DECOR_SCALE},   # skull_altar
	{"texture": CH_PROPS + "chaos_23.png", "base": Vector2(57, 86), "scale": CH_DECOR_SCALE},   # chest
	{"texture": CH_PROPS + "chaos_24.png", "base": Vector2(58, 88), "scale": CH_DECOR_SCALE},   # chest_2
	{"texture": CH_PROPS + "chaos_25.png", "base": Vector2(48, 110), "scale": CH_DECOR_SCALE},   # barrel
	{"texture": CH_PROPS + "chaos_26.png", "base": Vector2(93, 106), "scale": CH_DECOR_SCALE},   # warp_shrine
	{"texture": CH_PROPS + "chaos_27.png", "base": Vector2(44, 130), "scale": CH_DECOR_SCALE},   # brazier
	{"texture": CH_PROPS + "chaos_28.png", "base": Vector2(68, 96), "scale": CH_DECOR_SCALE},   # big_chest
	{"texture": CH_PROPS + "chaos_29.png", "base": Vector2(56, 111), "scale": CH_DECOR_SCALE},   # dome
]
# Знамёна UI_assets.png в тоне красного грунта: красно-чёрное с черепом, со скелетом, чёрное с черепом
const CH_WAR_BANNERS = [
	{"texture": CH_PROPS + "war_banner_1.png", "base": Vector2(40, 237), "scale": WAR_BANNER_SCALE},
	{"texture": CH_PROPS + "war_banner_2.png", "base": Vector2(39, 255), "scale": WAR_BANNER_SCALE},
	{"texture": CH_PROPS + "war_banner_3.png", "base": Vector2(41, 246), "scale": WAR_BANNER_SCALE},
]
# Меньше шума (решение пользователя 19.10.2026: глазу негде отдохнуть — между ориентирами нужен ровный
# грунт, как у Космодесанта): группы руин мельче, обелисков и кристаллов меньше, декора — "decor_chance"
const CH_FEATURES = [
	{"tiles": CH_CHAOS_RUINS + CH_TRENCH, "clusters": 5, "size": [2, 3]},
	{"tiles": CH_CRATER, "scatter": 0.04},
	{"tiles": CH_SMALL_CRATERS, "scatter": 0.06},
	{"tiles": CH_CRYSTALS, "scatter": 0.02},
	{"tiles": CH_OBELISK, "clusters": 2, "size": [3, 5]},
	{"tiles": CH_BLAST, "scatter": 0.03},   # последней — раскладка остальных деталей карты не меняется
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
		"grade": {},   # WorldGrade.DEFAULT — сталь в тенях, янтарь в светах
		"atmosphere": "ash",
		"building_tint": Color(0.5, 0.56, 0.68),   # блоки зданий без спрайта — готическая сталь
		"landmarks": {"campfire": SM_CAMPFIRE, "banners": SM_BANNERS, "random_banners": 2,
			"war_banners": SM_WAR_BANNERS, "war_banner_count": 3},
		# Крепость-бастион — лист assets/source_sheets/citadel_spacemarine_spritesheet.png (tools/citadel_from_bands.py:
		# кадры по номерам под рядами, каждый подогнан к первому кадру idle по силуэту и по высоте крыши — основание и размер
		# не гуляют, метки основания и следы снарядов убраны; цветокор — tools/sm_grade.py): стоит неподвижно — idle
		# из одного кадра (решение пользователя 19.10.2026: знамя на ветру прыгало; в листе 8 кадров),
		# выстрел орудия на крыше (вспышка во всех кадрах — снаряд на 2-м, из ствола muzzle),
		# попадание, обрушение до груды со знаменем. scale — площадка как у прежней крепости.
		# Ряд: [ряд листа, кадров, кадров/с]
		"citadel": {"sheet": SM_PROPS + "citadel/sheet.png", "frame_size": Vector2i(211, 219),
			"anchor": Vector2(105, 206), "scale": 0.88, "muzzle": Vector2(145, 44), "shot_frame": 1,
			"rows": {"idle": [0, 1, 8.0], "attack": [1, 9, 12.0], "hit": [2, 3, 10.0], "fall": [3, 12, 8.0]}},
	},
	"chaos": {
		"floor": CH_RUINS + CH_CRATER + CH_SMALL_CRATERS,
		"kingdom": CH_TERRAIN,
		"enemy": CH_RUINS + CH_CRATER + CH_SMALL_CRATERS,
		"ground": CH_TERRAIN,
		"features": CH_FEATURES,
		"flags": {"tiles": CH_FLAG, "count": 2},
		"map_seed": 131,
		"edge": CH_DEBRIS_WALL,
		"decorations": CH_DECOR,
		"decor_chance": 6,   # % клеток вне боевой полосы с декором (по умолчанию IsoGridRenderer.DECOR_CHANCE)
		# Подсветки края силуэта ("unit_rim", Soldier.RIM_SHADER) нет — решение пользователя 20.10.2026:
		# оранжевый контур на хаоситах лишний, поле и так темнее и глуше
		# Красное поле: насыщенность выше, тени — в бордо, света — в огонь
		"grade": {"saturation": 0.86, "shadow_tone": Color(0.028, 0.006, 0.01), "highlights": Color(1.08, 0.96, 0.86)},
		"atmosphere": "embers",
		"building_tint": Color(0.58, 0.38, 0.36),  # блоки зданий без спрайта — ржаво-бордовый камень
		"landmarks": {"war_banners": CH_WAR_BANNERS, "war_banner_count": 4},   # костров и знамён-GIF нет
		# Крепость с черепом — лист assets/source_sheets/Изометрический набор демонической крепости.png (решение
		# пользователя 17.10.2026; белый фон вырезан заливкой от краёв, нарезка tools/props_from_sheet.py,
		# объект 00); лист из одного кадра, размер на поле — как у цитадели Космодесанта
		"citadel": {"sheet": CH_PROPS + "fortress.png", "frame_size": Vector2i(272, 266),
			"anchor": Vector2(136, 198), "scale": 0.58, "fps": 1.0, "rows": {"idle": [0, 1]}},
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
