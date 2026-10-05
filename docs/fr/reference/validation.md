# Référence de l'API : clés et schémas

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Clés et validation](../validation.md).

## `Foundation.Keys`

Table en lecture seule.

### `Foundation.Keys.Parse(text, default_namespace)`

Normalise `text` en une clé `<espace de noms>:<chemin>`.

| Paramètre | Type | Description |
| --- | --- | --- |
| `text` | quelconque | Texte à analyser. Converti en minuscules |
| `default_namespace` | chaîne, facultatif | Espace de noms utilisé quand `text` n'en a pas |

Renvoie `key, namespace, path`, ou `nil, err` avec `err.code == "invalid_key"` quand `text`
n'est pas une chaîne ou pas une clé valide.

Règles :

- espace de noms : `a`-`z`, `0`-`9`, `_`, `-`, `.` ; de 1 à 64 caractères ;
- chemin : les mêmes caractères et `/` ; non vide, sans `/` au début ni à la fin, sans `//` ;
- clé complète : 128 caractères au plus.

Lève `invalid_argument` si `default_namespace` n'est pas une chaîne.

### `Foundation.Keys.Split(key)`

Renvoie `namespace, path` d'une clé renvoyée par `Parse`. Ne l'utilisez pas sur du texte non
vérifié.

### `Foundation.Keys.IsReserved(namespace)`

Renvoie `true` pour les espaces de noms réservés à Foundation (`foundation`).

## `Foundation.Schema`

Table en lecture seule. Les constructeurs renvoient un schéma, qui peut être réutilisé et
partagé ; ne le modifiez pas.

Les constructeurs lèvent `invalid_argument` ou `invalid_value` quand leurs options sont
incorrectes (option inconnue, mauvais type, `min` supérieur à `max`, borne infinie).

### `Foundation.Schema.String(options)`

| Option | Type | Description |
| --- | --- | --- |
| `min` | entier, facultatif | Longueur minimale en caractères (UTF-8) |
| `max` | entier, facultatif | Longueur maximale en caractères |
| `pattern` | chaîne, facultatif | Motif Lua que le texte doit respecter (`string.find`) ; ancrez-le avec `^` et `$` pour porter sur tout le texte |

Un texte qui n'est pas de l'UTF-8 valide est refusé.

### `Foundation.Schema.Number(options)` / `Foundation.Schema.Integer(options)`

Options `min` et `max` (nombres, inclus). `NaN` et les valeurs infinies sont refusés.
`Integer` accepte les nombres sans partie décimale, y compris les flottants comme `3.0`.

### `Foundation.Schema.Boolean()`

### `Foundation.Schema.Any()`

Accepte toute valeur sauf `nil`. La valeur n'est pas copiée.

### `Foundation.Schema.Enum(values)`

`values` : tableau non vide. Accepte une valeur égale à l'une d'elles.

### `Foundation.Schema.Optional(schema, default)`

Accepte `nil`, remplacé par une copie de `default` (qui peut être `nil`), ou ce que `schema`
accepte.

### `Foundation.Schema.Record(fields, options)`

`fields` : table associant des noms de champs (chaînes) à des schémas. Les champs sont vérifiés
dans l'ordre alphabétique.

| Option | Valeurs | Description |
| --- | --- | --- |
| `extra` | `"reject"` (par défaut), `"strip"`, `"allow"` | Que faire des champs absents de `fields` : les refuser, les omettre du résultat, ou les copier sans vérification |

### `Foundation.Schema.List(schema, options)`

Accepte une séquence (clés `1` à `n`, sans trou) dont les éléments respectent `schema`. Options
`min`, `max` : nombre d'éléments.

### `Foundation.Schema.Map(key_schema, value_schema, options)`

Accepte une table dont les clés respectent `key_schema` et les valeurs `value_schema`. Option
`max` : nombre d'entrées.

### `Foundation.Schema.Custom(key, fn)`

| Paramètre | Type | Description |
| --- | --- | --- |
| `key` | chaîne | Nom de la vérification, une clé avec un espace de noms explicite (`"my-package:even"`) |
| `fn` | fonction | `fn(value)` renvoie `true`, ou `false` et un message |

Si `fn` lève une erreur, la valeur est refusée avec `check '<key>' failed` et l'erreur est
journalisée pour l'espace de noms de `key`. La valeur n'est pas copiée.

### `Foundation.Schema.Validate(schema, value, limits)`

Renvoie une copie validée de `value`, valeurs par défaut appliquées, ou `nil, err` avec
`err.code == "validation_failed"`.

| Champ de `limits` | Défaut | Description |
| --- | --- | --- |
| `max_depth` | 16 | Profondeur d'imbrication maximale |
| `max_items` | 10000 | Nombre maximal de valeurs vérifiées ; la validation s'arrête au-delà |
| `max_problems` | 20 | Nombre maximal de problèmes listés |

En cas d'échec :

- `err.message` : nombre de problèmes et le premier d'entre eux ;
- `err.details.count` : nombre total de problèmes ;
- `err.details.problems` : tableau de `{ path, reason, params, message }` ; `path` vaut `$`
  pour la valeur, `$.champ`, `$[1]` ou `$["clé"]` en dessous ; `message` vaut
  `"<path>: <texte de la raison>"` dans la langue du serveur ; `reason` est un identifiant
  stable du type de problème.

Les valeurs ne sont jamais converties : validez après avoir converti le texte en nombres ou en
booléens.

Lève `invalid_argument` si `schema` n'est pas un schéma, `invalid_value` pour une limite
inconnue.

### `Foundation.Schema.IsSchema(value)`

Renvoie `true` si `value` a été construit par `Foundation.Schema`.
