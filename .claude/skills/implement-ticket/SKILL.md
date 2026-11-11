---
name: implement-ticket
description: Use when the user asks to implement a Linear ticket end to end from its identifier (e.g. "/implement-ticket BCL-12", "implémente BCL-12", "prends le ticket BCL-12"), or when a Paradev session is started with arguments "<ticket-id> --worker".
---

# implement-ticket

Mène un ticket Linear du backlog jusqu'au merge. Une session « lanceur » évalue le ticket, puis démarre une session Paradev dédiée avec le modèle et l'effort adaptés. Cette session « worker » implémente, vérifie, fait relire, ouvre la PR et la suit jusqu'au merge.

**Arguments :** `<ticket-id>` (ex. `BCL-12`) lance le mode lanceur. `<ticket-id> --worker` lance le mode worker. Sans identifiant, demander lequel.

**Outils :** Linear passe par le serveur MCP `linear-bclt` (`get_issue`, `list_comments`, `list_issues`, `save_issue`, `save_comment`). S'ils sont différés, les charger avec ToolSearch (`select:mcp__linear-bclt__get_issue,...`). GitHub passe par `gh`, Paradev par `superset`. `<skill>` désigne `.claude/skills/implement-ticket` à la racine du dépôt.

**Langue :** commentaires Linear et description de PR en français. Titres de commits et de PR en anglais (`feat:`, `fix:`, `test:`, `chore:`, `docs:`), chaque commit terminé par la ligne `Co-Authored-By:` que l'environnement fournit.

**Priorité des règles :** les règles de statut de ce skill priment sur les consignes du ticket. « Fermer le ticket » veut toujours dire « Done après merge ». Les cases à cocher de la description se cochent après le merge, avec `save_issue` et `patch`.

**Statut résolu :** un ticket est résolu si son `statusType` est `completed`, `canceled` ou `duplicate`. Un ticket est **prêt** si aucun de ses bloqueurs, ni ceux de ses ancêtres, n'est non résolu.

---

## Mode lanceur (étapes 1 à 5)

### 0. Prérequis

`git fetch origin main && git cat-file -e origin/main:.claude/skills/implement-ticket/SKILL.md`. S'il échoue, s'arrêter : la session worker part de `main` et n'aurait pas le skill. Il faut d'abord merger le skill sur `main`.

### 1. Trouver le ticket

1. `get_issue <ID>` avec `includeRelations: true`, puis `list_comments <ID>`.
2. Sous-tickets **du ticket** : `list_issues` avec `parentId: <ID>`.
3. Ancêtres : remonter `parentId` jusqu'à la racine, avec `get_issue` et `includeRelations: true` à chaque niveau.
4. Pour chaque `blockedBy` du ticket et de chaque ancêtre : `get_issue` du bloqueur et lire son `statusType`. La relation seule ne donne pas le statut.

Arrêter et expliquer à l'utilisateur, sans rien lancer, si :

| Condition                                                                                      | Message                                                                                                         |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Label `Epic`                                                                                   | Un epic ne s'implémente pas : proposer ses tickets prêts.                                                       |
| Le ticket a des sous-tickets non résolus                                                       | C'est un conteneur : lister ses sous-tickets prêts.                                                             |
| Un bloqueur du ticket ou d'un ancêtre n'est pas résolu                                         | Lister les bloqueurs avec leur statut. Continuer seulement si l'utilisateur le demande explicitement.           |
| Le ticket est résolu                                                                           | Rien à faire.                                                                                                   |
| Une PR existe pour la branche (`gh pr list --head <gitBranchName> --state all`)                | PR mergée : passer le ticket en Done (étape 15). Sinon, proposer de reprendre la session existante.             |
| Un workspace existe sur la branche (`superset workspaces list --local --json`, champ `branch`) | Proposer de reprendre ce workspace (`superset agents create --workspace <id> --local …`) au lieu d'en créer un. |

### 2. Lire le ticket et trancher les questions ouvertes

Lire toute la description, y compris « Agent notes », les commentaires, le ticket parent, et les sections de plan ou de spec citées (les ouvrir dans le dépôt). En tirer : le périmètre, les critères d'acceptation, les points de vigilance, les questions ouvertes.

Poser à l'utilisateur maintenant toute question ouverte qui bloque l'implémentation : décision produit, de protocole ou d'outillage, ou mot « trancher » dans le ticket. Écrire ses réponses dans un commentaire Linear « Décisions », **avant** l'étape 4 : le worker les lit dans les commentaires.

### 3. Choisir modèle et effort

Prendre la première ligne qui s'applique :

| Le ticket…                                                                                                                             | Modèle              | Effort   |
| -------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | -------- |
| touche crypto, signature, parsing d'entrées réseau, authentification, ou porte un point de revue sécurité                              | `claude-opus-5-5`   | `high`   |
| laisse des décisions de conception non tranchées après l'étape 2, ou couvre plusieurs modules                                          | `claude-opus-5-5`   | `high`   |
| produit du code bien spécifié (tests fournis par le ticket ou le plan) dans un seul module, ou de la config qui se vérifie par un test | `claude-sonnet-5-5` | `medium` |
| modifie de la doc ou un plan, avec un raisonnement technique (types, exemples de code, cohérence avec la spec)                         | `claude-sonnet-5-5` | `medium` |
| modifie du texte ou de la config sans logique ni test (licence, README, recopie)                                                       | `claude-haiku-5-5`  | `low`    |

