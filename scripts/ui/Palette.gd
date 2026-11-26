class_name Palette
extends RefCounted

# -------------------------------------------------------
# ПАЛИТРА — по концепту меню assets_menu.png: холодный тёмно-синий металл,
# стальная окантовка, янтарь для акцентов (наведение, главное действие, цифры).
# Без зависимостей — можно звать из данных (StatusEffects и т.п.); UITheme ссылается на неё теми же
# именами (UITheme тянет Building и автолоады — из скриптов данных его не звать).
# Имена исторические: GOLD* — янтарные акценты, GOLD_DIM — сталь рамок.
# -------------------------------------------------------
# 16.11.2026 (решение пользователя, единый стиль под новое меню; было — холодный синий: BG_DEEP 0a0e15, BG_MID 16202e,
# PANEL (0.055, 0.075, 0.105), PANEL_DARK (0.035, 0.05, 0.075), GOLD_DIM 3b4350, TEXT d5dae0, TEXT_DIM 7f8893): тёплый тёмный камень
const BG_DEEP      = Color("0d090b")
const BG_MID       = Color("1f1619")
const PANEL        = Color(0.085, 0.058, 0.064, 0.99)
const PANEL_DARK   = Color(0.055, 0.036, 0.042, 0.96)
const GOLD         = Color("d39a3a")
const GOLD_BRIGHT  = Color("f0b04a")
const GOLD_DIM     = Color("4a3a36")
const TEXT         = Color("dad2c4")
const TEXT_DIM     = Color("8c8478")
const RED          = Color("8e2620")
const RED_BRIGHT   = Color("c8463a")
const GREEN        = Color("6fbf5a")

