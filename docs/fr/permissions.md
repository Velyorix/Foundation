# Permissions

Une **permission** est un droit nommé, comme `homes.admin.delete`. Les packages déclarent les
permissions qu'ils utilisent et les vérifient avant d'agir ; Foundation décide si un compte en
dispose. Foundation n'a lui-même ni groupes ni grades : un package séparé peut les fournir, voir
[Fournisseurs](#fournisseurs).

## Exemple

<!-- example: tests/integration/packages/foundation-example-arena/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Arena",
})

local PLAY = context:DeclarePermission("foundation-example-arena.play", {
    description = "Join arena matches",
    default = "everyone",
})
local MANAGE = context:DeclarePermission("foundation-example-arena.manage", {
    description = "Start matches and appoint referees",
    default = "operators",
})

context:RegisterCommand({
    name = "arena",
    permission = MANAGE,
    subcommands = {
        {
            name = "start",
            run = function(sender)
                sender:Reply("match started")
            end,
        },
        {
            name = "join",
            permission = PLAY,
            run = function(sender)
                sender:Reply(sender:GetName() .. " joined the match")
            end,
        },
        {
            name = "referee",
            arguments = { { name = "account" } },
            run = function(sender, args)
                context:AttachPermission(args.account, MANAGE, true, { duration = 10 * 60 * 1000 })
                sender:Reply(args.account .. " can manage matches for 10 minutes")
            end,
        },
    },
})
```

Tous les joueurs peuvent taper `/arena join` ; `/arena start` et `/arena referee` demandent
`foundation-example-arena.manage`, que les opérateurs ont par défaut et que les arbitres
reçoivent pour dix minutes.

## Déclarer des permissions

`context:DeclarePermission(node, definition)` renvoie la permission en minuscules.

- La permission se compose de segments séparés par des points et commence par l'identifiant
  de votre package : `my-package.homes.set`. Les segments utilisent des lettres minuscules,
  des chiffres, `_` et `-`.
- `description` explique la permission aux administrateurs.
- `default` indique qui l'a quand rien d'autre ne décide : `everyone`, `nobody`, `operators`
  (par défaut) ou `non_operators`.
- `deprecated = "use my-package.homes.manage"` (ou `true`) marque une permission que vous
  prévoyez de retirer ; sa première vérification journalise un avertissement.

Les déclarations sont retirées à l'arrêt de votre package. Une permission que personne n'a
déclarée fonctionne quand même, et seuls les opérateurs l'ont.

## Vérifier une permission

`Foundation.Permissions.Has(subject, node)` renvoie `true` ou `false`. Le sujet est un
expéditeur de commande ou un identifiant de compte. La console a toutes les permissions.

Dans les commandes, indiquez `permission = "<permission>"` plutôt que de vérifier à la main :
Foundation refuse la commande avec « you do not have permission to use this command » avant son
délai et avant `foundation:command`. Une sous-commande sans permission utilise celle de la
commande au-dessus. Voir [Commandes](commands.md).

`Foundation.Permissions.Explain(subject, node)` indique pourquoi : `{ allowed, source, package }`,
où `source` vaut `console`, `attachment`, `provider` ou `default`.

## Comment la décision est prise

1. La console a toutes les permissions.
2. Les **attachements** posés par des packages pour ce compte et cette permission. Quand
   plusieurs packages ne sont pas d'accord, le refus l'emporte.
3. Le **fournisseur**, si un package en fournit un et qu'il a une réponse.
4. La **valeur par défaut** de la déclaration (`operators` pour une permission non déclarée).

## Attachements

`context:AttachPermission(subject, node, value, options)` accorde (`true`) ou retire (`false`)
une permission à un compte, par exemple pendant un mini-jeu. `options.duration`
(millisecondes) la rend temporaire. Elle renvoie un handle : `handle:Release()` la retire, et
elle est retirée à l'arrêt de votre package.

## Fournisseurs

Un package qui gère des grades ou des groupes fournit le service
`foundation:permission_provider`, en version de contrat 1, avec une méthode :
`Check(account, node)` renvoie `true`, `false`, ou `nil` quand il n'a pas de réponse pour ce
compte et cette permission.

<!-- example: tests/integration/packages/foundation-example-ranks/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Ranks",
})

local ranks = { ["76561198000000011"] = "moderator" }
local grants = {
    moderator = {
        ["foundation-example-arena.manage"] = true,
        ["foundation.command.packages"] = true,
    },
}

context:ProvideService("foundation:permission_provider", "1.0", {
    Check = function(_, account, node)
        local rank = ranks[account]
        if rank and grants[rank][node] then
            return true
        end
        return nil
    end,
})
```

Le fournisseur est interrogé à chaque vérification : gardez `Check` rapide et mettez en cache
dans votre package si nécessaire. S'il lève une erreur ou renvoie autre chose que `true`,
`false` ou `nil`, la réponse est ignorée et l'erreur journalisée : un fournisseur défaillant
n'accorde jamais d'accès. Plusieurs fournisseurs suivent les
[règles habituelles des services](services.md#fournir-un-service) : la priorité la plus élevée
est utilisée. Chaque changement de fournisseur est journalisé et enregistré dans le journal
d'audit.

## Opérateurs

Les opérateurs sont les comptes auxquels les administrateurs font confiance : ils ont toutes
les permissions dont la valeur par défaut est `operators`. Ils se gèrent avec
[`foundation op`](administration.md#opérateurs). Les packages lisent la liste avec
`Foundation.Operators.IsOperator(subject)` et `Foundation.Operators.List()`.

## Événements

| Événement | Champs | Quand |
| --- | --- | --- |
| `foundation:operator_added` | `account`, `name`, `by` | Un compte est devenu opérateur |
| `foundation:operator_removed` | `account`, `name`, `by` | Un compte n'est plus opérateur |

Voir la [référence](reference/permissions.md) pour toutes les méthodes et erreurs.
