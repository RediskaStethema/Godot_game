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
#            на линии по другой оси плита отражается
# decorations — [имя файла Decorations_tiles, плоский ли] (как TerrainTiles.DECORATIONS)
#
# citadel — вид цитадели:
#   {}                — башня из блоков тайлсета (Citadel.BLOCKS)
#   {"sheet": путь к PNG-листу кадров, "frame_size": Vector2i, "anchor": Vector2
#    (точка основания башни в кадре, px), "scale": float, "fps": float,
#    "rows": {"idle": [ряд, кадров], "attack": [...], "hit": [...], "fall": [...]}}
#    idle — по кругу; attack (выстрел), hit (попадание) — один раз и снова idle;
#    fall — при 0 HP, остаётся на последнем кадре.
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

# Плиты Космодесанта: лист assets/FightFleed/photo_2026-10-13_12-08-49.png → tools/tiles_from_sheet.py.
# Решение пользователя: королевство — seamless terrain (осыпь), край карты — debris wall (стена),
# ядовитый ручей — только линиями рек через поле, остальное (ничья земля, зона врага) — как реальная
# местность: грунт (та же осыпь) и редкие детали — пара групп руин и окопов, одиночные кратеры;
# знамёна — немного и только на стороне игрока
const SM_TILES = "res://assets/sprites/tiles/space_marines/"
const SM_TERRAIN = [{"texture": SM_TILES + "tile_0.png", "top": 15}]      # каменная осыпь с воронками
const SM_DEBRIS_WALL = [{"texture": SM_TILES + "tile_5.png", "top": 8, "axis": "u"}]   # стена с обломками
const SM_RIVER = [{"texture": SM_TILES + "tile_6.png", "top": 8, "axis": "v"}]        # ядовитый ручей
const SM_RUINS = [
	{"texture": SM_TILES + "tile_1.png", "top": 72},   # руины с бункером
	{"texture": SM_TILES + "tile_7.png", "top": 20},   # бункер
	{"texture": SM_TILES + "tile_8.png", "top": 34},   # развалины
]
const SM_CRATER = [{"texture": SM_TILES + "tile_2.png", "top": 18}]   # большой кратер
const SM_TRENCH = [{"texture": SM_TILES + "tile_4.png", "top": 6}]    # окоп
const SM_FLAG = [{"texture": SM_TILES + "tile_3.png", "top": 84}]     # обломки и знамя
const SM_FEATURES = [
	{"tiles": SM_RUINS, "clusters": 3, "size": [2, 4]},
	{"tiles": SM_TRENCH, "clusters": 2, "size": [2, 3]},
	{"tiles": SM_CRATER, "scatter": 0.04},
]

const THEMES = {
	"space_marines": {
		"floor": SM_RUINS + SM_CRATER + SM_TRENCH,
		"kingdom": SM_TERRAIN,
		"enemy": SM_RUINS + SM_CRATER + SM_TRENCH,
		"ground": SM_TERRAIN,
		"features": SM_FEATURES,
		"flags": {"tiles": SM_FLAG, "count": 3},
		"edge": SM_DEBRIS_WALL,
		"river": SM_RIVER,
		"decorations": TerrainTiles.DECORATIONS,
		# TODO: листы assets/citadel_sprite_list/space_marine и плитки assets/FightFleed/space_marin,
		# когда будут PNG с прозрачным фоном
		"citadel": {},
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
