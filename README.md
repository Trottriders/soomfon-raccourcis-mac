# Soomfon Raccourcis pour Mac


## Pourquoi ce projet ?

Je ne suis pas développeur. J’ai créé cette application pour mon usage personnel,
parce que le logiciel du constructeur me posait régulièrement des problèmes sur
mon Mac. Je voulais pouvoir utiliser mon boîtier Soomfon avec les raccourcis et les
fonctions dont j’avais besoin au quotidien.

Si ce projet peut servir à d’autres personnes, tant mieux ! Les idées, les
corrections et les améliorations sont les bienvenues. Vous pouvez signaler un
problème dans les Issues ou proposer une modification avec une pull request.
Toute aide pour faire évoluer l’application est appréciée.

Application native pour le boîtier Soomfon XF-CN001 (15 touches, USB `1500:3003`).
Mac Apple Silicon, macOS 14 ou ultérieur. Version 0.9.6.

## Fonctionnalités

- Raccourcis clavier, combinaisons Ctrl/Option/Majuscule/Commande, appui simple ou maintien sous le doigt.
- Insertion de texte avec accents, emojis et retours à la ligne.
- Macros : raccourcis, textes, pauses, ouverture de logiciels et de sites.
- Pages de touches, associations automatiques avec le logiciel actif, page liée à l’ouverture d’un logiciel ou d’un site.
- Icônes personnelles, taille et fond réglables, titres facultatifs.
- Bande de droite : heure, logiciel actif, météo Open-Meteo, image ou zone vide.
- Veille : horloge, image, Pac-Man et Matrix avec construction puis désagrégation de l’heure.
- Réveil avec la souris ; extinction matérielle du boîtier pendant la veille des écrans du Mac.
- Capture directe avec Snapzy, si cette application est installée.

## Construire et lancer

Installer les outils en ligne de commande de Xcode, puis exécuter depuis ce dossier :

```sh
zsh build.sh
```

Le script compile, signe localement et vérifie l’application. Ouvrir ensuite
`output/Soomfon Raccourcis.app`. Le dossier `output` n’est pas suivi par Git.
Le programme utilise les frameworks macOS et aucune dépendance tierce téléchargée.

Fermer l’application officielle Soomfon avant de lancer celle-ci.
Autoriser **Soomfon Raccourcis** dans Réglages Système → Confidentialité et sécurité → Accessibilité.
Après une recompilation, si cette autorisation n’est plus reconnue, remplacer son ancienne
entrée par la version actuelle. Aucun changement de réglages n’est automatique.

Dans **Touches**, choisir un bouton puis son **Action**. Les réglages sont sauvegardés
automatiquement. Les actions clavier et texte s’appliquent au logiciel au premier plan ;
elles sont suspendues pendant que la fenêtre de configuration est active.
La capture directe Snapzy peut aussi fonctionner depuis cette fenêtre.
Fermer la fenêtre conserve l’application dans la barre des menus.

## Réglages et données

Les réglages personnels sont conservés sur le Mac dans
`~/Library/Application Support/Soomfon Raccourcis/raccourcis.json`, avec une sauvegarde précédente.
Ils ne font pas partie de ce dépôt. Les icônes choisies sont intégrées à ces réglages.
Le menu de l’application permet leur export et leur import.
Pendant la saisie d’un titre, d’un texte ou d’une adresse, le fichier est écrit une demi-seconde
après la dernière frappe, et tout de suite à la fermeture de la fenêtre ou en quittant.
Si le fichier principal est abîmé au lancement, la sauvegarde précédente est restaurée
automatiquement : l’ancien fichier est gardé à côté (`raccourcis.corrupt-….json`) et un message
l’indique dans la fenêtre. Sans sauvegarde utilisable, rien n’est modifié, l’application reste en
pause et l’import d’une configuration la répare.

L’insertion de texte utilise un collage en texte brut ; le presse-papiers précédent est
restauré après une demi-seconde, sauf si un autre contenu a été copié entre-temps.
Un champ acceptant le collage doit être actif.
Le texte est marqué comme temporaire et confidentiel pour les gestionnaires de presse-papiers qui
respectent cette convention. Les textes enregistrés restent en clair dans le fichier de réglages et
dans les exports : n’y mets pas de mot de passe.
La météo ne nécessite pas de clé et utilise uniquement la ville choisie.
Les touches sans action sont noires ; le protocole connu ne permet pas l’extinction
individuelle de leur rétroéclairage.

## Vérification

Le script de construction lance les vérifications natives. Le binaire accepte aussi :

```sh
"output/Soomfon Raccourcis.app/Contents/MacOS/SoomfonRaccourcis" --self-test
```

Ces vérifications couvrent le protocole USB, la sauvegarde et les migrations, les rendus,
les pages, les macros et leur annulation, les raccourcis maintenus, le texte et la restauration
du presse-papiers. Les essais du presse-papiers utilisent une zone isolée.
Une vérification sur le boîtier reste nécessaire pour le comportement matériel.

Voir [REFERENCES.md](REFERENCES.md) pour les sources du protocole et des API.
