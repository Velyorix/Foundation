# Référence de l'API : localisation

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Localisation](../localization.md).

## Codes de langue

Un code de langue se compose de deux ou trois lettres minuscules (`en`, `fr`), suivies
éventuellement de `_` ou `-` et d'une région ou d'une variante (`fr_CA`, `pt-BR`). La partie
avant `_` ou `-` est la langue de base.

## `context:RegisterCatalog(locale, entries)`

Enregistre les textes du package pour une langue. Le catalogue est retiré quand le package est
désactivé.

| Paramètre | Type | Description |
| --- | --- | --- |
| `locale` | chaîne | Code de langue |
| `entries` | table | Clé → texte, ou clé → table de formes plurielles |

- Clés : lettres, chiffres, `_`, `-`, `.`.
- Les textes peuvent contenir des emplacements `{nom}` (lettres, chiffres et `_`, commençant
  par une lettre ou `_`).
- Formes plurielles : une table contenant tout ou partie de `zero`, `one`, `two`, `few`,
  `many`, `other` ; `other` est obligatoire ; chaque valeur est une chaîne.

Lève :

| Code | Quand |
| --- | --- |
| `invalid_value` | Code de langue, clé ou table de pluriels mal formé, ou valeur qui n'est ni une chaîne ni une table |
| `invalid_argument` | `entries` n'est pas une table |
| `invalid_state` | Le package a déjà enregistré un catalogue pour cette langue, ou son contexte n'est plus actif |

## `context:Translate(key, params, locale)`

Renvoie le texte de `key`, emplacements remplacés.

| Paramètre | Type | Description |
| --- | --- | --- |
| `key` | chaîne | Clé dans les catalogues du package, ou `"<package>:<clé>"` pour les catalogues d'un autre package |
| `params` | table, facultatif | Valeurs des emplacements ; `count` choisit aussi la forme plurielle |
| `locale` | chaîne, facultatif | Langue préférée |

Ordre de recherche, le premier texte trouvé l'emporte : `locale`, sa langue de base, la langue
du serveur (`language` dans `foundation/config.toml`), sa langue de base, `en`.

Les emplacements sont remplacés par `tostring(params[nom])` ; un emplacement sans valeur est
conservé tel quel. Pour une table de pluriels, la forme est choisie d'après `params.count` (un
nombre) avec la règle de pluriel de la langue dont le catalogue a fourni le texte ; quand
`count` manque ou que la forme n'est pas dans la table, `other` est utilisée. Règles de
pluriel : anglais (`one` pour 1), français (`one` pour 0 et 1, et toute valeur inférieure à
2) ; les autres langues suivent la règle anglaise.

Quand aucun catalogue ne contient la clé, renvoie `"<package>:<clé>"` et journalise un
avertissement pour le package propriétaire du catalogue, une fois par clé.

Lève `invalid_argument` si `key` n'est pas une chaîne ou `params` pas une table,
`invalid_value` si `key` est vide ou `locale` n'est pas un code de langue, `invalid_state` si
le contexte n'est plus actif.
