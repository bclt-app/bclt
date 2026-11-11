# Plan 1 : fondations et protocole v0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un dépôt outillé (Bun, TypeScript, CI) contenant la spec formelle du protocole bclt v0, ses vecteurs de test, et le paquet `@bclt/protocol` qui les passe tous.

**Architecture:** Monorepo Bun à espaces de travail. `spec/` est la source de vérité lisible par un humain et par une autre implémentation ; `packages/protocol` en est la seule implémentation TypeScript, pure (aucune dépendance de plateforme, aucune notion de produit), consommée ensuite par `core`, `relay` et `media` (plans 2 et 3).

**Tech Stack:** Bun 1.4 (`bun check` pour le typage, `bun fmt` pour le formatage, `bun test`, et `bun lint --type-aware` dès sa première version stable), TypeScript strict, `@types/bun` 1.4.4 (dépendance de dev), `@noble/ed25519` 2.2.3, `@noble/hashes` 1.8.0, `@scure/base` 1.2.6, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-11-bclt-design.md` (sections 2, 4.1, 4.6, 8.4).

## Global Constraints

- Tout en TypeScript strict (`"strict": true`, `"noUncheckedIndexedAccess": true`), modules ESM, cible ES2022.
- Bun est le gestionnaire de paquets, le lanceur de tests et le runtime des scripts. Pas de `npm`, pas de `node_modules` commités.
- Versions de dépendances épinglées exactement (pas de `^`), `bun.lock` commité.
- `packages/protocol` : licence MIT, aucune dépendance autre que `@noble/ed25519`, `@noble/hashes`, `@scure/base`. Jamais de crypto maison.
- Hexadécimal toujours en minuscules ; une chaîne hex en majuscules est invalide.
- Textes destinés aux utilisateurs en français ; identifiants de code, messages de protocole et commits en anglais.
- Commits fréquents, préfixés `feat:`, `test:`, `chore:`, `docs:`, chacun terminé par la ligne `Co-Authored-By:` du modèle qui a réellement produit le commit, telle que l'environnement la fournit au moment du commit (ne jamais recopier un nom de modèle depuis ce plan).
- Développement en TDD : chaque tâche commence par ses tests qui échouent.
- Les blocs de test de ce plan dépassent `print-width = 100` : lancer `bun fmt` (ou `bun fmt --changed=origin/main`) avant chaque `bun run verify`, sinon `bun fmt --check` échoue.
- Un ticket = une branche (nom fourni par Linear) = une PR vers `main`. Jamais de push direct sur `main`.
- Dépendances de dev : seul `@types/bun` 1.4.4 à la racine (tâche 1), plus `typescript` en version exacte si `bun check` l'exige. La contrainte « aucune dépendance » de `packages/protocol` ne vise que ses dépendances d'exécution.

## Review Focus

Chaque ligne est couverte par un test ajouté dans la tâche qui possède le code.

1. Un événement JSON avec un champ en plus (`"foo": 1`) ou un champ hex en majuscules doit être rejeté par la validation, sinon deux encodages du même événement circulent avec des identifiants différents. (Tâche 5)
2. Un événement dont la sérialisation dépasse 65 536 octets doit être rejeté **avant** toute vérification de signature, sinon un relais peut être saturé en calcul. (Tâche 5)
3. `created_at` flottant, négatif, ou plus de 900 s dans le futur doit être rejeté ; un relais ne doit pas stocker des événements datés de 2050. (Tâche 5)
4. Les hashtags doivent être normalisés (NFKC puis minuscules) : `#Été` et `#été` sont le même hashtag, sinon la page d'un hashtag est éclatée. (Tâche 9)
5. Un message de relais malformé (`["EVENT"]` sans sous-identifiant, JSON non tableau, type inconnu) doit produire une erreur typée et jamais une exception non attrapée. (Tâche 7)

---

### Tâche 1 : squelette du monorepo et CI

**Files:**
- Create: `package.json`, `bunfig.toml`, `tsconfig.base.json`, `.gitignore`, `.editorconfig`, `LICENSE` (AGPL-3.0), `.github/workflows/ci.yml`
- Create: `packages/protocol/package.json`, `packages/protocol/tsconfig.json`, `packages/protocol/LICENSE` (MIT), `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/smoke.test.ts`
- Modify: `README.md`
- Modify (formatage seul, commit séparé, étape 4) : `docs/**/*.md`

**Interfaces:**
- Produces: script racine `bun run verify` (= `bun fmt --check && bun check && bun test`) ; paquet `@bclt/protocol` importable par les futurs espaces de travail.

- [ ] **Step 1: Écrire le test de fumée**

```ts
// packages/protocol/test/smoke.test.ts
import { test, expect } from "bun:test";
import { PROTOCOL_VERSION } from "../src/index";

test("protocol package exposes its version", () => {
  expect(PROTOCOL_VERSION).toBe("v0");
});
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `bun test packages/protocol`
Expected: FAIL, module `../src/index` introuvable.

- [ ] **Step 3: Créer la racine**

`package.json` racine : `"name": "bclt"`, `"private": true`, `"workspaces": ["packages/*", "apps/*"]`, scripts `fmt: "bun fmt"`, `lint: "bun lint --type-aware"`, `verify: "bun fmt --check && bun check && bun test"` (le lint rejoint `verify` à la tâche 10, voir ci-dessous). Typage par `bun check`, formatage par `bun fmt`. Une seule dépendance de dev, à la racine : `"devDependencies": { "@types/bun": "1.4.4" }` (version exacte, celle de Bun). Elle est nécessaire : vérifié avec Bun 1.4.4, sans `@types/bun` installé, `bun check` ne résout ni `bun:test` ni `Bun`, que `types` soit présent ou non. Si `bun check` réclame aussi `typescript`, l'ajouter en version exacte et le noter dans le README.

`tsconfig.base.json` : `strict`, `noUncheckedIndexedAccess`, `noUnusedLocals`, `noUnusedParameters`, `module: "ESNext"`, `moduleResolution: "bundler"`, `target: "ES2022"`, `types: ["bun"]` (fourni par `@types/bun`), `resolveJsonModule: true` (les tests importent `spec/vectors/*.json`), `noEmit`.

`bunfig.toml` : section `[fmt]` avec `print-width = 100` (2 espaces, guillemets doubles et points-virgules sont les défauts), et section `[lint]` avec `typeAware = true`, prête pour `bun lint` (présent en canary, absent de la 1.4.4 stable ; la configuration est inerte tant que la commande n'existe pas).

`.gitignore` : `node_modules`, `dist`, `.expo`, `*.log`, `.env*`, `.DS_Store`.

`LICENSE` racine : texte AGPL-3.0, avec `README.md` précisant que `packages/protocol` et `packages/core` sont sous MIT.

- [ ] **Step 4: Formater l'existant dans un commit séparé**

`bun fmt --check` vérifie aussi le Markdown : sans cette étape, `verify` échouerait sur `docs/**/*.md` et `README.md`, qui existent déjà. Pas d'exclusion dans `bunfig.toml`. Une fois `bunfig.toml` créé (étape 3), formater le dépôt existant et le committer seul, avant le commit de squelette :

```bash
bun fmt
git add -u
git commit -m "chore: format existing docs"
```

`git add -u` n'ajoute que les fichiers déjà suivis, donc pas les fichiers de l'étape 3.

- [ ] **Step 5: Créer le paquet `@bclt/protocol`**

`packages/protocol/package.json` : `"name": "@bclt/protocol"`, `"version": "0.0.1"`, `"license": "MIT"`, `"type": "module"`, `"exports": { ".": "./src/index.ts" }`, dépendances exactes `@noble/ed25519@2.2.3`, `@noble/hashes@1.8.0`, `@scure/base@1.2.6`. `tsconfig.json` étend la base, `include: ["src", "test"]`.

`src/index.ts` : `export const PROTOCOL_VERSION = "v0" as const;`

- [ ] **Step 6: Installer et vérifier**

Run: `bun install && bun fmt && bun run verify`
Expected: les trois commandes passent, 1 test PASS.

- [ ] **Step 7: CI**

`.github/workflows/ci.yml` : déclenché sur `push` et `pull_request`, un job Ubuntu avec `oven-sh/setup-bun@v2` (version `1.4.4`), puis `bun install --frozen-lockfile` et `bun run verify`.

- [ ] **Step 8: README**

Remplacer la section "Statut" du README par : structure du dépôt (`spec/`, `packages/`, `apps/`, `deploy/`, `docs/`), prérequis (Bun 1.4), et les trois commandes.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold bun monorepo, protocol package and CI"
```

