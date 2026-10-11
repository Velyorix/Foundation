# Référence de l'API : stockage et données persistantes

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guides : [Stockage](../storage.md), [Données persistantes](../persistent-data.md).

## Espaces de stockage

### `context:Store(name, options)`

Renvoie l'espace `<package>` (sans `name`) ou `<package>/<name>`. Le même nom renvoie le même
espace tant que le package tourne. L'espace est libéré quand le package est désactivé ; ses
données sont conservées.

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne, facultatif | Lettres minuscules, chiffres, `_` et `-` |
| `options` | table, facultatif | Voir ci-dessous ; sans elle, l'espace n'a pas de version |

| Option | Type | Description |
| --- | --- | --- |
| `version` | entier | Version des données, 1 ou plus. Obligatoire quand `options` est donné |
| `migrations` | table, facultatif | Fonctions ; `migrations[n]` convertit la version `n` en `n + 1`. Obligatoire pour chaque `n` de 1 à `version - 1` |

Une migration reçoit `{ [key] = value }` avec toutes les entrées de l'espace et renvoie les
entrées de la version suivante, selon les mêmes règles que `Set`. Ses erreurs sont
journalisées sous la forme `store_migration callback of <package> failed`.

Lève `invalid_argument` pour des types incorrects, `invalid_value` pour un nom mal formé, une
option inconnue, une version inférieure à 1 ou une migration manquante, `invalid_state` quand
l'espace est déjà ouvert avec une autre version ou que le contexte n'est plus actif.

### Méthodes d'un espace

Toutes les méthodes sauf `Usage` et `GetName` renvoient une [future](scheduling.md#futures)
appartenant au package. Toutes lèvent `invalid_state` une fois le package arrêté.

| Méthode | Résolue avec |
| --- | --- |
| `store:Get(key)` | La valeur, ou `nil` |
| `store:Set(key, value)` | `true` |
| `store:Delete(key)` | `true` si la clé existait, sinon `false` |
| `store:Keys(prefix, limit)` | Tableau trié des clés qui commencent par `prefix` (par défaut `""`), au plus `limit` (par défaut et au maximum 10000) |
| `store:Batch(operations)` | `true` ; les opérations sont écrites ensemble ou pas du tout |
| `store:Usage()` | Renvoie immédiatement `{ count, bytes, max_keys, max_bytes }` |
| `store:GetName()` | Renvoie immédiatement `"<package>"` ou `"<package>/<name>"` |

- `key` : chaîne non vide de 256 caractères au plus, sans caractère de contrôle.
- `value` : tout ce que l'encodeur JSON accepte : `boolean`, `number` fini, `string`, et des
  tables qui sont soit des séquences, soit des tables à clés textuelles, sur 32 niveaux au plus,
  sans cycle. Le texte JSON fait au plus 1048576 octets. Les entiers et les nombres décimaux
  restent distincts.
- `operations` : tableau de `{ op = "set", key = ..., value = ... }` et
  `{ op = "delete", key = ... }`. Un tableau vide est résolu immédiatement.

Lève `invalid_argument` pour des types incorrects ou une valeur `nil`, `invalid_value` pour une
clé invalide, une opération invalide ou une valeur refusée par l'encodeur.

Rejets :

| Code | Catégorie | Quand |
| --- | --- | --- |
| `storage_quota` | developer | Une écriture dépasserait `max_keys` ou `max_bytes` ; `params` contient `namespace`, `max_keys`, `max_bytes` |
| `storage_failed` | infrastructure | La base de données a refusé l'opération ; `cause` contient son message. Les comptes et le cache de l'espace sont restaurés |
| `storage_unavailable` | infrastructure | Pas de base de données, ou l'espace n'a pas pu lire ses clés ni migrer ses données |
| `storage_corrupt` | infrastructure | Le texte enregistré n'est pas du JSON valide ; `params` contient `namespace` et `key` |

### Tailles et quotas

La taille d'une clé est la longueur de la clé plus la longueur de son texte JSON, en octets.
`bytes` est la somme pour l'espace et `count` son nombre de clés. Une écriture est rejetée
quand elle fait passer `count` au-dessus de `max_keys` ou `bytes` au-dessus de `max_bytes`
(`storage.max_keys_per_package` et `storage.max_bytes_per_package` dans
[`foundation/config.toml`](../configuration.md#réglages-de-foundation)). Les limites
s'appliquent à chaque espace séparément.

## Données persistantes

### `context:DefineData(name, schema, options)`

Définit `<package>:<name>` et renvoie sa clé de données.

| Paramètre | Type | Description |
| --- | --- | --- |
| `name` | chaîne | Lettres minuscules, chiffres, `_`, `-` et `.` ; 64 caractères au plus |
| `schema` | schéma | Construit avec [`Foundation.Schema`](validation.md#foundationschema) |
| `options` | table, facultatif | `default` : valeur renvoyée pour les sujets qui n'en ont pas ; doit respecter `schema` |

Lève `invalid_argument` pour des types incorrects, `invalid_value` pour un nom mal formé, une
option inconnue ou une valeur par défaut qui ne respecte pas le schéma, `invalid_state` quand le
nom est déjà défini par le package ou que le contexte n'est plus actif.

### Méthodes d'une clé de données

| Méthode | Description |
| --- | --- |
| `key:GetName()` | `"<package>:<name>"` |
| `key:Get(subject)` | Future résolue avec la valeur, ou une copie de la valeur par défaut |
| `key:Set(subject, value)` | Future résolue avec `true`. Enregistre la valeur renvoyée par [`Foundation.Schema.Validate`](validation.md#foundationschemavalidateschema-value-limits) |
| `key:Delete(subject)` | Future résolue avec `true` si le sujet avait une valeur |

- `subject` : chaîne non vide de 128 caractères au plus sans caractère de contrôle, ou un
  [expéditeur de commande](commands.md#expéditeur) joueur (son identifiant de compte).

Lève `invalid_value` pour un sujet invalide ou une valeur qui ne respecte pas le schéma
(`params.reason` nomme le premier problème) ou que l'encodeur JSON refuse, `invalid_state` une
fois le package arrêté. Les futures sont rejetées comme celles des espaces de stockage.

### `context:ReadData(key)`

Renvoie un lecteur en lecture seule pour `<package>:<name>`, défini par n'importe quel package,
maintenant ou plus tard.

| Méthode | Description |
| --- | --- |
| `reader:GetName()` | `"<package>:<name>"` |
| `reader:Get(subject)` | Future appartenant au package lecteur, résolue avec la valeur enregistrée ou `nil` |

Le lecteur continue de fonctionner pendant que le package qui définit les données est arrêté.
Lève `invalid_value` quand `key` n'est pas une clé avec espace de noms ; `reader:Get` lève
`invalid_value` pour un sujet invalide.

## Messages journalisés

| Message | Niveau |
| --- | --- |
| `storage opened at <path>` | info |
| `storage could not be opened at <path> (...)` | error |
| `the keys of '<store>' could not be read (...)` | error |
| `migrated '<store>' from version <n> to <m> (<k> change(s))` | info |
| `the data of '<store>' could not be migrated from version <n> (...); nothing was changed` | error |
| `the data of '<store>' is version <n>, newer than version <m> declared by its package; it is left untouched` | error |
| `wrote <n> pending storage operation(s) before stopping` | info |

Ces messages sont écrits dans la langue du serveur ; ils sont cités ici en anglais.