Ajustement : monter l'effort d'un cran si le ticket est Urgent ou High, ou a plus de cinq critères d'acceptation. Plafond : `high`. `xhigh`, `max` et `claude-fable-5-1` seulement si l'utilisateur le demande.

Écrire la justification en une phrase.

### 4. Démarrer la session Paradev

Écrire le prompt dans un fichier temporaire avec un heredoc entre apostrophes : la justification peut contenir des backticks ou des `$`.

```bash
PROMPT_FILE=$(mktemp)
cat >"$PROMPT_FILE" <<'EOF'
Invoque le skill implement-ticket avec les arguments `<ID> --worker`.
Ticket : <url>
Modèle choisi : <modèle>/<effort>, parce que <justification>.
EOF
PROJECT_ID=$(superset projects list --json | jq -r --arg p "$SUPERSET_ROOT_PATH" '.[] | select(.path==$p) | .id')
superset workspaces create --local --project "$PROJECT_ID" \
  --branch "<gitBranchName du ticket>" --skip-branch-prefix --base-branch main \
  --name "<ID> <titre court>" --tag implement-ticket \
  --agent claude --model <modèle> --effort <effort> \
  --prompt "$(cat "$PROMPT_FILE")" --json
```

Si `$SUPERSET_ROOT_PATH` est vide, prendre le dossier parent de `git rev-parse --path-format=absolute --git-common-dir`. Garder le nom de branche Linear tel quel : c'est lui qui relie la PR au ticket.

Si la commande échoue, s'arrêter et rapporter l'erreur, sans toucher au ticket. Si la sortie ne donne pas de terminal, le trouver avec `superset terminals list --workspace <id> --local --json`.

### 5. Passer le ticket en In Progress

`save_issue` avec `state: "In Progress"`, puis `save_comment` : session démarrée, modèle et effort, justification, branche, ID du workspace.

Rendre la main à l'utilisateur avec l'ID du workspace et la commande de suivi : `superset terminals attach --workspace <id> --terminal <id> --local`. Le lanceur s'arrête là.

---

## Mode worker (étapes 6 à 15)

### Reprise

Avant tout, voir où on en est avec `gh pr list --head "$(git branch --show-current)" --state all --json number,state` :

- PR mergée : étape 15.
- PR ouverte : étape 12.
- Pas de PR, mais `git rev-list --count origin/main..HEAD` > 0 : étape 7.
- Sinon : étape 6.

### 6. Implémenter

1. Relire le ticket, ses commentaires (dont « Décisions ») et son parent. Ce sont les seules sources du périmètre ; une décision en commentaire remplace un « à trancher » de la description.
2. Mettre la branche à jour : `git fetch origin main && git merge --ff-only origin/main`.
3. Si le ticket produit ou modifie du code : **REQUIRED SUB-SKILL :** superpowers:test-driven-development. Les tests du ticket ou du plan d'abord, les voir échouer, puis le code.
4. Si le ticket ne modifie que de la doc ou un plan : partir de la liste des points du ticket, et pour chaque point noter comment on vérifie qu'il est fait (relecture de la ligne, `grep`, exemple de code qui compile).
5. Rester dans le périmètre. Ce qui déborde (bug voisin, amélioration) devient un commentaire sur le ticket, pas du code.
6. Commits petits et fréquents.

### 7. Lancer les vérifications

Prendre les commandes du dépôt, dans cet ordre :

1. le script `verify` de `package.json` (`bun run verify`) ;
2. sinon, les scripts `fmt`, `check`, `lint`, `test` qui existent ;
3. sinon, ce que le ticket indique.

Avant `verify`, formater seulement si le dépôt configure le formatage (script `fmt` ou section `[fmt]` de `bunfig.toml`), et seulement les fichiers modifiés : `bun fmt --changed=origin/main`. Ne jamais reformater des fichiers hors du ticket.

Si aucune commande n'existe encore (ticket d'amorçage, ticket de doc), le noter pour la PR et lancer les vérifications de l'étape 6.4.

### 8. Corriger

En cas d'échec : **REQUIRED SUB-SKILL :** superpowers:systematic-debugging. Corriger la cause, jamais le symptôme : ne pas désactiver un test, ne pas assouplir une assertion, ne pas contourner un hook. Relancer l'étape 7.

Après trois tours sans succès : étape « Blocage ».

### 9. Faire relire

**REQUIRED SUB-SKILL :** superpowers:requesting-code-review.

Donner au relecteur :

- l'URL du ticket, ses critères d'acceptation et ses points de vigilance ;
- la plage `$(git merge-base origin/main HEAD)..HEAD`.

Ne pas lui donner son propre avis sur le code : il lit le diff sans a priori.

