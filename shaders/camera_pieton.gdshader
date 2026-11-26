// Effet « caméra-piéton » (bodycam) appliqué à l'image finale (après le tonemap de Godot).
// Imite une petite caméra corporelle : objectif très grand-angle (fisheye, coins noirs arrondis),
// aberration chromatique, flou de mouvement, compression vidéo (macroblocs et couleurs sous-échantillonnées
// surtout quand l'image bouge vite), bruit numérique dans le noir (luminance + chroma, en grumeaux),
// étalonnage de capteur bon marché (noirs bouchés, hautes lumières brûlées, couleurs ternes),
// reflets d'objectif (traînée horizontale et images fantômes près des lampes), sang sur l'objectif.
// `intensity` dose tout ; `distortion` = 0 coupe la déformation (option mal des transports).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;      // réglage global de l'effet
uniform float distortion : hint_range(0.0, 1.0) = 0.42;     // 0 = coupé (option mal des transports)
uniform float zoom_fit : hint_range(0.5, 1.2) = 0.72;       // recadrage pour garder l'image utile
uniform float corner_round : hint_range(0.0, 1.0) = 1.0;    // coins noirs arrondis de l'objectif
uniform float chroma : hint_range(0.0, 0.02) = 0.004;
uniform float grain : hint_range(0.0, 0.5) = 0.09;
uniform float chroma_noise : hint_range(0.0, 0.5) = 0.06;
uniform float compression : hint_range(0.0, 1.0) = 0.6;
uniform float vignette : hint_range(0.0, 2.0) = 0.6;
uniform float contrast : hint_range(0.5, 2.0) = 1.18;
uniform float saturation : hint_range(0.0, 1.5) = 0.74;
uniform float exposure : hint_range(0.2, 3.0) = 1.0;
uniform float black_crush : hint_range(0.0, 0.2) = 0.045;   // noirs bouchés
uniform float black_lift : hint_range(0.0, 0.1) = 0.012;    // voile du capteur
uniform float highlight_burn : hint_range(0.0, 1.0) = 0.5;  // hautes lumières qui brûlent vers le blanc
uniform vec3 tint_shadows : source_color = vec3(0.45, 0.53, 0.52);
uniform vec3 tint_highlights : source_color = vec3(0.56, 0.53, 0.45);
uniform float split_tone : hint_range(0.0, 1.0) = 0.3;
uniform float flare : hint_range(0.0, 2.0) = 0.5;           // reflets d'objectif
uniform vec2 motion = vec2(0.0);                             // déplacement de l'image (UV/seconde)
uniform float motion_blur : hint_range(0.0, 1.0) = 0.7;
uniform float blood : hint_range(0.0, 1.0) = 0.0;           // sang sur l'objectif
uniform float hurt : hint_range(0.0, 1.0) = 0.0;            // blessure : vision trouble, désaturée
uniform float flash : hint_range(0.0, 1.0) = 0.0;           // éblouissement (tir, explosion)
uniform float frame_seed = 0.0;                              // change à chaque image (bruit temporel)

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

vec2 barrel(vec2 uv, float k, float aspect, float fit) {
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float r2 = dot(c, c);
	c *= (1.0 + k * r2 + 0.45 * k * r2 * r2) * fit;
	return c / vec2(aspect, 1.0) + 0.5;
}

vec3 rgb2ycc(vec3 c) {
	float y = dot(c, vec3(0.299, 0.587, 0.114));
	return vec3(y, (c.b - y) * 0.565, (c.r - y) * 0.713);
}

vec3 ycc2rgb(vec3 c) {
	return vec3(c.x + 1.403 * c.z, c.x - 0.344 * c.y - 0.714 * c.z, c.x + 1.773 * c.y);
}

// sang sur l'objectif : grosses taches irrégulières sur les bords, gouttelettes, courtes coulures
float blood_mask(vec2 uv, float aspect) {
	vec2 p = uv * vec2(aspect, 1.0);
	float m = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(hash(vec2(fi, 3.1)) < 0.5 ? 0.12 * aspect : 0.86 * aspect, 0.15 + 0.7 * hash(vec2(7.7, fi)));
		c.x += (hash(vec2(fi, 1.3)) - 0.5) * 0.15;
		float r = 0.1 + 0.12 * hash(vec2(fi * 1.7, 2.3));
		vec2 d = p - c;
		float f = fbm(p * 6.0 + fi * 13.0);
		float blob = smoothstep(r, r * 0.55, length(d * vec2(1.0, 1.3)) + (f - 0.5) * 0.18);
		float col_x = fract(d.x * 14.0 + fi);
		float drip = step(0.82, hash(vec2(floor(d.x * 14.0 + fi), fi))) * smoothstep(0.25, 0.0, abs(col_x - 0.5))
			* step(0.0, d.y) * smoothstep(r + 0.12 * hash(vec2(floor(d.x * 14.0), 4.0)), r * 0.6, d.y) * step(abs(d.x), r * 0.8);
		m = max(m, max(blob, drip * 0.85) * step(fi, 2.0 * blood));
	}
	vec2 g = p * 9.0;
	vec2 gi = floor(g);
	vec2 gf = fract(g) - 0.5;
	vec2 o = vec2(hash(gi), hash(gi + 5.0)) - 0.5;
	float dr = 0.06 + 0.2 * hash(gi + 9.0);
	float drop = smoothstep(dr, dr * 0.6, length(gf - o * 0.5)) * step(0.9, hash(gi + 2.0));
	m = max(m, drop * smoothstep(0.2, 0.7, fbm(p * 2.0 + 3.0)));
	return clamp(m, 0.0, 1.0);
}

