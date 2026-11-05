"""Плита Космодесанта → красная (поле Хаоса): камень — приглушённый тёмно-красный, вода реки — кровь.

    python tools/tiles_recolor_red.py assets/sprites/tiles/space_marines/terrain.png assets/sprites/tiles/chaos/red_terrain.png

Форма и прозрачность плиты те же — top в FactionTheme как у исходной плиты.
"""
import sys, numpy as np
from PIL import Image
def redden(src, dst, hue=0.995, sat_mult=1.3, sat_add=0.08, val_mult=0.85):
    im = Image.open(src).convert('RGBA')
    a = np.array(im.getchannel('A'))
    hsv = np.array(im.convert('RGB').convert('HSV')).astype(float) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    liquid = (h > 0.18) & (h < 0.5) & (s > 0.25)
    h2 = (hue + (h - 0.6) * 0.06) % 1.0
    s2 = np.clip(s * sat_mult + sat_add * (v > 0.08), 0, 1)
    v2 = np.clip(v * val_mult, 0, 1)
    h2 = np.where(liquid, 0.99, h2)
    s2 = np.where(liquid, np.clip(0.55 + s * 0.5, 0, 0.95), s2)
    v2 = np.where(liquid, np.clip(v * 1.35, 0, 1), v2)
    out = Image.merge('HSV', [Image.fromarray((c * 255).astype(np.uint8)) for c in (h2, s2, v2)]).convert('RGBA')
    out.putalpha(Image.fromarray(a))
    out.save(dst)
if __name__ == '__main__':
    redden(sys.argv[1], sys.argv[2])
