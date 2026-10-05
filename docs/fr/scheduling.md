# Minuteries et travail asynchrone

Le contexte de votre package crée des minuteries et des futures qui appartiennent au package :
quand le package s'arrête, ses minuteries en attente sont annulées et ses futures en attente
sont abandonnées, si bien qu'aucun callback d'un package arrêté ne s'exécute ensuite. Une
erreur dans un callback est journalisée avec le nom du package et n'empêche pas les autres
callbacks de s'exécuter.

## Minuteries

| Méthode | Exécute `fn` |
| --- | --- |
| `context:NextTick(fn)` | Une fois, au prochain tick du serveur |
| `context:Delay(ms, fn)` | Une fois, après `ms` millisecondes |
| `context:Repeat(ms, fn, options)` | Toutes les `ms` millisecondes (10 au minimum), jusqu'à ce que `fn` renvoie `false` ou que la tâche soit annulée |
| `context:Debounce(ms, fn)` | `ms` millisecondes après le dernier appel de `Trigger` |
| `context:Throttle(ms, fn)` | Immédiatement à l'appel de `Trigger`, au plus une fois toutes les `ms` millisecondes |

`NextTick`, `Delay` et `Repeat` renvoient une tâche : `task:Cancel()` l'arrête,
`task:IsActive()` indique si elle peut encore s'exécuter, `task:GetState()` et
`task:GetRuns()` la décrivent.

Une tâche répétée dont la fonction lève une erreur 3 fois de suite est arrêtée, et un
avertissement est journalisé. Passez `{ max_failures = n }` dans `options` pour changer ce
nombre.

### Debounce et throttle

Les deux renvoient un objet dont vous appelez la méthode `Trigger(...)` à la place de la
fonction :

- **debounce** attend que les appels cessent : chaque `Trigger` relance le délai, et `fn`
  s'exécute une fois, avec les arguments du dernier `Trigger`. Utile pour enregistrer après
  une rafale de modifications.
- **throttle** exécute `fn` immédiatement, puis ignore `Trigger` jusqu'à ce que `ms`
  millisecondes se soient écoulées. `Trigger` renvoie `true` quand `fn` s'est exécutée. Utile
  pour limiter la fréquence d'une action.

<!-- example: tests/integration/packages/foundation-example-autosave/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Autosave",
})

local unsaved = 0

local save = context:Debounce(500, function()
    Console.Log("saved %d change(s)", unsaved)
    unsaved = 0
end)

local report = context:Throttle(2000, function(count)
    Console.Log("unsaved changes: %d", count)
end)

local function on_changed()
    unsaved = unsaved + 1
    report:Trigger(unsaved)
    save:Trigger()
end

Events.Subscribe("autosave:changed", on_changed)
context:Track("event_listener", function()
    Events.Unsubscribe("autosave:changed", on_changed)
end)
```

Trois événements `autosave:changed` rapprochés affichent :

```
unsaved changes: 1
saved 3 change(s)
```

## Futures

Une future représente un résultat qui arrivera plus tard, comme les lignes d'une requête en
base de données. Elle permet d'enchaîner la suite et de gérer les erreurs à un seul endroit,
au lieu d'imbriquer des callbacks.

`context:Future(executor)` en crée une. `executor` s'exécute immédiatement et reçoit deux
fonctions : appelez `resolve(value)` quand le résultat est disponible, ou `reject(error)` quand
l'opération a échoué. Toute fonction du moteur qui prend un callback devient ainsi une future :

<!-- example: tests/integration/packages/foundation-example-announcer/Server/Index.lua -->
```lua
local context = Foundation.Register(Package, {
    api = "0.1",
    name = "Announcer",
})

local db = Database(DatabaseEngine.SQLite, "db=:memory:")
db:Execute("CREATE TABLE announcements (position INTEGER, text TEXT)")
db:Execute([[INSERT INTO announcements VALUES
    (1, 'Welcome to the server!'),
    (2, 'Read the rules with /rules.'),
    (3, 'Have fun!')]])

local function select_async(query)
    return context:Future(function(resolve, reject)
        db:SelectAsync(query, function(rows, err)
            if err then
                reject(err)
            else
                resolve(rows)
            end
        end)
    end)
end

local function announce_all(rows)
    local index = 0
    context:Repeat(1000, function()
        index = index + 1
        Console.Log("announcement: %s", rows[index].text)
        if index == #rows then
            return false
        end
    end)
end

context:OnReady(function()
    select_async("SELECT text FROM announcements ORDER BY position")
        :Timeout(5000)
        :Then(function(rows)
            Console.Log("loaded %d announcements", #rows)
            announce_all(rows)
        end)
        :Catch(function(err)
            Console.Error("could not load announcements: %s", tostring(err))
        end)
end)
```

Sortie, une annonce par seconde :

```
loaded 3 announcements
announcement: Welcome to the server!
announcement: Read the rules with /rules.
announcement: Have fun!
```

### Enchaînement

- `future:Then(on_resolved, on_rejected)` renvoie une nouvelle future, réglée avec ce que
  renvoie la fonction. Si la fonction renvoie une future, la nouvelle future l'attend : les
  étapes s'enchaînent sans imbrication.
- `future:Catch(fn)` traite une erreur de n'importe quelle étape précédente. Ce que renvoie
  `fn` devient le résultat, et la chaîne peut continuer.
- `future:Finally(fn)` exécute `fn` en cas de succès comme d'erreur, et transmet le résultat
  sans le modifier.
- `future:Timeout(ms)` rejette la future avec une erreur `timeout` si elle est toujours en
  attente après `ms` millisecondes.
- `context:All({ a, b, c })` attend toutes les futures et donne leurs résultats dans le même
  ordre, ou la première erreur.

Une erreur levée dans `Then`, `Catch` ou dans l'exécuteur rejette la future suivante avec une
erreur `async_failed` et est journalisée avec le nom du package.

Les fonctions passées à `Then`, `Catch` et `Finally` s'exécutent dès que la future est réglée,
ou immédiatement si elle l'est déjà. Une future n'est réglée qu'une fois : les appels suivants
de `resolve` ou `reject` sont ignorés et renvoient `false`.

Voir la [référence](reference/scheduling.md) pour toutes les méthodes.
