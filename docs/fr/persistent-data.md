# Données persistantes

Les **données persistantes** conservent une valeur par sujet, en général un compte joueur, sous
un nom que votre package définit : un profil, un nombre de visites, des objets débloqués. Les
valeurs sont vérifiées avec un [schéma](validation.md), les valeurs absentes ont une valeur par
défaut, et les autres packages peuvent les lire. Les données sont conservées sur le disque
comme les [espaces de stockage](storage.md) et suivent les mêmes règles : conservées après un
redémarrage, jamais supprimées à l'arrêt d'un package, écrites avant l'arrêt du serveur.

## Exemple

<!-- example: tests/integration/packages/foundation-example-profiles/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Profiles",
})

local S = Foundation.Schema

local profile = context:DefineData(
    "profile",
    S.Record({
        nickname = S.String({ min = 1, max = 24 }),
        color = S.Optional(S.Enum({ "red", "green", "blue" }), "blue"),
    })
)
local visits = context:DefineData("visits", S.Integer({ min = 0 }), { default = 0 })

context:RegisterCommand({
    name = "profile",
    subcommands = {
        {
            name = "set",
            arguments = {
                { name = "account" },
                { name = "nickname", min = 1, max = 24 },
                { name = "color", type = "enum", values = { "red", "green", "blue" }, default = "blue" },
            },
            run = function(sender, args)
                profile:Set(args.account, { nickname = args.nickname, color = args.color }):Then(function()
                    sender:Reply("profile of " .. args.account .. " saved")
                end)
            end,
        },
        {
            name = "show",
            arguments = { { name = "account" } },
            run = function(sender, args)
                context:All({ profile:Get(args.account), visits:Get(args.account) }):Then(function(values)
                    local current, count = values[1], values[2]
                    if current == nil then
                        sender:Reply(args.account .. " has no profile, " .. count .. " visit(s)")
                        return
                    end
                    sender:Reply(string.format("%s (%s), %d visit(s)", current.nickname, current.color, count))
                end)
            end,
        },
    },
})

Player.Subscribe("Spawn", function(player)
    local account = player:GetAccountID()
    visits:Get(account):Then(function(count)
        return visits:Set(account, count + 1)
    end)
end)
```

Dans la console du serveur :

```
profile set 76561198000000021 Alex green
[foundation] profile of 76561198000000021 saved
profile show 76561198000000021
[foundation] Alex (green), 0 visit(s)
```

## Définir des données

`context:DefineData(name, schema, options)` renvoie une clé de données.

- `name` utilise des lettres minuscules, des chiffres, `_`, `-` et `.` (64 caractères au plus).
  Le nom complet est `<package>:<name>`, par exemple `foundation-example-profiles:profile` ;
  les autres packages l'utilisent pour lire les données.
- `schema` est un [schéma](validation.md) construit avec `Foundation.Schema`.
- `options.default` est renvoyé pour les sujets sans valeur. Il doit respecter le schéma. Sans
  lui, la valeur par défaut est `nil`.

Chaque nom peut être défini une fois pendant que le package tourne. Le définir à nouveau après
un redémarrage ou un rechargement donne accès aux valeurs enregistrées auparavant.

## Sujets

Un sujet identifie à qui ou à quoi appartient la valeur : une chaîne non vide de 128 caractères
au plus, sans caractère de contrôle. Utilisez l'identifiant de compte des joueurs
(`player:GetAccountID()`), qui reste le même d'une session à l'autre et après un changement de
nom. Un expéditeur de commande joueur peut être passé directement : son identifiant de compte
est utilisé. La console n'est pas un sujet.

## Lire et écrire

| Méthode | Résolue avec |
| --- | --- |
| `key:Get(subject)` | La valeur, ou une copie de la valeur par défaut quand le sujet n'en a pas |
| `key:Set(subject, value)` | `true` une fois la valeur écrite |
| `key:Delete(subject)` | `true` si le sujet avait une valeur, `false` sinon |

`Set` vérifie la valeur avec le schéma et lève une erreur à votre ligne quand elle ne le
respecte pas :

```
[foundation:invalid_value] data:Set: argument #2 'value' is invalid: does not match the schema of 'foundation-example-profiles:profile': $.nickname: must have at least 1 characters
```

La valeur vérifiée est enregistrée, complétée par les valeurs par défaut du schéma : l'exemple
ci-dessus enregistre `color = "blue"` quand aucune couleur n'est donnée. `Get` renvoie une
nouvelle table à chaque fois.

Les opérations s'exécutent dans l'ordre où elles sont faites : un `Get` fait après un `Set` voit
la nouvelle valeur. Un `Get` suivi d'un `Set`, comme pour le compteur de visites ci-dessus,
convient aux changements occasionnels ; quand plusieurs changements de la même valeur peuvent
se chevaucher, gardez la valeur courante en mémoire et écrivez-la avec `Set`.

## Lire les données d'un autre package

`context:ReadData("<package>:<name>")` donne un accès en lecture seule aux données définies par
n'importe quel package :

<!-- example: tests/integration/packages/foundation-example-nametags/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Name Tags",
})

local profiles = context:ReadData("foundation-example-profiles:profile")

context:RegisterCommand({
    name = "nametag",
    arguments = { { name = "account" } },
    run = function(sender, args)
        profiles:Get(args.account):Then(function(profile)
            if profile == nil then
                sender:Reply(args.account .. ": no name tag")
                return
            end
            sender:Reply(string.format("%s: [%s] %s", args.account, profile.color, profile.nickname))
        end)
    end,
})
```

```
nametag 76561198000000021
[foundation] 76561198000000021: [green] Alex
```

- `reader:Get(subject)` est résolue avec la valeur enregistrée ou `nil`. Les valeurs par
  défaut ne sont connues que du package qui définit les données.
- Les lecteurs n'ont ni `Set` ni `Delete` : seul le package qui définit les données les
  modifie.
- La lecture fonctionne même quand le package qui définit les données est arrêté ou n'est pas
  installé, et voit ses écritures dans l'ordre.

## Limites

Les données persistantes d'un package comptent comme un seul espace pour les
[quotas](storage.md#quotas) : chaque valeur de chaque nom et de chaque sujet ajoute sa taille
(`<name>|<subject>` plus la valeur JSON).

## Quand votre package s'arrête

Utiliser une clé de données après l'arrêt de votre package lève `invalid_state` ; les lecteurs
des autres packages continuent de fonctionner. Rien n'est supprimé.

Voir la [référence](reference/storage.md#données-persistantes) pour toutes les méthodes et
erreurs.
