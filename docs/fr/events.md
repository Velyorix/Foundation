# Événements

Les événements permettent aux packages de réagir les uns aux autres sans s'appeler
directement. Un package **définit** un événement et l'**émet** quand quelque chose se produit ;
d'autres packages l'**écoutent** et peuvent le modifier ou l'annuler quand la définition le
permet.

## Exemple

Une boutique définit un événement `purchase` et l'émet depuis sa commande `buy` :

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

Un package de fidélité accorde 10 % de remise, refuse les épées achetées depuis la console et
journalise chaque commande exécutée :

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

Taper `buy apple 3` puis `buy sword` dans la console du serveur affiche :

```
console bought 3 apple for 27
console ran buy (success)
purchase refused
console ran buy (success)
```

## Définir un événement

`context:DefineEvent(name, definition)` nomme l'événement `<package>:<nom>`, où `<package>`
est l'identifiant de votre package, et renvoie ce nom complet. La définition indique :

- `fields` : les données transportées, chacune avec un [schéma](validation.md#schémas). Les
  données passées à `Emit` sont vérifiées ; une valeur incorrecte est une erreur de
  programmation, levée à la ligne de l'appel à `Emit` ;
- `mutable` : les champs que les écouteurs peuvent modifier ;
- `cancellable` : si les écouteurs peuvent annuler l'événement.

Seul le package qui définit un événement peut l'émettre. Définissez vos événements pendant
l'exécution de votre `Index.lua`, pour que les packages qui les écoutent les trouvent à leur
chargement.

## Écouter

`context:Listen("<package>:<nom>", fn, options)` appelle `fn(event)` à chaque émission de
l'événement. L'événement doit déjà être défini : indiquez le package qui le définit dans le
`depends` de votre manifeste et dans les `packages_requirements` de votre `Package.toml`, pour
qu'il soit chargé avant.

Dans la fonction :

- `event:Get(field)` lit un champ ; `event:GetData()` les renvoie tous (copies) ;
- `event:Set(field, value)` modifie un champ déclaré `mutable` ; la valeur est vérifiée avec son
  schéma ;
- `event:Cancel()` ou `event:SetCancelled(cancelled)` annule un événement annulable, ou le
  rétablit ;
- `event:IsCancelled()`, `event:GetName()`.

### Ordre

`options.priority` fixe le moment où votre fonction s'exécute :

| Priorité | Usage |
| --- | --- |
| `lowest`, `low` | S'exécute tôt ; les écouteurs suivants peuvent remplacer vos modifications |
| `normal` (par défaut) | |
| `high`, `highest` | S'exécute tard, pour avoir le dernier mot |
| `monitor` | S'exécute en dernier, pour observer le résultat final. Ne peut ni modifier ni annuler l'événement |

Les écouteurs de même priorité s'exécutent dans l'ordre où ils ont été ajoutés. Avec
`ignore_cancelled = true`, votre fonction est ignorée tant que l'événement est annulé.

Quand tous les écouteurs se sont exécutés, l'événement est figé et renvoyé à l'émetteur, qui
lit le résultat : `IsCancelled()` et les valeurs finales des champs.

### Erreurs et nettoyage

Une erreur dans un écouteur est journalisée avec le nom de votre package ; les autres
écouteurs s'exécutent quand même. Écouter deux fois le même événement avec la même fonction
lève une erreur.

`Listen` renvoie un handle : `handle:Release()` arrête l'écoute. Les écouteurs sont retirés à
l'arrêt de votre package, et un événement disparaît avec ses écouteurs à l'arrêt du package
qui le définit.

## Événements de Foundation

Foundation émet ses propres événements dans l'espace de noms `foundation`. Ils signalent ce qui
s'est passé et ne peuvent pas être annulés, sauf `foundation:command`.

| Événement | Champs | Quand |
| --- | --- | --- |
| `foundation:package_ready` | `package`, `version` | Un package est prêt |
| `foundation:package_failed` | `package`, `version`, `message` | Un package a échoué |
| `foundation:package_disabled` | `package`, `version`, `reason` | Un package a été désactivé ; `reason` vaut `unload`, `dependency_disabled`, `dependency_failed` ou `foundation_stopping` |
| `foundation:config_reloaded` | `package`, `path`, `changed`, `pending` | Un fichier de configuration a été rechargé (`changed` et `pending` listent des clés de réglages) |
| `foundation:command` | `command`, `owner`, `sender`, `name`, `arguments` | Une commande va s'exécuter. **Annulable** |
| `foundation:command_completed` | les mêmes, et `outcome` | Une commande s'est exécutée ; `outcome` vaut `success` ou `failure` |

Un package ne reçoit pas `package_disabled` pour lui-même : ses écouteurs sont déjà retirés.

Voir la [référence](reference/events.md) pour toutes les méthodes et erreurs.
