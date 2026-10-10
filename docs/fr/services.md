# Services et capacités

Un **service** est un objet qu'un package offre aux autres sous un nom partagé, par exemple
`economy:bank`. Le nom désigne un contrat : les méthodes et leur sens. N'importe quel package
peut le fournir, et les packages qui l'utilisent ne dépendent pas de celui qui le fournit : un
serveur peut ainsi remplacer son package d'économie sans modifier les autres.

Une **capacité** indique que quelque chose est disponible, par exemple
`economy:offline-payments`. Elle ne transporte aucun objet ; les packages la consultent pour
décider de ce qu'ils proposent.

## Exemple

Un package fournit le service `economy:bank` et déclare une capacité :

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

Un autre package exige le service, suit son fournisseur et consulte la capacité :

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

Sortie, le package fournisseur s'appelant `foundation-example-coins` :

```
salaries are paid through foundation-example-coins
paid 100 to alex, balance 100
offline players are paid too
```

## Fournir un service

`context:ProvideService(name, version, implementation, options)` :

- `name` s'écrit `<espace de noms>:<nom>`. L'espace de noms désigne le contrat, pas votre
  package : plusieurs packages peuvent fournir `economy:bank`. Sans espace de noms,
  l'identifiant de votre package est utilisé ;
- `version` est la version du contrat que vous implémentez, `"<majeure>.<mineure>"`. Augmentez
  la version mineure quand vous ajoutez des méthodes, la majeure quand des méthodes existantes
  changent ;
- `implementation` est une table de champs et de méthodes ;
- `options.priority` (entier, 0 par défaut) départage les fournisseurs : le plus élevé
  l'emporte.

Deux packages ne peuvent pas fournir le même service, à la même version majeure, avec la même
priorité : choisissez des priorités différentes, pour que le choix ne dépende jamais de l'ordre
de chargement. Pour remplacer votre propre fournisseur, rappelez `ProvideService` avec
`{ replace = true }`.

Le service est retiré à l'arrêt de votre package, ou avec le handle renvoyé :
`handle:Release()`.

## Utiliser un service

`context:GetService(name, version)` renvoie le service du meilleur fournisseur, et une table
`info` contenant `provider`, `version` et `priority` ; ou `nil` quand aucun fournisseur
compatible n'existe.

`version` sélectionne les fournisseurs compatibles : `"1"` accepte toute version 1.x, `"1.2"`
accepte la 1.2 et les versions 1.x suivantes, `nil` accepte toute version.
`context:GetServices(name, version)` les renvoie tous, le meilleur en premier.

L'objet renvoyé transmet chaque appel au fournisseur. Une fois le fournisseur arrêté, l'utiliser
lève une erreur qui le nomme, au lieu d'appeler un package qui ne fonctionne plus. Redemandez le
service, ou suivez les changements avec `OnService`.

### Suivre le fournisseur

`context:OnService(name, version, fn)` appelle `fn(service, info)` tout de suite si un
fournisseur compatible existe, puis à chaque changement du meilleur fournisseur compatible : un
meilleur apparaît, l'actuel s'arrête et un autre prend le relais, ou il n'en reste aucun, auquel
cas `fn(nil)` est appelée.

### Exiger un service

Listez dans le manifeste les services sans lesquels votre package ne peut pas fonctionner :

```lua
services = {
    { name = "economy:bank", version = "1" },
    { name = "chat:format", optional = true },
}
```

Au moment où votre package va passer prêt, un service exigé sans fournisseur compatible le fait
échouer avec un message clair, au lieu d'un échec plus tard au premier appel. Si le dernier
fournisseur compatible s'arrête pendant que votre package fonctionne, votre package échoue
aussi (ses hooks de désactivation s'exécutent). Les fournisseurs des packages chargés après le
vôtre sont trouvés : la vérification a lieu une fois tous les packages chargés. Les services
facultatifs ne servent qu'aux diagnostics.

## Capacités

Déclarez les capacités dans le manifeste :

```lua
capabilities = { "chat:colors", { name = "chat:emotes", version = "2.1" } }
```

Une capacité est disponible tant que le package qui la déclare est prêt. Vérifiez-la avec
`Foundation.Capabilities.Has(name, version)`, ou listez les packages qui la déclarent avec
`Foundation.Capabilities.Providers(name, version)`. Les versions fonctionnent comme pour les
services.

Pour vérifier une capacité depuis votre hook `OnReady`, chargez-vous après le package qui la
déclare : indiquez-le dans les `packages_requirements` de votre `Package.toml`.

## Événements

| Événement | Champs | Quand |
| --- | --- | --- |
| `foundation:service_available` | `service`, `provider`, `version`, `priority` | Un fournisseur a été ajouté |
| `foundation:service_unavailable` | les mêmes | Un fournisseur a été retiré |
| `foundation:capability_available` | `capability`, `package`, `version` | Un package déclarant la capacité est devenu prêt |
| `foundation:capability_unavailable` | les mêmes | Ce package s'est arrêté ou a échoué |

Les administrateurs voient les services, fournisseurs, consommateurs et capacités avec
[`foundation services`](administration.md#services). Voir la
[référence](reference/services.md) pour toutes les méthodes et erreurs.