### 10. Trier les retours

**REQUIRED SUB-SKILL :** superpowers:receiving-code-review. Classer chaque retour :

- **corriger** : bug, critère d'acceptation non tenu, faille, test manquant sur un point de vigilance ;
- **reporter** : juste mais hors périmètre, à mettre en commentaire sur le ticket Linear ;
- **rejeter** : faux ou contraire au plan, avec la raison en une phrase.

Après des corrections, refaire les étapes 7 et 8. Si les corrections touchent la logique, faire une seconde relecture. Deux tours de relecture au plus. Garder la liste pour la PR.

### 11. Ouvrir la PR

Écrire le corps dans un fichier `mktemp`, hors du dépôt, dans cet ordre :

1. lien du ticket ;
2. ce qui change ;
3. critères d'acceptation cochés ;
4. vérifications lancées et leur résultat ;
5. revue : corrigé, reporté, rejeté avec raison ;
6. ligne d'attribution fournie par l'environnement.

```bash
git push -u origin HEAD
gh pr create --base main --title "<type>(<scope>): <résumé> (<ID>)" --body-file "$BODY_FILE"
```

Commenter le ticket avec le lien de la PR.

### 12. Surveiller la PR

```bash
bash <skill>/scripts/wait-pr.sh <numéro> ci
```

Le lancer en arrière-plan (`run_in_background`) et attendre la notification, sans boucle `sleep` au premier plan. Sans CI configurée, le script attend 5 minutes avant de conclure `no-checks` : ce n'est pas un blocage.

La dernière ligne commence par `RESULT=` :

| RESULT                              | Suite                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| `green`                             | Étape 14.                                                                      |
| `no-checks`                         | Aucune CI : le dire dans la PR, puis étape 14.                                 |
| `conflict`                          | Étape 13, conflits.                                                            |
| `ci-failed`                         | Étape 13, CI.                                                                  |
| `merged`                            | Étape 15.                                                                      |
| `closed`                            | Commenter le ticket, prévenir l'utilisateur, s'arrêter sans changer le statut. |
| `timeout` ou pas de ligne `RESULT=` | Relancer le script une fois ; la seconde fois, étape « Blocage ».              |

### 13. Corriger conflits et CI

- **Conflits :** `git fetch origin main && git merge origin/main`. Résoudre en gardant l'intention des deux côtés, relancer l'étape 7, `git push`. Pas de rebase ni de force-push.
- **CI :** `gh pr checks <numéro>`, puis `gh run view <run-id> --log-failed`. Si l'échec ne se reproduit pas en local, chercher d'abord la différence d'environnement (version de Bun, lockfile, variables), avant de toucher au code. Corriger avec superpowers:systematic-debugging, relancer l'étape 7, `git push`.

Puis retour à l'étape 12. Le compteur vaut pour toute la vie de la PR, étapes 12 à 15 comprises : au quatrième passage par l'étape 13, aller à l'étape « Blocage ».

### 14. Signaler que la PR est prête

PR sans conflit, et CI verte ou absente et signalée :

1. Commenter le ticket : « PR prête à merger » et le lien. Laisser le ticket en In Progress.
2. Prévenir l'utilisateur :
   ```bash
   superset notifications show "<ID> prêt à merger" --body "<url de la PR>" --sound
   ```
3. Ne pas merger soi-même.
4. Enchaîner sur l'étape 15 dans la même session.

### 15. Après le merge, passer le ticket en Done

```bash
bash <skill>/scripts/wait-pr.sh <numéro> merge 120 1440
```

Le lancer en arrière-plan, puis selon le résultat :

- `merged` : `save_issue` avec `state: "Done"`, cocher les cases de la description (`patch`), commentaire avec le SHA du merge.
- `conflict` ou `ci-failed` (la branche principale a bougé) : étape 13.
- `closed` : comme à l'étape 12.
- `timeout` : dire à l'utilisateur que relancer `/implement-ticket <ID>` après le merge passera le ticket en Done.

### Blocage

1. Commenter le ticket : ce qui bloque, ce qui a été essayé, ce qu'il faut (décision, accès, correction du plan).
2. Laisser le statut tel quel.
3. Prévenir l'utilisateur avec `superset notifications show`, puis s'arrêter.

## Erreurs courantes

| Erreur                                                                             | Conséquence                                                                           |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Lancer le worker sur un conteneur, ou sur un sous-ticket dont le parent est bloqué | Travail sur une base incomplète. L'étape 1 doit filtrer avant toute création.         |
| Laisser le worker trancher une question ouverte                                    | Décision non validée dans la PR. La poser à l'étape 2 et l'écrire dans « Décisions ». |
| Faire relire avec le résumé de l'implémenteur                                      | Relecture biaisée. Le relecteur part du ticket et du diff.                            |
| Lancer `bun fmt` sur tout le dépôt                                                 | Diff hors périmètre. N'utiliser que `--changed`.                                      |
| Passer le ticket en Done quand la PR est prête                                     | Faux signal. Done veut dire mergé.                                                    |
