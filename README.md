# Soomfon Raccourcis pour Mac

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

L’insertion de texte utilise un collage en texte brut ; le presse-papiers précédent est
restauré après une demi-seconde, sauf si un autre contenu a été copié entre-temps.
Un champ acceptant le collage doit être actif.
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
