# bclt : spécification de conception v1

Date : 11 novembre 2026
Statut : validé en brainstorming, en attente de relecture finale avant plan d'implémentation
Auteur : Jérémy (fondateur, opérateur du premier serveur), avec Claude

---

## 1. Mission et cadre

### 1.1 Pourquoi

bclt est un réseau social français que ni une plateforme ni un blocage des
fournisseurs d'accès français ne peuvent couper. Il reprend les codes des
applications grand public (Instagram d'abord, puis Snapchat, TikTok, X) pour
être adopté par le même public, sans que la décentralisation se voie.

C'est un projet de conviction, pas de croissance : le succès à douze mois est
une communauté réelle qui l'utilise, même petite.

### 1.2 Contre quoi on se défend

| Menace | Défense |
|---|---|
| Bannissement ou suppression de compte par une plateforme | L'identité est une clé sur l'appareil de l'utilisateur ; aucun serveur ne possède de compte |
| Suppression de contenu par un serveur | Contenus signés et répliqués sur plusieurs relais indépendants |
| Blocage DNS ou IP par les FAI français | Plusieurs noms de domaine dans des juridictions différentes, adresses IP embarquées, bascule automatique entre relais |
| Saisie ou fermeture d'un serveur | Plusieurs relais chez plusieurs hébergeurs, aucun n'est indispensable |
| Retrait de l'app des stores | APK direct et version web dès la bêta |
| Pression sur l'opérateur | Protocole et code ouverts, tout opérateur peut lancer un relais ; association loi 1901 à terme |

### 1.3 Ce qu'on ne défend pas

bclt n'a pas vocation à rendre toute censure impossible. Les contenus
terroristes et pédocriminels doivent pouvoir être retirés, et le réseau ne
doit pas pouvoir être détourné pour les diffuser. Le modèle de modération
(section 7) en découle.

Hors périmètre, explicitement : coupure nationale d'internet, adversaire
disposant d'un téléphone compromis, anonymat de l'opérateur.

### 1.4 Décisions fondatrices

| Sujet | Décision |
|---|---|
| Modèle de décentralisation | Identité par clé, publications signées envoyées à plusieurs relais interchangeables, médias adressés par empreinte |
| Protocole | Protocole propre à bclt, inspiré des bons principes existants (Nostr notamment) mais maîtrisé par nous ; seules des briques standard stables (Ed25519, SHA-256, Argon2id, TLS) sont réutilisées |
| Modération | Protocole neutre ; chaque opérateur applique la loi et ses règles sur son serveur ; filtres opt-in pour le reste |
| Premier opérateur | Jérémy, serveur chez 1984 Hosting (Islande), budget 20 € par mois |
| Produit v1 | Fil photo public façon Instagram, tout public, abonnements publics |
| Inscription | Pseudo et photo, sans email ni téléphone ; pseudonymat par défaut |
| Récupération de compte | Sauvegarde chiffrée automatique par phrase de trois mots ; récupération sociale en v2 |
| Plateformes | iOS, Android et web dès la v1, un seul code d'interface |
| Pile technique | TypeScript partout, Bun, Expo, SQLite, Docker |
| Licences | MIT pour `protocol` et `core`, AGPL-3.0 pour `app`, `relay`, `media` |
| Nom | bclt, définitif ; domaines `bclt.is` (principal) et `bclt.ch` (secours) |
| Calendrier | Bêta fermée visée mi-décembre 2026, limite dure début janvier 2027, périmètre v1 non négociable |

---

## 2. Le protocole bclt v0

### 2.1 Identité

- Paire de clés Ed25519 générée sur l'appareil.
- La clé publique est l'identifiant permanent du compte. Forme lisible :
  encodage bech32 avec préfixe `bclt1`.
- Le pseudo est un champ de profil, choisi librement, **non unique** au niveau
  du protocole. L'app lève l'ambiguïté avec un discriminant (premiers
  caractères de la clé) à côté du pseudo et en classant d'abord les comptes
  déjà suivis. Aucun registre central de noms.

### 2.2 Événement

L'unité de base est un document JSON signé :

```
{
  id:         sha256 de la forme canonique (hex)
  pubkey:     clé publique de l'auteur (hex)
  created_at: horodatage Unix en secondes
  kind:       entier, type d'événement
  tags:       tableau d'étiquettes [nom, valeur, ...]
  content:    chaîne
  sig:        signature Ed25519 de id (hex)
}
```

La forme canonique est la sérialisation JSON sans espaces du tableau
`[0, pubkey, created_at, kind, tags, content]`, chaînes échappées de façon
déterministe. La spec exacte et les vecteurs de test vivent dans `spec/`.

### 2.3 Types d'événements de la v1

| Kind | Nom | Contenu | Étiquettes | Remplaçable |
|---|---|---|---|---|
| 0 | profil | JSON : pseudo, bio, empreinte de la photo, relais d'écriture | | oui (le plus récent gagne) |
| 1 | publication | légende | `media` (empreinte, adresses, description), `t` (hashtag), `p` (mention) | non |
| 2 | commentaire | texte | `e` (publication), `p` (auteur de la publication) | non |
| 3 | like | vide | `e` (publication), `p` (auteur) | non, un seul par auteur et publication |
| 4 | abonnements | vide | `p` (clé suivie) répétée | oui |
| 5 | suppression | vide | `e` (identifiants à effacer) | non |
| 6 | commentaires masqués | vide | `d` (identifiant de la publication), `e` (commentaires masqués) répétée | oui, par publication |
| 7 | sauvegarde chiffrée | blob chiffré (base64) | `d` (index de recherche) | oui |

Règles :

- Un événement remplaçable est identifié par (pubkey, kind[, d]) ; un relais ne
  conserve que le plus récent.
- Une suppression ne vaut que pour les événements du même auteur ; un relais
  conforme efface réellement les événements visés et conserve la suppression.
- Le masquage de commentaires (kind 6) n'est valide que si son auteur est
  l'auteur de la publication visée ; les apps conformes n'affichent pas les
  commentaires masqués.
- Blocages, sourdines et réglages locaux ne sont **jamais publiés** : ils
  vivent dans l'appareil et dans la sauvegarde chiffrée.
- Hashtags et mentions sont extraits de la légende par l'app à la publication
  et dupliqués en étiquettes pour permettre les requêtes.

### 2.4 Relais

Serveur WebSocket. Messages client vers relais :

| Message | Rôle |
|---|---|
| `["PUBLISH", event]` | soumettre un événement |
| `["REQ", subId, filter...]` | s'abonner à des événements correspondant aux filtres |
| `["CLOSE", subId]` | fermer un abonnement |
| `["AUTH", event]` | répondre à un défi d'authentification |

Messages relais vers client :

| Message | Rôle |
|---|---|
| `["EVENT", subId, event]` | un événement correspondant |
| `["EOSE", subId]` | fin des événements stockés |
| `["OK", eventId, accepted, message]` | résultat d'un PUBLISH |
| `["AUTH", challenge]` | défi à signer |
| `["NOTICE", message]` | information |

Un filtre combine : `ids`, `authors`, `kinds`, `since`, `until`, `limit`,
`search` (pseudo, pour les profils), et étiquettes (`#e`, `#p`, `#t`).

Le relais vérifie signature et empreinte, stocke, indexe, répond aux filtres.
Il ne classe pas, ne recommande pas, ne comprend pas le produit.

- **Lire** est libre.
- **Écrire** exige l'authentification par défi signé (`AUTH`). Elle permet
  à l'opérateur d'appliquer ses règles : code d'invitation à la première
  écriture d'une clé, limites de débit par clé et par IP, taille maximale,
  bannissement d'une clé en écriture, retrait d'événements. Ces décisions ne
  concernent que ce relais.
- Le premier message de chaque connexion porte la version du protocole
  (`v0`). Un relais refuse une version inconnue avec un `NOTICE` explicite.

Le relais expose aussi une petite API HTTP : signalements (section 7), état
de santé, et document d'information (opérateur, CGU, contact, règles).

### 2.5 Serveur de médias

Serveur HTTP distinct, volontairement stupide : il stocke des octets
identifiés par leur empreinte SHA-256.

- `PUT /upload` : corps binaire, authentifié par un événement signé en
  en-tête (clé, empreinte annoncée, horodatage). Répond avec l'empreinte et
  l'adresse.
- `GET /{sha256}` : renvoie le fichier. L'app vérifie l'empreinte à la
  réception et rejette toute divergence.
- `HEAD /{sha256}` : existence.
- `DELETE /{sha256}` : par le déposant, authentifié.
- Règles opérateur : types acceptés (JPEG, WebP en v1), taille maximale,
  quota par clé, limites de débit, retrait.

Une publication référence chaque photo par empreinte, accompagnée d'une
liste d'adresses où la trouver et d'une description optionnelle (texte
alternatif). Redimensionnement et suppression des métadonnées EXIF ont lieu
sur l'appareil avant envoi.

### 2.6 Circulation (modèle de boîte d'envoi)

- Le profil déclare les relais d'écriture de son auteur.
- L'app publie chaque événement sur tous les relais d'écriture de
  l'utilisateur. La publication est réussie dès qu'un relais a accepté ; les
  autres sont retentés en arrière-plan.
- Pour lire quelqu'un, l'app interroge les relais déclarés dans son profil,
  en plus des relais par défaut.
- Une liste de relais par défaut est embarquée dans l'app (noms et adresses
  IP) et mise à jour par un fichier signé par bclt, récupérable à plusieurs
  adresses.
