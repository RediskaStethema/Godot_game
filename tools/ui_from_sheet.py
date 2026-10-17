"""Лист интерфейса UI_assets.png (корень проекта, прозрачный фон) → текстуры UITheme и главного меню.

    python tools/ui_from_sheet.py UI_assets.png

Пишет:
  assets/ui/button_normal|hover|pressed.png — кнопки без текста и иконки (StyleBoxTexture 9-slice:
      левый и правый край листа + чистый кусок середины, BUTTON_CAP по краям)
  assets/ui/frame.png       — рамка окна, внутри залита PANEL, аквила сверху заменена ровной кромкой
  assets/ui/frame_eagle.png — аквила рамки (ставится поверх окна отдельно — 9-slice её бы растянул)
  assets/ui/divider_skull.png — разделитель с черепом
  assets/ui/menu/icon_*.png — иконки, menu_scene.png — сцена с башней, logo_eagle.png — золотая аквила
Координаты — по листу 1536×1024 (найдены по альфе); новый лист другой раскладки — поправить таблицы ниже.
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

OUT = Path("assets/ui")
PAD = 2
PANEL = (14, 19, 27, 252)          # UITheme.PANEL
BUTTON_CAP = 16                    # чистый край кнопки слева / справа (дальше — иконка листа)
BUTTON_MIDDLE = 24                 # ширина куска середины (повторяется при растяжении)

ICONS = {   # имя → рамка на листе
    "icon_eagle": (1248, 88, 1306, 127), "icon_skull": (1320, 86, 1352, 127),
    "icon_settings": (1369, 86, 1407, 126), "icon_book": (1421, 88, 1459, 124),
    "icon_quit": (1475, 86, 1510, 125), "icon_eagle_wide": (1247, 164, 1303, 204),
    "icon_continue": (1313, 161, 1355, 203), "icon_skull_2": (1369, 161, 1403, 203),
    "icon_target": (1418, 160, 1459, 203), "icon_cog": (1471, 160, 1511, 203),
    "icon_search": (1255, 232, 1299, 276), "icon_compass": (1313, 230, 1357, 279),
    "icon_diamond": (1368, 232, 1406, 275), "icon_list": (1422, 236, 1455, 270),
    "icon_warning": (1472, 234, 1510, 271),
}
# Кнопка: рамка и x чистой середины (правее надписи «NEW GAME»)
BUTTONS = {
    "button_normal": ((993, 91, 1207, 143), 1158),
    "button_hover": ((993, 185, 1211, 239), 1160),
    "button_pressed": ((995, 288, 1210, 341), 1160),
}
FRAME = (1230, 423, 1507, 552)
FRAME_EAGLE = (102, 0, 178, 44)    # в координатах рамки
FRAME_PLAIN = (60, 96)             # ровный кусок кромки (между углом и аквилой) — повторяется на её месте
DIVIDER = (1229, 562, 1508, 612)
SCENE = (355, 42, 711, 628)
LOGO = (104, 82, 256, 138)         # золотая аквила над названием (без надписи листа)


def crop(img, box, pad=PAD):
    return img.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))


def blank_button(img, box, mid_x):
    """Кнопка без иконки и надписи: левый край + кусок середины + правый край."""
    src = img.crop(box)
    w, h = src.size
    mid = img.crop((mid_x, box[1], mid_x + BUTTON_MIDDLE, box[3]))
    out = Image.new("RGBA", (BUTTON_CAP * 2 + BUTTON_MIDDLE, h), (0, 0, 0, 0))
    out.paste(src.crop((0, 0, BUTTON_CAP, h)), (0, 0))
    out.paste(mid, (BUTTON_CAP, 0))
    out.paste(src.crop((w - BUTTON_CAP, 0, w, h)), (BUTTON_CAP + BUTTON_MIDDLE, 0))
    return out


def fill_inside(frame):
    """Прозрачная середина рамки (заливка от центра) — цвет панели. Подложка — с запасом 3 px под
    кромку: полупрозрачная тень рамки внутри ложится на панель, а не на затемнение окна."""
    px = frame.load()
    w, h = frame.size
    inside = Image.new("L", (w, h), 0)
    ip = inside.load()
    stack, seen = [(w // 2, h // 2)], set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or px[x, y][3] > 200:
            continue
        seen.add((x, y))
        ip[x, y] = 255
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    inside = inside.filter(ImageFilter.MaxFilter(7))
    under = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    under.paste(Image.new("RGBA", (w, h), PANEL), (0, 0), inside)
    under.alpha_composite(frame)
    return under


def main(sheet):
    img = Image.open(sheet).convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda a: 0 if a < 16 else a))   # ореол фона листа
    (OUT / "menu").mkdir(parents=True, exist_ok=True)
    for name, box in ICONS.items():
        crop(img, box).save(OUT / "menu" / f"{name}.png")
    for name, (box, mid_x) in BUTTONS.items():
        blank_button(img, box, mid_x).save(OUT / f"{name}.png")

    frame = img.crop(FRAME)
    eagle = frame.crop(FRAME_EAGLE)
    ex0, ey0, ex1, ey1 = FRAME_EAGLE
    # аквила → ровная кромка: кусок левее повторяется по ширине аквилы, до её низа
    frame.paste((0, 0, 0, 0), (ex0, ey0, ex1, ey1))
    plain = frame.crop((FRAME_PLAIN[0], ey0, FRAME_PLAIN[1], ey1))
    for x in range(ex0, ex1, plain.width):
        frame.paste(plain.crop((0, 0, min(plain.width, ex1 - x), plain.height)), (x, ey0))
    frame = fill_inside(frame)
    frame.save(OUT / "frame.png")
    eagle.save(OUT / "frame_eagle.png")
    crop(img, DIVIDER).save(OUT / "divider_skull.png")
    img.crop(SCENE).save(OUT / "menu" / "menu_scene.png")
    img.crop(LOGO).save(OUT / "menu" / "logo_eagle.png")
    print("готово:", OUT)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "UI_assets.png")
