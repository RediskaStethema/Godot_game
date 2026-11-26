// Лист эффекта / снаряда с обычным смешиванием — пиксельный (fx_pixel.gdshaderinc); Vfx._make, Projectile
shader_type canvas_item;
#include "res://shaders/fx_pixel.gdshaderinc"
void fragment() {
	COLOR = fx_pixel(COLOR, FRAGCOORD.xy);
}
