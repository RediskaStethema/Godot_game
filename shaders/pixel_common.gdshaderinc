// Общее для пиксельной стилизации (решение пользователя 12.11.2026: «стилизуй эффекты, модельки и ассеты»):
// упорядоченный дизеринг Байера 4×4 — порог 0..1 по клетке экрана. Без массивов (надёжнее в Compatibility):
// известная формула через bayer2 — значение клетки 2×2, рекурсивно до 4×4
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}
// Ступени: значение 0..1 → levels ступеней, граница ступени — по порогу дизеринга d (0..1)
vec3 posterize_dither(vec3 c, float levels, float d) {
	return clamp(floor(c * levels + d) / levels, 0.0, 1.0);
}
