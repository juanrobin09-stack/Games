shader_type canvas_item;

// Rend le dessin du personnage lisible sur les deux types de sol qu'il traverse,
// sans le rendre plus lumineux et sans rien ajouter autour de lui.
//
// Le sprite et le sol partagent la meme bande de clarte une fois eclaires
// ensemble, mais ils echouent de deux facons opposees, mesurees sur 52 captures
// du jeu reel : sur un sol sombre c'est le trait quasi noir qui se perd (38,9 %
// de son perimetre sans contraste), sur un sol clair c'est le modele interne du
// vetement (34,9 % du corps dans le bruit du sol). Deux actions distinctes, donc,
// chacune declenchee la ou elle aide :
//
//   1. LE TRAIT (albedo sous key_lo) se creuse TOUJOURS. Un ton deja presque
//      noir ne peut pas se rapprocher d'un sol qui, meme sombre, n'est jamais
//      noir : le creuser l'en eloigne. La courbe t^(1/k) sur la profondeur
//      relative t laisse t = 1 a 1, donc aucun ton n'est ecrase qui ne l'etait
//      pas deja dans la texture.
//   2. LE MODELE INTERNE s'ecarte autour du ton median du sprite, mais seulement
//      quand le sol derriere est clair. Sur sol sombre cette action pousserait le
//      corps vers la valeur du sol, alors elle s'eteint.
//
// Rien ne touche l'alpha, la silhouette, ni la position d'un seul pixel. La cape
// et les sources lumineuses (yeux, amulette) sont exclues par leur couleur
// source, donc la teinte d'un hit flash ne change pas qui est protege.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// Ton median de l'interieur modifiable du sprite, mesure sur les 30 frames
// (60 581 texels) : 30,3 / 255. C'est le pivot des deux courbes.
uniform float mid_tone : hint_range(0.0, 1.0) = 0.1188;
// Intensite du creusement du trait, et de l'ecart du modele interne.
uniform float key_strength : hint_range(0.0, 4.0) = 2.0;
uniform float model_strength : hint_range(0.0, 2.0) = 0.9;
// Bornes du fondu entre "trait" et "modele interne", en albedo.
uniform float key_lo : hint_range(0.0, 1.0) = 0.0314;   // 8/255
uniform float key_hi : hint_range(0.0, 1.0) = 0.0784;   // 20/255
// Bornes du fondu entre sol sombre et sol clair, en luminance ecran.
uniform float bg_lo : hint_range(0.0, 1.0) = 0.102;     // 26/255
uniform float bg_hi : hint_range(0.0, 1.0) = 0.1725;    // 44/255
// Ce qui n'est jamais touche : les sources lumineuses, et la cape a sa
// dominante rouge.
uniform float keep_above : hint_range(0.0, 1.0) = 0.353;      // 90/255
uniform float cape_chroma : hint_range(0.0, 1.0) = 0.137;     // 35/255
// Rayons de lecture du fond, en pixels ecran. Ils doivent rester grands devant
// la maille du dallage, sinon la correction suit le grain et grouille.
uniform float bg_radius_near : hint_range(1.0, 128.0) = 18.0;
uniform float bg_radius_far : hint_range(1.0, 256.0) = 44.0;

float luma3(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lt = luma3(src.rgb);
	// Exclusions, lues sur la couleur SOURCE et non sur COLOR : un hit flash ne
	// doit pas faire entrer ou sortir un pixel de la zone protegee.
	float garde = step(keep_above, lt);
	garde = max(garde, step(cape_chroma, src.r - max(src.g, src.b)));
	garde = max(garde, step(src.a, 0.0));
	garde = max(garde, step(lt, 0.0));

	// Le NIVEAU D'ECLAIRAGE du sol derriere, et surtout pas son grain. Un
	// echantillonnage serre suivrait les joints du dallage : comme le sol defile
	// sous le personnage, la correction se mettrait a grouiller d'une image a
	// l'autre. On lit donc large -- deux anneaux, 13 taps -- pour ne garder que
	// la composante basse frequence, celle qui ne bouge quasiment pas quand le
	// personnage avance d'un pixel.
	float bg = luma3(texture(screen_tex, SCREEN_UV).rgb) * 0.2;
	vec2 r1 = SCREEN_PIXEL_SIZE * bg_radius_near;
	vec2 r2 = SCREEN_PIXEL_SIZE * bg_radius_far;
	for (int i = 0; i < 4; i++) {
		float a = float(i) * 1.5707963 + 0.7853982;
		vec2 d = vec2(cos(a), sin(a));
		bg += luma3(texture(screen_tex, SCREEN_UV + d * r1).rgb) * 0.1;
	}
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982;
		vec2 d = vec2(cos(a), sin(a));
		bg += luma3(texture(screen_tex, SCREEN_UV + d * r2).rgb) * 0.05;
	}

	float light = smoothstep(bg_lo, bg_hi, bg);

	float safe_lt = max(lt, 1e-5);
	float w_key = 1.0 - smoothstep(key_lo, key_hi, lt);
	float t = clamp((mid_tone - lt) / max(mid_tone, 1e-5), 0.0, 1.0);

	float l_key = mid_tone * (1.0 - pow(t, 1.0 / (1.0 + key_strength)));

	float ke = 1.0 + model_strength * light;
	float l_bas = mid_tone * (1.0 - pow(t, 1.0 / ke));
	float l_haut = mid_tone + (lt - mid_tone) * ke;
	float l_exp = mix(l_haut, l_bas, step(lt, mid_tone));

	float cible = clamp(mix(l_exp, l_key, w_key), 0.0, 1.0);
	// On applique le rapport a COLOR, pas a la texture : la teinte du pixel, le
	// modulate du personnage et le hit flash traversent intacts. Sur un pixel
	// garde, le rapport vaut exactement 1.
	float f = mix(cible / safe_lt, 1.0, garde);
	COLOR.rgb *= f;
}