// part « brûlée » d'une couleur (au-dessus du seuil), pour les reflets d'objectif
vec3 hot(vec3 c, float thr) {
	return max(c - thr, vec3(0.0)) / (1.0 - thr);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = SCREEN_UV;
	float I = intensity;

	// 1) grand-angle déformé (fisheye) ; le recadrage suit la déformation
	float k = distortion * I;
	float fit = mix(1.0, zoom_fit, distortion > 0.0 ? I : 0.0);
	vec2 duv = barrel(uv, k, aspect, fit);

	// 2) compression : quand l'image bouge vite, des macroblocs « glissent » (vecteurs de mouvement faux)
	float speed = length(motion);
	float moving = clamp(speed * 1.5, 0.0, 1.0);
	vec2 block = floor(duv * res / 16.0);
	float tick = floor(TIME * 15.0);
	float bad = step(1.0 - 0.35 * moving * compression * I, hash(block + tick));
	duv -= bad * motion * 0.02 * (0.5 + hash(block * 1.7 + tick));

	// 3) aberration chromatique (croît vers les bords) + flou de mouvement
	vec2 fromc = duv - 0.5;
	float ca = chroma * I * (0.3 + 3.0 * dot(fromc, fromc)) + hurt * 0.004;
	vec2 cdir = normalize(fromc + 1e-5) * ca;
	vec2 mv = motion * motion_blur * I * 0.045;
	int taps = length(mv) * res.x > 1.5 ? 8 : 1;
	vec3 col = vec3(0.0);
	for (int i = 0; i < taps; i++) {
		float t = taps > 1 ? float(i) / 7.0 - 0.5 : 0.0;
		vec2 p = duv + mv * t;
		col.r += textureLod(screen_tex, p + cdir, 0.0).r;
		col.g += textureLod(screen_tex, p, 0.0).g;
		col.b += textureLod(screen_tex, p - cdir, 0.0).b;
	}
	col /= float(taps);

	// 4) compression : chroma sous-échantillonnée (4:2:0) et, en mouvement, macroblocs lissés
	vec3 ycc = rgb2ycc(col);
	vec3 low = rgb2ycc(textureLod(screen_tex, duv, 1.5).rgb);
	ycc.yz = mix(ycc.yz, low.yz, 0.8 * compression * I);
	vec2 bc = (floor(duv * res / 8.0) + 0.5) * 8.0 / res;
	vec3 blk = rgb2ycc(textureLod(screen_tex, bc, 3.0).rgb);
	float smear = clamp(moving * compression * I * 1.2 + bad * 0.6, 0.0, 0.9);
	// garde un peu de détail quantifié (blocs visibles mais pas une bouillie)
	float detail = ycc.x - blk.x;
	detail = floor(detail * 24.0 + 0.5) / 24.0;
	ycc.x = mix(ycc.x, blk.x + detail * 0.35, smear);
	ycc.yz = mix(ycc.yz, blk.yz, smear);
	col = ycc2rgb(ycc);

	// vision trouble quand on est blessé
	if (hurt > 0.01) {
		vec3 b = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.047 + TIME;
			b += textureLod(screen_tex, duv + vec2(cos(a), sin(a)) * 0.006 * hurt, 2.0).rgb;
		}
		col = mix(col, b / 6.0, hurt * 0.7);
	}

	// 5) reflets d'objectif : traînée horizontale légère (anamorphique) et images fantômes
	if (flare > 0.0 && I > 0.0) {
		vec3 fl = vec3(0.0);
		for (int i = 1; i <= 4; i++) {
			float o = float(i) * 0.035;
			fl += hot(textureLod(screen_tex, duv + vec2(o, 0.0), 3.0).rgb, 0.8) * (1.0 - float(i) * 0.2);
			fl += hot(textureLod(screen_tex, duv - vec2(o, 0.0), 3.0).rgb, 0.8) * (1.0 - float(i) * 0.2);
		}
		vec3 streak = fl * vec3(0.55, 0.75, 1.0) * 0.12;
		vec2 gv = 0.5 - duv;
		vec3 gh = hot(textureLod(screen_tex, 0.5 + gv * 0.7, 5.0).rgb, 0.75) * vec3(0.4, 0.8, 0.6);
		gh += hot(textureLod(screen_tex, 0.5 + gv * 1.6, 4.0).rgb, 0.75) * vec3(0.9, 0.5, 0.3) * 0.6;
		gh += hot(textureLod(screen_tex, 0.5 - gv * 0.35, 5.0).rgb, 0.75) * vec3(0.5, 0.5, 0.9) * 0.5;
		col += (streak + gh * 0.18) * flare * I;
	}

	// hors image (bords du fisheye) -> noir
	if (duv.x < 0.0 || duv.x > 1.0 || duv.y < 0.0 || duv.y > 1.0) col = vec3(0.0);

	// 6) étalonnage : capteur bon marché
	col *= exposure;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// hautes lumières brûlées : au-dessus de ~0.8 tout part vers le blanc
	col = mix(col, vec3(1.0), smoothstep(0.72, 1.0, l) * highlight_burn * I);
	col = mix(vec3(l), col, mix(1.0, saturation, I) * (1.0 - hurt * 0.6));
	col = (col - 0.45) * mix(1.0, contrast, I) + 0.45;
	vec3 tone = mix(tint_shadows, tint_highlights, smoothstep(0.05, 0.6, l)) * 2.0;
	col = mix(col, col * tone, split_tone * I);
	// noirs bouchés (le capteur et l'encodeur écrasent les ombres) puis léger voile
	float crush = black_crush * I;
	col = max(col - crush, vec3(0.0)) / (1.0 - crush);
	col = col * (1.0 - black_lift * I) + black_lift * I * vec3(0.9, 1.0, 1.0);

	// 7) sang sur l'objectif
	float bm = blood_mask(uv, aspect) * smoothstep(0.0, 0.3, blood);
	if (bm > 0.0) {
		vec3 behind = textureLod(screen_tex, duv, 3.0).rgb;
		float thick = fbm(uv * 30.0);
		vec3 blood_col = behind * vec3(0.32, 0.03, 0.025) + vec3(0.045, 0.002, 0.0);
		blood_col *= 0.6 + 0.6 * thick;
		col = mix(col, blood_col, bm * 0.95);
	}

	// 8) vignettage optique + coins noirs arrondis de l'objectif
	vec2 vc = (uv - 0.5) * vec2(aspect, 1.0);
	float vig = 1.0 - smoothstep(0.3, 1.0, length(vc * 0.85)) * vignette * I;
	col *= vig;
	if (corner_round > 0.0 && distortion > 0.0) {
		// cercle image de l'objectif un peu plus petit que la diagonale du capteur
		float rc = length(vc / vec2(aspect * 0.5, 0.5) * vec2(1.0, 0.56));
		float lim = mix(2.0, 1.1, corner_round * I);
		col *= 1.0 - smoothstep(lim - 0.035, lim + 0.005, rc);
	}

	// 9) bruit numérique : fort dans le noir, en grumeaux (débruitage de l'encodeur), avec chroma
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float dark = pow(1.0 - clamp(lum, 0.0, 1.0), 2.2);
	vec2 px = uv * res;
	float fs = fract(frame_seed * 0.6180339) * 100.0 + fract(TIME * 7.13) * 31.0;
	float n1 = hash(px + fs) - 0.5;
	float n2 = noise(px * 0.5 + fs * 13.0) - 0.5;
	float nl = mix(n1, n2, 0.6) * grain * I * (0.25 + 1.6 * dark);
	vec2 nc = vec2(noise(px * 0.33 + fs * 7.0), noise(px * 0.33 + 50.0 + fs * 5.0)) - 0.5;
	vec3 nchroma = ycc2rgb(vec3(0.0, nc * chroma_noise * I * dark * 2.0));
	col += nl + nchroma;

	// éblouissement : l'exposition saute (les ombres restent noires), petit voile chaud
	col = col * (1.0 + flash * 4.0) + flash * vec3(0.12, 0.1, 0.07);
	// lignes de balayage à peine visibles (obturateur roulant)
	col *= 1.0 - 0.015 * I * step(0.5, fract(uv.y * res.y * 0.5));
	// quantification 8 bits sale dans les ombres (aplats de l'encodeur)
	float q = mix(255.0, 40.0, compression * I);
	vec3 qcol = floor(col * q + hash(block) * 0.5) / q;
	col = mix(col, qcol, smoothstep(0.25, 0.0, lum) * 0.7);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
