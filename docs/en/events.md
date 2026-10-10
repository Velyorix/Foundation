# Events

Events let packages react to each other without calling each other directly. A package
**defines** an event and **emits** it when something happens; other packages **listen** to it
and can change or cancel it when the definition allows.

## Example

A shop defines a `purchase` event and emits it from its `buy` command:

<!-- example: tests/integration/packages/foundation-example-shop/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Shop",
})

local S = Foundation.Schema
local prices = { apple = 10, sword = 150 }

context:DefineEvent("purchase", {
    fields = {
        buyer = S.String(),
        item = S.String(),
        price = S.Integer({ min = 0 }),
    },
    mutable = { "price" },
    cancellable = true,
})

context:RegisterCommand({
    name = "buy",
    description = "Buy an item",
    arguments = {
        { name = "item", type = "enum", values = { "apple", "sword" } },
        { name = "amount", type = "integer", min = 1, max = 10, default = 1 },
    },
    cooldown = 2000,
    run = function(sender, args)
        local event = context:Emit("purchase", {
            buyer = sender:GetName(),
            item = args.item,
            price = prices[args.item] * args.amount,
        })
        if event:IsCancelled() then
            sender:Reply("purchase refused")
            return
        end
        sender:Reply(
            string.format("%s bought %d %s for %d", sender:GetName(), args.amount, args.item, event:Get("price"))
        )
    end,
})
```

A loyalty package gives a 10% discount, refuses swords bought from the console, and logs
every command that ran:

<!-- example: tests/integration/packages/foundation-example-loyalty/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Loyalty",
    depends = { "foundation-example-shop" },
})

local PURCHASE = "foundation-example-shop:purchase"

context:Listen(PURCHASE, function(event)
    event:Set("price", event:Get("price") * 9 // 10)
end)

context:Listen(PURCHASE, function(event)
    if event:Get("item") == "sword" and event:Get("buyer") == "console" then
        event:Cancel()
    end
end, { priority = "high" })

context:Listen("foundation:command_completed", function(event)
    Console.Log("%s ran %s (%s)", event:Get("name"), event:Get("command"), event:Get("outcome"))
end, { priority = "monitor" })
```

Typing `buy apple 3`, then `buy sword` in the server console prints:

```
console bought 3 apple for 27
console ran buy (success)
purchase refused
console ran buy (success)
```

## Defining an event

`context:DefineEvent(name, definition)` names the event `<package>:<name>`, where
`<package>` is your package identifier, and returns that full name. The definition says:

- `fields`: the data the event carries, each with a [schema](validation.md#schemas). The data
  given to `Emit` is checked against them; a wrong value is a programming error and raises at
  the line of the `Emit` call;
- `mutable`: the fields listeners may change;
- `cancellable`: whether listeners may cancel the event.

Only the package that defines an event can emit it. Define your events while your `Index.lua`
runs, so that packages listening to them find them when they load.

## Listening

`context:Listen("<package>:<name>", fn, options)` calls `fn(event)` each time the event is
emitted. The event must already be defined: list the defining package in the `depends` of
your manifest and in the `packages_requirements` of your `Package.toml`, so it loads first.

Inside the function:

- `event:Get(field)` reads a field; `event:GetData()` returns all of them (copies);
- `event:Set(field, value)` changes a field declared `mutable`; the value is checked against
  its schema;
- `event:Cancel()` or `event:SetCancelled(cancelled)` cancels a cancellable event, or
  restores it;
- `event:IsCancelled()`, `event:GetName()`.

### Order

`options.priority` sets when your function runs:

| Priority | Use |
| --- | --- |
| `lowest`, `low` | Run first; later listeners can override your changes |
| `normal` (default) | |
| `high`, `highest` | Run late, to have the last word |
| `monitor` | Run last, to observe the final result. Cannot change or cancel the event |

Listeners with the same priority run in the order they were added. With
`ignore_cancelled = true`, your function is skipped while the event is cancelled.

When every listener has run, the event is frozen and returned to the emitter, which reads the
outcome: `IsCancelled()` and the final values of the fields.

### Errors and cleanup

An error in a listener is logged with your package name; the other listeners still run.
Listening twice to the same event with the same function raises an error.

`Listen` returns a handle: `handle:Release()` stops listening. Listeners are removed when your
package stops, and an event disappears with its listeners when its defining package stops.

## Foundation's events

Foundation emits its own events under the `foundation` namespace. They report what happened
and cannot be cancelled, except `foundation:command`.

| Event | Fields | When |
| --- | --- | --- |
| `foundation:package_ready` | `package`, `version` | A package became ready |
| `foundation:package_failed` | `package`, `version`, `message` | A package failed |
| `foundation:package_disabled` | `package`, `version`, `reason` | A package was disabled; `reason` is `unload`, `dependency_disabled`, `dependency_failed` or `foundation_stopping` |
| `foundation:config_reloaded` | `package`, `path`, `changed`, `pending` | A configuration file was reloaded (`changed` and `pending` list setting keys) |
| `foundation:command` | `command`, `owner`, `sender`, `name`, `arguments` | A command is about to run. **Cancellable** |
| `foundation:command_completed` | the same, and `outcome` | A command ran; `outcome` is `success` or `failure` |
| `foundation:service_available`, `service_unavailable` | `service`, `provider`, `version`, `priority` | A service provider was added or removed, see [Services](services.md#events) |
| `foundation:capability_available`, `capability_unavailable` | `capability`, `package`, `version` | A capability became available or went away |

A package does not receive `package_disabled` for itself: its listeners are already removed.

See the [reference](reference/events.md) for every method and error.
