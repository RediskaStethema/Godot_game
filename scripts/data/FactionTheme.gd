class_name FactionTheme
extends RefCounted

# Оформление поля боя и цитадели по расе ИГРОКА (решение пользователя: цитадель
# только у игрока; все плитки поля — в стиле выбранной игроком расы, раса врага
# на вид не влияет). Раса забега — RunManager.player_faction (выбор расы — позже).
#
# Плитка (floor / kingdom / enemy) — вариант для клетки, выбирается по хэшу клетки:
#   int    — номер Tiles/Slice N лунного тайлсета (блок, TerrainTiles.draw_block)
#   String — путь к PNG ромба клетки целиком (TerrainTiles.draw_tile_texture):
#            ширина картинки = ширина клетки, верхняя грань — ромб 2:1 в верхней части
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

const THEMES = {
	"space_marines": {
		"floor": TerrainTiles.FLOOR,
		"kingdom": TerrainTiles.KINGDOM,
		"enemy": TerrainTiles.ENEMY,
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