---

### Tâche 2 : spec formelle du protocole v0 et vecteurs de test

**Files:**
- Create: `spec/README.md`, `spec/protocol-v0.md`, `spec/vectors/keys.json`, `spec/vectors/events.json`

**Interfaces:**
- Produces: le document normatif que les tâches 3 à 9 implémentent, et les vecteurs que la tâche 3 vérifie. Toutes les valeurs ci-dessous sont normatives.

- [ ] **Step 1: Écrire `spec/protocol-v0.md`**

Sections, chacune avec exactement ces règles :

**1. Encodages.** Octets en hex minuscules. Clé publique 32 octets (64 hex), identifiant 32 octets (64 hex), signature 64 octets (128 hex). Forme lisible d'une clé publique : bech32 (BIP-173, limite 90 caractères), préfixe `bclt`, données = clé publique en mots de 5 bits. Discriminant : les 4 premiers caractères après `bclt1`.

**2. Événement.** Objet JSON à exactement sept clés : `id`, `pubkey`, `created_at`, `kind`, `tags`, `content`, `sig`. Toute clé supplémentaire rend l'événement invalide. `created_at` entier ≥ 0 en secondes Unix. `kind` entier ≥ 0. `tags` tableau de tableaux de chaînes, chaque étiquette ayant au moins un élément (son nom). `content` chaîne.

**3. Forme canonique et identifiant.** Forme canonique = sérialisation JSON sans espaces du tableau `[0, pubkey, created_at, kind, tags, content]`, avec les règles d'échappement de `JSON.stringify` d'ECMAScript : seuls `"`, `\` et les caractères de contrôle U+0000 à U+001F sont échappés (`\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t`, sinon `\u00XX`), tout autre caractère est émis tel quel en UTF-8. `id` = SHA-256 des octets UTF-8 de la forme canonique.

**4. Signature.** `sig` = Ed25519 (RFC 8032, pure, sans préhachage) sur les 32 octets de `id`. Vérification : recalculer `id`, puis vérifier `sig` avec `pubkey`.

**5. Limites.** Sérialisation JSON de l'événement ≤ 65 536 octets, vérifiée avant toute autre validation. `tags` ≤ 200 étiquettes ; chaque élément d'étiquette ≤ 2 048 caractères. `created_at` ≤ maintenant + 900 s pour être accepté par un relais.

**6. Types (kinds).** Tableau des kinds 0 à 7, 100 et 101 avec, pour chacun, le contenu, les étiquettes obligatoires et interdites, et la règle de remplacement :

| kind | nom | content | étiquettes | remplaçable |
|---|---|---|---|---|
| 0 | profile | objet JSON `{ name, about?, picture?, relays? }` : `name` 1 à 30 caractères, `about` 0 à 150, `picture` 64 hex optionnel, `relays` 0 à 10 URL `wss://` ; sérialisation ≤ 8 192 octets | aucune obligatoire | oui, (pubkey, kind) |
| 1 | post | légende 0 à 2 200 caractères | 1 à 5 `["media", sha256, alt, url...]` avec `alt` 0 à 500 caractères et 1 à 10 URL `https://` ; 0 à 30 `["t", hashtag]` minuscules ; 0 à 20 `["p", pubkey]` | non |
| 2 | comment | 1 à 2 200 caractères | exactement une `["e", postId]` et une `["p", postAuthor]` | non |
| 3 | like | vide | exactement une `["e", postId]` et une `["p", postAuthor]` | non |
| 4 | follows | vide | 0 à 5 000 `["p", pubkey]`, sans doublon | oui, (pubkey, kind) |
| 5 | delete | vide | 1 à 500 `["e", eventId]` | non |
| 6 | hidden-comments | vide | exactement une `["d", postId]`, 0 à 500 `["e", commentId]` | oui, (pubkey, kind, d) |
| 7 | backup | base64, 1 à 16 384 caractères | exactement une `["d", index]` avec `index` 64 hex | oui, (pubkey, kind, d) |
| 100 | auth | vide | exactement une `["challenge", c]` (32 à 128 caractères) et une `["relay", url]` ; jamais stocké ; valide si `created_at` à ± 600 s de maintenant | non |
| 101 | media-auth | vide | exactement une `["x", sha256]` et une `["action", "upload" \| "delete"]` ; jamais stocké ; ± 600 s | non |

Règles sémantiques : un kind 5 n'efface que des événements du même `pubkey` ; un kind 6 n'est pris en compte que si son auteur est l'auteur du post `d` ; le kind 3 est unique par (pubkey, postId), un doublon est ignoré.

**7. Texte.** Hashtag : `#` suivi d'un ou plusieurs caractères `\p{L}`, `\p{N}` ou `_`, 1 à 100 caractères après le `#` ; valeur normalisée = NFKC puis minuscules ; l'app duplique chaque hashtag normalisé en étiquette `t`, sans doublon. Mention : `@` suivi d'une clé bech32 `bclt1…` ; l'app duplique chaque mention en étiquette `p` (hex), sans doublon.

**8. Relais.** WebSocket, sous-protocole `bclt.v0` négocié au handshake (`Sec-WebSocket-Protocol`), connexion refusée sinon. Messages client : `["PUBLISH", event]`, `["REQ", subId, filter, ...filters]`, `["CLOSE", subId]`, `["AUTH", event]`. Messages relais : `["EVENT", subId, event]`, `["EOSE", subId]`, `["OK", eventId, boolean, message]`, `["AUTH", challenge]`, `["NOTICE", message]`. `subId` : 1 à 64 caractères. Un `REQ` porte 1 à 10 filtres. Messages `OK` refusés : `message` commence par un préfixe parmi `invalid:`, `auth-required:`, `rate-limited:`, `blocked:`, `duplicate:`, `error:`.

**9. Filtre.** Objet à clés optionnelles : `ids` (hex 64, ≤ 500), `authors` (hex 64, ≤ 500), `kinds` (entiers, ≤ 20), `since`, `until` (entiers, inclusifs), `limit` (1 à 500), `search` (chaîne 1 à 100, cherche les profils par `name`, insensible à la casse et aux accents), `#e`, `#p`, `#t`, `#d` (listes de ≤ 500 valeurs). Un événement correspond si toutes les clés présentes correspondent ; dans une liste, une valeur suffit ; correspondance exacte, pas de préfixe.

