# PROMPT — FPS « Dernière mission »

Tu vas créer un FPS solo complet, dans l'esprit de « Better Than Dead » : vue caméra-piéton (bodycam), réalisme, tension, combats courts et mortels, niveaux en couloirs, violence au maximum, et une histoire racontée entre et pendant les niveaux. Vise la MEILLEURE qualité visuelle et de ressenti possible.

## QUI JE SUIS ET COMMENT TRAVAILLER
- Je ne code pas, je ne modélise pas, je n'anime pas et je ne télécharge rien : tu fais TOUT toi-même. Je joue, je regarde et je donne mon avis.
- Outils : Godot 4.7 (console : « E:\_jeu perso\godot\Godot_v4.7.2-stable_win64_console.exe ») et Blender 5.2 installé sur mon PC (trouve son chemin toi-même, en général « C:\Program Files\Blender Foundation\Blender 5.2\blender.exe »). Utilise Blender en ligne de commande, sans fenêtre (blender -b -P script.py) ; le MCP « blender » seulement si je l'ai ouvert et démarré. Garde tous tes scripts Blender dans le projet (tools/blender/) pour pouvoir régénérer chaque ressource.
- Utilise les skills du plugin gamedev-skills quand ils s'appliquent (commence par le skill router ; notamment fps-shooter, game-feel, game-ai, ai-behavior-trees-utility-ai, level-design, camera-systems, input-systems, shader-programming, audio-design, save-systems, dialogue-systems, game-ui-ux, performance-optimization, et les skills godot-*).
- 100 % gratuit. J'habite en France : n'utilise que des ressources dont la licence s'applique dans l'Union européenne (CC0 de préférence, sinon CC-BY ou licence libre de droits avec crédit). Vérifie chaque licence et note chaque ressource dans CREDITS.md (auteur, licence, lien, usage).
- Tout le texte du jeu en français, via le système de traduction de Godot (tr() + fichier CSV), pour pouvoir traduire plus tard.
- Je continue à utiliser mon PC pendant que tu travailles : ne prends jamais le focus, ne capture jamais la souris, le clavier ou la manette ; Godot en --headless quand c'est possible, et captures dans une fenêtre hors écran (--position 6000,3000) sans lire les entrées réelles. Ne ferme ni ne redémarre mes programmes.
- Git dès le début, un commit par étape avec un message en français. Crée un CLAUDE.md qui résume le projet, l'histoire, les règles, les commandes et l'avancement, et tiens-le à jour.
- Après chaque phase : ARRÊTE-TOI, montre-moi le résultat (captures ET courtes vidéos MP4 ou GIF) et attends mon avis. Avant de me solliciter, vérifie toi-même tes vidéos et corrige ce qui ne va pas.

