# Localisation

Un package enregistre ses textes une fois par langue, dans un **catalogue**, et les demande
par clé. Foundation choisit la langue, insère les valeurs et choisit la forme du singulier ou
du pluriel.

## Exemple

<!-- example: tests/integration/packages/foundation-example-welcome/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Welcome",
})

context:RegisterCatalog("en", {
    ["join.welcome"] = "Welcome, {name}!",
    ["homes.count"] = {
        one = "You have {count} home.",
        other = "You have {count} homes.",
    },
})

context:RegisterCatalog("fr", {
    ["join.welcome"] = "Bienvenue, {name} !",
    ["homes.count"] = {
        one = "Vous avez {count} maison.",
        other = "Vous avez {count} maisons.",
    },
})

Console.Log(context:Translate("join.welcome", { name = "Alex" }))
Console.Log(context:Translate("homes.count", { count = 1 }))
Console.Log(context:Translate("join.welcome", { name = "Alex" }, "fr"))
Console.Log(context:Translate("homes.count", { count = 0 }, "fr"))
Console.Log(context:Translate("homes.count", { count = 3 }, "fr_CA"))
```

Sortie sur un serveur dont la langue est l'anglais :

```
Welcome, Alex!
You have 1 home.
Bienvenue, Alex !
Vous avez 0 maison.
Vous avez 3 maisons.
```

## Catalogues

`context:RegisterCatalog(locale, entries)` enregistre les textes d'une langue :

- `locale` est un code de langue (`en`, `fr`) ou un code régional (`fr_CA` ou `fr-CA`) ;
- chaque clé peut contenir des lettres, des chiffres, `_`, `-` et `.` ; les points permettent
  de regrouper les clés (`join.welcome`, `join.goodbye`) ;
- chaque valeur est un texte, ou une table de formes plurielles (voir plus bas).

Enregistrez chaque langue une seule fois ; un second catalogue pour la même langue lève une
erreur. Les catalogues sont retirés à l'arrêt de votre package.

Placez vos catalogues dans leurs propres fichiers, par exemple `Server/locales/en.lua` qui
renvoie la table, et enregistrez-les depuis `Server/Index.lua` avec
`context:RegisterCatalog("en", Package.Require("locales/en.lua"))`.

## Valeurs

`{name}` dans un texte est remplacé par `params.name`, converti avec `tostring`. Un
emplacement sans valeur est laissé tel quel, ce qui rend un paramètre oublié facile à repérer.

## Pluriels

Une table de formes est choisie avec `params.count` :

```lua
["homes.count"] = {
    one = "You have {count} home.",
    other = "You have {count} homes.",
}
```

Les noms de formes disponibles sont `zero`, `one`, `two`, `few`, `many` et `other` ; `other`
est obligatoire et sert quand la forme voulue manque. La forme dont un nombre a besoin dépend
de la langue du texte : en anglais, `one` ne sert que pour 1 ; en français, pour 0 et 1. Les
langues autres que l'anglais et le français suivent pour l'instant la règle anglaise.

## Choix de la langue

`context:Translate(key, params, locale)` cherche la clé dans cet ordre et utilise le premier
texte trouvé :

1. `locale`, s'il est fourni (par exemple la langue d'un joueur) ;
2. sa langue de base (`fr` pour `fr_CA`) ;
3. la langue du serveur (`language` dans `foundation/config.toml`, voir
   [Configuration](configuration.md)) et sa langue de base ;
4. l'anglais.

Sans `locale`, la langue du serveur est utilisée. Une clé introuvable est renvoyée sous la
forme `<package>:<clé>`, et un avertissement est journalisé une fois :

```
[foundation] WARN  my-package/i18n: missing translation for 'my-package:join.welcome'
```

## Textes d'un autre package

Préfixez la clé par l'identifiant de l'autre package pour utiliser son catalogue :

```lua
context:Translate("my-economy:balance", { amount = 120 })
```

Voir la [référence](reference/localization.md) pour les règles exactes et les erreurs.
