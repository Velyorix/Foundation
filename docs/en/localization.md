# Localization

A package registers its texts once per language, in a **catalog**, and asks for them by key.
Foundation picks the language, fills in values and chooses the singular or plural form.

## Example

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

Output on a server whose language is English:

```
Welcome, Alex!
You have 1 home.
Bienvenue, Alex !
Vous avez 0 maison.
Vous avez 3 maisons.
```

## Catalogs

`context:RegisterCatalog(locale, entries)` registers the texts of one language:

- `locale` is a language code (`en`, `fr`) or a regional code (`fr_CA` or `fr-CA`);
- each key may contain letters, digits, `_`, `-` and `.`; dots are a convenient way to group
  keys (`join.welcome`, `join.goodbye`);
- each value is a text, or a table of plural forms (see below).

Register each language once; a second catalog for the same language raises an error. Catalogs
are removed when your package stops.

Keep your catalogs in their own files, for example `Server/locales/en.lua` returning the
table, and register them from `Server/Index.lua` with
`context:RegisterCatalog("en", Package.Require("locales/en.lua"))`.

## Values

`{name}` in a text is replaced with `params.name`, converted with `tostring`. A placeholder
without a value is left as it is, which makes a forgotten parameter easy to spot.

## Plurals

A table of forms is chosen with `params.count`:

```lua
["homes.count"] = {
    one = "You have {count} home.",
    other = "You have {count} homes.",
}
```

The available form names are `zero`, `one`, `two`, `few`, `many` and `other`; `other` is
required and is used when the matching form is missing. Which form a number needs depends on
the language of the text: in English, `one` is used for 1 only; in French, for 0 and 1.
Languages other than English and French currently follow the English rule.

## Choosing the language

`context:Translate(key, params, locale)` looks for the key in this order and uses the first
text found:

1. `locale`, when given (for example a player's language);
2. its base language (`fr` for `fr_CA`);
3. the server language (`language` in `foundation/config.toml`, see
   [Configuration](configuration.md)) and its base language;
4. English.

Without `locale`, the server language is used. A key found nowhere is returned as
`<package>:<key>`, and a warning is logged once:

```
[foundation] WARN  my-package/i18n: missing translation for 'my-package:join.welcome'
```

## Texts of another package

Prefix the key with the other package's identifier to use its catalog:

```lua
context:Translate("my-economy:balance", { amount = 120 })
```

See the [reference](reference/localization.md) for the exact rules and errors.
