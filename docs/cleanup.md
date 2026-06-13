---
title: Cleanup
permalink: /cleanup/
---

## Destroying a pool

```lua
pool:destroy()
```

Releases the pool and everything it owns: it cancels any Futures still waiting in the submit buffer, tears down the result event, and destroys all worker actors. After `destroy`, the pool is dead and any further call that needs a worker raises `pool is destroyed`.

`destroy` is idempotent; calling it twice is harmless.

```lua
local pool = ParallelFlow.createPool()

-- ... use the pool ...

pool:destroy()

-- pool:dispatch(...) here would raise "pool is destroyed"
```

## When to destroy

A pool is meant to live across many calls, so destroy it on the lifecycle boundary that owns it, not after each batch. Typical points:

- A pool tied to a system: destroy it when that system shuts down.
- A pool tied to a player or a session on the server: destroy it when the player leaves.
- A short-lived pool for one heavy job: destroy it once the job's results are collected.

Leaving a pool alive keeps its worker actors resident, which is the intended steady state. The cost to avoid is the opposite: creating and destroying pools frequently, since each creation spawns actors and runs a calibration.

## Cancelling work

A single in-flight operation is cancelled through its Future rather than by destroying the pool.

```lua
local future = pool:mapAsync(data, MyWorker)

future:Cancel()
```

After cancellation, a result that still arrives from a worker is discarded, and `Await` returns `nil`. The worker itself returns to the pool and is reused. See [Async & Futures](../async/) for the full Future surface.

## Timeouts

A job that does not return within `timeout` seconds (10 by default) is dropped, counted in `timedOut`, and reported through `onError` if one is set. The worker is freed so the pool keeps running; a single stuck job does not block the rest. Raise `timeout` for legitimately long jobs, and watch `timedOut` in the telemetry on the [General](../general/) page to tell real hangs from a budget set too low.
