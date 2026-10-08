# Vérification de la version 0.9.6

Compilation native et suite de vérifications réussies sur Mac Apple Silicon.

- Messages USB natifs, correspondance des touches, récupération après erreur et coalescence des images.
- Raccourcis et relâchement des modificateurs, maintien sous le doigt.
- Sauvegarde, sauvegarde précédente, migration et refus des fichiers invalides.
- Pages, associations par logiciel, retours à l’accueil et ouvertures différées annulables.
- Macros ordonnées, pauses asynchrones et annulation.
- Texte Unicode multiligne, limites et persistance ; restauration du presse-papiers,
  protection d’une copie simultanée, nettoyage après échec et annulation.
- Rendu des icônes, zoom, fonds, titres et orientations.
- Horloge, météo, veille, secondes facultatives, Matrix et fragments de l’heure.
- Sommeil des écrans, sommeil général et reprise dans les deux ordres de notification.

Interface vérifiée pour l’action texte et son champ multiligne.
Le protocole connu dispose d’une luminosité et d’une veille globales, sans extinction individuelle documentée.
La suite ne certifie pas la stabilité matérielle après plusieurs heures ni le collage dans tous les logiciels.

## Modifications après la version 0.9.6 — à vérifier sur Mac

Ces changements ont été écrits sans pouvoir compiler ni lancer l’application. À valider avec
`zsh build.sh` (les vérifications intégrées couvrent la restauration des réglages et le marquage
du presse-papiers), puis à la main :

- ⌘C, ⌘V, ⌘X, ⌘A et ⌘Z fonctionnent dans les champs de texte de la fenêtre.
- Après une insertion de texte, un gestionnaire de presse-papiers n’enregistre pas ce texte.
- Un fichier de réglages abîmé est remplacé par la sauvegarde précédente, avec un message visible.
- La saisie d’un titre ou d’un texte reste fluide, et rien n’est perdu en quittant juste après.
