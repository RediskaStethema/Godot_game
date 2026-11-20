class_name ChapterSelectDialog
extends ModalOverlay

# Выбор ордена (Космодесант) или бога-покровителя (Хаос) нового забега (Chapters) — после выбора расы; карусель
# жетонов (TokenCarousel, решение пользователя 13.11.2026). Под жетоном — бонус, минус и особые карты выбранного.
# chosen(chapter) — по выбору; «◀ НАЗАД» / Esc закрывает окно без старта забега. Без рамки — на фоне главного меню (build_bare).

signal chosen(chapter: String)

var carousel: TokenCarousel
var _chosen: bool = false   # двойной клик в одном кадре не запустит забег дважды
var all_open: bool = false  # тестовый режим: открыты все ордены / боги, мета-прогрессия не держит

func setup(faction: String = Chapters.FACTION, open_all: bool = false) -> void:
	all_open = open_all
	close_on_cancel = true
	build_bare(860.0)   # на фоне главного меню, без рамки (решение пользователя 13.11.2026)
	var text: Array = Chapters.SELECT_TEXT.get(faction, Chapters.SELECT_TEXT[Chapters.FACTION])
	add_title(text[0])
	add_title(text[1], "DimLabel")
	var items: Array = []
	var start := -1
	for c in Chapters.for_faction(faction):
		var open := _is_open(c["id"])
		if open and start < 0:
			start = items.size()
		items.append(_item(c, open))
	carousel = TokenCarousel.new()
	content.add_child(carousel)
	carousel.setup(items, "Chapter_", maxi(start, 0))
	carousel.chosen.connect(choose)
	_focus_taken = true   # фокус — на первый открытый орден (жетон в центре)
	add_back_button()
	if not items.is_empty():
		ModalOverlay.focus_later(carousel.token(items[maxi(start, 0)]["id"]))

# Жетон ордена / бога: поле — цвет брони ордена или бога, строки — бонус, минус, особые карты (у открытых)
func _item(c: Dictionary, open: bool) -> Dictionary:
	var accent: Color = UITheme.GOLD_DIM
	var title_color: Color = UITheme.GOLD_BRIGHT
	if c.has("armor"):
		var a: Dictionary = c["armor"]
		accent = c.get("token_color", Color.from_hsv(a["hue"], a["sat"], a["val"]))
	elif Palette.GOD_COLORS.has(c["id"]):
		accent = Palette.GOD_COLORS[c["id"]][0]
		title_color = Palette.GOD_COLORS[c["id"]][1]
	var lines: Array = []
	if open:
		lines.append([c["desc"], "SmallLabel", null])
		if c.has("malus_desc"):
			lines.append(["Минус: " + c["malus_desc"], "SmallLabel", UITheme.RED_BRIGHT])
		var specials: Array[String] = []
		for key in ["unit_card", "building_card"]:
			var card_data := CardFactory.special_card(c.get(key, ""))
			if card_data:
				specials.append(card_data.display_title())
		if not specials.is_empty():
			lines.append(["Особые: " + ", ".join(specials), "DimLabel", null])
	else:
		lines.append([MetaProgress.chapter_lock_text(c["id"]), "DimLabel", null])
	return {"id": c["id"], "name": Names.of(c["name"]), "open": open, "icon": UITheme.ui_icon("emblems", c["id"]),
		"accent": accent, "title_color": title_color, "lines": lines, "fire": c.has("token_color")}

func choose(chapter: String) -> void:
	if _chosen or Chapters.get_chapter(chapter).is_empty() or not _is_open(chapter):
		return
	_chosen = true
	emit_signal("chosen", chapter)
	close()

func _is_open(chapter: String) -> bool:
	return all_open or MetaProgress.is_chapter_unlocked(chapter)
