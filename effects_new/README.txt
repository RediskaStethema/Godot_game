WH40KINGS — pixel grimdark flamethrower VFX

Source sheets (transparent RGBA, frames arranged left-to-right):
assets/source_sheets/flamethrower_start.png — 6 x 64x64, 24 fps, muzzle anchor (0,32), one-shot.
assets/source_sheets/flamethrower_jet.png — 8 x 128x48, 20 fps, loop; left and right edge columns match pixel-for-pixel for seamless tiling.
assets/source_sheets/flamethrower_hit.png — 8 x 64x64, 20 fps, center anchor (32,32), one-shot.
assets/source_sheets/flamethrower_tail.png — 4 x 64x48, 20 fps, optional P2 fade-out.

Numbered individual PNG frames are under frames/<animation>/.
Fire palette: #260A08, #8C1E0C, #C94311, #E85E16, #FAA83A, #FFE296. Smoke uses low-alpha dark neutral for normal alpha blending.