**10. Serveur de médias.** `PUT /upload` avec en-tête `Authorization: bclt <base64(event kind 101)>`, corps binaire dont le SHA-256 doit égaler `x` ; réponse `201 { "sha256", "url", "size" }`. `GET /{sha256}`, `HEAD /{sha256}`, `DELETE /{sha256}` (même en-tête, action `delete`). Types v1 : `image/jpeg`, `image/webp`.

**11. Erreurs.** Tout événement invalide est ignoré par un client ; un relais répond `OK false` avec un préfixe de la section 8.

- [ ] **Step 2: Écrire `spec/vectors/keys.json`**

```json
{
  "description": "Test key, derived as sha256('bclt-test-key-1'). Never use outside tests.",
  "secretKey": "6903e913131897bebb2ad105600c13206fad4e94ca0001a00a0ceb6000386b68",
  "publicKey": "1419125c7a25bcfbde6009ab0ec434b35ce410285a48a6c96f8a3b72fde876c6",
  "bech32": "bclt1zsv3yhr6yk70hhnqpx4sa3p5kdwwgypgtfy2djt03gah9l0gwmrqyudghp",
  "discriminator": "zsv3"
}
```

- [ ] **Step 3: Écrire `spec/vectors/events.json`**

Un tableau de quatre objets `{ name, event, canonical }`, tous signés par la clé ci-dessus. Les `tags` et `content` sont ceux des formes canoniques suivantes, à reproduire exactement :

| name | kind | created_at | id | sig |
|---|---|---|---|---|
| profile | 0 | 1764000000 | `609186311e935e39e9c0ddc76055932c4df7a5a4ea8df75e686004b00abb524a` | `ddbce2dc2a1a51465465a5d67518a447a9e92e5a2f5067e790c8ed17f8dfbfc7319c5f4139257535a96a04c6cf0a0f94237f42846327eb4785fea39a0b465402` |
| post | 1 | 1764000100 | `54cc85297e373f57b406dfda9929334347c377fbb1c75ef7cb39983c18032e1b` | `35c504d9d05aa82b6a6edcd88e353dd8df63ac17f4bde376fca7c0fdb7fc1e945509594496853fbba46f99e2163edcafea867d48bac048955edc521583291103` |
| like | 3 | 1764000300 | `09e47039e741047220a71a451098a680e7c9530d0188af2a75fda812c5a19235` | `cfddb62ecfa58ca85278b9bfad2540b82cf8d6fc04a3168ca33923fdbf229633f4f3f9fa482f8643e93b4dc15e5eb267f698fa14b638870f513a626474f78e0d` |
| auth | 100 | 1764000200 | `44a9c7b69483458b4baadc388c0ee8c7f259583f53b2c99024804260195c20e1` | `81b33ec8650f6bcaa8f8cdb8debde178bd4e6b8e96c86eeddaaf81fb59a9f6d2bab3f5e404629699b8c53f4a0dc65f795e85ff28bd051a463288d97565b0cd02` |

Formes canoniques (`PK` = la clé publique hex, `B64` = 64 fois `b`, `NPUB` = la clé bech32) :

- profile : `[0,"PK",1764000000,0,[],"{\"name\":\"léa\",\"about\":\"salut \\\"tout\\\" le monde\",\"picture\":\"aaaa…(64 a)\",\"relays\":[\"wss://relay.bclt.is\"]}"]`
- post : `[0,"PK",1764000100,1,[["media","B64","Un chat","https://media.bclt.is/B64"],["t","chat"],["p","PK"]],"Mon #Chat et @NPUB à Paris"]`
- like : `[0,"PK",1764000300,3,[["e","54cc85297e373f57b406dfda9929334347c377fbb1c75ef7cb39983c18032e1b"],["p","PK"]],""]`
- auth : `[0,"PK",1764000200,100,[["challenge","cccccccccccccccccccccccccccccccc"],["relay","wss://relay.bclt.is"]],""]`

- [ ] **Step 4: Écrire `spec/README.md`**

Trois paragraphes : rôle de `spec/` (source de vérité, toute implémentation doit passer `vectors/`), comment proposer une évolution (un fichier `spec/changes/NNNN-titre.md`, jamais de modification silencieuse d'un kind existant), et le lien vers la spec de conception.

- [ ] **Step 5: Commit**

```bash
git add spec
git commit -m "docs: add protocol v0 specification and test vectors"
```

---

### Tâche 3 : clés, forme canonique, identifiant et signature

**Files:**
- Create: `packages/protocol/src/types.ts`, `packages/protocol/src/canonical.ts`, `packages/protocol/src/keys.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/canonical.test.ts`, `packages/protocol/test/keys.test.ts`, `packages/protocol/test/vectors.test.ts`

**Interfaces:**
- Produces, dans `types.ts` :
  - `type Hex = string`
  - `interface UnsignedEvent { pubkey: Hex; created_at: number; kind: number; tags: string[][]; content: string }`
  - `interface Event extends UnsignedEvent { id: Hex; sig: Hex }`
  - `type EventTemplate = Omit<UnsignedEvent, "pubkey">`
- Produces, dans `canonical.ts` : `canonicalize(e: UnsignedEvent): string`, `computeId(e: UnsignedEvent): Hex`
- Produces, dans `keys.ts` : `generateSecretKey(): Uint8Array` (32 octets aléatoires), `getPublicKey(sk: Uint8Array): Hex`, `signEvent(t: EventTemplate, sk: Uint8Array): Event`, `verifyEvent(e: Event): boolean` (recalcule l'id et vérifie la signature ; `false` si l'id ne correspond pas)

- [ ] **Step 1: Tests de forme canonique**

```ts
// test/canonical.test.ts
import { test, expect } from "bun:test";
import { canonicalize, computeId } from "../src/canonical";
import keys from "../../../spec/vectors/keys.json";

const PK = keys.publicKey;

test("canonical form escapes quotes and keeps unicode raw", () => {
  const c = canonicalize({ pubkey: PK, created_at: 1, kind: 1, tags: [], content: 'a"b\\c\nd é' });
  expect(c).toBe(`[0,"${PK}",1,1,[],"a\\"b\\\\c\\nd é"]`);
});

test("computeId matches the profile vector", () => {
  const content = JSON.stringify({ name: "léa", about: 'salut "tout" le monde', picture: "a".repeat(64), relays: ["wss://relay.bclt.is"] });
  expect(computeId({ pubkey: PK, created_at: 1764000000, kind: 0, tags: [], content }))
    .toBe("609186311e935e39e9c0ddc76055932c4df7a5a4ea8df75e686004b00abb524a");
});
```

- [ ] **Step 2: Tests de clés et de signature**

```ts
// test/keys.test.ts
import { test, expect } from "bun:test";
import { hexToBytes } from "@noble/hashes/utils";
import { generateSecretKey, getPublicKey, signEvent, verifyEvent } from "../src/keys";
import keys from "../../../spec/vectors/keys.json";

const SK = hexToBytes(keys.secretKey);

test("getPublicKey matches the vector", () => {
  expect(getPublicKey(SK)).toBe(keys.publicKey);
});

test("generateSecretKey returns 32 random bytes", () => {
  const a = generateSecretKey(); const b = generateSecretKey();
  expect(a.length).toBe(32);
  expect(a).not.toEqual(b);
});

