# API reference: timers and futures

Availability: **server**. Introduced in 0.1.0 (API 0.1). Status: pre-release; the API may
change before 1.0.

Guide: [Timers and asynchronous work](../scheduling.md).

Everything on this page belongs to the package whose context created it. When the package is
disabled, its tasks are cancelled, its debounced and throttled functions stop, and its pending
futures are cancelled. Functions supplied by the package run guarded: an error is logged as
`<kind> callback of <package> failed` with its stack trace.

Delays are integers in milliseconds, from 0 to 2147483647. They raise `invalid_argument` when
not an integer and `invalid_value` when out of range. Every method below raises
`invalid_state` if the context is no longer active.

## Timers

### `context:NextTick(fn)`

Runs `fn()` once on the next server tick. Returns a [task](#task).

### `context:Delay(milliseconds, fn)`

Runs `fn()` once after `milliseconds`. Returns a [task](#task).

### `context:Repeat(milliseconds, fn, options)`

Runs `fn()` every `milliseconds` (10 at least). Returns a [task](#task).

- Returning `false` from `fn` stops the task (state `completed`).
- After `options.max_failures` consecutive errors (default 3) the task stops (state
  `failed`) and a warning is logged. A successful run resets the count.

### Task

| Method | Description |
| --- | --- |
| `task:Cancel()` | Stops the task. Returns `true` if it was still active |
| `task:IsActive()` | `true` while the state is `scheduled` or `running` |
| `task:GetState()` | `"scheduled"`, `"running"`, `"completed"`, `"failed"` or `"cancelled"` |
| `task:GetRuns()` | Number of times `fn` started |

A one-shot task ends `completed`, or `failed` if `fn` raised an error.

### `context:Debounce(milliseconds, fn)`

Returns an object with:

- `Trigger(...)`: (re)starts the delay; when it ends, `fn` runs with the arguments of the
  last `Trigger`. Returns `false` once the package is disabled.
- `Cancel()`: cancels the pending run, if any. Later `Trigger` calls work again.

### `context:Throttle(milliseconds, fn)`

Returns an object with:

- `Trigger(...)`: runs `fn(...)` at once unless it ran less than `milliseconds` ago. Returns
  `true` when `fn` ran.
- `Cancel()`: stops the throttled function for good; `Trigger` then returns `false`.

## Futures

### `context:Future(executor)`

Returns a pending future. `executor`, optional, is called at once with `resolve(value)` and
`reject(err)`. If it raises an error, the future is rejected with `async_failed`. Without an
executor, settle the future with its own methods.

### `context:All(futures)`

Returns a future resolved with the array of the results, in the order of `futures`, once
they are all resolved. It is rejected with the first error, and cancelled if one of them is
cancelled. An empty array resolves at once with `{}`. Raises `invalid_argument` if an item
is not a future.

### Future methods

| Method | Description |
| --- | --- |
| `future:Resolve(value)` | Settles as resolved. Returns `false` if already settled |
| `future:Reject(err)` | Settles as rejected. Returns `false` if already settled |
| `future:Cancel()` | Settles as cancelled; pending `Then`, `Catch` and `Finally` functions never run. Returns `false` if already settled |
| `future:GetState()` | `"pending"`, `"resolved"`, `"rejected"` or `"cancelled"` |
| `future:IsDone()` | `true` once settled |
| `future:GetValue()` | Value of a resolved future |
| `future:GetError()` | Error of a rejected future |
| `future:Then(on_resolved, on_rejected)` | Returns a new future, see below |
| `future:Catch(on_rejected)` | Same as `Then(nil, on_rejected)` |
| `future:Finally(fn)` | Returns a new future settled like this one, after `fn()` ran. `fn` does not run on cancellation |
| `future:Timeout(milliseconds)` | Rejects this future with a `timeout` error if still pending after `milliseconds`. Returns the same future |

`Then` returns a new future settled with the outcome of the handler that runs:

- the handler's return value resolves it; a returned future is waited for;
- an error raised by the handler rejects it with `async_failed` (`err.cause` holds the
  original error);
- without a handler for the outcome, the outcome is passed on unchanged;
- a cancelled future cancels it.

Handlers run when the future settles, or at once when it is already settled. Arguments
are checked: a handler that is not a function raises `invalid_argument`.
