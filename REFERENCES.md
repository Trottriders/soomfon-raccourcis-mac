# Références techniques

Application Swift originale, sans dépendance téléchargée et sans intégrer de code Rust.
Les formats de messages USB et la correspondance des adresses ont été vérifiés dans :

- [opendeck-akp153, mappings.rs](https://github.com/4ndv/opendeck-akp153/blob/main/src/mappings.rs) : XF-CN001 `1500:3003`, interface `FFA0:1`, protocole 3, images JPEG 95 × 95.
- [opendeck-akp153, inputs.rs](https://github.com/4ndv/opendeck-akp153/blob/main/src/inputs.rs) : adresses des touches et des points tactiles.
- [mirajazz, device.rs](https://github.com/4ndv/mirajazz/blob/main/src/device.rs) : commandes CRT, DIS, LIG, BAT, STP et CONNECT ; `Device::sleep` utilise `HAN` pour la veille matérielle.
- [mirajazz, state.rs](https://github.com/4ndv/mirajazz/blob/main/src/state.rs) : messages ACK, adresse à l’octet 9 et état à l’octet 10.

Les trois emplacements du tableau de bord utilisent les adresses 16, 17 et 18,
avec des images JPEG 82 × 82. Leur contenu est configurable depuis la version 0.3.
Leurs appuis tactiles sont exclus de l’envoi de raccourcis.
Les échanges natifs macOS excluent l’octet d’identifiant de rapport ajouté par HIDAPI.

- [API météo Open-Meteo](https://open-meteo.com/en/docs) : conditions actuelles,
  température, état jour/nuit et codes WMO ; temps Unix, unité Celsius.
- [API de géocodage Open-Meteo](https://open-meteo.com/en/docs/geocoding-api) :
  recherche de ville, nom, région, pays et coordonnées publiques de la commune.
- [Liens de commande Snapzy](https://snapzy.app/docs/url-scheme/) : lancement direct
  d’une capture de zone (`snapzy://capture/area`), d’écran (`fullscreen`) ou de fenêtre
  (`application`), sans raccourci clavier simulé.
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) :
  ouverture asynchrone des logiciels et des URL, avec résultat avant d’afficher la page liée.
- [Écrans en veille](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification)
  et [écrans réveillés](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidwakenotification) :
  notifications reçues depuis le centre de notifications de NSWorkspace, distinctes du sommeil du Mac.
