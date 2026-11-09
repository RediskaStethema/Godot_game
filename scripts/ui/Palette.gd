class_name Palette
extends RefCounted

# -------------------------------------------------------
# ПАЛИТРА — по концепту меню assets_menu.png: холодный тёмно-синий металл,
# стальная окантовка, янтарь для акцентов (наведение, главное действие, цифры).
# Без зависимостей — можно звать из данных (StatusEffects и т.п.); UITheme ссылается на неё теми же
# именами (UITheme тянет Building и автолоады — из скриптов данных его не звать).
# Имена исторические: GOLD* — янтарные акценты, GOLD_DIM — сталь рамок.
# -------------------------------------------------------
const BG_DEEP      = Color("0a0e15")
const BG_MID       = Color("16202e")
const PANEL        = Color(0.055, 0.075, 0.105, 0.99)
const PANEL_DARK   = Color(0.035, 0.05, 0.075, 0.96)
const GOLD         = Color("d39a3a")
const GOLD_BRIGHT  = Color("f0b04a")
const GOLD_DIM     = Color("3b4350")
const TEXT         = Color("d5dae0")
const TEXT_DIM     = Color("7f8893")
const RED          = Color("8e2620")
const RED_BRIGHT   = Color("c8463a")
const GREEN        = Color("6fbf5a")

# --- Мир боя: общие цвета подсветки, сигналов и надписей (новые цвета — сюда, не литералами в файлах) ---
const OUTLINE      = Color(0.0, 0.0, 0.0, 0.85)   # обводка надписей в мире и HUD
const BUILDING_OUTLINE = Color(0.0, 0.0, 0.0, 1.0)  # контур зданий: на тёмном грунте Хаоса 0.85 не читался
const DIM_OVERLAY  = Color(0.0, 0.0, 0.0, 0.6)    # затемнение под окнами и баннерами
const PLAYER_SIDE  = GOLD                         # свои: кольцо под бойцом, рамка королевства
const ENEMY_SIDE   = RED_BRIGHT
const AMBER_LIGHT  = Color(1.0, 0.83, 0.4)        # огонёк: ромбики уровня, усиление, выстрел цитадели
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

# Космос главного меню (решение пользователя 06.11.2026: «меню на фоне космоса, звёзды сияют») — MenuStarfield
const LANDING_CLOUD = Color("3a3c40")              # дым посадки на поле (BattleLanding) — Космодесант: пепельный
const LANDING_CLOUD_CHAOS = Color("3b2422")        # то же у Хаоса — бурый дым
const LANDING_FIRE   = Color("8a3a12")              # отсвет пожаров снизу сквозь дым (гримдарк, 08.11.2026)
const LAUNCH_ASH     = Color("8e8a84")              # лучи взлёта — пепел и сталь, не цветные звёзды
const LAUNCH_EMBER   = Color("a8742a")              # редкий тусклый янтарь в лучах
const WARP_RIFT      = Color("3c0f2e")              # разрыв варпа при прыжке — мутный бордово-фиолетовый
const WARP_RIFT_CORE = Color("7a2a5a")
const MENU_SPACE   = Color("0b1018")               # космос главного меню — ровный, как на образце exampel.png
const MENU_BUTTON_TEXT = Color("d6cfc0")           # надпись кнопки меню — бежево-белая (образец)
const MENU_TITLE   = Color("cdc4b2")               # название WH40KINGS — светлый беж (образец)
const MENU_SUBTITLE = Color("9a9282")              # «Удержите цитадель 15 волн»
const SPACE_DEEP   = Color("05070c")               # глубина космоса (низ и левый край)
const STAR_WHITE   = Color(0.95, 0.96, 1.0)
const STAR_BLUE    = Color(0.7, 0.82, 1.0)
const STAR_AMBER   = Color(1.0, 0.86, 0.62)
# Телепорт Deep Strike (EFFECTS_NEEDED 5.3, кодом 09.11.2026 — BuildingFx.teleport): варп Империума
const TELEPORT_DEEP = Color("264e8a")
const TELEPORT      = Color("76bae8")
const TELEPORT_CORE = Color("e8f8ff")
# Шрамы поля (ScarLayer, 09.11.2026): подпалина — сажа с бурым краем, угольки
const SCORCH        = Color(0.05, 0.045, 0.04)
const SCORCH_EDGE   = Color(0.16, 0.12, 0.09)
const SCORCH_EMBER  = Color(1.0, 0.45, 0.12)
