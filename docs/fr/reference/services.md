# Référence de l'API : services et capacités

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Services et capacités](../services.md).

## Versions

Un fournisseur déclare `"<majeure>.<mineure>"`. Un consommateur demande `"<majeure>"` (même
majeure, toute mineure), `"<majeure>.<mineure>"` (même majeure, mineure au moins égale à celle
demandée) ou `nil` (toute version).

## `context:ProvideService(name, version, implementation, options)`

Ajoute un fournisseur et renvoie un handle avec `Release()` et `IsActive()`. Le fournisseur est
retiré quand le package est désactivé.

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne | Clé du service ; sans espace de noms, celui du package |
| `version` | chaîne | `"<majeure>.<mineure>"` |
| `implementation` | table | Champs et méthodes du service |
| `options` | table, facultatif | Voir ci-dessous |

| Option | Type | Description |
| --- | --- | --- |
| `priority` | entier | De -1000000 à 1000000. Par défaut 0. La plus élevée est choisie |
| `replace` | booléen | Remplace le fournisseur de ce package pour le même service |

Lève `invalid_argument` pour un mauvais type, `invalid_value` pour un nom ou une version mal
formés, une option inconnue ou une priorité hors limites, `invalid_state` quand un autre
package fournit le même service et la même version majeure avec la même priorité, quand le
package fournit déjà le service sans `replace`, ou quand le contexte n'est plus actif.

## `context:GetService(name, version)`

Renvoie `service, info` pour le meilleur fournisseur compatible (priorité la plus élevée, puis
premier enregistré), ou `nil`.

- `service` : objet intermédiaire vers l'implémentation. Les méthodes appelées avec `:`
  s'exécutent sur l'implémentation elle-même ; les champs sont lus au travers. Affecter un champ
  lève `invalid_state`. Toute utilisation après le retrait du fournisseur lève `invalid_state`
  en nommant le service et son fournisseur.
- `info` : `{ service = <objet>, provider = <package>, version = <chaîne>, priority = <entier> }`.

Lève `invalid_value` pour un nom ou une version mal formés, `invalid_state` si le contexte n'est
plus actif.

## `context:GetServices(name, version)`

Renvoie le tableau des tables `info` de tous les fournisseurs compatibles, le meilleur en
premier.

## `context:OnService(name, version, fn)`

Appelle `fn(service, info)` tout de suite quand un fournisseur compatible existe, puis à chaque
changement du meilleur fournisseur compatible ; `fn(nil)` quand il n'en reste aucun. Un
remplacement fait avec `replace = true` est signalé une seule fois. Renvoie un handle avec
`Release()` et `IsActive()` ; le suivi s'arrête quand le package est désactivé. `fn` s'exécute
sous protection : une erreur est journalisée sous la forme
`service_watcher callback of <package> failed`.

Lève `invalid_argument` si `fn` n'est pas une fonction, `invalid_value` pour un nom ou une
version mal formés, `invalid_state` si le contexte n'est plus actif.

## Champ `services` du manifeste

Tableau de `{ name, version, optional }` :

| Champ | Type | Description |
| --- | --- | --- |
| `name` | chaîne | Clé du service avec un espace de noms explicite |
| `version` | chaîne, facultatif | Versions acceptées, comme pour `GetService` |
| `optional` | booléen, facultatif | `true` pour un service dont le package peut se passer |

Quand le package passe prêt, chaque service exigé doit avoir un fournisseur compatible ; sinon
le package échoue (`'<package>' requires the service '<name>' (...), which no package
provides`). Quand le dernier fournisseur compatible d'un service exigé est retiré alors que le
package est prêt, le package échoue. Chaque nom n'apparaît qu'une fois.

## Champ `capabilities` du manifeste

Tableau de `"<espace>:<nom>"` ou de `{ name = "<espace>:<nom>", version = "<majeure>.<mineure>" }`.
Les noms sont uniques dans la liste ; l'espace de noms `foundation` est réservé. Une capacité est
disponible tant que le package est `ready`.

Une capacité portant le nom d'un service fourni est acceptée avec un avertissement : utilisez
des noms distincts.

## `Foundation.Capabilities.Has(name, version)`

Renvoie `true` si un package prêt déclare une capacité compatible. Une capacité déclarée sans
version ne correspond qu'aux demandes sans version.

## `Foundation.Capabilities.Providers(name, version)`

Renvoie le tableau des `{ package, version }` des packages prêts qui déclarent une capacité
compatible, dans l'ordre où ils sont devenus prêts.

Les deux lèvent `invalid_value` pour un nom sans espace de noms ou une version mal formée.

## Événements

| Événement | Champs |
| --- | --- |
| `foundation:service_available` | `service`, `provider`, `version`, `priority` |
| `foundation:service_unavailable` | `service`, `provider`, `version`, `priority` |
| `foundation:capability_available` | `capability`, `package`, `version` (ou `nil`) |
| `foundation:capability_unavailable` | `capability`, `package`, `version` (ou `nil`) |

Non annulables. Un remplacement émet `service_unavailable` pour l'ancien fournisseur, puis
`service_available` pour le nouveau.