## GITHUB
Dépôt : https://github.com/NengD/derniere_mission
- Au tout début : relie le projet à ce dépôt (branche main). Si je dois me connecter à GitHub (git ou la commande gh), guide-moi pas à pas et attends ma confirmation.
- Le dépôt est PUBLIC, et je le veux ainsi : tout ce que tu envoies est visible par tout le monde. N'y mets aucune information personnelle (ni mon adresse e-mail dans le texte, ni chemins personnels inutiles dans la documentation). Ajoute un fichier LICENSE : propose-moi le choix (par exemple code sous licence MIT et contenus du jeu tous droits réservés, ou tout tous droits réservés) et attends ma réponse ; respecte aussi les licences des ressources externes (crédits dans CREDITS.md).
- .gitignore adapté à Godot : .godot/, exports, fichiers temporaires, sauvegardes de Blender (*.blend1), vidéos et captures de travail lourdes. Ne mets JAMAIS de mot de passe, clé API ou jeton dans le dépôt.
- Fichiers lourds : aucun fichier au-dessus de 50 Mo (GitHub refuse au-delà de 100 Mo). Préfère des ressources régénérables par tes scripts. N'utilise Git LFS que si c'est vraiment nécessaire, après avoir vérifié le quota gratuit actuel de GitHub et m'avoir prévenu.
- Commits : petits et fréquents, messages en français ; pousse sur GitHub à la fin de chaque étape.
- Étiquettes de version : un tag à chaque phase validée par moi (v0.0-phase0, v0.1-niveau1, etc.).
- Releases : à chaque phase validée, crée une Release GitHub avec DEUX versions jouables : Windows (.zip) et Linux x86_64 (.tar.gz, avec le fichier marqué exécutable), le résumé des nouveautés en français et 2 ou 3 captures.
- Issues : note dans les Issues GitHub les bugs trouvés, mes retours et les idées pour plus tard (avec des étiquettes bug / retour / idée / niveau-N), et ferme-les quand c'est corrigé en citant le commit.
- Milestones : un jalon par phase (Phase 0 à Phase 4) et un par niveau en phase 3, pour suivre l'avancement.
- GitHub Actions (gratuit pour un dépôt public) : un workflow qui, à chaque envoi, lance l'import et tous les tests automatiques de Godot en mode sans fenêtre, pour vérifier que rien n'est cassé ; et un workflow qui, à chaque tag de version, fabrique automatiquement les exports Windows et Linux et les joint à la Release.
- README.md : présentation du jeu, histoire en quelques lignes, captures, commandes, comment lancer sur Windows et sur Linux, comment exporter, avertissement bien visible « contenu très violent, réservé aux adultes (18+) », et lien vers CREDITS.md et LICENSE.

## L'HISTOIRE
- Titre provisoire : « Dernière mission ».
- Héros : Marc, 48 ans, ancien commando des forces spéciales, retiré depuis dix ans.
- Sa fille : Léa, 22 ans, enlevée lors d'un voyage parce qu'elle a vu quelque chose qu'elle n'aurait pas dû voir.
- Le cartel : un cartel FICTIF dans un pays FICTIF d'Amérique latine, avec des membres de toutes origines (pas de caricature d'un vrai pays ou d'un vrai peuple). Invente leurs noms, le nom du pays, de la ville et du cartel, et un logo / des tags cohérents.
- Pourquoi la caméra-piéton : Marc porte une caméra pour que son vieil ami de l'armée, Vincent, le guide à distance par radio.
- Narration SANS cinématique avec des personnages qui parlent : écran-titre entre les niveaux (date, lieu, quelques phrases), messages radio de Vincent sous-titrés pendant les niveaux, documents à ramasser (lettres, carnets, téléphones) qui révèlent l'histoire. Voix : synthèse vocale gratuite en local seulement si sa licence le permet pour un jeu, sinon sous-titres seuls.
- Les 8 niveaux, en couloirs, 5 à 10 minutes chacun :
  1. L'aéroport de fret, de nuit — arrivée clandestine, premiers gardes, apprentissage discret des commandes.
  2. Le bidonville — ruelles étroites, toits, Marc cherche un informateur.
  3. Le club — boîte de nuit du cartel, néons, musique, fumée ; il apprend où est Léa.
  4. Les égouts — passage sombre sous la ville, peu de lumière, tension.
  5. Le laboratoire de drogue — usine dans la jungle, vapeurs, éléments qui explosent.
  6. Le commissariat corrompu — la police travaille pour le cartel ; une trahison est suggérée.
  7. L'hacienda du chef — villa de luxe, gardes d'élite ; Léa a été déplacée.
  8. Le port, final — cargo prêt à partir avec Léa, combat dans la cale et sur le pont, face au chef.
- Dans chaque niveau : des otages à libérer (facultatifs) et des documents à trouver (facultatifs), dont un document CACHÉ quelque part dans la campagne qui prouve que Vincent travaille pour le cartel.