test("signEvent produces the like vector exactly (deterministic Ed25519)", () => {
  const e = signEvent({ created_at: 1764000300, kind: 3, tags: [["e", "54cc85297e373f57b406dfda9929334347c377fbb1c75ef7cb39983c18032e1b"], ["p", keys.publicKey]], content: "" }, SK);
  expect(e.id).toBe("09e47039e741047220a71a451098a680e7c9530d0188af2a75fda812c5a19235");
  expect(e.sig).toBe("cfddb62ecfa58ca85278b9bfad2540b82cf8d6fc04a3168ca33923fdbf229633f4f3f9fa482f8643e93b4dc15e5eb267f698fa14b638870f513a626474f78e0d");
  expect(verifyEvent(e)).toBe(true);
});

test("verifyEvent rejects a tampered content, id or sig", () => {
  const e = signEvent({ created_at: 1, kind: 1, tags: [], content: "x" }, SK);
  expect(verifyEvent({ ...e, content: "y" })).toBe(false);
  expect(verifyEvent({ ...e, id: "0".repeat(64) })).toBe(false);
  expect(verifyEvent({ ...e, sig: "0".repeat(128) })).toBe(false);
});
```

- [ ] **Step 3: Test des vecteurs**

```ts
// test/vectors.test.ts
import { test, expect } from "bun:test";
import { canonicalize, computeId } from "../src/canonical";
import { verifyEvent } from "../src/keys";
import vectors from "../../../spec/vectors/events.json";

for (const v of vectors) {
  test(`vector ${v.name}: canonical form, id and signature`, () => {
    expect(canonicalize(v.event)).toBe(v.canonical);
    expect(computeId(v.event)).toBe(v.event.id);
    expect(verifyEvent(v.event)).toBe(true);
  });
}
```

- [ ] **Step 4: Lancer, vérifier l'échec**

Run: `bun test packages/protocol`
Expected: FAIL, modules `../src/canonical` et `../src/keys` introuvables.

- [ ] **Step 5: Implémenter `types.ts`, `canonical.ts`, `keys.ts`**

`canonicalize` utilise `JSON.stringify([0, e.pubkey, e.created_at, e.kind, e.tags, e.content])`. `computeId` = `sha256` de `@noble/hashes/sha256` sur les octets UTF-8, hex via `bytesToHex`. `keys.ts` configure `ed.etc.sha512Sync` avec `@noble/hashes/sha512` pour utiliser l'API synchrone de `@noble/ed25519`, signe les 32 octets de l'id avec `ed.sign`, vérifie avec `ed.verify` dans un `try/catch` renvoyant `false`. Exporter tout depuis `index.ts`.

- [ ] **Step 6: Lancer, vérifier le succès**

Run: `bun run verify`
Expected: tous PASS, aucune erreur de typage ni de lint.

- [ ] **Step 7: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): canonical form, event id, ed25519 signing"
```

---

### Tâche 4 : encodage lisible des clés

**Files:**
- Create: `packages/protocol/src/encoding.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/encoding.test.ts`

**Interfaces:**
- Produces : `encodePubkey(hex: Hex): string` (bech32, préfixe `bclt`), `decodePubkey(s: string): Hex | null` (`null` si préfixe, checksum ou longueur invalides), `discriminator(hex: Hex): string` (4 caractères), `isHex(s: unknown, bytes: number): s is Hex` (minuscules uniquement, longueur `bytes * 2`).

- [ ] **Step 1: Tests**

```ts
import { test, expect } from "bun:test";
import { encodePubkey, decodePubkey, discriminator, isHex } from "../src/encoding";
import keys from "../../../spec/vectors/keys.json";

test("encodePubkey matches the vector", () => expect(encodePubkey(keys.publicKey)).toBe(keys.bech32));
test("decodePubkey round-trips", () => expect(decodePubkey(keys.bech32)).toBe(keys.publicKey));
test("decodePubkey rejects wrong prefix, bad checksum and garbage", () => {
  expect(decodePubkey(keys.bech32.replace("bclt1", "npub1"))).toBeNull();
  expect(decodePubkey(keys.bech32.slice(0, -1) + "q")).toBeNull();
  expect(decodePubkey("hello")).toBeNull();
});
test("discriminator is the 4 chars after the prefix", () => expect(discriminator(keys.publicKey)).toBe("zsv3"));
test("isHex accepts lowercase of the right length only", () => {
  expect(isHex(keys.publicKey, 32)).toBe(true);
  expect(isHex(keys.publicKey.toUpperCase(), 32)).toBe(false);
  expect(isHex(keys.publicKey.slice(1), 32)).toBe(false);
  expect(isHex(42, 32)).toBe(false);
});
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol/test/encoding.test.ts` — Expected: FAIL.

- [ ] **Step 3: Implémenter `encoding.ts`** avec `bech32` de `@scure/base` (limite 90), `isHex` par expression régulière `/^[0-9a-f]+$/`.

- [ ] **Step 4: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): bech32 pubkey encoding and hex helpers"
```

---

### Tâche 5 : validation structurelle et par kind

**Files:**
- Create: `packages/protocol/src/constants.ts`, `packages/protocol/src/validate.ts`, `packages/protocol/src/kinds/profile.ts`, `packages/protocol/src/kinds/post.ts`, `packages/protocol/src/kinds/interactions.ts` (kinds 2, 3, 4, 5, 6), `packages/protocol/src/kinds/backup.ts`, `packages/protocol/src/kinds/auth.ts` (kinds 100, 101)
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/validate.test.ts`, `packages/protocol/test/kinds.test.ts`

**Interfaces:**
- Produces, dans `constants.ts` : `Kind` (objet `as const` : `Profile: 0, Post: 1, Comment: 2, Like: 3, Follows: 4, Delete: 5, HiddenComments: 6, Backup: 7, Auth: 100, MediaAuth: 101`), `LIMITS` (objet `as const` reprenant toutes les valeurs de la section 5 et 6 de la spec : `MAX_EVENT_BYTES: 65536`, `MAX_TAGS: 200`, `MAX_TAG_ITEM_CHARS: 2048`, `MAX_FUTURE_SECONDS: 900`, `AUTH_WINDOW_SECONDS: 600`, `MAX_CAPTION_CHARS: 2200`, `MAX_MEDIA_PER_POST: 5`, `MAX_URLS_PER_MEDIA: 10`, `MAX_ALT_CHARS: 500`, `MAX_HASHTAGS: 30`, `MAX_MENTIONS: 20`, `MAX_FOLLOWS: 5000`, `MAX_DELETE_IDS: 500`, `MAX_HIDDEN_COMMENTS: 500`, `MAX_BACKUP_CHARS: 16384`, `MAX_PROFILE_BYTES: 8192`, `MAX_NAME_CHARS: 30`, `MAX_ABOUT_CHARS: 150`, `MAX_PROFILE_RELAYS: 10`).
- Produces, dans `validate.ts` :
  - `type ValidationError = { code: "too-large" | "malformed" | "bad-hex" | "bad-time" | "bad-kind" | "bad-tags" | "bad-content" | "bad-signature"; message: string }`
  - `type Validation = { ok: true; event: Event } | { ok: false; error: ValidationError }`
  - `validateEvent(input: unknown, opts?: { now?: number; verifySignature?: boolean }): Validation` — ordre : taille sérialisée, forme, hex, temps, kind connu, règles du kind, signature (si `verifySignature !== false`).
  - `validateStructure(input: unknown): Validation` (tout sauf règles du kind et signature) utilisé par les relais pour rejeter tôt.
