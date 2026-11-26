# Dernière mission — notes de projet

FPS solo en vue caméra-piéton (bodycam), dans l'esprit de « Better Than Dead » : réalisme, tension, combats courts et mortels, couloirs, violence maximale (réglable), histoire racontée entre et pendant les niveaux. Godot 4.7 (Forward+), Windows et Linux. Cahier des charges complet : `PROMPT_FPS_DERNIERE_MISSION.md` (à relire en cas de doute). Conception : `docs/CONCEPTION.md`.

## Histoire (résumé)
Marc Delmas, 48 ans, ex-commando, vient chercher sa fille Léa (22 ans), enlevée à Puerto Ceniza (République de Calimar, pays fictif) par le cartel « El Círculo de Cobre » de Teodoro Arriaga « El Relojero ». Vincent Roque « Faucon », vieil ami de l'armée, le guide par radio via la caméra… mais il vend des armes au cartel et se sert de Marc pour éliminer le Relojero au profit de « La Viuda ». 8 niveaux ; 3 fins (rebondissement si document caché trouvé > heureuse si tout trouvé > tragique).

## Règles de travail
- Le propriétaire ne code pas, ne modélise pas, ne télécharge rien : tout est fait ici. Il joue, regarde, donne son avis.
- Tout le texte du jeu en français via `tr()` + CSV (Godot), traduisible plus tard.
- 100 % gratuit, licences valables dans l'UE (CC0 de préférence, sinon CC-BY avec crédit). Chaque ressource dans `CREDITS.md`. Dépôt PUBLIC : pas de licence qui interdit de republier les fichiers bruts (Sonniss, Mixamo exclus), pas de NC ni de SA.
- Ne jamais prendre le focus ni capturer souris / clavier. Godot en `--headless` si possible ; captures dans une fenêtre hors écran (`--position 6000,3000`). Ne fermer ni redémarrer aucun programme.
- Blender en ligne de commande (`-b --factory-startup -P script.py`) ; MCP « blender » seulement si le propriétaire l'a ouvert. Tous les scripts dans `tools/blender/` pour pouvoir tout régénérer.
- Clavier-souris uniquement (pas de manette). Noms de fichiers en minuscules, sans espaces ni accents. Sauvegardes et options dans `user://`.
- Git : petits commits en français, push à la fin de chaque étape. Tag + Release (Windows .zip, Linux .tar.gz) à chaque phase validée. Aucune donnée personnelle, aucun secret dans le dépôt. Aucun fichier > 50 Mo.
- Après chaque phase : S'ARRÊTER, montrer captures ET vidéos (vérifiées avant), attendre l'avis.
- Pas de ffmpeg sur ce PC : vidéos converties par le montage de Blender (`tools/blender/avi_to_mp4.py`, chemins complets ; `view_transform = Standard`).

## Organisation du travail (demande du propriétaire, 25/11/2026)
- Une seule session : ne jamais en ouvrir de nouvelle, on continue toujours dans celle-ci.
- **Chef de projet / ouvriers** : la session principale ne fait pas les grosses tâches elle-même (joueur, garde, sang et démembrement, décor, exports, personnages MPFB, recherche de ressources…). Chaque grosse tâche part à un sous-agent à mémoire vierge, avec des instructions complètes et autonomes : objectif précis, fichiers à lire (CLAUDE.md, PROMPT_FPS_DERNIERE_MISSION.md, docs/PROGRESSION.md, docs/CONCEPTION.md), règles du projet (100 % gratuit, licences valables en France, crédits, texte via tr(), arrière-plan sans prendre le focus, tests qui passent), ce qu'il doit renvoyer.
- Retour exigé COURT : fait, fichiers modifiés, résultat des tests, problèmes restants, chemins des captures et vidéos. Les sous-agents ne font ni commit ni push (sauf consigne contraire) : le chef vérifie (tests, une ou deux captures), met à jour docs/PROGRESSION.md, puis commit + push.
- Tâches indépendantes lancées en parallèle quand c'est possible (fichiers distincts).
- **Mémoire dans les fichiers** : `docs/PROGRESSION.md` (tâche en cours, fait, décisions, retours du propriétaire, prochaines étapes) mis à jour à chaque tâche terminée et avant toute opération longue. Retours importants aussi dans les Issues GitHub.
- **Après chaque compactage** : relire CLAUDE.md, docs/PROGRESSION.md (et la partie utile de PROMPT_FPS_DERNIERE_MISSION.md) avant de continuer, puis reprendre sans demander.
- **Économiser la mémoire** : longues sorties (téléchargements, exports, journaux, tests) redirigées dans `logs/` (ignoré par git), n'en lire que les erreurs et le résumé ; ne pas relire en entier les gros fichiers (chercher) ; images et vidéos avec parcimonie (une planche réduite plutôt que beaucoup d'images).

