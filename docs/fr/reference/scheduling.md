# Référence de l'API : minuteries et futures

Disponibilité : **serveur**. Introduit en 0.1.0 (API 0.1). Statut : préliminaire ; l'API peut
changer avant la 1.0.

Guide : [Minuteries et travail asynchrone](../scheduling.md).

Tout ce qui est décrit ici appartient au package dont le contexte l'a créé. Quand le package
est désactivé, ses tâches sont annulées, ses fonctions debounce et throttle s'arrêtent et ses
futures en attente sont annulées. Les fonctions fournies par le package s'exécutent sous
protection : une erreur est journalisée sous la forme `<kind> callback of <package> failed`
avec sa trace d'appels.

Les délais sont des entiers en millisecondes, de 0 à 2147483647. Ils lèvent
`invalid_argument` s'ils ne sont pas entiers et `invalid_value` s'ils sont hors limites. Toutes
les méthodes ci-dessous lèvent `invalid_state` si le contexte n'est plus actif.

## Minuteries

### `context:NextTick(fn)`

Exécute `fn()` une fois au prochain tick du serveur. Renvoie une [tâche](#tâche).

### `context:Delay(milliseconds, fn)`

Exécute `fn()` une fois après `milliseconds`. Renvoie une [tâche](#tâche).

### `context:Repeat(milliseconds, fn, options)`

Exécute `fn()` toutes les `milliseconds` (10 au minimum). Renvoie une [tâche](#tâche).

- Renvoyer `false` depuis `fn` arrête la tâche (état `completed`).
- Après `options.max_failures` erreurs consécutives (3 par défaut), la tâche s'arrête (état
  `failed`) et un avertissement est journalisé. Une exécution réussie remet le compte à zéro.

### Tâche

| Méthode | Description |
| --- | --- |
| `task:Cancel()` | Arrête la tâche. Renvoie `true` si elle était encore active |
| `task:IsActive()` | `true` tant que l'état est `scheduled` ou `running` |
| `task:GetState()` | `"scheduled"`, `"running"`, `"completed"`, `"failed"` ou `"cancelled"` |
| `task:GetRuns()` | Nombre de fois où `fn` a démarré |

Une tâche à exécution unique se termine `completed`, ou `failed` si `fn` a levé une erreur.

### `context:Debounce(milliseconds, fn)`

Renvoie un objet avec :

- `Trigger(...)` : (re)lance le délai ; à son terme, `fn` s'exécute avec les arguments du
  dernier `Trigger`. Renvoie `false` une fois le package désactivé.
- `Cancel()` : annule l'exécution en attente, s'il y en a une. Les appels suivants de
  `Trigger` fonctionnent de nouveau.

### `context:Throttle(milliseconds, fn)`

Renvoie un objet avec :

- `Trigger(...)` : exécute `fn(...)` immédiatement, sauf si elle s'est exécutée il y a moins de
  `milliseconds`. Renvoie `true` quand `fn` s'est exécutée.
- `Cancel()` : arrête définitivement la fonction ; `Trigger` renvoie ensuite `false`.

## Futures

### `context:Future(executor)`

Renvoie une future en attente. `executor`, facultatif, est appelé immédiatement avec
`resolve(value)` et `reject(err)`. S'il lève une erreur, la future est rejetée avec
`async_failed`. Sans exécuteur, réglez la future avec ses propres méthodes.

### `context:All(futures)`

Renvoie une future résolue avec le tableau des résultats, dans l'ordre de `futures`, une fois
toutes résolues. Elle est rejetée avec la première erreur, et annulée si l'une d'elles est
annulée. Un tableau vide est résolu immédiatement avec `{}`. Lève `invalid_argument` si un
élément n'est pas une future.

### Méthodes des futures

| Méthode | Description |
| --- | --- |
| `future:Resolve(value)` | Règle la future comme résolue. Renvoie `false` si elle est déjà réglée |
| `future:Reject(err)` | Règle la future comme rejetée. Renvoie `false` si elle est déjà réglée |
| `future:Cancel()` | Règle la future comme annulée ; les fonctions `Then`, `Catch` et `Finally` en attente ne s'exécutent jamais. Renvoie `false` si elle est déjà réglée |
| `future:GetState()` | `"pending"`, `"resolved"`, `"rejected"` ou `"cancelled"` |
| `future:IsDone()` | `true` une fois réglée |
| `future:GetValue()` | Valeur d'une future résolue |
| `future:GetError()` | Erreur d'une future rejetée |
| `future:Then(on_resolved, on_rejected)` | Renvoie une nouvelle future, voir plus bas |
| `future:Catch(on_rejected)` | Équivaut à `Then(nil, on_rejected)` |
| `future:Finally(fn)` | Renvoie une nouvelle future réglée comme celle-ci, après l'exécution de `fn()`. `fn` ne s'exécute pas en cas d'annulation |
| `future:Timeout(milliseconds)` | Rejette cette future avec une erreur `timeout` si elle est encore en attente après `milliseconds`. Renvoie la même future |

`Then` renvoie une nouvelle future réglée avec le résultat de la fonction qui s'exécute :

- la valeur renvoyée par la fonction la résout ; une future renvoyée est attendue ;
- une erreur levée par la fonction la rejette avec `async_failed` (`err.cause` contient
  l'erreur d'origine) ;
- sans fonction pour ce résultat, celui-ci est transmis tel quel ;
- une future annulée l'annule.

Les fonctions s'exécutent quand la future est réglée, ou immédiatement si elle l'est déjà. Les
arguments sont vérifiés : une fonction qui n'en est pas une lève `invalid_argument`.
