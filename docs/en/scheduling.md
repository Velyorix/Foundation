# Timers and asynchronous work

The context of your package creates timers and futures that belong to the package: when the
package stops, its pending timers are cancelled and its pending futures are abandoned, so no
callback of a stopped package runs afterwards. An error in a callback is logged with the
package name and does not stop the other callbacks.

## Timers

| Method | Runs `fn` |
| --- | --- |
| `context:NextTick(fn)` | Once, on the next server tick |
| `context:Delay(ms, fn)` | Once, after `ms` milliseconds |
| `context:Repeat(ms, fn, options)` | Every `ms` milliseconds (10 at least), until `fn` returns `false` or the task is cancelled |
| `context:Debounce(ms, fn)` | `ms` milliseconds after the last call of `Trigger` |
| `context:Throttle(ms, fn)` | At once when `Trigger` is called, at most once every `ms` milliseconds |

`NextTick`, `Delay` and `Repeat` return a task: `task:Cancel()` stops it,
`task:IsActive()` tells whether it can still run, `task:GetState()` and `task:GetRuns()` describe
it.

A repeating task whose function raises an error 3 times in a row is stopped, and a warning is
logged. Pass `{ max_failures = n }` as `options` to change that number.

### Debounce and throttle

Both return an object whose `Trigger(...)` method you call instead of the function:

- **debounce** waits for calls to stop: each `Trigger` restarts the delay, and `fn` runs once,
  with the arguments of the last `Trigger`. Use it to save after a burst of changes.
- **throttle** runs `fn` immediately, then ignores `Trigger` until `ms` milliseconds have
  passed. `Trigger` returns `true` when `fn` ran. Use it to limit how often something can
  happen.

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

Three `autosave:changed` events in quick succession print:

```
unsaved changes: 1
saved 3 change(s)
```

## Futures

A future stands for a result that arrives later, such as the rows of a database query. It
lets you chain what happens next and handle errors in one place, instead of nesting
callbacks.

`context:Future(executor)` creates one. `executor` runs at once and receives two functions:
call `resolve(value)` when the result is there, or `reject(error)` when the operation failed.
This turns any engine function that takes a callback into a future:

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

Output, one announcement per second:

```
loaded 3 announcements
announcement: Welcome to the server!
announcement: Read the rules with /rules.
announcement: Have fun!
```

### Chaining

- `future:Then(on_resolved, on_rejected)` returns a new future, settled with what the
  function returns. If the function returns a future, the new future waits for it, so steps
  can be chained without nesting.
- `future:Catch(fn)` handles an error from any earlier step. What `fn` returns becomes the
  result, so the chain can continue.
- `future:Finally(fn)` runs `fn` on success and on error, and passes the outcome on unchanged.
- `future:Timeout(ms)` rejects the future with a `timeout` error if it is still pending after
  `ms` milliseconds.
- `context:All({ a, b, c })` waits for all the futures and gives their results in the same
  order, or the first error.

An error raised inside `Then`, `Catch` or the executor rejects the next future with an
`async_failed` error and is logged with the package name.

Functions given to `Then`, `Catch` and `Finally` run as soon as the future is settled, or at
once if it already is. A future settles only once: further calls to `resolve` or `reject`
are ignored and return `false`.

See the [reference](reference/scheduling.md) for every method.