# --- Мир боя: общие цвета подсветки, сигналов и надписей (новые цвета — сюда, не литералами в файлах) ---
const OUTLINE      = Color(0.0, 0.0, 0.0, 0.85)   # обводка надписей в мире и HUD
const BUILDING_OUTLINE = Color(0.0, 0.0, 0.0, 1.0)  # контур зданий: на тёмном грунте Хаоса 0.85 не читался
const DIM_OVERLAY  = Color(0.0, 0.0, 0.0, 0.6)    # затемнение под окнами и баннерами
const PLAYER_SIDE  = GOLD                         # свои: кольцо под бойцом, рамка королевства
const ENEMY_SIDE   = RED_BRIGHT
const TUTORIAL_DIM = Color(0.05, 0.035, 0.04, 0.38)   # затемнение под диалогом обучения: тёплый тёмный камень вместо чистого чёрного
const TUTORIAL_PULSE = Color(1.45, 1.25, 0.8)         # пульс подсказанной карты / слота: было (1.7, 1.4, 0.7) — пересвет
const AMBER_LIGHT  =Color(1.0, 0.83, 0.4)        # огонёк: ромбики уровня, усиление, выстрел цитадели
const TIMELINE_DONE = Color(0.95, 0.42, 0.36)    # лента забега: пройденный путь и волны тлеют красным
const TIMELINE_GLOW = Color(1.0, 0.27, 0.18)     # лента забега: свечение текущей волны
const GOLD_PALE    = Color("ffeaa8")               # белое золото: ромб клетки «свой отряд того же типа»
# Стена вокруг владений (KingdomWall): камень Космодесанта — готическая сталь с латунью, Хаоса — бордовый
# камень с костяными шипами
const WALL_STONE       = Color(0.11, 0.12, 0.16)
const WALL_STONE_TOP   = Color(0.2, 0.22, 0.28)
const WALL_STONE_DARK  = Color(0.045, 0.05, 0.07)
const WALL_TRIM        = Color(0.66, 0.5, 0.26)    # латунные навершия столбов
# Стена Хаоса — тёмный бордо поля (палитра «бордо + варп», 23.10.2026; было 0.21 / 0.36 — плоская яркая)
const CHAOS_WALL_STONE = Color(0.13, 0.045, 0.055)
const CHAOS_WALL_TOP   = Color(0.23, 0.08, 0.095)
const CHAOS_WALL_DARK  = Color(0.06, 0.018, 0.026)
const CHAOS_WALL_SPIKE = Color(0.64, 0.57, 0.48)   # кость шипов
# Стена края поля Хаоса (FieldWall, решение пользователя 10.11.2026 по образцу «Мимо сетки…»): тёмный буро-бордовый
# камень, серые каменные шипы, фонари — красный огонь; тень стены на земле и грань платформы (IsoGridRenderer)
const CHAOS_FIELD_WALL      = Color(0.15, 0.085, 0.085)
const CHAOS_FIELD_WALL_TOP  = Color(0.23, 0.14, 0.13)
const CHAOS_FIELD_WALL_DARK = Color(0.05, 0.028, 0.032)
const CHAOS_FIELD_SPIKE     = Color(0.36, 0.3, 0.28)
const CHAOS_LANTERN         = Color(1.0, 0.4, 0.18)
const CHAOS_LANTERN_GLOW    = Color(1.0, 0.36, 0.16, 0.38)
const CHAOS_BRAZIER_GLOW    = Color(1.0, 0.34, 0.58, 0.32)   # жаровня у цитадели — розово-малиновое пламя
# Стена края поля Космодесанта кодом (FieldWall, решение пользователя 12.11.2026, `Screenshot 2026-11-10 130254.png`:
# плиты "edge" выбивались — светлее, холоднее, без объёма): камень стены владений, навершия — латунь, фонари — огонь
const SM_FIELD_WALL      = Color(0.145, 0.125, 0.14)   # 16.11.2026: был холодный (0.12, 0.13, 0.165) — под бордо-камень меню
const SM_FIELD_WALL_TOP  = Color(0.25, 0.215, 0.235)
const SM_FIELD_WALL_DARK = Color(0.06, 0.045, 0.058)
const SM_FIELD_SPIKE     = Color(0.42, 0.33, 0.18)    # латунное навершие столба
const SM_LANTERN         = Color(1.0, 0.62, 0.26)
const SM_LANTERN_GLOW    = Color(1.0, 0.55, 0.2, 0.32)
const FIELD_WALL_SHADE      = Color(0.0, 0.0, 0.0, 0.7)   # тень стены на земле у основания (к полю — в ноль)
const CHAOS_PLATFORM_SIDE   = Color(0.07, 0.035, 0.04)     # грань платформы под ближним краем
const SM_PLATFORM_SIDE      = Color(0.06, 0.045, 0.058)    # то же у Космодесанта — тёмная сталь
const FIRE         = Color(1.0, 0.55, 0.15)
const POISON       = Color(0.55, 0.9, 0.3)
const RARE_GLOW    = Color("4f8fc4")               # подсветка Rare карт — сине-стальная, тлеющая (CardGlare)
const EPIC_GLOW    = Color("9a4cc8")               # подсветка Epic карт — варп-фиолетовая
const WARP_EMBER   = Color("e8a0ff")               # искры варпа на кромке Epic карт
const POISON_DEEP  = Color("4f7a24")               # кромка ауры котла Nurgle (AuraRing)
const SLAANESH     = Color("b8436e")               # аура святилища Slaanesh: розовое бордо (AuraRing)
const SLAANESH_PALE = Color("f3b6cc")
const LEVEL_RING_CHAOS = Color("d0405a")          # кольцо уровня здания у Хаоса (у Космодесанта — GOLD)
const HEAL         = Color(0.55, 1.0, 0.55)
const HEAL_DEEP    = Color("449458")               # кромка света лечения (Казармы — LevelUpGlow "heal")
const SHIELD_BLUE  = Color(0.45, 0.72, 1.0)       # щит Iron Halo и щит цитадели
const SLOW_BLUE    = Color(0.45, 0.65, 0.95)      # замедление (статус и аура стены)
const HIT_RED      = Color(1.0, 0.45, 0.4)        # урон по своим: цифры, вспышка цитадели
# Эффекты зданий и стены кодом (BuildingFx, EFFECTS_NEEDED 4.2 / 4.10 / 8.5 / 8.6): волна от здания к соседям,
# вампиризм Чаши крови, камни и пыль разбитого звена стены
const BLOOD        = Color("730508")
const BLOOD_BRIGHT = Color("cc0d0d")
const FROST        = Color("76bae8")               # клич Волчьего тотема
const FROST_PALE   = Color("e8f8ff")
const FORGE        = Color("e85e16")               # жар Кузни Вулкана
const FORGE_PALE   = Color("ffe296")
const DUST         = Color("584c3e")
const DUST_PALE    = Color("b6a894")
# Знак бога под ногами нового бойца бога (Святилище культа, EFFECTS_NEEDED 4.9): тёмный → яркий
const GOD_COLORS = {
	"khorne": [Color("801218"), Color("de441e")],
	"nurgle": [Color("58801e"), Color("d0ee76")],
	"tzeentch": [Color("264e8a"), Color("76bae8")],
	"slaanesh": [Color("ff5ab4"), Color("f6c8ff")],
}
# Имя бога в тексте (решение пользователя 09.11.2026: «бог подписан цветом бога»): читается на тёмной карточке
const GOD_TEXT = {
	"khorne": Color("e0432a"),     # кровь
	"nurgle": Color("8fc23a"),     # гниль
	"tzeentch": Color("5aa0e8"),   # варп-синий
	"slaanesh": Color("ff5ab4"),   # розовый
}
# Цвет легиона примарха-лоялиста (подпись босса); демоны-примархи — GOD_TEXT своего бога
const PRIMARCH_COLORS = {
	"primarch_guilliman": Color("4f86d8"),    # Ультрамарины — синий
	"primarch_sanguinius": Color("d8343a"),   # Кровавые Ангелы — алый
	"primarch_dorn": Color("e8c22a"),         # Имперские Кулаки — жёлтый
	"primarch_russ": Color("a8c4d6"),         # Космические Волки — серо-голубой
	"primarch_vulkan": Color("4fa83e"),       # Саламандры — зелёный
}

