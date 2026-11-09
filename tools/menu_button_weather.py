"""Состаренные кнопки главного меню (решение пользователя 08.11.2026, образец assets/FInalUI/exampel.png):
у кнопок пакета ровная тёмно-синяя заливка, на образце — потёртая серая сталь: зерно, царапины, сколы, темнее
к рамке. Рамка кнопки остаётся своей (сталь / янтарь), заливка внутри рамки (заливкой от центра по цвету фона
кнопки) — новая, крупным пикселем (зерно рисуется вчетверо мельче и растягивается без сглаживания — как арт пакета).

  python tools/menu_button_weather.py

Вход:  assets/ui/button_<состояние>.png (не меняются)
Выход: assets/ui/button_menu_<состояние>.png (UITheme._menu_button_styles), потом godot --headless --import
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "assets/ui"
SEED = 40
CHUNK = 4            # зерно — блоками CHUNK×CHUNK px текстуры (на экране ×0.5 — 2 px)
FILL_TOL = 34        # насколько пиксель может отличаться от цвета заливки, чтобы считаться заливкой
# состояние: (базовый цвет стали, сила потемнения к рамке, яркость царапин)
STATES = {
    "normal":   ((50, 51, 53), 0.45, 1.0),
    "hover":    ((44, 38, 32), 0.5, 0.9),    # янтарная рамка — заливка теплее и темнее (образец: «Продолжить»)
    "pressed":  ((36, 32, 28), 0.55, 0.7),
    "disabled": ((30, 31, 33), 0.4, 0.5),
}


def fill_mask(rgba: np.ndarray) -> np.ndarray:
    """Заливка внутри рамки: от центра по пикселям цвета центра (рамка и уголки её останавливают)."""
    h, w = rgba.shape[:2]
    rgb = rgba[..., :3].astype(np.int32)
    ref = rgb[h // 2, w // 2]
    close = (np.abs(rgb - ref).sum(axis=2) <= FILL_TOL) & (rgba[..., 3] > 200)
    mask = np.zeros((h, w), bool)
    q = deque([(h // 2, w // 2)])
    mask[h // 2, w // 2] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and close[ny, nx]:
                mask[ny, nx] = True
                q.append((ny, nx))
    return mask


def chunky_noise(rng, h, w, scale):
    """Шум крупным пикселем: случайное поле размером /scale, растянутое без сглаживания."""
    small = rng.random((h // scale + 2, w // scale + 2))
    return np.kron(small, np.ones((scale, scale)))[:h, :w]


def smooth_noise(rng, h, w, cell):
    """Плавные пятна (грязь, потёртости) — билинейно из сетки cell."""
    gh, gw = h // cell + 2, w // cell + 2
    g = rng.random((gh, gw))
    yy = np.arange(h) / cell
    xx = np.arange(w) / cell
    y0 = yy.astype(int)
    x0 = xx.astype(int)
    fy = (yy - y0)[:, None]
    fx = (xx - x0)[None, :]
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def edge_distance(mask: np.ndarray) -> np.ndarray:
    """Расстояние (px) от пикселя заливки до края заливки — простое по осям (заливка — прямоугольник)."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    yy = np.arange(h)[:, None]
    xx = np.arange(w)[None, :]
    return np.minimum(np.minimum(yy - y0, y1 - yy), np.minimum(xx - x0, x1 - xx)).astype(np.float32)


def scratches(rng, h, w, count, brightness):
    """Царапины: тонкие наклонные штрихи, светлые (сталь под краской) и тёмные (бороздки)."""
    out = np.zeros((h, w), np.float32)
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(0, h)
        length = rng.uniform(10, 46)
        ang = rng.uniform(-0.5, 0.5) + (np.pi if rng.random() < 0.5 else 0.0)
        sign = 1.0 if rng.random() < 0.6 else -1.0
        for t in np.linspace(0, length, int(length) * 2):
            px = int(x + np.cos(ang) * t) // 2 * 2
            py = int(y + np.sin(ang) * t * 0.35) // 2 * 2
            if 0 <= py < h - 1 and 0 <= px < w - 1:
                out[py:py + 2, px:px + 2] = sign * brightness
    return out


def weather(state: str, base, edge_dark: float, scratch_k: float) -> None:
    src = Image.open(UI / f"button_{state}.png").convert("RGBA")
    rgba = np.array(src)
    h, w = rgba.shape[:2]
    # форма заливки у всех состояний одна — берётся с обычной кнопки (у неактивной центр другого цвета)
    mask = fill_mask(np.array(Image.open(UI / "button_normal.png").convert("RGBA")))
    rng = np.random.default_rng(SEED)   # одна раскладка на все состояния — кнопка не «перерисовывается» при наведении
    grain = chunky_noise(rng, h, w, CHUNK) - 0.5                  # зерно металла
    blot = smooth_noise(rng, h, w, 18) - 0.5                       # пятна грязи и потёртостей
    streak = np.kron(rng.random((h // CHUNK + 2, 1)), np.ones((CHUNK, w)))[:h, :w] - 0.5   # следы шлифовки
    marks = scratches(rng, h, w, 34, 26.0 * scratch_k)
    chips = (chunky_noise(rng, h, w, CHUNK) > 0.985) * -22.0       # сколы — тёмные точки
    dist = edge_distance(mask)
    vignette = 1.0 - edge_dark * np.clip(1.0 - dist / 22.0, 0.0, 1.0) ** 1.5
    lum = (np.array(base, np.float32)[None, None, :]
           + (grain * 14.0 + blot * 22.0 + streak * 6.0 + marks + chips)[..., None])
    lum *= vignette[..., None]
    # верх заливки чуть светлее низа — свет сверху, как у всего интерфейса
    yy = np.arange(h, dtype=np.float32)[:, None, None] / h
    lum *= 1.08 - 0.16 * yy
    out = rgba.copy()
    out[..., :3][mask] = np.clip(lum, 0, 255).astype(np.uint8)[mask]
    out[..., 3][mask] = 255
    Image.fromarray(out).save(UI / f"button_menu_{state}.png")
    print(f"button_menu_{state}.png — заливка {mask.sum()} px")


def main() -> None:
    for state, (base, edge_dark, scratch_k) in STATES.items():
        if (UI / f"button_{state}.png").exists():
            weather(state, base, edge_dark, scratch_k)


if __name__ == "__main__":
    main()
