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
- [~] Phase 0 — recherche et direction artistique (25/11/2026) : tableau des ressources (`docs/phase0/RESSOURCES.md`), aperçus A et B (`docs/phase0/`), conception (`docs/CONCEPTION.md`). **Direction artistique A (photoréaliste sombre) choisie par le propriétaire le 25/11/2026** (tag `v0.0-phase0`). Licence choisie : code MIT, contenus tous droits réservés (`LICENSE`). Fin heureuse : 100 % strict (`data/fins.json`). Reste : installer `gh` (guidé) pour Issues / jalons / Releases.
- [ ] Phase 1 — tranche verticale (niveau 1)
- [ ] Phase 2 — arsenal et ennemis
- [ ] Phase 3 — niveaux 2 à 8 et fins
- [ ] Phase 4 — menus, options, polissage, exports
