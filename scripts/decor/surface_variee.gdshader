// Surface de décor sans répétition visible (murs, sols, plafonds en boîtes alignées sur les axes).
// - projection planaire monde selon l'axe dominant de la normale (repère tangent exact : relief juste)
// - deux échelles de la même texture, la seconde tournée, mélangées par un bruit large
// - second matériau optionnel (sol usé, peinture écaillée…) mélangé par plaques
// - macro-variation de teinte et de rugosité, décalage UV propre à chaque surface
// - saleté en bas (pied de mur), suie en haut, humidité qui remonte par plaques
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool second_actif = false;
uniform sampler2D tex2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex2_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex2_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float echelle = 0.4;            // répétitions par mètre (texture 1)
uniform float echelle2 = 0.35;          // texture 2
uniform vec2 decalage = vec2(0.0);      // décalage UV propre à la surface
uniform vec4 teinte : source_color = vec4(1.0);
uniform float variation_teinte = 0.18;  // ± luminosité par plaques de ~3 m
uniform vec4 teinte_macro : source_color = vec4(0.86, 0.82, 0.74, 1.0); // couleur vers laquelle tirent les plaques
uniform float melange_echelles = 0.5;   // part de la deuxième échelle (bruit)
uniform float part_second = 0.35;       // proportion de la surface couverte par la texture 2
uniform float rugosite_mult = 1.0;
uniform float relief = 1.0;

uniform float sol_y = 0.0;              // hauteur du sol (monde)
uniform float salete_hauteur = 0.0;     // 0 = pas de saleté au pied (sols, plafonds)
uniform vec4 salete_couleur : source_color = vec4(0.32, 0.27, 0.21, 1.0);
uniform float salete_force = 0.7;
uniform float plafond_y = 3.0;
uniform float suie_hauteur = 0.0;       // noircissement sous le plafond
uniform float humidite = 0.0;           // plaques sombres et lisses qui remontent du sol

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 tourner(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 a = abs(n);
	vec2 uv;
	vec3 T;
	vec3 B;
	if (a.y >= a.x && a.y >= a.z) {
		if (n.y > 0.0) { uv = wpos.xz; T = vec3(1, 0, 0); B = vec3(0, 0, -1); }
		else { uv = vec2(wpos.x, -wpos.z); T = vec3(1, 0, 0); B = vec3(0, 0, 1); }
	} else if (a.x >= a.z) {
		float s = sign(n.x);
		uv = vec2(-wpos.z * s, -wpos.y); T = vec3(0, 0, -s); B = vec3(0, 1, 0);
	} else {
		float s = sign(n.z);
		uv = vec2(wpos.x * s, -wpos.y); T = vec3(s, 0, 0); B = vec3(0, 1, 0);
	}
	uv += decalage;
	// bruit large (R), moyen (G), fin (B)
	vec3 m = texture(macro, uv * 0.09 + decalage * 0.37).rgb;
	vec3 m2 = texture(macro, uv * 0.031 + vec2(0.37, 0.71)).rgb;

	// deux échelles de la texture 1 : la seconde tournée de 37° et plus grande
	vec2 uv1 = uv * echelle;
	vec2 uv1b = tourner(uv * echelle * 0.57, 0.65) + vec2(0.31, 0.17);
	float k = smoothstep(0.5 - 0.18, 0.5 + 0.18, m.r) * melange_echelles * 2.0;
	k = clamp(k, 0.0, 1.0);
	vec3 alb = mix(texture(tex_albedo, uv1).rgb, texture(tex_albedo, uv1b).rgb, k);
	vec3 orm = mix(texture(tex_orm, uv1).rgb, texture(tex_orm, uv1b).rgb, k);
	vec3 nm = mix(texture(tex_normal, uv1).rgb, texture(tex_normal, uv1b).rgb, k);

	if (second_actif) {
		vec2 uv2 = tourner(uv * echelle2, 1.2) + vec2(0.53, 0.29);
		// plaques franches mais bord bruité
		float p = smoothstep(1.0 - part_second - 0.06, 1.0 - part_second + 0.06, m2.g * 0.75 + m.b * 0.25);
		alb = mix(alb, texture(tex2_albedo, uv2).rgb, p);
		orm = mix(orm, texture(tex2_orm, uv2).rgb, p);
		nm = mix(nm, texture(tex2_normal, uv2).rgb, p);
	}

	// macro-variation de teinte et de luminosité
	float var = (m2.r - 0.5) * 2.0;
	alb *= teinte.rgb * (1.0 + var * variation_teinte);
	alb = mix(alb, alb * teinte_macro.rgb * 1.15, smoothstep(0.45, 0.85, m.g) * 0.5);
	float rough = orm.g * rugosite_mult * (0.9 + 0.2 * m.b);
	float ao = orm.r;

	// saleté au pied des murs (bord irrégulier), suie sous le plafond
	if (salete_hauteur > 0.0) {
		float hb = (wpos.y - sol_y) / (salete_hauteur * (0.6 + 0.8 * m.g));
		float g = (1.0 - smoothstep(0.0, 1.0, hb)) * salete_force;
		g = max(g, (1.0 - smoothstep(0.0, 0.08, wpos.y - sol_y)) * 0.9);
		alb = mix(alb, alb * salete_couleur.rgb * 1.4, g);
		rough = mix(rough, 1.0, g * 0.5);
	}
	if (suie_hauteur > 0.0) {
		float hs = (plafond_y - wpos.y) / (suie_hauteur * (0.5 + m.r));
		alb *= mix(0.55, 1.0, smoothstep(0.0, 1.0, hs));
	}
	if (humidite > 0.0) {
		float hu = smoothstep(0.55, 0.75, m2.b * 0.6 + m.g * 0.4) * (1.0 - smoothstep(0.2, 1.4, wpos.y - sol_y - m.r * 0.8));
		alb *= 1.0 - hu * humidite * 0.45;
		rough = mix(rough, 0.35, hu * humidite);
	}

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	METALLIC = orm.b;
	// les cartes normales sont importées en RG (compression RGTC) : z reconstruit
	vec2 xy = (nm.rg * 2.0 - 1.0) * relief;
	float tz = sqrt(max(0.0, 1.0 - dot(xy, xy)));
	vec3 wn = normalize(T * xy.x + B * xy.y + n * max(tz, 0.05));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
