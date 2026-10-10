# Permissions

A **permission** is a named right, such as `homes.admin.delete`. Packages declare the
permissions they use and check them before acting; Foundation decides whether an account has
one. Foundation itself has no groups or ranks: a separate package can provide them, see
[Providers](#providers).

## Example

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

Every player can type `/arena join`; `/arena start` and `/arena referee` need
`foundation-example-arena.manage`, which operators have by default and referees get for ten
minutes.

## Declaring permissions

`context:DeclarePermission(node, definition)` returns the node in lowercase.

- The node is made of segments separated by dots and starts with your package identifier:
  `my-package.homes.set`. Segments use lowercase letters, digits, `_` and `-`.
- `description` explains the permission to administrators.
- `default` says who has it when nothing else decides: `everyone`, `nobody`, `operators` (the
  default) or `non_operators`.
- `deprecated = "use my-package.homes.manage"` (or `true`) marks a permission you plan to
  remove; the first check logs a warning.

Declarations are removed when your package stops. A permission that nobody declared still
works, and only operators have it.

## Checking a permission

`Foundation.Permissions.Has(subject, node)` returns `true` or `false`. The subject is a command
sender or an account id. The console has every permission.

In commands, set `permission = "<node>"` instead of checking by hand: Foundation refuses the
command with "you do not have permission to use this command" before its cooldown and before
`foundation:command`. A subcommand without its own permission uses the one of the command
above it. See [Commands](commands.md).

`Foundation.Permissions.Explain(subject, node)` tells why: `{ allowed, source, package }`, where
`source` is `console`, `attachment`, `provider` or `default`.

## How the decision is made

1. The console has every permission.
2. **Attachments** made by packages for this account and permission. When several packages
   disagree, a deny wins.
3. The **provider**, if a package provides one and it has an answer.
4. The **default** of the declaration (`operators` for undeclared permissions).

## Attachments

`context:AttachPermission(subject, node, value, options)` gives (`true`) or removes (`false`) a
permission to one account, for example during a mini-game. `options.duration` (milliseconds)
makes it temporary. It returns a handle: `handle:Release()` removes it, and it is removed when
your package stops.

## Providers

A package that manages ranks or groups provides the service `foundation:permission_provider`,
contract version 1, with one method: `Check(account, node)` returns `true`, `false`, or `nil`
when it has no answer for this account and permission.

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

The provider is asked on every check, so keep `Check` fast and cache in your package if you
need to. If it raises an error or returns something else than `true`, `false` or `nil`, the
answer is ignored and the error is logged: a broken provider never grants access. Several
providers follow the usual [service rules](services.md#providing-a-service): the highest
priority is used. Each change of provider is logged and recorded in the audit log.

## Operators

Operators are the accounts administrators trust: they have every permission whose default is
`operators`. They are managed with [`foundation op`](administration.md#operators). Packages read
the list with `Foundation.Operators.IsOperator(subject)` and `Foundation.Operators.List()`.

## Events

| Event | Fields | When |
| --- | --- | --- |
| `foundation:operator_added` | `account`, `name`, `by` | An account became an operator |
| `foundation:operator_removed` | `account`, `name`, `by` | An account is no longer an operator |

See the [reference](reference/permissions.md) for every method and error.
