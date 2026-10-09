# Référence de l'API : commandes

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Commandes](../commands.md). Pour les administrateurs :
[Commandes d'administration](../administration.md).

## `context:RegisterCommand(spec)`

Déclare une commande et renvoie un handle avec `Release()` et `IsActive()`. La commande est
retirée quand le package est désactivé.

### Champs d'une commande

| Champ | Type | Description |
| --- | --- | --- |
| `name` | chaîne | `[a-z][a-z0-9_-]*`, 32 caractères au plus |
| `aliases` | tableau de chaînes, facultatif | Mêmes règles que `name` |
| `description` | chaîne, facultatif | Affichée par `foundation help` |
| `description_key` | chaîne, facultatif | Clé des catalogues du package, traduite à la place de `description` |
| `arguments` | tableau, facultatif | [Déclarations d'arguments](#déclarations-darguments) |
| `run` | fonction, facultatif | `run(sender, args, info)` ; `info.path` est le tableau des noms de commandes, `info.line` le texte tapé |
| `subcommands` | tableau, facultatif | Champs des sous-commandes, imbriquées sur 8 niveaux au plus |
| `senders` | tableau, facultatif | `"player"`, `"console"` ou les deux (par défaut) |
| `cooldown` | entier, facultatif | Millisecondes entre deux utilisations par le même joueur |
| `audit` | booléen, facultatif | Enregistre chaque utilisation dans le journal d'audit |

Une commande a besoin de `run` ou de `subcommands`. Les noms et alias sont uniques parmi les
sous-commandes d'une commande. `foundation` ne peut pas servir de nom ni d'alias de premier
niveau.

Noms : chaque nom et alias de premier niveau est accessible tel quel et sous la forme
`<package>:<nom>`. En cas de conflit entre packages, les noms passent d'abord, dans l'ordre
d'enregistrement, puis les alias encore libres ; le package qui perd un nom reçoit un
avertissement. Un nom libéré revient au package suivant qui l'a déclaré.

Lève `invalid_argument` pour un mauvais type de champ, `invalid_value` pour un nom mal formé, un
champ inconnu, un nom réservé ou en double, des arguments, une liste d'expéditeurs ou un délai
invalides, `invalid_state` si un nom est déjà utilisé par une autre commande du même package ou
si le contexte n'est plus actif.

### Déclarations d'arguments

| Champ | Type | Description |
| --- | --- | --- |
| `name` | chaîne | `[a-z][a-z0-9_]*`, unique dans la commande ; clé de la valeur dans `args` |
| `type` | chaîne, facultatif | `"string"` (par défaut), `"greedy"`, `"integer"`, `"number"`, `"boolean"`, `"enum"` ou un type de package `"<package>:<nom>"` |
| `optional` | booléen, facultatif | La valeur vaut `nil` si l'argument manque |
| `default` | quelconque, facultatif | Valeur si l'argument manque ; rend l'argument facultatif. Vérifiée pour les types intégrés |
| `description` | chaîne, facultatif | Description de l'argument |
| `min`, `max` | nombre, facultatif | Bornes pour `integer` et `number` ; longueur en caractères pour `string` et `greedy` |
| `values` | tableau de chaînes en minuscules | Mots acceptés par `enum` (obligatoire pour lui) |

Les arguments obligatoires viennent d'abord ; un argument `greedy` vient en dernier. Un type de
package doit être enregistré au moment où la commande est déclarée.

Règles de lecture :

- les mots sont séparés par des espaces ; `"..."` forme un seul argument, où `\"` et `\\` sont
  des échappements ;
- `greedy` prend la fin de la ligne telle que tapée, espaces finaux retirés ;
- `integer` accepte un signe facultatif et des chiffres ; `number` la notation décimale sans
  exposant ;
- `boolean` accepte `true`, `yes`, `on`, `false`, `no`, `off`, sans tenir compte de la casse ;
- `enum` compare sans tenir compte de la casse et donne la valeur déclarée.

Une saisie incorrecte n'exécute pas la commande : l'expéditeur reçoit le problème et la ligne
d'usage.

## `context:RegisterArgumentType(name, definition)`

Enregistre un type d'argument utilisable par tous les packages sous la forme
`<package>:<nom>`, et renvoie ce nom. Le type est retiré quand le package est désactivé ; les
commandes qui l'utilisent répondent alors `<argument> could not be read`.

| Champ de `definition` | Type | Description |
| --- | --- | --- |
| `parse` | fonction | `parse(text)` renvoie la valeur, ou `nil` et un message pour l'expéditeur |
| `suggest` | fonction, facultatif | `suggest(prefix)` renvoie un tableau de complétions |

Les deux fonctions s'exécutent sous protection : une erreur est journalisée, et l'expéditeur
reçoit `<argument> could not be read`.

Lève `invalid_argument` pour un mauvais type, `invalid_value` pour un nom mal formé ou un champ
inconnu, `invalid_state` si le type existe déjà ou si le contexte n'est plus actif.

## Expéditeur

| Méthode | Description |
| --- | --- |
| `sender:Reply(text)` | Envoie `text` dans le chat du joueur ou dans la console |
| `sender:GetKind()` | `"player"` ou `"console"` |
| `sender:IsPlayer()`, `sender:IsConsole()` | |
| `sender:GetId()` | Identifiant de compte du joueur, `"console"` pour la console |
| `sender:GetName()` | Nom de compte du joueur, `"console"` pour la console |
| `sender:GetPlayer()` | Objet joueur, `nil` pour la console |
| `sender:GetLocale()` | `nil` dans cette version (langue du serveur) |

## Exécution

Pour chaque commande tapée : lecture, type d'expéditeur (`senders`), délai,
`foundation:command` (annulable), `run`, audit, `foundation:command_completed`. Voir
[Événements de Foundation](events.md#événements-de-foundation).

- Une erreur levée par `run` est journalisée sous la forme `command callback of <package>
  failed` ; l'expéditeur reçoit un message générique. Le délai ne démarre pas.
- Les délais sont gardés en mémoire par commande et par joueur, et ne s'appliquent jamais à la
  console.
- Les entrées d'audit utilisent l'action `<package>:command/<noms séparés par />`, l'auteur
  `console` ou `player:<id>`, le résultat et `details.arguments` (valeurs non scalaires sous
  forme de texte ; champs aux noms de secrets masqués).

## Erreurs

Une saisie incorrecte est signalée à l'expéditeur par une valeur d'erreur de code
`command_usage` (catégorie `user`) ; son `message` est traduit.
