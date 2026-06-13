---
title: Quickstart
permalink: /quickstart/
---

## 1. Write a worker

A worker is a `ModuleScript` that returns a function. The pool calls it once per element of the input. It runs inside an isolated actor, so it does not share state with the rest of the game while it executes.

```lua
-- Square.luau
return function(value)
    return value * value
end
```

## 2. Create a pool

Create the pool once and reuse it across calls. Creating a pool spawns the workers and runs a short calibration, so it is not something to do per frame.

```lua
local ParallelFlow = require(game.ReplicatedStorage.ParallelFlow)

local pool = ParallelFlow.createPool({ size = 8 })
```

## 3. Map over data

`map` runs the worker over the list and returns the results in order, plus an errors list (`nil` when nothing failed). It picks sequential or parallel execution on its own.

```lua
local Square = game.ReplicatedStorage.Workers.Square

local numbers = {}
for i = 1, 5000 do numbers[i] = i end

local results, errors = pool:map(numbers, Square)

print(results[1])     --> 1
print(results[5000])  --> 25000000
```

## 4. Many independent jobs

When the work is not a single list but a set of separate jobs, use `submit`. It returns a Future immediately and coalesces all submissions made in the same frame into roughly one round trip per worker. `awaitAll` waits for a list of Futures and returns the results in order.

```lua
local futures = {}
for i = 1, 100 do
    futures[i] = pool:submit(Square, i)
end

local results = pool:awaitAll(futures)
```

## 5. Release the pool

When a pool is no longer needed, destroy it to free its workers.

```lua
pool:destroy()
```

## Next steps

- [General](../general/) for every configuration option.
- [Mapping](../mapping/) for `filter`, `Pipeline`, and the binary paths.
- [Async & Futures](../async/) for the non-blocking API.
- [Error handling](../errors/) for partial results and strict mode.
