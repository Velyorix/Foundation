# Services and capabilities

A **service** is an object one package offers to the others under a shared name, for example
`economy:bank`. The name stands for a contract: the methods and their meaning. Any package can
provide it, and the packages that use it do not depend on which one does, so a server can
replace its economy package without changing the others.

A **capability** is a statement that something is available, for example
`economy:offline-payments`. It carries no object; packages check it to decide what to offer.

## Example

A package provides the `economy:bank` service and declares a capability:

<!-- example: tests/integration/packages/foundation-example-coins/Server/Index.lua -->
```lua
Foundation.Register(Package, {
    api = "0.1",
    name = "Coins",
    capabilities = { "economy:offline-payments" },
}):ProvideService("economy:bank", "1.0", {
    balances = {},
    Balance = function(self, account)
        return self.balances[account] or 0
    end,
    Deposit = function(self, account, amount)
        self.balances[account] = self:Balance(account) + amount
        return self.balances[account]
    end,
})
```

Another package requires the service, follows its provider and checks the capability:

<!-- example: tests/integration/packages/foundation-example-salary/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Salary",
    services = { { name = "economy:bank", version = "1" } },
})

local bank

context:OnService("economy:bank", "1", function(service, info)
    bank = service
    if service then
        Console.Log("salaries are paid through %s", info.provider)
    else
        Console.Log("no bank available, salaries are paused")
    end
end)

context:OnReady(function()
    Console.Log("paid 100 to alex, balance %d", bank:Deposit("alex", 100))
    if Foundation.Capabilities.Has("economy:offline-payments") then
        Console.Log("offline players are paid too")
    end
end)
```

Output, the provider package being named `foundation-example-coins`:

```
salaries are paid through foundation-example-coins
paid 100 to alex, balance 100
offline players are paid too
```

## Providing a service

`context:ProvideService(name, version, implementation, options)`:

- `name` is `<namespace>:<name>`. The namespace names the contract, not your package: several
  packages can provide `economy:bank`. Without a namespace, your package identifier is used;
- `version` is the contract version you implement, `"<major>.<minor>"`. Increase the minor
  version when you add methods, the major version when existing ones change;
- `implementation` is a table of fields and methods;
- `options.priority` (integer, default 0) decides between providers: the highest wins.

Two packages cannot provide the same service and major version with the same priority:
choose different priorities, so that the choice never depends on load order. To replace your
own provider, call `ProvideService` again with `{ replace = true }`.

The service is removed when your package stops, or with the returned handle:
`handle:Release()`.

## Using a service

`context:GetService(name, version)` returns the service of the best provider, and a table
`info` with `provider`, `version` and `priority`; or `nil` when no compatible provider exists.

`version` selects compatible providers: `"1"` accepts any 1.x, `"1.2"` accepts 1.2 and later
1.x versions, `nil` accepts any version. `context:GetServices(name, version)` returns all of
them, best first.

The returned object forwards every call to the provider. Once the provider stops, using it
raises an error naming the provider, instead of calling a package that is no longer running.
Ask again, or follow changes with `OnService`.

### Following the provider

`context:OnService(name, version, fn)` calls `fn(service, info)` at once if a compatible provider
exists, and again each time the best compatible provider changes: a better one appears, the
current one stops and another takes over, or none is left, in which case `fn(nil)` is called.

### Requiring a service

List the services your package cannot work without in its manifest:

```lua
services = {
    { name = "economy:bank", version = "1" },
    { name = "chat:format", optional = true },
}
```

When your package is about to become ready, a required service without a compatible provider
makes it fail with a clear message instead of failing later on the first call. If the last
compatible provider stops while your package runs, your package fails as well (its disable
hooks run). Providers of packages loaded after yours are found: the check happens once every
package has loaded. Optional services are listed for diagnostics only.

## Capabilities

Declare capabilities in the manifest:

```lua
capabilities = { "chat:colors", { name = "chat:emotes", version = "2.1" } }
```

A capability is available while the declaring package is ready. Check it with
`Foundation.Capabilities.Has(name, version)`, or list the packages that declare it with
`Foundation.Capabilities.Providers(name, version)`. Versions work as for services.

To check a capability from your `OnReady` hook, load after the declaring package: list it in
the `packages_requirements` of your `Package.toml`.

## Events

| Event | Fields | When |
| --- | --- | --- |
| `foundation:service_available` | `service`, `provider`, `version`, `priority` | A provider was added |
| `foundation:service_unavailable` | the same | A provider was removed |
| `foundation:capability_available` | `capability`, `package`, `version` | A package declaring the capability became ready |
| `foundation:capability_unavailable` | the same | That package stopped or failed |

Administrators see services, providers, consumers and capabilities with
[`foundation services`](administration.md#services). See the
[reference](reference/services.md) for every method and error.
