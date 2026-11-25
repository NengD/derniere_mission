// Effet « caméra-piéton » (bodycam) appliqué à l'image finale.
// Grand-angle déformé (fisheye), aberration chromatique, flou de mouvement directionnel,
// compression vidéo (blocs 8x8, couleurs écrasées), grain, vignettage, sang sur l'objectif.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;      // réglage global de l'effet
uniform float distortion : hint_range(0.0, 1.0) = 0.24;     // 0 = coupé (option mal des transports)
uniform float zoom_fit : hint_range(0.5, 1.2) = 0.76;      // recadrage pour cacher les bords courbés
uniform float chroma : hint_range(0.0, 0.02) = 0.0035;
uniform float grain : hint_range(0.0, 0.5) = 0.07;
uniform float compression : hint_range(0.0, 1.0) = 0.35;
uniform float vignette : hint_range(0.0, 2.0) = 0.9;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float saturation : hint_range(0.0, 1.5) = 0.78;
uniform float exposure : hint_range(0.2, 3.0) = 1.0;
uniform float black_lift : hint_range(0.0, 0.1) = 0.012;
uniform vec3 tint_shadows : source_color = vec3(0.47, 0.52, 0.55);
uniform vec3 tint_highlights : source_color = vec3(0.55, 0.52, 0.47);
uniform float split_tone : hint_range(0.0, 1.0) = 0.25;
uniform vec2 motion = vec2(0.0);                             // déplacement de l'image (UV/seconde), pour le flou
uniform float motion_blur : hint_range(0.0, 1.0) = 0.6;
uniform float blood : hint_range(0.0, 1.0) = 0.0;           // sang sur l'objectif
uniform float hurt : hint_range(0.0, 1.0) = 0.0;            // blessure : vision trouble, désaturée
uniform float flash : hint_range(0.0, 1.0) = 0.0;           // éblouissement (tir, explosion)

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec2 barrel(vec2 uv, float k, float aspect) {
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float r2 = dot(c, c);
	c *= (1.0 + k * r2 + 0.35 * k * r2 * r2) * zoom_fit;
	return c / vec2(aspect, 1.0) + 0.5;
}

vec3 sample_rgb(vec2 uv, vec2 dir, float ca) {
	vec3 col;
	col.r = textureLod(screen_tex, uv + dir * ca, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - dir * ca, 0.0).b;
	return col;
}

