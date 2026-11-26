// Flaque d'eau sale posée sur le sol : on voit le béton dessous (assombri, mouillé), la surface est
// un miroir presque parfait (rugosité très faible : SSR + sonde de reflets), bord découpé par un
// masque (seuil) et ourlet plus mat là où l'eau est très peu profonde.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D masque : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D sol_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D vaguelettes : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float sol_echelle = 0.35;      // même échelle que le sol (le motif continue sous l'eau)
uniform float assombrir = 0.55;        // béton mouillé
uniform vec4 eau : source_color = vec4(0.30, 0.27, 0.22, 1.0);   // eau trouble
uniform float trouble = 0.35;
uniform float seuil = 0.5;
uniform float rugosite = 0.03;
uniform float relief = 0.18;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = texture(masque, UV).a;
	vec3 fond = texture(sol_albedo, wpos.xz * sol_echelle).rgb * assombrir;
	ALBEDO = mix(fond, fond * eau.rgb * 2.0, trouble);
	// bord : film d'eau mince, moins lisse
	float bord = smoothstep(seuil, seuil + 0.25, a);
	ROUGHNESS = mix(0.25, rugosite, bord);
	SPECULAR = 0.25;   // eau : F0 ≈ 0,02
	METALLIC = 0.0;
	vec2 xy = (texture(vaguelettes, wpos.xz * 0.6).rg * 2.0 - 1.0) * relief * bord;
	vec3 wn = normalize(vec3(xy.x, 1.0, -xy.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = seuil;
}

// Éclairage direct propre à l'eau : diffus de Lambert, reflet direct borné. Une lampe ponctuelle sur
// un miroir (rugosité 0,03) donnerait un point d'intensité quasi infinie qui éteint toute l'image par
// l'exposition automatique ; le vrai reflet du tube vient de la sonde de reflets et du SSR.
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), 180.0);
	SPECULAR_LIGHT += s * nl * ATTENUATION * LIGHT_COLOR * 0.05;
}