## LES FINS (plusieurs fins selon la façon de jouer)
- Fin HEUREUSE mais avec un prix : le joueur a libéré tous les otages et trouvé tous les documents (sauf éventuellement le document caché). Marc tue le chef, libère Léa, est grièvement blessé ; Léa le soutient jusqu'au bateau de secours, l'image tremble, écran noir. Épilogue texte « Trois mois plus tard… » avec une image de Marc et Léa à la maison, lui avec une canne.
- Fin TRAGIQUE : le joueur a foncé en ignorant otages et documents. Marc sauve Léa mais meurt dans la fusillade finale : la caméra tombe au sol et continue de filmer, on entend Léa l'appeler, puis les sirènes. Texte final : la vidéo de la caméra devient la preuve qui fait tomber le cartel.
- Fin avec REBONDISSEMENT (prioritaire sur les deux autres) : le joueur a trouvé le document caché. Après avoir libéré Léa, Marc comprend que Vincent l'a utilisé pour éliminer un chef rival. Il coupe la radio, regarde la caméra, Léa derrière lui. Texte : « Mission suivante : lui. »
- Les conditions exactes sont dans des données faciles à régler ; affiche à la fin un récapitulatif (otages, documents, précision, temps, morts).

## LE JEU
- Vue caméra-piéton : objectif grand-angle avec légère déformation (fisheye), grain, compression vidéo, aberration chromatique, flou de mouvement, petites saccades de la caméra quand on court ou qu'on est touché, horodatage discret « REC » dans un coin, sang sur l'objectif. Un réglage d'intensité de l'effet (et une option qui coupe la déformation et les saccades pour ceux qui ont le mal des transports).
- Aucun HUD par défaut : on compte ses balles, on sent ses blessures à l'image et au son (bruit de cœur, respiration, vision qui se trouble). Option dans le menu pour afficher les munitions et un petit point de visée.
- Combats courts et mortels : 2 ou 3 balles suffisent pour le joueur comme pour les ennemis. Soins rares (trousses) ; pas de régénération automatique, ou très lente (réglable).
- 3 armes : pistolet, fusil à pompe, fusil d'assaut. Recul réaliste, visée (clic droit), rechargement réel (le chargeur partiellement vidé est conservé à part, rechargement plus lent si vide), enrayement rare, munitions ramassées sur les ennemis, flash et fumée du canon, douilles éjectées, son qui résonne différemment selon la pièce (petite pièce, couloir, extérieur).
- Mouvements : marche, course, accroupi, se pencher à gauche / droite (A et E), saut bas. Le corps du joueur est visible quand on regarde ses pieds si c'est réalisable proprement, sinon seulement les bras et l'arme.
- Ennemis : membres du cartel, visages couverts (cagoules, bandanas, masques, casques). Plusieurs types (garde de base, tireur au fusil, gros bras au fusil à pompe, élite de l'hacienda, policier corrompu, chef final). IA en arbre de comportement : patrouille, entend les tirs, appelle des renforts, se met à couvert, contourne, tire en rafale, lance des grenades (types avancés), recule blessé. Dégâts localisés (tête, torse, bras, jambes) avec réactions différentes ; un ennemi touché à la jambe tombe et continue de tirer à terre ; certains blessés rampent. Mort en ragdoll.
- Otages et Léa : ne peuvent pas être pris comme cible pour s'amuser ; tirer sur un otage fait échouer le niveau. Léa et les civils ne servent jamais de spectacle gore.
- Niveaux : couloirs réalistes, intérieurs surtout, avec une lecture claire du chemin (lumière, portes), un objectif simple par niveau, sauvegarde au début de chaque niveau et à 1 ou 2 points de contrôle, score de fin de niveau.
- Menus : menu principal, choix du niveau débloqué, options (son par bus Musique / Effets / Voix / Ambiance, sensibilité de la souris, FOV, intensité de l'effet caméra-piéton, niveau de violence, qualité graphique Bas / Moyen / Élevé, touches réassignables), pause.
- Clavier-souris UNIQUEMENT : pas de prise en charge de la manette (ni commandes, ni menus, ni options).

## VIOLENCE AU MAXIMUM (réglable dans les options : Maximum / Réduite / Sans sang)
- Giclées de sang dans la direction de la balle, impacts, traînées et éclaboussures sur les murs et le sol, flaques qui s'étendent, sang sur l'objectif de la caméra.
- Démembrement : membres et tête arrachés par le fusil à pompe, les tirs à bout portant et les explosions, morceaux en ragdoll. Il n'existe presque pas de ressources gore gratuites : crée toi-même la découpe des modèles en Blender, les textures de chair et les effets.
- Les corps et le sang restent dans le niveau (avec une limite réglable pour les performances).
- La violence vise uniquement les membres armés du cartel.

## LES RESSOURCES (toutes gratuites)
- Décors : textures et modèles scannés de Poly Haven et ambientCG (CC0), éclairage précalculé (LightmapGI) et réflexions soignées pour un rendu réaliste en intérieur.
- Armes, ennemis, animations : packs CC0 (Quaternius dont la Universal Animation Library 1 et 2 avec maniement d'armes, Kenney, KayKit, OpenGameArt CC0), base de capture de mouvement de CMU (libre pour usage commercial, citer la source), puis retravaillés par toi dans Blender. Ne crée de zéro que ce qui n'existe nulle part.
- Sons : packs gratuits libres de droits (vérifie la licence) et CC0 (Freesound CC0, OpenGameArt, Kenney) pour tirs, impacts, pas, voix d'ennemis (cris, ordres), ambiance ; musique CC0 ou générée par toi.

## LA MÉTHODE
### PHASE 0 — Recherche et direction artistique (ne construis rien)
1. Tableau des meilleures ressources gratuites utilisables (ressource, contenu, qualité, licence, utilisable en France oui/non) pour : décors intérieurs, armes, ennemis, animations, sons, voix.
2. Deux aperçus d'un couloir du niveau 1 avec un garde du cartel, vus à travers l'effet caméra-piéton : A) photoréaliste sombre ; B) réaliste mais plus stylisé et contrasté. Dis-moi honnêtement le niveau atteignable pour chacun et ce qui risque de décevoir.
3. Le document de conception (docs/CONCEPTION.md) : histoire détaillée, noms, déroulé et objectif de chaque niveau, emplacement des otages et documents, conditions des fins.
4. ATTENDS mes choix.

### PHASE 1 — Tranche verticale : UN niveau, au meilleur niveau
Le niveau 1 seulement, avec le pistolet et le garde de base : effet caméra-piéton, sensation de tir, IA, sons, sang et démembrement, otage, document, radio de Vincent, écran-titre, sauvegarde, score de fin. Tests automatiques de la logique (dégâts, munitions, IA, conditions de fin, sauvegarde) qui passent. ARRÊTE-TOI : je dois le trouver beau et prenant avant d'aller plus loin.

### PHASE 2 — Arsenal et ennemis
Fusil à pompe, fusil d'assaut, grenades ennemies, tous les types d'ennemis. Une chose à la fois, validée par moi.

### PHASE 3 — Les niveaux 2 à 8 et les trois fins
Un niveau à la fois, chacun validé par moi, avec sa narration. Puis les trois fins et le récapitulatif.

### PHASE 4 — Menus, options et polissage
Menus complets, options, performances (60 images/s minimum sur mon PC : Ryzen 9 5900X, Radeon RX 7800 XT 16 Go, écran 2560x1440 à 165 Hz), corrections, et des exports jouables pour Windows ET Linux.

## VERSION LINUX
- Le jeu doit fonctionner sous Windows ET sous Linux (x86_64) dès la phase 1 : installe les modèles d'exportation de Godot 4.7 et crée les deux préréglages d'export (Windows Desktop et Linux).
- Pas de code ni d'outil propre à Windows dans le jeu (chemins, séparateurs, commandes) ; sauvegardes et options dans user:// ; noms de fichiers de ressources en minuscules sans espaces ni accents (Linux est sensible à la casse).
- Rendu compatible Vulkan (Forward+) avec repli possible.
- Vérifie l'export Linux sur le runner Ubuntu de GitHub Actions : lancement en mode sans fenêtre et tests de logique.

Commence par la PHASE 0.