// sang sur l'objectif : deux ou trois grosses taches irrégulières sur les bords, des gouttelettes,
// et de courtes coulures (procédural, déformé par du bruit pour éviter les formes géométriques)
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float blood_mask(vec2 uv, float aspect) {
	vec2 p = uv * vec2(aspect, 1.0);
	float m = 0.0;
	// grosses taches près des bords
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(hash(vec2(fi, 3.1)) < 0.5 ? 0.12 * aspect : 0.86 * aspect, 0.15 + 0.7 * hash(vec2(7.7, fi)));
		c.x += (hash(vec2(fi, 1.3)) - 0.5) * 0.15;
		float r = 0.1 + 0.12 * hash(vec2(fi * 1.7, 2.3));
		vec2 d = p - c;
		float f = fbm(p * 6.0 + fi * 13.0);
		float blob = smoothstep(r, r * 0.55, length(d * vec2(1.0, 1.3)) + (f - 0.5) * 0.18);
		// coulures courtes vers le bas
		float col_x = fract(d.x * 14.0 + fi) ;
		float drip = step(0.82, hash(vec2(floor(d.x * 14.0 + fi), fi))) * smoothstep(0.25, 0.0, abs(col_x - 0.5))
			* step(0.0, d.y) * smoothstep(r + 0.12 * hash(vec2(floor(d.x * 14.0), 4.0)), r * 0.6, d.y) * step(abs(d.x), r * 0.8);
		m = max(m, max(blob, drip * 0.85) * step(fi, 2.0 * blood));
	}
	// gouttelettes projetées
	vec2 g = p * 9.0;
	vec2 gi = floor(g);
	vec2 gf = fract(g) - 0.5;
	vec2 o = vec2(hash(gi), hash(gi + 5.0)) - 0.5;
	float dr = 0.06 + 0.2 * hash(gi + 9.0);
	float drop = smoothstep(dr, dr * 0.6, length(gf - o * 0.5)) * step(0.9, hash(gi + 2.0));
	m = max(m, drop * smoothstep(0.2, 0.7, fbm(p * 2.0 + 3.0)));
	return clamp(m, 0.0, 1.0);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = SCREEN_UV;

	// 1) grand-angle déformé
	float k = distortion * intensity;
	vec2 duv = barrel(uv, k, aspect);

	// 2) blocs de compression : légère quantification de la position en blocs de 8 px là où ça bouge
	float moving = clamp(length(motion) * 2.0, 0.0, 1.0);
	vec2 block = floor(duv * res / 8.0);
	float bjit = (hash(block + floor(TIME * 12.0)) - 0.5) * compression * intensity * moving;
	duv += vec2(bjit) * SCREEN_PIXEL_SIZE * 6.0;

	// 3) aberration chromatique (croît vers les bords) + flou de mouvement
	vec2 fromc = duv - 0.5;
	float ca = chroma * intensity * (0.4 + 2.5 * dot(fromc, fromc)) + hurt * 0.004;
	vec3 col = vec3(0.0);
	float n = 0.0;
	vec2 mv = motion * motion_blur * intensity * 0.05;
	for (int i = 0; i < 8; i++) {
		float t = float(i) / 7.0 - 0.5;
		col += sample_rgb(duv + mv * t, normalize(fromc + 1e-5), ca);
		n += 1.0;
	}
	col /= n;
	// vision trouble quand on est blessé
	if (hurt > 0.01) {
		vec3 b = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.047 + TIME;
			b += textureLod(screen_tex, duv + vec2(cos(a), sin(a)) * 0.006 * hurt, 2.0).rgb;
		}
		col = mix(col, b / 6.0, hurt * 0.7);
	}

	// hors image (bords du fisheye) -> noir
	if (duv.x < 0.0 || duv.x > 1.0 || duv.y < 0.0 || duv.y > 1.0) col = vec3(0.0);

	// 4) étalonnage : capteur bon marché (exposition, contraste, couleurs ternes, noirs relevés)
	col *= exposure;
	col = col / (1.0 + col * 0.15);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(l), col, mix(1.0, saturation, intensity) * (1.0 - hurt * 0.6));
	col = (col - 0.5) * mix(1.0, contrast, intensity) + 0.5;
	vec3 tone = mix(tint_shadows, tint_highlights, smoothstep(0.05, 0.6, l)) * 2.0;
	col = mix(col, col * tone, split_tone * intensity);
	col = max(col, vec3(0.0)) * (1.0 - black_lift) + black_lift * intensity;

	// 5) compression : couleurs écrasées dans les zones sombres (banding), blocs 8x8
	float q = mix(255.0, 48.0, compression * intensity);
	vec3 qcol = floor(col * q + hash(block) * 0.5) / q;
	col = mix(col, qcol, smoothstep(0.35, 0.0, l));

	// 6) sang sur l'objectif
	float bm = blood_mask(uv, aspect) * smoothstep(0.0, 0.3, blood);
	// le sang est translucide : il teinte et brouille l'image derrière lui
	vec3 behind = textureLod(screen_tex, duv, 3.0).rgb;
	float thick = fbm(uv * 30.0);
	vec3 blood_col = behind * vec3(0.32, 0.03, 0.025) + vec3(0.045, 0.002, 0.0);
	blood_col *= 0.6 + 0.6 * thick;
	col = mix(col, blood_col, bm * 0.95);

	// 7) vignettage optique + grain du capteur (plus fort dans les ombres)
	vec2 vc = (uv - 0.5) * vec2(aspect, 1.0) * 0.82;
	float vig = 1.0 - smoothstep(0.35, 1.05, length(vc)) * vignette * intensity;
	col *= vig;
	float g = hash(uv * res + fract(TIME * 37.1) * 100.0) - 0.5;
	col += g * grain * intensity * (1.4 - l);
	col += flash * vec3(1.0, 0.92, 0.8);
	// légère ligne de balayage (capteur à obturateur roulant)
	col *= 1.0 - 0.025 * intensity * step(0.5, fract(uv.y * res.y * 0.5));

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
