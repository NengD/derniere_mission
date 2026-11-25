# Progression

Mémoire de travail du projet : à relire après chaque compactage, à mettre à jour à chaque tâche terminée.

## Tâche en cours
Phase 1 (tranche verticale, niveau 1) — tâche **Joueur** (confiée à un sous-agent) et, en parallèle, **gardes MPFB** (issue #1, confiée à un autre sous-agent ; captures + courte vidéo à montrer au propriétaire AVANT de continuer la tâche Garde).

## Fait
- Phase 0 validée (tag `v0.0-phase0`) : direction artistique A (photoréaliste sombre), conception (`docs/CONCEPTION.md`), ressources (`docs/phase0/RESSOURCES.md`).
- Phase 1, socle : autoloads `Audio`, `Reglages`, `Commandes`, `Jeu` (`scripts/autoload/`) ; logique pure `Degats`, `EtatArme`, `Fins`, `Score`, `Sauvegarde` (`scripts/logique/`) ; arbre de comportement `BT` (`scripts/ia/bt.gd`) ; 43 tests (`tests/tests_logique.gd`), tous verts.
- Sons (commit 099214a) : 49 WAV mono 44,1 kHz dans `assets/sons/`, produits par `tools/blender/make_sounds.py` (tirs `tir_pistolet_1..3`, `tir_pistolet_loin_1..2`, `tir_garde_1..2`, `tir_garde_loin_1..2` ; `chargeur_sortie/entree`, `culasse`, `douille_1..3`, `clic_vide` ; `pas_dur_1..4`, `pas_doux_1..4` ; `respiration_calme/peur/affolee`, `souffle_coupe`, `toux`, `cri`, `coeur`, `douleur_1..4` ; `impact_chair/beton_1..3`, `impact_metal_1..2`, `chute_corps` ; `radio_bip`, `radio_gresil` ; boucles `amb_machines`, `amb_grillons`, `amb_hangar` — boucler à l'exécution). Crédits dans `CREDITS.md`.

## Décisions
- Direction A ; code MIT, contenus réservés ; fin heureuse à 100 % strict (`data/fins.json`).
- Équilibrage : pistolet du joueur 55 dégâts, garde 35 ; tête ×4, torse ×1, bras ×0,5, jambe ×0,6 ; 2 balles au torse tuent un garde, 3 tuent le joueur.
- Pistolet : 15 + 1, chargeur partiel gardé, rechargement 1,7 s (tactique) / 2,4 s (à vide), enrayement 0,4 %.
- Organisation chef de projet / sous-agents (voir CLAUDE.md), une seule session.

## Retours du propriétaire
- Issue #1 : gardes MakeHuman / MPFB (CC0 ; ressources communautaires CC-BY à créditer), plusieurs variantes (corpulence, âge, vêtements réalistes, visage couvert), branchés sur les animations ; montrer captures + courte vidéo avant de continuer.
- Issue #2 : mains et prise de l'arme à soigner. Issue #3 : sang sur l'objectif plus réaliste.

## Prochaines étapes (phase 1)
1. Joueur : déplacements, caméra-piéton, pistolet à la 1re personne, santé, sons.
2. Gardes MPFB → avis du propriétaire → IA (arbre de comportement), dégâts localisés, ragdoll.
3. Sang, démembrement, sons d'impact.
4. Niveau 1 : décor, otage, documents, radio de Vincent, écran-titre, score, points de contrôle, CSV des traductions ; `main_scene` à changer.
5. Exports Windows/Linux, workflows GitHub Actions, tests.
6. Captures, vidéos, Release ; S'ARRÊTER pour l'avis.
