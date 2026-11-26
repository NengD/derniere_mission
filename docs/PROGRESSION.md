# Progression

Mémoire de travail du projet : à relire après chaque compactage, à mettre à jour à chaque tâche terminée.

## Tâche en cours
Phase 1 — **chantier « réalisme » demandé par le propriétaire le 26/11/2026 (issue #4)** : 1) lumière et rendu, 2) bras et arme à la 1re personne — confiés à deux sous-agents en parallèle ; MONTRER 1 et 2 au propriétaire AVANT de faire 3) gardes (matériaux, défauts, animations CMU, ragdoll) et 4) décor. Ensuite seulement : IA des gardes, dégâts localisés.

## Fait
- Phase 0 validée (tag `v0.0-phase0`) : direction artistique A (photoréaliste sombre), conception (`docs/CONCEPTION.md`), ressources (`docs/phase0/RESSOURCES.md`).
- Phase 1, socle : autoloads `Audio`, `Reglages`, `Commandes`, `Jeu` (`scripts/autoload/`) ; logique pure `Degats`, `EtatArme`, `Fins`, `Score`, `Sauvegarde` (`scripts/logique/`) ; arbre de comportement `BT` (`scripts/ia/bt.gd`) ; 43 tests (`tests/tests_logique.gd`), tous verts.
- Sons (commit 099214a) : 49 WAV mono 44,1 kHz dans `assets/sons/`, produits par `tools/blender/make_sounds.py` (tirs `tir_pistolet_1..3`, `tir_pistolet_loin_1..2`, `tir_garde_1..2`, `tir_garde_loin_1..2` ; `chargeur_sortie/entree`, `culasse`, `douille_1..3`, `clic_vide` ; `pas_dur_1..4`, `pas_doux_1..4` ; `respiration_calme/peur/affolee`, `souffle_coupe`, `toux`, `cri`, `coeur`, `douleur_1..4` ; `impact_chair/beton_1..3`, `impact_metal_1..2`, `chute_corps` ; `radio_bip`, `radio_gresil` ; boucles `amb_machines`, `amb_grillons`, `amb_hangar` — boucler à l'exécution). Crédits dans `CREDITS.md`.

- Joueur (sous-agent, vérifié : 43 + 37 tests verts, captures `captures/joueur/`) : `scripts/joueur/joueur.gd` (+ `scenes/joueur/joueur.tscn`), `bras_ik.gd`, `camera_pieton.gd`, `fx_impact.gd` ; logique `sante_joueur.gd`, `dispersion.gd` ; salle de test `scenes/test/salle_test.tscn` (`-- photo <png> [jeu|visee|tir|pieds|penche|recharge|blesse|plan|mains]`, `-- video`) ; `data/traductions.csv` ; tests `tests/tests_joueur.gd`.
  - Couches physiques : 1 monde, 2 joueur, 3 corps ennemis, 4 hitboxes, 5 interactifs. Corps/arme du joueur sur le calque de rendu 2 (décalques sur le calque 1 seulement).
  - Tir du joueur → `recevoir_tir(degats, os_ou_zone, point, normale, direction, tireur)` sur le collider ou jusqu'à 4 parents ; `degats` = 55 × atténuation, le RECEVEUR applique `Degats.MULTIPLICATEUR[zone]` ; `os_ou_zone` = méta `"os"` (nom d'os UE) sinon méta `"zone"` ; méta décor `"materiau" = "metal"`.
  - Joueur (groupe `"joueur"`) : `recevoir_tir(...)`, `recevoir_degats(montant, zone, direction)` (montant déjà multiplié) ; signaux `mort`, `blesse`, `tir_bruit(position, portee)` (ouïe des gardes), `aide_changee`, `munitions_changees` ; `ramasser_chargeur(nb)`, `ramasser_trousse()`, `vers_dict/depuis_dict`, `capturer_souris(oui)` (le niveau l'appelle en jeu réel seulement). Interaction F : rayon 2 m couches 1+5 → `interagir(joueur)`, `texte_aide()` optionnel.
  - Reste : mains de Marc massives (bosse sous la culasse en visée), rechargement perfectible (main gauche ouverte, fond du chargeur soudé visible), pas de pas de côté, issue #3 non traitée.
- Gardes MPFB (issue #1, sous-agent, vérifié) : MPFB 2.0.18 installé dans le profil Blender (extensions.blender.org) + 13 paquets officiels MakeHuman (`tools/blender/install_mpfb_packs.py`, sources dans `_sources/mpfb/`). `tools/blender/build_gardes_mpfb.py [-- garde_2 …]` → `assets/characters/gardes/garde_1..4.glb` (5-6 Mo, 42-59 k triangles) : 1 « El Flaco » 22 ans mince (casquette, bandana), 2 35 ans moyen (cagoule, gilet tactique), 3 « El Gordo » 48 ans en surpoids (cache-cou), 4 30 ans costaud (capuche, bandana, gilet). Squelette Quaternius (mêmes os), poids MPFB, animations UAL recalculées : `hand_r`, `finger_curl.gd`, `_calibrate_grips` marchent tels quels. Aperçu `scenes/apercu/gardes.tscn -- ensemble|visages|video|controle`. Reste : LOD à prévoir, anneau de peau sous la cagoule du garde 2, bandana petit et plaqué, cache-cou du garde 3 moulé sur le nez.

## Décisions
- Direction A ; code MIT, contenus réservés ; fin heureuse à 100 % strict (`data/fins.json`).
- Équilibrage : pistolet du joueur 55 dégâts, garde 35 ; tête ×4, torse ×1, bras ×0,5, jambe ×0,6 ; 2 balles au torse tuent un garde, 3 tuent le joueur.
- Pistolet : 15 + 1, chargeur partiel gardé, rechargement 1,7 s (tactique) / 2,4 s (à vide), enrayement 0,4 %.
- Organisation chef de projet / sous-agents (voir CLAUDE.md), une seule session.

## Retours du propriétaire
- Issue #1 : gardes MakeHuman / MPFB (CC0 ; ressources communautaires CC-BY à créditer), plusieurs variantes (corpulence, âge, vêtements réalistes, visage couvert), branchés sur les animations ; montrer captures + courte vidéo avant de continuer.
- Issue #2 : mains et prise de l'arme à soigner. Issue #3 : sang sur l'objectif plus réaliste.

- 26/11/2026, avis sur joueur + gardes : « pas encore assez réaliste ». Objectif : qu'une capture puisse passer pour une vraie vidéo de caméra-piéton (références : Better Than Dead, Unrecord, vraies bodycams de police). Comparer côte à côte référence / avant / après à chaque retouche, courte vidéo, ≥ 60 i/s sur son PC. Ordre :
  1. Lumière et rendu : LightmapGI avec rebonds, SSAO + SSIL, ombres de contact, volumétrique et poussière, sources visibles (néons qui grésillent, ampoules nues, lampes de sécurité), forts contrastes ; exposition auto qui « pompe » ; étalonnage désaturé, verts/jaunes de néon ; effet bodycam plus fort (fisheye, blocs de compression dans les mouvements rapides, bruit numérique dans le noir, saccades, flou de mouvement, reflets d'objectif).
  2. Bras et arme : bras réalistes à la bonne taille (manches usées, gants tactiques cuir texturés ou mains détaillées), MPFB ou Blender ; doigts sur poignée / détente / glissière, main gauche en soutien, rechargement à deux mains ; pistolet détaillé (glissière, mire, rayures, usure, numéros, polymère), glissière qui recule, douille, flash ; arme tenue bras tendus depuis la poitrine, balancement réaliste, recul fort.
  3. Gardes : vêtements (plis, coutures, usure, taches, normal maps), peau à pores ; corriger cache-cou moulé, bandana plaqué, anneau de peau ; animations de capture CMU (citer la source) retravaillées ; mort = ragdoll physique avec élan et zone d'impact.
  4. Décor : câbles, tuyaux, gaines, aérations, humidité, flaques réfléchissantes, déchets, mégots, tags, affiches déchirées, portes abîmées, poussière (décalques) ; textures Poly Haven / ambientCG 2K sans répétition visible.

## Prochaines étapes (phase 1)
1. Joueur : déplacements, caméra-piéton, pistolet à la 1re personne, santé, sons.
2. Gardes MPFB → avis du propriétaire → IA (arbre de comportement), dégâts localisés, ragdoll.
3. Sang, démembrement, sons d'impact.
4. Niveau 1 : décor, otage, documents, radio de Vincent, écran-titre, score, points de contrôle, CSV des traductions ; `main_scene` à changer.
5. Exports Windows/Linux, workflows GitHub Actions, tests.
6. Captures, vidéos, Release ; S'ARRÊTER pour l'avis.
