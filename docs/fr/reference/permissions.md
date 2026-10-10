# Référence de l'API : permissions et opérateurs

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Permissions](../permissions.md). Pour les administrateurs :
[Commandes d'administration](../administration.md#opérateurs).

## Permissions et sujets

Une permission se compose de deux segments ou plus séparés par des points, en `a`-`z`, `0`-`9`,
`_` et `-`, 128 caractères au plus. Les permissions sont comparées en minuscules. Un sujet est
un expéditeur de commande ou un identifiant de compte (chaîne non vide) ; les expéditeurs
console ont toutes les permissions.

## `context:DeclarePermission(node, definition)`

Déclare une permission appartenant au package et renvoie la permission en minuscules. La
déclaration est retirée quand le package est désactivé.

| Champ de `definition` | Type | Description |
| --- | --- | --- |
| `description` | chaîne, facultatif | Montrée aux administrateurs |
| `default` | chaîne, facultatif | `"everyone"`, `"nobody"`, `"operators"` (par défaut) ou `"non_operators"` |
| `deprecated` | `true` ou chaîne, facultatif | Marque la permission comme obsolète ; la chaîne indique quoi utiliser à la place |

Lève `invalid_argument` pour un mauvais type, `invalid_value` pour une permission mal formée,
qui ne commence pas par `<package>.`, un champ ou une valeur par défaut inconnus,
`invalid_state` si la permission est déjà déclarée ou si le contexte n'est plus actif.

## `context:AttachPermission(subject, node, value, options)`

Accorde (`value = true`) ou retire (`false`) une permission pour un compte. Renvoie un handle
avec `Release()` et `IsActive()` ; l'attachement est retiré avec le handle ou quand le package
est désactivé.

| Option | Type | Description |
| --- | --- | --- |
| `duration` | entier | Millisecondes après lesquelles l'attachement ne s'applique plus |

Quand des attachements de plusieurs packages s'appliquent au même compte et à la même
permission, `false` l'emporte.

Lève `invalid_argument` pour un mauvais type, `invalid_value` pour un sujet console, une
permission mal formée, une option inconnue ou une durée nulle ou négative, `invalid_state` si
le contexte n'est plus actif.

## `Foundation.Permissions.Has(subject, node)`

Indique si le sujet a la permission. Ordre de décision : console, attachements, fournisseur,
valeur par défaut de la déclaration (`operators` pour une permission non déclarée). La première
vérification d'une permission obsolète journalise un avertissement.

Lève `invalid_argument` pour un sujet invalide ou une permission qui n'est pas une chaîne,
`invalid_value` pour une permission mal formée.

## `Foundation.Permissions.Explain(subject, node)`

Renvoie `{ allowed = <booléen>, source = <chaîne>, package = <chaîne ou nil> }`. `source` vaut
`"console"`, `"attachment"`, `"provider"` ou `"default"` ; `package` désigne le package à
l'origine d'un attachement ou le fournisseur. Mêmes erreurs que `Has`.

## `Foundation.Permissions.Get(node)`

Renvoie `{ node, owner, description, default, deprecated }` pour une permission déclarée, ou
`nil`.

## `Foundation.Permissions.List(package)`

Renvoie les déclarations, triées par permission, éventuellement seulement celles de `package`.

## Contrat de fournisseur

Service `foundation:permission_provider`, version de contrat `1.x`, fourni avec
[`context:ProvideService`](services.md#contextprovideservicename-version-implementation-options).

| Méthode | Description |
| --- | --- |
| `provider:Check(account, node)` | Renvoie `true`, `false`, ou `nil` quand il n'a pas de réponse |

`node` est en minuscules. Le meilleur fournisseur (priorité la plus élevée) est interrogé à
chaque vérification qu'aucun attachement n'a tranchée. Une erreur levée par `Check` est
journalisée sous la forme `permission_provider callback of <package> failed` ; une réponse autre
que `true`, `false` ou `nil` est journalisée une fois ; dans les deux cas, elle compte comme une
absence de réponse. Chaque changement de fournisseur est journalisé et enregistré dans le
journal d'audit sous `foundation:permissions/provider`.

## `Foundation.Operators.IsOperator(subject)`

Indique si le compte est opérateur. Les expéditeurs console comptent comme opérateurs. Lève
`invalid_argument` pour un sujet invalide.

## `Foundation.Operators.List()`

Renvoie `{ id, name, added_by, added_at }` pour chaque opérateur, trié par identifiant de compte.
`added_by` vaut `"console"` ou `"player:<identifiant de compte>"` ; `added_at` est un horodatage
Unix en secondes.

## Événements

| Événement | Champs |
| --- | --- |
| `foundation:operator_added` | `account`, `name` (ou `nil`), `by` |
| `foundation:operator_removed` | `account`, `name` (ou `nil`), `by` |

## Permissions de Foundation

| Permission | Défaut | Autorise |
| --- | --- | --- |
| `foundation.command.version` | tout le monde | `foundation version` |
| `foundation.command.help` | tout le monde | `foundation help` |
| `foundation.command.packages` | opérateurs | `foundation packages` |
| `foundation.command.services` | opérateurs | `foundation services` |
| `foundation.command.reload-config` | opérateurs | `foundation reload-config` |
| `foundation.command.op` | opérateurs | `foundation op` |
| `foundation.command.permissions` | opérateurs | `foundation permissions` |