## Armes : modèles Sketchfab (demande du propriétaire, 26/11/2026)
- Armes = modèles réalistes Sketchfab plutôt que faits main. Jeton d'API du propriétaire dans `.secrets/sketchfab_token` (ignoré par git) ou variable d'environnement `SKETCHFAB_TOKEN` : JAMAIS dans le dépôt, un journal, un commit, la doc ou un message.
- Licences : CC0 et CC-BY uniquement (crédit complet dans CREDITS.md : auteur, titre, lien, licence). Refuser NC, ND, SA, licences Standard/Editorial de Sketchfab et tout asset Fab.
- Montrer 2 ou 3 choix par arme (capture, auteur, licence, polygones) AVANT d'intégrer. Retirer logos et marques, noms génériques dans le jeu. Optimiser (polygones raisonnables en 1re personne, textures 2K), séparer les pièces mobiles (glissière/culasse, chargeur, détente, pompe) et les brancher sur les animations de tir et de rechargement.
- Calendrier : fusil à pompe et fusil d'assaut en Phase 2 (arsenal) ; pistolet actuel : d'abord une comparaison avant/après proposée au propriétaire.

## Commandes
- Chemins locaux de Godot 4.7.2 (console) et Blender 5.2 : dans `CLAUDE.local.md` (ignoré par git). Modèles d'export 4.7.2 installés.
- Import : `godot --headless --path . --import`
- Ressources : `python tools/fetch_polyhaven.py tex:<id>:2k model:<id>:1k` (dans `_sources/`, ignoré par git) ; `python tools/make_cloth_textures.py` ; `python tools/make_fx_textures.py` ; `blender -b --factory-startup -P tools/blender/build_characters.py -- garde|marc` ; `blender -b --factory-startup -P tools/blender/build_pistol.py`.
- Aperçu phase 0 : `godot --path . --resolution 1920x1080 --position 6000,3000 -- A|B photo|blesse|plan|mains <fichier.png>` ; vidéo : ajouter `--write-movie captures/x.avi --fixed-fps 30` et `-- A|B video`, puis `blender -b --factory-startup -P tools/blender/avi_to_mp4.py -- <x.avi> <x.mp4> 30`. Contrôle image par image : `tools/blender/video_frames.py -- <video> <dossier> <pas>`.

## Organisation
- `assets/` (characters, weapons, decor, fx), `scenes/`, `scripts/`, `shaders/`, `tests/`, `tools/` (+ `tools/blender/`), `docs/` (conception, comptes rendus de phase), `_sources/` (téléchargements bruts, ignoré), `captures/` (travail, ignoré).

## Pièges connus
- Godot retire le suffixe `_Loop` des noms d'animations à l'import (`Pistol_Idle_Loop` → `Pistol_Idle`).
- Utiliser la version « Unreal-Godot » de UAL1 (`UAL1_Standard.glb`) : l'autre couche les personnages.
- Poly Haven `steel_frame_shelves_01` est 10× trop grand ; les modèles « modular_* » contiennent plusieurs variantes côte à côte (garder un seul enfant).
- Doigts : les animations libres tiennent le pistolet main ouverte → `scripts/finger_curl.gd` (axe Z). Main gauche ramenée sur l'arme par `TwoBoneIK3D`. Arme calée dans la main par calcul (`_calibrate_grips` dans l'aperçu).

## Avancement
- [~] Phase 0 — recherche et direction artistique (25/11/2026) : tableau des ressources (`docs/phase0/RESSOURCES.md`), aperçus A et B (`docs/phase0/`), conception (`docs/CONCEPTION.md`). **Direction artistique A (photoréaliste sombre) choisie par le propriétaire le 25/11/2026** (tag `v0.0-phase0`). Licence choisie : code MIT, contenus tous droits réservés (`LICENSE`). Fin heureuse : 100 % strict (`data/fins.json`). `gh` installé et connecté (compte NengD) : étiquettes, jalons (Phase 0 à 4, Niveaux 2 à 8) et Issues #1–#3 créés.
- [~] Phase 1 — tranche verticale (niveau 1), lancée le 25/11/2026. Socle et tests de logique faits. **Demande du propriétaire (issue #1)** : à la tâche « Garde », remplacer les corps Quaternius par des gardes MakeHuman / MPFB (CC0 ; ressources communautaires CC-BY à créditer), plusieurs variantes (corpulence, âge, vêtements, visage couvert), branchés sur les animations ; montrer captures + courte vidéo AVANT de continuer.
- [ ] Phase 2 — arsenal et ennemis
- [ ] Phase 3 — niveaux 2 à 8 et fins
- [ ] Phase 4 — menus, options, polissage, exports
