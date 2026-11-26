// То же со сложением (огонь, искры, свечение — "add": true в Vfx.EFFECTS)
shader_type canvas_item;
render_mode blend_add;
#include "res://shaders/fx_pixel.gdshaderinc"
void fragment() {
	COLOR = fx_pixel(COLOR, FRAGCOORD.xy);
}