- Produces, dans `kinds/*.ts` : une fonction par kind `validateKindN(e: Event): ValidationError | null`, et `parseProfile(content: string): Profile | null` avec `interface Profile { name: string; about?: string; picture?: Hex; relays?: string[] }`.

- [ ] **Step 1: Tests structurels**

```ts
// test/validate.test.ts
import { test, expect } from "bun:test";
import { hexToBytes } from "@noble/hashes/utils";
import { signEvent } from "../src/keys";
import { validateEvent, validateStructure } from "../src/validate";
import keys from "../../../spec/vectors/keys.json";
import vectors from "../../../spec/vectors/events.json";

const SK = hexToBytes(keys.secretKey);
const NOW = 1764000400;
const post = vectors.find((v) => v.name === "post")!.event;

test("accepts every vector", () => {
  for (const v of vectors) expect(validateEvent(v.event, { now: NOW }).ok).toBe(true);
});
test("rejects an extra field", () => {
  const r = validateEvent({ ...post, foo: 1 }, { now: NOW });
  expect(r).toMatchObject({ ok: false, error: { code: "malformed" } });
});
test("rejects uppercase hex", () => {
  expect(validateEvent({ ...post, pubkey: post.pubkey.toUpperCase() }, { now: NOW })).toMatchObject({ ok: false, error: { code: "bad-hex" } });
});
test("rejects oversized events before checking the signature", () => {
  const big = { ...post, content: "x".repeat(70000), sig: "0".repeat(128) };
  expect(validateEvent(big, { now: NOW })).toMatchObject({ ok: false, error: { code: "too-large" } });
});
test("rejects float, negative and far-future created_at", () => {
  for (const t of [1.5, -1, NOW + 901]) {
    expect(validateEvent({ ...post, created_at: t }, { now: NOW })).toMatchObject({ ok: false, error: { code: "bad-time" } });
  }
  expect(validateEvent(post, { now: 1764000100 - 100000 }).ok).toBe(false); // le vecteur est 100000 s dans le futur
});
test("rejects non-string tag items and empty tags", () => {
  expect(validateStructure({ ...post, tags: [["t", 1]] })).toMatchObject({ ok: false, error: { code: "bad-tags" } });
  expect(validateStructure({ ...post, tags: [[]] })).toMatchObject({ ok: false, error: { code: "bad-tags" } });
});
test("rejects unknown kinds and bad signatures", () => {
  const unknown = signEvent({ created_at: NOW, kind: 42, tags: [], content: "" }, SK);
  expect(validateEvent(unknown, { now: NOW })).toMatchObject({ ok: false, error: { code: "bad-kind" } });
  expect(validateEvent({ ...post, sig: "0".repeat(128) }, { now: NOW })).toMatchObject({ ok: false, error: { code: "bad-signature" } });
});
test("verifySignature: false skips only the signature step", () => {
  expect(validateEvent({ ...post, sig: "0".repeat(128) }, { now: NOW, verifySignature: false }).ok).toBe(true);
});
```

- [ ] **Step 2: Tests par kind**

```ts
// test/kinds.test.ts
import { test, expect } from "bun:test";
import { hexToBytes } from "@noble/hashes/utils";
import { signEvent } from "../src/keys";
import { validateEvent } from "../src/validate";
import { parseProfile } from "../src/kinds/profile";
import { Kind } from "../src/constants";
import keys from "../../../spec/vectors/keys.json";

const SK = hexToBytes(keys.secretKey);
const PK = keys.publicKey;
const NOW = 1764000400;
const H = "b".repeat(64);
const sign = (kind: number, tags: string[][], content = "") => signEvent({ created_at: NOW, kind, tags, content }, SK);
const code = (e: unknown) => { const r = validateEvent(e, { now: NOW }); return r.ok ? "ok" : r.error.code; };

test("profile: valid, name required and bounded, bad json", () => {
  expect(code(sign(Kind.Profile, [], JSON.stringify({ name: "léa" })))).toBe("ok");
  expect(code(sign(Kind.Profile, [], JSON.stringify({ about: "x" })))).toBe("bad-content");
  expect(code(sign(Kind.Profile, [], JSON.stringify({ name: "x".repeat(31) })))).toBe("bad-content");
  expect(code(sign(Kind.Profile, [], "{not json"))).toBe("bad-content");
  expect(parseProfile(JSON.stringify({ name: "léa", relays: ["wss://r"] }))).toEqual({ name: "léa", relays: ["wss://r"] });
  expect(parseProfile(JSON.stringify({ name: "léa", relays: ["http://r"] }))).toBeNull();
});
test("post: media count 1..5, alt bound, https urls, caption bound", () => {
  const media = (n: number) => Array.from({ length: n }, () => ["media", H, "", "https://m/" + H]);
  expect(code(sign(Kind.Post, media(1), "ok"))).toBe("ok");
  expect(code(sign(Kind.Post, media(0), "ok"))).toBe("bad-tags");
  expect(code(sign(Kind.Post, media(6), "ok"))).toBe("bad-tags");
  expect(code(sign(Kind.Post, [["media", H, "x".repeat(501), "https://m/x"]]))).toBe("bad-tags");
  expect(code(sign(Kind.Post, [["media", H, "", "http://m/x"]]))).toBe("bad-tags");
  expect(code(sign(Kind.Post, media(1), "x".repeat(2201)))).toBe("bad-content");
  expect(code(sign(Kind.Post, [...media(1), ["t", "Chat"]]))).toBe("bad-tags"); // hashtags must be lowercase
});
test("comment and like: exactly one e and one p", () => {
  expect(code(sign(Kind.Comment, [["e", H], ["p", PK]], "salut"))).toBe("ok");
  expect(code(sign(Kind.Comment, [["e", H], ["p", PK]], ""))).toBe("bad-content");
  expect(code(sign(Kind.Comment, [["e", H]], "salut"))).toBe("bad-tags");
  expect(code(sign(Kind.Like, [["e", H], ["p", PK]]))).toBe("ok");
  expect(code(sign(Kind.Like, [["e", H], ["e", H], ["p", PK]]))).toBe("bad-tags");
  expect(code(sign(Kind.Like, [["e", H], ["p", PK]], "x"))).toBe("bad-content");
});
test("follows: unique p tags, bounded", () => {
  expect(code(sign(Kind.Follows, [["p", PK]]))).toBe("ok");
  expect(code(sign(Kind.Follows, []))).toBe("ok");
  expect(code(sign(Kind.Follows, [["p", PK], ["p", PK]]))).toBe("bad-tags");
});
test("delete: at least one e", () => {
  expect(code(sign(Kind.Delete, [["e", H]]))).toBe("ok");
  expect(code(sign(Kind.Delete, []))).toBe("bad-tags");
});
test("hidden-comments: exactly one d", () => {
  expect(code(sign(Kind.HiddenComments, [["d", H], ["e", H]]))).toBe("ok");
  expect(code(sign(Kind.HiddenComments, [["e", H]]))).toBe("bad-tags");
});
test("backup: one d index of 64 hex, base64 content bounded", () => {
  expect(code(sign(Kind.Backup, [["d", H]], "aGVsbG8="))).toBe("ok");
  expect(code(sign(Kind.Backup, [["d", "zz"]], "aGVsbG8="))).toBe("bad-tags");
  expect(code(sign(Kind.Backup, [["d", H]], "not base64!"))).toBe("bad-content");
  expect(code(sign(Kind.Backup, [["d", H]], "A".repeat(16388)))).toBe("bad-content");
});
test("auth and media-auth: required tags and time window", () => {
  expect(code(sign(Kind.Auth, [["challenge", "c".repeat(32)], ["relay", "wss://r"]]))).toBe("ok");
  expect(code(sign(Kind.Auth, [["challenge", "short"], ["relay", "wss://r"]]))).toBe("bad-tags");
  expect(code(signEvent({ created_at: NOW - 601, kind: Kind.Auth, tags: [["challenge", "c".repeat(32)], ["relay", "wss://r"]], content: "" }, SK))).toBe("bad-time");
  expect(code(sign(Kind.MediaAuth, [["x", H], ["action", "upload"]]))).toBe("ok");
  expect(code(sign(Kind.MediaAuth, [["x", H], ["action", "rename"]]))).toBe("bad-tags");
});
```

