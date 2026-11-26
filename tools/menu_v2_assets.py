"""Новое главное меню (решение пользователя 16.11.2026: «переделай меню так, как на эталоне exec-cd0d7c5f….png», ассеты —
NewAssets/07_ui/assets/ui/menu/anim): слои сцены и элементы интерфейса пакета → файлы игры.

  слои сцены (как есть) -> assets/ui/menu/anim/: menu_night_sky_stars, menu_storm_clouds, distant_fortress_bridge,
      menu_capital_ship, menu_castle_battlement (положение и масштаб слоёв на холсте 1774x887 — MenuSceneArt, подобраны по
      эталону: assets/source_sheets/menu_v2/locate.py / mock.py / layout.json);
  кнопки -> assets/ui/button_menu_{normal,hover,pressed,disabled}.png 640x104 (рамка пакета обрезана по видимому и
      уменьшена; hover — «active» рамка, pressed — она же темнее, disabled — обычная тусклая);
  шапка -> assets/ui/menu/header_wreath.png (череп в венке), header_rule.png (разделитель; половинки — по краям венка);
  иконки кнопок -> assets/ui/menu/icon_chevrons / icon_wreath / icon_ammo / icon_gear / icon_exit .png (квадрат 144 px).
Прежние файлы — assets/source_sheets/_backup_before_redesign_2026-11-15/ui/menu_v2/.

  python tools/menu_v2_assets.py        затем  godot --headless --import
"""
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "NewAssets/07_ui/assets/ui/menu/anim"
UI = ROOT / "assets/ui"
ANIM = UI / "menu/anim"
BACKUP = ROOT / "assets/source_sheets/_backup_before_redesign_2026-11-15/ui/menu_v2"
LAYERS = ["menu_night_sky_stars", "menu_storm_clouds", "distant_fortress_bridge", "menu_capital_ship",
          "menu_castle_battlement"]
BUTTON = (640, 104)
ICON = 144
ICON_PAD = 0.1
ICON_GAIN = 1.55   # яркость иконок кнопок (в эталоне — светлая медь)
WREATH_H = 200
RULE_W = 720


def crop_alpha(im: Image.Image, thr: int = 20) -> Image.Image:
    bb = im.getchannel("A").point(lambda v: 255 if v > thr else 0).getbbox()
    return im.crop(bb)


def load(name: str) -> Image.Image:
    return Image.open(SRC / (name + ".png")).convert("RGBA")


def premult_resize(im: Image.Image, size) -> Image.Image:
    """Уменьшение без тёмной каймы на прозрачном краю: цвет — по премультиплицированной альфе."""
    import numpy as np
    a = np.asarray(im).astype(np.float32)
    al = a[..., 3:4] / 255.0
    pm = Image.fromarray(np.concatenate([a[..., :3] * al, a[..., 3:4]], 2).round().astype(np.uint8))
    sm = np.asarray(pm.resize(size, Image.BOX)).astype(np.float32)
    al2 = sm[..., 3:4] / 255.0
    rgb = np.where(al2 > 0, sm[..., :3] / np.maximum(al2, 1e-4), 0).clip(0, 255)
    return Image.fromarray(np.concatenate([rgb, sm[..., 3:4]], 2).round().astype(np.uint8))


def square_icon(name: str, out: str) -> None:
    im = crop_alpha(load(name))
    side = int(max(im.size) * (1 + 2 * ICON_PAD))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
    r, g, b, al = premult_resize(sq, (ICON, ICON)).split()
    rgb = Image.merge("RGB", (r, g, b)).point(lambda v: min(255, int(v * ICON_GAIN)))   # иконки пакета тёмные — на кнопке не читались
    Image.merge("RGBA", (*rgb.split(), al)).save(UI / "menu" / (out + ".png"))


def main() -> None:
    BACKUP.mkdir(parents=True, exist_ok=True)
    for f in [UI / f"button_menu_{s}.png" for s in ("normal", "hover", "pressed", "disabled")] + \
             [UI / "menu" / f"icon_{n}.png" for n in ("continue", "eagle", "skull", "test", "settings", "quit")]:
        if f.exists() and not (BACKUP / f.name).exists():
            shutil.copyfile(f, BACKUP / f.name)
    for n in LAYERS:
        shutil.copyfile(SRC / (n + ".png"), ANIM / (n + ".png"))
    normal = premult_resize(crop_alpha(load("menu_button_frame_default")), BUTTON)
    active = premult_resize(crop_alpha(load("menu_button_frame_active")), BUTTON)

    def shade(im: Image.Image, k: float, alpha: float = 1.0) -> Image.Image:
        r, g, b, a = im.split()
        rgb = Image.merge("RGB", (r, g, b)).point(lambda v: min(255, int(v * k)))
        out = Image.merge("RGBA", (*rgb.split(), a.point(lambda v: int(v * alpha))))
        return out

    normal.save(UI / "button_menu_normal.png")
    active.save(UI / "button_menu_hover.png")
    shade(active, 0.78).save(UI / "button_menu_pressed.png")
    shade(normal, 0.55, 0.85).save(UI / "button_menu_disabled.png")
    wreath = crop_alpha(load("menu_skull_wreath_emblem"))
    premult_resize(wreath, (round(wreath.size[0] * WREATH_H / wreath.size[1]), WREATH_H)).save(UI / "menu/header_wreath.png")
    rule = crop_alpha(load("menu_divider"))
    premult_resize(rule, (RULE_W, round(rule.size[1] * RULE_W / rule.size[0]))).save(UI / "menu/header_rule.png")
    square_icon("menu_selection_chevrons", "icon_chevrons")
    square_icon("menu_skull_wreath_emblem", "icon_wreath")
    square_icon("menu_arsenal_icon", "icon_ammo")
    square_icon("menu_gear_icon", "icon_gear")
    square_icon("menu_exit_icon", "icon_exit")
    print("слои, кнопки, шапка и иконки меню записаны; затем: godot --headless --import")


if __name__ == "__main__":
    main()
