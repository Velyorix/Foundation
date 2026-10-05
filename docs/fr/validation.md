# Clés et validation

Deux outils pour les données que votre package ne contrôle pas : les **clés** placent les noms
dans un espace de noms, pour que deux packages n'utilisent jamais le même identifiant par
accident, et les **schémas** vérifient la forme d'une valeur (configuration, données lues dans
un stockage, valeurs envoyées par des joueurs) avant que votre code ne l'utilise.

Les deux sont disponibles sous `Foundation.Keys` et `Foundation.Schema` dès que Foundation est
chargé.

## Exemple

Un package qui permet à d'autres codes de définir des kits valide chaque définition et nomme
chaque kit avec une clé dans son propre espace de noms :

<!-- example: tests/integration/packages/foundation-example-kits/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Kits",
})

local S = Foundation.Schema

local Kit = S.Record({
    name = S.String({ min = 1, max = 32 }),
    items = S.List(S.String({ min = 1 }), { min = 1, max = 10 }),
    cooldown = S.Optional(S.Integer({ min = 0 }), 300),
})

local kits = {}

local function define_kit(id, definition)
    local key, key_error = Foundation.Keys.Parse(id, context:GetId())
    if not key then
        return nil, key_error
    end
    local kit, err = S.Validate(Kit, definition)
    if not kit then
        return nil, err
    end
    kits[key] = kit
    return key
end

local key = define_kit("starter", { name = "Starter", items = { "pistol", "bandage" } })
Console.Log("defined %s, cooldown %d s", key, kits[key].cooldown)

local _, err = define_kit("builder", { name = "", items = { "hammer", 42 } })
Console.Log("rejected: %s", err.message)
for _, problem in ipairs(err.details.problems) do
    Console.Log("- %s", problem.message)
end

local _, key_error = define_kit("Bad Kit", { name = "Bad", items = { "stick" } })
Console.Log("rejected: %s", key_error.message)
```

Sortie (le dossier du package est `foundation-example-kits`, serveur en anglais) :

```
defined foundation-example-kits:starter, cooldown 300 s
rejected: invalid value (2 problem(s)): $.items[2]: expected string, got integer
- $.items[2]: expected string, got integer
- $.name: must have at least 1 characters
rejected: 'Bad Kit' is not a valid key: expected '<namespace>:<path>' with lowercase letters, digits, '_', '-', '.' and, in the path, '/'
```

## Clés

Une clé s'écrit `<espace de noms>:<chemin>`, par exemple `my-shop:items/apple` :

- l'espace de noms est en général l'identifiant de votre package (`context:GetId()`) ;
  `foundation` est réservé à Foundation ;
- l'espace de noms peut contenir des lettres minuscules, des chiffres, `_`, `-` et `.`
  (64 caractères au plus) ;
- le chemin peut aussi contenir `/`, mais pas au début, pas à la fin et pas deux fois de suite ;
- la clé complète fait au plus 128 caractères.

`Foundation.Keys.Parse` met le texte en minuscules, ajoute l'espace de noms par défaut quand
le texte n'en a pas, et renvoie la clé, ou `nil` et une erreur pour un texte qui ne peut pas
être une clé. Utilisez-la pour du texte venant de joueurs, de fichiers ou d'autres packages.

## Schémas

Un schéma décrit la valeur attendue. Construisez-le une fois, au chargement, et réutilisez-le :

| Constructeur | Accepte |
| --- | --- |
| `S.String({ min, max, pattern })` | Du texte ; les longueurs comptent des caractères, pas des octets ; `pattern` est un motif Lua |
| `S.Number({ min, max })` | Un nombre fini |
| `S.Integer({ min, max })` | Un nombre sans partie décimale |
| `S.Boolean()` | `true` ou `false` |
| `S.Enum({ ... })` | Une des valeurs listées |
| `S.Any()` | Toute valeur sauf `nil` |
| `S.Optional(schema, default)` | `nil` (remplacé par `default`) ou une valeur acceptée par `schema` |
| `S.Record({ field = schema, ... }, { extra })` | Une table à champs nommés |
| `S.List(schema, { min, max })` | Une séquence `{ a, b, c }` sans trou |
| `S.Map(key_schema, value_schema, { max })` | Une table utilisée comme dictionnaire |
| `S.Custom(key, fn)` | Ce que `fn` accepte |

`S.Validate(schema, value)` renvoie une **copie** de la valeur avec les valeurs par défaut
ajoutées, ou `nil` et une erreur. La valeur d'origine n'est jamais modifiée, et la copie ne
contient que ce que le schéma autorise : vous pouvez la conserver sans risque. Seules
exceptions : les valeurs acceptées par `S.Any` ou `S.Custom` sont renvoyées telles quelles,
sans copie.

La validation ne convertit jamais les valeurs : le texte `"5"` n'est pas un entier. Convertissez
d'abord (par exemple avec `tonumber`), puis validez.

### Quand la validation échoue

L'erreur liste tous les problèmes, chacun avec l'endroit de la valeur où il a été trouvé (`$`
désigne la valeur elle-même, `$.items[2]` le deuxième élément de son champ `items`) :

```lua
local value, err = S.Validate(schema, input)
if not value then
    for _, problem in ipairs(err.details.problems) do
        Console.Warn(problem.message)
    end
end
```

Les messages sont dans la langue du serveur. Au plus 20 problèmes sont listés
(`err.details.count` donne le total).

### Records

Les champs absents du record sont refusés par défaut. Passez `{ extra = "strip" }` pour les
retirer de la copie, ou `{ extra = "allow" }` pour les garder sans vérification.

Un champ est obligatoire sauf si son schéma est enveloppé dans `S.Optional`.

### Vérifications personnalisées

`S.Custom` nomme une vérification avec une clé et appelle votre fonction avec la valeur.
Renvoyez `true` pour l'accepter, ou `false` et un message pour la refuser :

```lua
local Even = S.Custom("my-package:even", function(value)
    if math.type(value) == "integer" and value % 2 == 0 then
        return true
    end
    return false, "must be an even integer"
end)
```

Si la fonction lève une erreur, la valeur est refusée avec `check 'my-package:even' failed` et
l'erreur est journalisée pour l'espace de noms de la clé. Le texte de l'erreur n'est pas repris
dans le message du problème, qui peut être montré à des joueurs.

### Limites

La validation s'arrête à 16 niveaux d'imbrication et 10 000 valeurs, pour qu'une valeur
malveillante ne puisse pas la faire durer longtemps. Passez d'autres limites en troisième
argument de `S.Validate`. Voir la [référence](reference/validation.md).