const LANDING_CLOUD = Color("3a3c40")              # дым посадки на поле (BattleLanding) — Космодесант: пепельный
const LANDING_CLOUD_CHAOS = Color("3b2422")        # то же у Хаоса — бурый дым
const LANDING_FIRE   = Color("8a3a12")              # отсвет пожаров снизу сквозь дым (гримдарк, 08.11.2026)
const LAUNCH_ASH     = Color("8e8a84")              # лучи взлёта — пепел и сталь, не цветные звёзды
const LAUNCH_EMBER   = Color("a8742a")              # редкий тусклый янтарь в лучах
const WARP_RIFT      = Color("3c0f2e")              # разрыв варпа при прыжке — мутный бордово-фиолетовый
const WARP_RIFT_CORE = Color("7a2a5a")
const MENU_SPACE   = Color("0b1018")               # космос главного меню — ровный, как на образце exampel.png
const MENU_BUTTON_TEXT = Color("d6cfc0")           # надпись кнопки меню — бежево-белая (образец)
const MENU_TITLE   = Color("cdc4b2")               # название Grim Kingdom — светлый беж (образец)
# Жетоны выбора расы / ордена (TokenCarousel, 13.11.2026): потемневшая латунь обода — от тени к блику
const TOKEN_RIM = [Color("140e09"), Color("2e2114"), Color("4f3a20"), Color("7a5b30"), Color("a98446"), Color("dcbf7c")]
const TOKEN_OUTLINE = Color("07060a")
const TOKEN_BAND = Color(0, 0, 0, 0.62)   # тёмная полоса за каруселью на фоне меню — текст читается на сцене
const STAR_WHITE   = Color(0.95, 0.96, 1.0)
const STAR_BLUE    = Color(0.7, 0.82, 1.0)
const STAR_AMBER   = Color(1.0, 0.86, 0.62)
# Шрамы поля (ScarLayer, 09.11.2026): подпалина — сажа с бурым краем, угольки
const SCORCH        = Color(0.05, 0.045, 0.04)
const SCORCH_EDGE   = Color(0.16, 0.12, 0.09)
const SCORCH_EMBER  = Color(1.0, 0.45, 0.12)

# Продавец магазина (ShopVendor, решение пользователя 11.11.2026): техножрец Адептус Механикус / тёмный механикус Хаоса.
# Заглушка кодом, пока нет листа художника; облако реплики — бумага и чернила; цепи вывески «Обновить» — сталь
const VENDOR_ROBE        = Color("5e1c18")   # ряса Механикус — приглушённый кроваво-красный
const VENDOR_ROBE_DARK   = Color("2e0d0b")
const VENDOR_ROBE_CHAOS  = Color("2a2220")   # тёмный механикус — копоть и бронза
const VENDOR_ROBE_CHAOS_DARK = Color("140f0e")
const VENDOR_METAL       = Color("6d6a62")   # аугметика, механодендриты
const VENDOR_METAL_DARK  = Color("33312d")
const VENDOR_BRASS       = Color("8a6a32")
const VENDOR_LENS        = Color("6fd88a")   # глаз-линза Механикус — зеленоватый свет когитатора
const VENDOR_LENS_CHAOS  = Color("d8443a")   # у тёмного механикус — красный
const VENDOR_LENS_ANGRY  = Color("ff5a3c")   # «нет Req» — линза вспыхивает красным
const BUBBLE_PAPER       = Color("d9cfb8")   # облако реплики — старый пергамент
const BUBBLE_EDGE        = Color("1c1814")
const BUBBLE_INK         = Color("221c16")
const VENDOR_CHAIN       = Color("4a4843")
const VENDOR_CHAIN_LIGHT = Color("7c786e")

# Магазин поверх поля (решение пользователя 12.11.2026, образец download.png): полупрозрачная тьма панелей —
# сквозь неё видно поле боя; кромка — ржавая латунь с заклёпками (ShopFrame), значки шапки — кодом
const SHOP_VEIL          = Color(0.06, 0.04, 0.045, 0.38)   # панель карт и продавца
const SHOP_BAR_VEIL      = Color(0.055, 0.035, 0.04, 0.72)    # шапка — плотнее: текст поверх яркого поля
const HUD_FADE          = Color(0.05, 0.035, 0.04, 0.62)    # шапка без рамки: тёмная подложка ступенями, сверху гуще — значки читаются над полем (17.11.2026)
const SHOP_SCREEN_DIM    = Color(0.0, 0.0, 0.0, 0.08)        # всё поле под магазином чуть темнее
const SHOP_FRAME         = Color("8a5a2c")   # ржавая латунь
const SHOP_FRAME_DARK    = Color("2e1c10")
const SHOP_FRAME_LIGHT   = Color("c08a46")
const SHOP_RUST          = Color("5a3418")
const SHOP_ICON          = Color("b9874a")   # значки шапки (колода / армия / настройки)
const SHOP_ICON_HOVER    = Color("e0b46a")