- [ ] **Step 3: Lancer, vérifier l'échec** — Run: `bun test packages/protocol` — Expected: FAIL, modules introuvables.

- [ ] **Step 4: Implémenter `constants.ts`, `validate.ts`, `kinds/*.ts`**

`validateEvent` applique les étapes dans l'ordre de l'interface, chaque étape retournant tôt. La taille se mesure par `new TextEncoder().encode(JSON.stringify(input)).length` et se vérifie avant tout accès aux champs. Les règles par kind sont une table `Record<number, (e: Event) => ValidationError | null>` dans `validate.ts`, remplie par les modules `kinds/*`. Base64 : expression régulière `/^[A-Za-z0-9+/]+={0,2}$/` et longueur multiple de 4.

- [ ] **Step 5: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): structural and per-kind event validation"
```

---

### Tâche 6 : événements remplaçables et filtres

**Files:**
- Create: `packages/protocol/src/replaceable.ts`, `packages/protocol/src/filter.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/replaceable.test.ts`, `packages/protocol/test/filter.test.ts`

**Interfaces:**
- Produces, dans `replaceable.ts` : `isReplaceable(kind: number): boolean` (0, 4, 6, 7), `isParameterized(kind: number): boolean` (6, 7), `isEphemeral(kind: number): boolean` (100, 101, jamais stockés), `replaceableKey(e: Event): string | null` (`"${pubkey}:${kind}"` ou `"${pubkey}:${kind}:${d}"`, `null` si non remplaçable), `supersedes(a: Event, b: Event): boolean` (même clé et `a.created_at > b.created_at`, ou égalité de temps et `a.id < b.id`).
- Produces, dans `filter.ts` : `interface Filter { ids?: Hex[]; authors?: Hex[]; kinds?: number[]; since?: number; until?: number; limit?: number; search?: string; "#e"?: string[]; "#p"?: string[]; "#t"?: string[]; "#d"?: string[] }`, `validateFilter(input: unknown): Filter | null` (bornes de la section 9 de la spec ; toute clé inconnue rend le filtre invalide), `matchFilter(e: Event, f: Filter): boolean` (ignore `limit` et `search`), `matchFilters(e: Event, fs: Filter[]): boolean` (OU), `normalizeSearch(s: string): string` (NFKD, suppression des diacritiques, minuscules, espaces réduits) utilisée par les relais pour `search`.

- [ ] **Step 1: Tests**

```ts
// test/replaceable.test.ts
import { test, expect } from "bun:test";
import { isReplaceable, isEphemeral, replaceableKey, supersedes } from "../src/replaceable";
import vectors from "../../../spec/vectors/events.json";
const profile = vectors.find((v) => v.name === "profile")!.event;
const post = vectors.find((v) => v.name === "post")!.event;
const auth = vectors.find((v) => v.name === "auth")!.event;

test("kinds 0,4,6,7 are replaceable; 100,101 ephemeral", () => {
  expect([0, 4, 6, 7].every(isReplaceable)).toBe(true);
  expect([1, 2, 3, 5].some(isReplaceable)).toBe(false);
  expect(isEphemeral(auth.kind)).toBe(true);
});
test("replaceableKey includes d for parameterized kinds", () => {
  expect(replaceableKey(profile)).toBe(`${profile.pubkey}:0`);
  expect(replaceableKey({ ...profile, kind: 6, tags: [["d", "x"]] })).toBe(`${profile.pubkey}:6:x`);
  expect(replaceableKey(post)).toBeNull();
});
test("supersedes: newer wins, ties broken by lower id", () => {
  expect(supersedes({ ...profile, created_at: 2 }, { ...profile, created_at: 1 })).toBe(true);
  expect(supersedes({ ...profile, id: "a".repeat(64) }, { ...profile, id: "b".repeat(64) })).toBe(true);
  expect(supersedes(post, profile)).toBe(false);
});
```

```ts
// test/filter.test.ts
import { test, expect } from "bun:test";
import { validateFilter, matchFilter, matchFilters, normalizeSearch } from "../src/filter";
import vectors from "../../../spec/vectors/events.json";
const post = vectors.find((v) => v.name === "post")!.event;

test("matchFilter: each present key must match, lists are OR", () => {
  expect(matchFilter(post, { kinds: [1] })).toBe(true);
  expect(matchFilter(post, { kinds: [0, 1], authors: [post.pubkey] })).toBe(true);
  expect(matchFilter(post, { kinds: [0] })).toBe(false);
  expect(matchFilter(post, { "#t": ["chat", "chien"] })).toBe(true);
  expect(matchFilter(post, { "#t": ["chien"] })).toBe(false);
  expect(matchFilter(post, { since: 1764000100, until: 1764000100 })).toBe(true);
  expect(matchFilter(post, { since: 1764000101 })).toBe(false);
  expect(matchFilter(post, { ids: [post.id] })).toBe(true);
  expect(matchFilter(post, { ids: [post.id.slice(0, 10)] })).toBe(false); // pas de préfixe
});
test("matchFilters is OR across filters", () => {
  expect(matchFilters(post, [{ kinds: [0] }, { kinds: [1] }])).toBe(true);
  expect(matchFilters(post, [])).toBe(false);
});
test("validateFilter enforces bounds and types", () => {
  expect(validateFilter({ kinds: [1], limit: 500 })).toEqual({ kinds: [1], limit: 500 });
  expect(validateFilter({ limit: 501 })).toBeNull();
  expect(validateFilter({ ids: ["xyz"] })).toBeNull();
  expect(validateFilter({ authors: Array(501).fill("a".repeat(64)) })).toBeNull();
  expect(validateFilter({ unknown: 1 })).toBeNull();
  expect(validateFilter("nope")).toBeNull();
});
test("normalizeSearch strips accents and case", () => {
  expect(normalizeSearch("  Léa  Été ")).toBe("lea ete");
});
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol` — Expected: FAIL.

- [ ] **Step 3: Implémenter `replaceable.ts` et `filter.ts`**, exporter depuis `index.ts`.

- [ ] **Step 4: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): replaceable event keys and subscription filters"
```

---

### Tâche 7 : messages de relais

**Files:**
- Create: `packages/protocol/src/messages.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/messages.test.ts`