- Si un relais est injoignable, l'app bascule sans rien demander.

### 2.7 Versionnage et conformité

- La spec vit dans `spec/` : format des événements, messages, filtres,
  règles de validation, vecteurs de test.
- Chaque message porte la version. Les évolutions se font par ajout de kinds
  ou de champs, jamais par modification silencieuse.
- Toute implémentation (y compris un futur relais dans un autre langage) doit
  passer les vecteurs de test.

---

## 3. Identité, inscription et récupération

### 3.1 Inscription

Ouvrir l'app, choisir un pseudo et une photo (optionnelle), c'est tout. La
paire de clés est générée en arrière-plan et stockée dans l'espace sécurisé
du téléphone (Secure Enclave, Android Keystore). Aucune donnée de contact.
L'utilisateur peut publier immédiatement.

Sur le premier relais, la première écriture exige un code d'invitation
(bêta fermée). Le code est consommé par la clé ; il n'est jamais lié à une
identité civile.

### 3.2 Phrase de récupération

Dans la première session, un bandeau "Sécurise ton compte, 1 minute" propose
de créer une phrase de récupération :

- par défaut, trois mots français tirés d'une liste de 2048 mots plus un
  nombre à deux chiffres, du type `tigre-nuage-pomme-47` (environ 40 bits
  d'entropie) ;
- ou une phrase choisie par l'utilisateur, 8 caractères minimum.

L'app fait retaper la phrase une fois. Rappels non bloquants à J+1 et J+3,
puis à chaque changement de pseudo, tant qu'elle n'est pas définie. Le
message dit clairement qu'un compte sans phrase ni sauvegarde cloud est
perdu avec le téléphone.

Justification du choix contre un code à chiffres : la copie chiffrée est
récupérable sur les relais par quiconque connaît pseudo et phrase ; un code
à 6 chiffres se casse hors ligne en quelques heures, trois mots plus un
nombre avec Argon2id résistent à des années de calcul.

### 3.3 Sauvegarde chiffrée

Dérivation : Argon2id (paramètres fixés dans la spec, environ une seconde
sur un téléphone de milieu de gamme) à partir de la phrase et d'un sel
dérivé du pseudo normalisé, produisant deux clés : une clé de chiffrement et
une clé d'index.

Contenu chiffré (XChaCha20-Poly1305) : clé secrète, liste des relais,
abonnements, blocages, version du format.

Deux copies :

1. **Cloud du téléphone** : trousseau iCloud sur iOS, sauvegarde Google
   (Blockstore ou équivalent) sur Android. Illisible pour Apple et Google.
2. **Relais de l'utilisateur** : événement kind 7, étiquette `d` égale à
   l'index dérivé. Impossible de lister ou retrouver la copie de quelqu'un
   sans connaître pseudo et phrase.

Changer de phrase remplace les deux copies. La sauvegarde est rafraîchie à
chaque changement d'abonnements ou de blocages.

### 3.4 Récupération et second appareil

"Récupérer mon compte" : pseudo plus phrase. L'app calcule l'index, interroge
les relais par défaut, déchiffre, restaure clé, abonnements et blocages. Sur
iPhone vers iPhone, la restauration iCloud le fait sans saisie. Le même
parcours ajoute un second appareil.

### 3.5 Web

La clé est stockée chiffrée dans le navigateur (IndexedDB, chiffrement par
la clé dérivée de la phrase) et déverrouillée à la connexion. Option "rester
connecté" avec clé de session conservée dans le navigateur.

### 3.6 Limites assumées en v1

- Pas de changement de clé en cas de compromission ; prévu en v2 par un
  événement de migration signé par l'ancienne clé.
- Un utilisateur sans phrase ni sauvegarde cloud qui perd son téléphone perd
  son compte.
- Récupération sociale (amis de confiance, partage de secret) en v2.

### 3.7 Pour l'opérateur

Aucune donnée d'identité : ni email, ni téléphone, ni clé en clair. Il
stocke des copies chiffrées qu'il ne peut pas ouvrir et les journaux de
connexion que la loi impose (section 7).

---

## 4. Architecture logicielle

Un seul dépôt `bclt`. TypeScript strict partout, Bun comme gestionnaire de
paquets, lanceur de tests et runtime des serveurs. Expo pour l'app.

```
bclt/
  spec/                 spec du protocole, vecteurs de test
  packages/
    protocol/           protocole pur (MIT)
    core/               client sans écran (MIT)
  apps/
    app/                app Expo : iOS, Android, web (AGPL-3.0)
    relay/              relais (AGPL-3.0)
    media/              serveur de médias (AGPL-3.0)
  deploy/               docker-compose, Caddy, scripts de sauvegarde
  docs/                 cette spec, plans, textes légaux
```

### 4.1 `packages/protocol`

Types d'événements, sérialisation canonique, signature et vérification
Ed25519 (`@noble/ed25519`), SHA-256 (`@noble/hashes`), encodage bech32,
filtres et messages de relais, validation. Aucune dépendance de plateforme,
aucune notion de produit. Seule implémentation du protocole, partagée par
apps et serveurs. Vérifié par les vecteurs de `spec/`.

### 4.2 `packages/core`

Tout ce qu'une app fait sans écran :

- **KeyStore** : interface, implémentations par plateforme (enclave sur
  mobile, IndexedDB chiffré sur web, mémoire pour les tests).
- **RelayPool** : connexions à plusieurs relais, publication partout,
  requêtes multi-relais avec dédoublonnage, bascule et reconnexion, file
  d'attente locale des publications en attente.
- **Store** : cache local SQLite (`expo-sqlite`, même moteur sur mobile et
  web), schéma des événements et index produit (fil, profils, compteurs).
- **Services** : identité et sauvegarde (Argon2id via `libsodium`,
  XChaCha20-Poly1305), fil, profils, abonnements, interactions, blocages,
  recherche, notifications (calculées par requête des événements qui me
  référencent), médias (redimensionnement et EXIF délégués à l'app, envoi
  et vérification d'empreinte dans `core`).

Testé contre un relais en mémoire et contre des relais défaillants simulés.

### 4.3 `apps/app`

Une seule app Expo avec Expo Router, builds iOS, Android et web depuis le
même code. Caméra, galerie, recadrage, redimensionnement et nettoyage EXIF,
notifications locales. Elle ne parle jamais au réseau directement, tout passe
par `core`. État local minimal, l'essentiel est lu depuis le Store.

### 4.4 `apps/relay`

Bun, WebSocket natif, SQLite natif (`bun:sqlite`). Un conteneur Docker, aucune
dépendance externe. Configuration par fichier : nom, opérateur, règles
(invitation, débit, tailles, kinds acceptés). API HTTP : signalements, santé,
informations. Outil en ligne de commande pour l'opérateur : codes
d'invitation, retrait d'un événement, bannissement d'une clé, boîte des
signalements, statistiques, export.

### 4.5 `apps/media`

Bun, HTTP, fichiers sur disque, adressage par empreinte. Même outil
opérateur pour retirer un fichier ou bannir une clé. Stockage objet
(S3-compatible) possible plus tard derrière la même interface.

### 4.6 Outillage

- CI GitHub Actions : lint, typage, tests de tous les modules, vecteurs de
  test, build web.
- Builds mobiles par EAS, build local sur Mac en secours.
- Dépendances verrouillées, revue de chaque ajout.
- Miroir du dépôt sur Codeberg.

---

## 5. Fonctionnalités de la v1

### 5.1 Utilisateur

- **Inscription et sécurisation** (section 3), en français.
- **Fil** : publications des comptes suivis, ordre chronologique inverse,
  sans algorithme, sans suggestions, sans publicité. Tirer pour rafraîchir,
  chargement au défilement, lecture hors ligne du cache.
- **Publier** : une à cinq photos (carrousel), caméra ou galerie, recadrage,
  légende avec hashtags et mentions, description par photo optionnelle.
  Supprimer sa publication.
- **Interagir** : like, commentaire à plat en ordre chronologique, suppression
  de son commentaire, masquage des commentaires d'autrui sur ses publications.
- **Profils** : grille, compteurs de publications, d'abonnés et
  d'abonnements, listes d'abonnés et d'abonnements, bouton suivre. Modifier
  pseudo, photo, bio.
- **Trouver** : recherche par pseudo, page d'un hashtag, lien depuis une
  mention.
- **Notifications** : onglet dans l'app (likes, commentaires, nouveaux
  abonnés). Pas de push en v1.
- **Se protéger** : bloquer (ses contenus disparaissent pour moi, je
  disparais de ses résultats dans mon app ; l'app dit honnêtement qu'il peut
  toujours lire ce qui est public), signaler une publication, un commentaire
  ou un compte.
- **Réglages** : phrase de récupération, relais, comptes bloqués, mentions
  légales et CGU, suppression du compte.

Pas de sourdine : on incite à ne suivre que des comptes qui comptent, et le
blocage couvre le reste.

### 5.2 Opérateur

- Boîte des signalements, retrait d'événements et de médias, bannissement de
  clés en écriture, codes d'invitation, limites de débit configurables
  (défauts : 30 publications ou commentaires par heure et 20 photos par jour
  par clé, 10 premières écritures par heure par IP).
- Journaux limités au légal : IP, clé, horodatage, douze mois, rien d'autre.
- Sauvegarde quotidienne chiffrée hors site.

### 5.3 Suppression de compte et RGPD

Supprimer son compte publie une suppression de toutes ses publications,
commentaires et likes, vide le profil, et efface les sauvegardes chiffrées.
Le relais et le serveur de médias de bclt effacent réellement. Un relais
tiers non conforme est hors de notre contrôle ; la politique de
confidentialité le dit en clair.

---

## 6. Infrastructure, résilience et distribution

### 6.1 Serveurs

- **Principal** : VPS 1984 Hosting (Islande), Debian, 2 cœurs, 4 Go, 50 à
  80 Go de disque, environ 12 € par mois. `docker-compose` avec relais,
  médias et Caddy (TLS automatique). Sauvegarde quotidienne chiffrée de la
  base et des médias vers un stockage distinct chez un autre hébergeur.
- **Second relais** : petit VPS chez un autre hébergeur (Hetzner, environ
  5 € par mois), relais seul. Il prouve la bascule et donne deux relais
  d'écriture par défaut dès le premier jour.

Budget total visé : sous 20 € par mois.

### 6.2 Noms

- `bclt.is` (ISNIC, enregistré chez 1984 Hosting) : nom principal, site,
  `app.bclt.is`, `relay.bclt.is`, `media.bclt.is`.
- `bclt.ch` (SWITCH, enregistré chez Infomaniak) : secours, mêmes services.
- Adresses IP embarquées dans l'app pour se passer du DNS.
- `bclt.fr` est pris par un projet sans rapport ; pas de `.fr`.

### 6.3 Distribution

- iOS : TestFlight pour la bêta, App Store ensuite.
- Android : APK signé téléchargeable depuis le site, vérification de mise à
  jour dans l'app, dès la bêta. Play Store ensuite, F-Droid plus tard.
- Web : `app.bclt.is` et `app.bclt.ch`, installable sur l'écran d'accueil.
- Code source public sur GitHub, miroir Codeberg.

### 6.4 Résilience en v1, honnêtement

Avec un seul opérateur, le réseau est de fait centralisé chez bclt.
L'architecture garantit que ça cesse dès qu'un opérateur indépendant apparaît,
sans migration. Critère de sortie de la bêta : extinction du serveur
principal pendant une heure, personne ne perd rien ni n'est bloqué.

---

## 7. Modération et cadre légal

### 7.1 Modèle à trois niveaux

1. **Protocole : neutre.** Personne ne peut supprimer une identité ni empêcher
   quelqu'un de publier quelque part.
2. **Opérateur : responsable de son serveur.** Chaque relais et serveur de
   médias applique la loi de son pays et ses règles, y compris les retraits
   obligatoires. Comme les utilisateurs publient sur plusieurs relais, aucun
   opérateur ne censure à l'échelle du réseau.
3. **Utilisateur : filtres opt-in.** Blocage en v1 ; listes partagées et
   services de labellisation en v2.

### 7.2 Obligations du premier opérateur (France)

Statut d'hébergeur (LCEN) et de service intermédiaire (DSA). À faire valider
par un avocat avant l'ouverture publique.

- Retrait prompt des contenus manifestement illicites signalés ; une heure sur
  injonction pour terrorisme et pédocriminalité. Canal de signalement visible
  dans l'app et sur le site.
- Signalement à PHAROS des contenus pédocriminels et terroristes constatés.
- Conservation douze mois des données de connexion (IP, clé, horodatage).
- RGPD : mentions légales, politique de confidentialité, registre des
  traitements.
- DSA : CGU, point de contact, mécanisme de signalement, rapport de
  transparence annuel.
- Engagement écrit : traitement des signalements d'illégal grave sous
  quelques heures.
- Filtrage par listes de hachage CSAM après la bêta (accès à demander auprès
  d'organismes agréés).

Structure : en nom propre pour la bêta fermée, association loi 1901 avant
l'ouverture publique (titulaire des domaines, opérateur, mentions légales).

### 7.3 Âge

Cible 13 ans et plus comme Instagram, sans vérification puisque rien n'est
collecté. La majorité numérique française (15 ans, accord parental en
dessous) est un point à valider avec l'avocat. La bêta fermée, sur invitation
et entre adultes, n'est pas concernée.

---

## 8. Erreurs, sécurité et tests

### 8.1 Erreurs

- **Réseau** : un relais en panne est normal. Publication réussie dès qu'un
  relais accepte, retentatives en arrière-plan, file d'attente locale,
  publication hors ligne envoyée au retour du réseau. Lecture : cache
  d'abord, complété par les relais joignables. Indicateur discret "hors
  ligne" ou "en attente", jamais "relais injoignable".
- **Données** : tout événement reçu est vérifié (signature, empreinte, forme)
  avant d'entrer dans le cache ; invalide = ignoré. Photo dont l'empreinte
  diverge = rejetée, serveur suivant. Un relais ne peut ni falsifier ni
  attribuer faussement, au pire il cache, et un autre comble.
- **Humaines** : confirmation de suppression, phrase retapée à la création,
  message honnête sur le risque de perte de compte.

### 8.2 Sécurité, ce qu'on tient

- Clés dans l'enclave sécurisée, jamais en clair hors sauvegarde chiffrée.
- Crypto par bibliothèques auditées (noble, libsodium), jamais maison.
- TLS partout en plus des signatures.
- Serveurs qui ne font jamais confiance au client.
- Dépendances minimales et verrouillées.
- Aucun traqueur ni analytique tiers, jamais.

### 8.3 Sécurité, ce qu'on ne tient pas en v1

- L'opérateur voit les adresses IP.
- Les relais voient qui consulte quoi.
- Un téléphone compromis compromet la clé.
- Pas de rotation de clé.
- Une capture d'écran reste possible sur tout.

### 8.4 Tests

- `protocol` : unitaires et vecteurs de `spec/`.
- `core`, `relay`, `media` : intégration avec relais réel en mémoire,
  scénarios de panne (relais muet, menteur, réseau coupé), récupération de
  compte de bout en bout.
- Produit : liste de parcours manuels sur iPhone, Android et web avant chaque
  build de bêta ; test d'extinction d'une heure avant ouverture.
- Développement en TDD.

---

## 9. Phases

Périmètre v1 non négociable. Cible mi-décembre 2026, limite dure début
janvier 2027 : on prend du retard plutôt que de couper.

| Phase | Dates | Livrable | Côté fondateur |
|---|---|---|---|
| 0 Fondations | 11 au 16 nov. | Spec, dépôt, CI, licences, spec protocole et vecteurs, `protocol` testé | Comptes Apple et Google, commande du VPS 1984, relecture |
| 1 Réseau sans écran | 17 au 23 nov. | `core`, relais, médias, outil opérateur, CLI de démonstration, déploiement des deux relais, DNS, TLS, sauvegardes. Sortie : un relais éteint, rien ne se perd | Accès serveur, DNS |
| 2 App | 24 nov. au 6 déc. | Tous les parcours de la section 5, mobile et web. Parcours complet testable sur iPhone dès la fin de la première semaine | Tests quotidiens sur iPhone |
| 3 Durcissement | 7 au 13 déc. | Textes légaux, tests manuels, test d'extinction, TestFlight, APK, site, invitations | Relecture légale, tests Android et web |
| Bêta fermée | à partir du 14 déc. | 20 à 50 invités, non-techniciens en priorité | Invitations, retours |

Risques et réponses : validation Apple du TestFlight externe lancée dès la fin
de phase 2 ; build local si EAS sature ; retour à Node si Bun bloque côté
serveur (une journée).

---

## 10. Backlog v2 (hors périmètre v1, à ne pas perdre)

Produit :
- Stories 24 h, snaps éphémères, accusés de vue.
- Messagerie chiffrée de bout en bout, 1:1 et groupes, médias chiffrés.
- Vidéo courte.
- Comptes privés, amis proches.
- Réponses en fil sous les commentaires.
- Notifications push respectueuses de la vie privée.
- Page explorer, tendances francophones, suggestions.
- Sourdine, si la bêta la réclame.
- Récupération sociale (amis de confiance).
- Changement de clé après compromission (événement de migration).
- Choix d'algorithmes de fil, listes de blocage partagées, services de
  labellisation.

Résilience :
- Tor intégré, services onion pour chaque relais officiel.
- Transports masqués.
- Découverte de relais sans liste centrale.
- Synchronisation entre téléphones voisins (Bluetooth, Wi-Fi Direct).
- Builds reproductibles, F-Droid, boutiques alternatives DMA.
- Kit "lancer un relais" pour associations et particuliers.

Opérateur et organisation :
- Filtrage par listes de hachage CSAM.
- Rapports de transparence.
- Association loi 1901, dépôt de marque INPI, transfert des domaines.
- Relais en Go ou Rust si un second opérateur le demande.

---

## 11. Points à faire valider par un avocat avant l'ouverture publique

- Qualification hébergeur / service intermédiaire et obligations exactes.
- Durée et contenu de la conservation des données de connexion.
- Majorité numérique et accord parental.
- Textes : CGU, mentions légales, politique de confidentialité.
- Statuts de l'association et responsabilité du représentant.
