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
const DIM_OVERLAY  = Color(0.0, 0.0, 0.0, 0.6)    # затемнение под окнами и баннерами
const PLAYER_SIDE  = GOLD                         # свои: кольцо под бойцом, рамка королевства
const ENEMY_SIDE   = RED_BRIGHT
const AMBER_LIGHT  = Color(1.0, 0.83, 0.4)        # огонёк: ромбики уровня, усиление, выстрел цитадели
const FIRE         = Color(1.0, 0.55, 0.15)
const POISON       = Color(0.55, 0.9, 0.3)
const HEAL         = Color(0.55, 1.0, 0.55)
const SHIELD_BLUE  = Color(0.45, 0.72, 1.0)       # щит Iron Halo и щит цитадели
const SLOW_BLUE    = Color(0.45, 0.65, 0.95)      # замедление (статус и аура стены)
const HIT_RED      = Color(1.0, 0.45, 0.4)        # урон по своим: цифры, вспышка цитадели