**Interfaces:**
- Produces : `WS_SUBPROTOCOL = "bclt.v0"`,
  - `type ClientMessage = { type: "PUBLISH"; event: Event } | { type: "REQ"; subId: string; filters: Filter[] } | { type: "CLOSE"; subId: string } | { type: "AUTH"; event: Event }`
  - `type RelayMessage = { type: "EVENT"; subId: string; event: Event } | { type: "EOSE"; subId: string } | { type: "OK"; eventId: Hex; accepted: boolean; message: string } | { type: "AUTH"; challenge: string } | { type: "NOTICE"; message: string }`
  - `type OkPrefix = "invalid" | "auth-required" | "rate-limited" | "blocked" | "duplicate" | "error"`
  - `parseClientMessage(raw: string): { ok: true; message: ClientMessage } | { ok: false; error: string }` — valide la structure des événements avec `validateStructure` (pas la signature, c'est au relais de le faire après), les filtres avec `validateFilter`, `subId` 1 à 64 caractères, 1 à 10 filtres.
  - `parseRelayMessage(raw: string)` : même forme de résultat.
  - `serializeClientMessage(m: ClientMessage): string`, `serializeRelayMessage(m: RelayMessage): string`, `okMessage(prefix: OkPrefix, detail: string): string` (`"${prefix}: ${detail}"`).

- [ ] **Step 1: Tests**

```ts
import { test, expect } from "bun:test";
import { parseClientMessage, parseRelayMessage, serializeClientMessage, serializeRelayMessage, okMessage, WS_SUBPROTOCOL } from "../src/messages";
import type { ClientMessage, RelayMessage } from "../src/messages";
import vectors from "../../../spec/vectors/events.json";
const post = vectors.find((v) => v.name === "post")!.event;

test("subprotocol constant", () => expect(WS_SUBPROTOCOL).toBe("bclt.v0"));
test("client messages round-trip", () => {
  // Pas de `as const` : il rendrait `filters` et `kinds` readonly, que `serializeClientMessage` refuse.
  const messages: ClientMessage[] = [
    { type: "PUBLISH", event: post },
    { type: "REQ", subId: "feed", filters: [{ kinds: [1], limit: 50 }] },
    { type: "CLOSE", subId: "feed" },
  ];
  for (const m of messages) {
    const r = parseClientMessage(serializeClientMessage(m));
    expect(r).toEqual({ ok: true, message: m });
  }
});
test("relay messages round-trip", () => {
  const messages: RelayMessage[] = [
    { type: "EVENT", subId: "feed", event: post },
    { type: "EOSE", subId: "feed" },
    { type: "OK", eventId: post.id, accepted: false, message: okMessage("rate-limited", "slow down") },
    { type: "AUTH", challenge: "c".repeat(32) },
    { type: "NOTICE", message: "bye" },
  ];
  for (const m of messages) {
    expect(parseRelayMessage(serializeRelayMessage(m))).toEqual({ ok: true, message: m });
  }
});
test("malformed input never throws", () => {
  for (const raw of ["", "nope", "{}", "[]", '["EVENT"]', '["WHAT", 1]', '["REQ", "", {}]', '["REQ", "s"]', '["REQ", "s", "notafilter"]', '["PUBLISH", {"id": 1}]', '["REQ", "s", ' + Array(11).fill("{}").join(",") + "]"]) {
    expect(parseClientMessage(raw).ok).toBe(false);
    expect(parseRelayMessage(raw).ok).toBe(false);
  }
});
test("okMessage format", () => expect(okMessage("invalid", "bad sig")).toBe("invalid: bad sig"));
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol/test/messages.test.ts` — Expected: FAIL.

- [ ] **Step 3: Implémenter `messages.ts`** : `JSON.parse` dans un `try/catch`, puis dispatch sur `raw[0]`.

- [ ] **Step 4: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): relay message parsing and serialization"
```

---

### Tâche 8 : aides d'authentification relais et médias

**Files:**
- Create: `packages/protocol/src/auth.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/auth.test.ts`

**Interfaces:**
- Produces :
  - `createAuthEvent(challenge: string, relayUrl: string, sk: Uint8Array, now?: number): Event`
  - `verifyAuthEvent(e: Event, expected: { challenge: string; relayUrl: string }, now?: number): { ok: true; pubkey: Hex } | { ok: false; reason: string }` — passe par `validateEvent`, puis compare `challenge` et `relayUrl` (comparaison exacte après suppression du `/` final).
  - `createMediaAuthEvent(sha256: Hex, action: "upload" | "delete", sk: Uint8Array, now?: number): Event`
  - `encodeMediaAuthHeader(e: Event): string` (`"bclt " + base64(JSON.stringify(e))`)
  - `verifyMediaAuthHeader(header: string | null, expected: { sha256: Hex; action: "upload" | "delete" }, now?: number): { ok: true; pubkey: Hex } | { ok: false; reason: string }`

- [ ] **Step 1: Tests**

```ts
import { test, expect } from "bun:test";
import { hexToBytes } from "@noble/hashes/utils";
import { createAuthEvent, verifyAuthEvent, createMediaAuthEvent, encodeMediaAuthHeader, verifyMediaAuthHeader } from "../src/auth";
import keys from "../../../spec/vectors/keys.json";
const SK = hexToBytes(keys.secretKey);
const NOW = 1764000400;
const C = "c".repeat(32);

test("auth round-trip and mismatches", () => {
  const e = createAuthEvent(C, "wss://relay.bclt.is", SK, NOW);
  expect(verifyAuthEvent(e, { challenge: C, relayUrl: "wss://relay.bclt.is/" }, NOW)).toEqual({ ok: true, pubkey: keys.publicKey });
  expect(verifyAuthEvent(e, { challenge: "d".repeat(32), relayUrl: "wss://relay.bclt.is" }, NOW).ok).toBe(false);
  expect(verifyAuthEvent(e, { challenge: C, relayUrl: "wss://other" }, NOW).ok).toBe(false);
  expect(verifyAuthEvent(e, { challenge: C, relayUrl: "wss://relay.bclt.is" }, NOW + 601).ok).toBe(false);
});
test("media auth header round-trip and mismatches", () => {
  const h = encodeMediaAuthHeader(createMediaAuthEvent("b".repeat(64), "upload", SK, NOW));
  expect(h.startsWith("bclt ")).toBe(true);
  expect(verifyMediaAuthHeader(h, { sha256: "b".repeat(64), action: "upload" }, NOW)).toEqual({ ok: true, pubkey: keys.publicKey });
  expect(verifyMediaAuthHeader(h, { sha256: "c".repeat(64), action: "upload" }, NOW).ok).toBe(false);
  expect(verifyMediaAuthHeader(h, { sha256: "b".repeat(64), action: "delete" }, NOW).ok).toBe(false);
  expect(verifyMediaAuthHeader(null, { sha256: "b".repeat(64), action: "upload" }, NOW).ok).toBe(false);
  expect(verifyMediaAuthHeader("Bearer xyz", { sha256: "b".repeat(64), action: "upload" }, NOW).ok).toBe(false);
});
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol/test/auth.test.ts` — Expected: FAIL.

- [ ] **Step 3: Implémenter `auth.ts`** en s'appuyant sur `signEvent` et `validateEvent` ; base64 via `btoa`/`atob` sur une chaîne UTF-8 encodée (ou `@scure/base` `base64`).

- [ ] **Step 4: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): relay auth and media auth helpers"
```

---

### Tâche 9 : texte et constructeurs d'événements

**Files:**
- Create: `packages/protocol/src/text.ts`, `packages/protocol/src/builders.ts`
- Modify: `packages/protocol/src/index.ts`
- Test: `packages/protocol/test/text.test.ts`, `packages/protocol/test/builders.test.ts`

