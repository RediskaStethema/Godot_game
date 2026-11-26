class_name RaceSelectDialog
extends ModalOverlay

# Выбор расы нового забега (FactionTheme.FACTIONS) — карусель жетонов (TokenCarousel, решение пользователя
# 13.11.2026: «выбор расы и ордена колесом, но не карт, а жетонов»): жетон на расу, закрытые видны, но недоступны
# («Скоро»). chosen(faction) — по выбору доступной; окно закрывается и при выборе, и по «◀ НАЗАД» / Esc. Без рамки — на фоне главного меню (build_bare).

# Цвет поля жетона расы
const ACCENTS = {"space_marines": Color("2c4f8c"), "chaos": Color("8a1c1c"), "tyranids": Color("6b3d7a"),
	"necrons": Color("2f7a4a")}

signal chosen(faction: String)

var carousel: TokenCarousel
var _chosen: bool = false   # двойной клик в одном кадре не запустит забег дважды

func setup() -> void:
	close_on_cancel = true
	build_bare(860.0)   # на фоне главного меню, без рамки (решение пользователя 13.11.2026)
	add_title("ВЫБОР РАСЫ")
	add_title("Раса определяет армию, поле боя и цитадель", "DimLabel")
	var items: Array = []
	var start := -1
	for f in FactionTheme.FACTIONS:
		var open: bool = f["available"]
		if open and start < 0:
			start = items.size()
		items.append({"id": f["id"], "name": f["name"], "open": open,
			"icon": UITheme.ui_icon("races", f["id"]), "accent": ACCENTS.get(f["id"], UITheme.GOLD_DIM),
			"lines": [[f["desc"], "SmallLabel", null]] if open else [["Скоро", "DimLabel", null]]})
	carousel = TokenCarousel.new()
	content.add_child(carousel)
	carousel.setup(items, "Race_", maxi(start, 0))
	carousel.chosen.connect(choose)
	_focus_taken = true   # фокус — на первую доступную расу (жетон в центре)
	add_back_button()
	ModalOverlay.focus_later(carousel.token(items[maxi(start, 0)]["id"]))

# Выбор расы; закрытую выбрать нельзя
func choose(faction: String) -> void:
	if _chosen or not FactionTheme.is_available(faction):
		return
	_chosen = true
	emit_signal("chosen", faction)
	close()