**Interfaces:**
- Produces, dans `text.ts` : `normalizeHashtag(raw: string): string` (NFKC, minuscules, sans `#`), `extractHashtags(text: string): string[]` (normalisés, uniques, ordre d'apparition, ≤ 100 caractères chacun), `extractMentions(text: string): Hex[]` (clés hex uniques, mentions invalides ignorées).
- Produces, dans `builders.ts` : `interface MediaRef { sha256: Hex; alt: string; urls: string[] }`, `mediaTag(ref: MediaRef): string[]`, `parseMediaTags(tags: string[][]): MediaRef[]`, et des gabarits non signés (`EventTemplate`) : `buildProfile(p: Profile, now: number)`, `buildPost(caption: string, media: MediaRef[], now: number)` (extrait hashtags et mentions ; étiquettes dans l'ordre `media`, puis `t`, puis `p`, dans l'ordre d'apparition), `buildComment(postId: Hex, postAuthor: Hex, text: string, now: number)`, `buildLike(postId: Hex, postAuthor: Hex, now: number)`, `buildFollows(pubkeys: Hex[], now: number)`, `buildDelete(ids: Hex[], now: number)`, `buildHiddenComments(postId: Hex, commentIds: Hex[], now: number)`, `buildBackup(index: Hex, ciphertextBase64: string, now: number)`.

- [ ] **Step 1: Tests**

```ts
// test/text.test.ts
import { test, expect } from "bun:test";
import { extractHashtags, extractMentions, normalizeHashtag } from "../src/text";
import keys from "../../../spec/vectors/keys.json";

test("hashtags are NFKC-normalized, lowercased, unique, in order", () => {
  expect(extractHashtags("Mon #Chat et mon #chat, #Été #été #été #_ok_ #123")).toEqual(["chat", "été", "_ok_", "123"]);
  expect(extractHashtags("pas de # seul, ni #")).toEqual([]);
  expect(extractHashtags("#" + "a".repeat(101))).toEqual([]);
  expect(normalizeHashtag("#Été")).toBe("été");
});
test("mentions resolve bech32 keys and ignore junk", () => {
  expect(extractMentions(`salut @${keys.bech32} et @${keys.bech32} et @lea et @bclt1nope`)).toEqual([keys.publicKey]);
});
```

```ts
// test/builders.test.ts
import { test, expect } from "bun:test";
import { hexToBytes } from "@noble/hashes/utils";
import { signEvent } from "../src/keys";
import { validateEvent } from "../src/validate";
import { buildPost, buildComment, buildLike, buildFollows, mediaTag, parseMediaTags } from "../src/builders";
import keys from "../../../spec/vectors/keys.json";
import vectors from "../../../spec/vectors/events.json";
const SK = hexToBytes(keys.secretKey);
const NOW = 1764000400;
const H = "b".repeat(64);

test("buildPost reproduces the post vector template", () => {
  const v = vectors.find((v) => v.name === "post")!.event;
  const t = buildPost(v.content, [{ sha256: H, alt: "Un chat", urls: ["https://media.bclt.is/" + H] }], 1764000100);
  expect(signEvent(t, SK)).toEqual(v);
});
test("media tags round-trip", () => {
  const ref = { sha256: H, alt: "", urls: ["https://a/x", "https://b/x"] };
  expect(mediaTag(ref)).toEqual(["media", H, "", "https://a/x", "https://b/x"]);
  expect(parseMediaTags([mediaTag(ref), ["t", "x"]])).toEqual([ref]);
});
test("every builder yields a valid event", () => {
  const templates = [
    buildComment(H, keys.publicKey, "bravo", NOW),
    buildLike(H, keys.publicKey, NOW),
    buildFollows([keys.publicKey, keys.publicKey], NOW), // dédoublonne
  ];
  for (const t of templates) expect(validateEvent(signEvent(t, SK), { now: NOW }).ok).toBe(true);
  expect(buildFollows([keys.publicKey, keys.publicKey], NOW).tags).toHaveLength(1);
});
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol` — Expected: FAIL.

- [ ] **Step 3: Implémenter `text.ts` et `builders.ts`**. Hashtags : expression régulière `/#([\p{L}\p{N}_]{1,100})(?![\p{L}\p{N}_])/gu`. Mentions : `/@(bclt1[02-9ac-hj-np-z]{6,})/g` puis `decodePubkey`. Exporter depuis `index.ts`.

- [ ] **Step 4: Lancer, vérifier le succès** — Run: `bun run verify` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol
git commit -m "feat(protocol): hashtag and mention extraction, event builders"
```

---

### Tâche 10 : clôture du paquet et de la phase

**Files:**
- Create: `packages/protocol/README.md`, `spec/vectors/generate.ts`
- Modify: `packages/protocol/src/index.ts`, `docs/superpowers/specs/2026-11-11-bclt-design.md` (section 2.4, un paragraphe)

**Interfaces:**
- Produces : l'API publique complète de `@bclt/protocol`, documentée, et un générateur de vecteurs qui doit reproduire `spec/vectors/events.json` à l'identique.

- [ ] **Step 1: Test du générateur**

```ts
// packages/protocol/test/generate.test.ts
import { test, expect } from "bun:test";
import { generateVectors } from "../../../spec/vectors/generate";
import vectors from "../../../spec/vectors/events.json";
test("generate.ts reproduces the committed vectors byte for byte", () => {
  expect(generateVectors()).toEqual(vectors);
});
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Run: `bun test packages/protocol/test/generate.test.ts` — Expected: FAIL.

- [ ] **Step 3: Écrire `spec/vectors/generate.ts`** : importe `signEvent` par chemin relatif (`../../packages/protocol/src/index`, car `spec/` n'est pas un espace de travail), exporte `generateVectors()` qui construit les quatre événements à partir de `keys.json`, et, lancé directement (`bun spec/vectors/generate.ts`), réécrit `events.json`.

- [ ] **Step 4: Vérifier l'API publique** : `index.ts` exporte tout ce que les tâches 3 à 9 déclarent dans leurs blocs Interfaces, rien d'autre. `packages/protocol/README.md` : trois exemples (créer une identité et signer une publication, valider un événement reçu, parser un message de relais) et le lien vers `spec/protocol-v0.md`.

- [ ] **Step 5: Mettre à jour la spec de conception** : dans la section 2.4, remplacer la phrase sur le premier message portant la version par la négociation du sous-protocole `bclt.v0` au handshake WebSocket, et ajouter kinds 100 et 101 au tableau 2.3 avec la mention "jamais stockés".

- [ ] **Step 6: Activer `bun lint` si une version stable le contient** : vérifier sur https://bun.com/blog si une version stable postérieure à 1.4.4 inclut `bun lint`. Si oui : mettre cette version dans `oven-sh/setup-bun` de la CI, mettre à jour Bun localement (`bun upgrade`), ajouter `bun lint --type-aware --max-warnings 0 &&` en tête du script `verify`, corriger ce qu'il remonte, et noter la version minimale de Bun dans le README. Si non : laisser `verify` tel quel et ouvrir une tâche dans le plan 2.

- [ ] **Step 7: Vérification finale de la phase** — Run: `bun install --frozen-lockfile && bun fmt && bun run verify` — Expected: tout PASS en local.

- [ ] **Step 8: Commit, push de la branche et PR**

```bash
git add -A
git commit -m "docs: protocol package readme, vector generator, spec alignment"
git push -u origin HEAD
gh pr create --base main --fill
```

`HEAD` est la branche Linear du ticket ; ajouter l'identifiant du ticket (ex. `BCL-12`) au titre de la PR. Vérifier ensuite que la CI GitHub est verte sur la PR (`gh pr checks`). La PR est mergée après CI verte, jamais poussée directement sur `main`.
