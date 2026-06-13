---
title: Async & Futures
permalink: /async/
---

The blocking methods on [Mapping](../mapping/) each have a non-blocking counterpart that returns a Future. There is also `submit`, built for many independent jobs rather than a single collection.

## submit

```lua
local future = pool:submit(module, arg)
```

Queues one job and returns a Future immediately, without blocking. Submissions made within the same frame are buffered and coalesced: instead of one round trip per job, the buffered jobs are split across the workers and sent as roughly one message per worker. This is what makes a burst of small independent jobs cheap, where a loop of `dispatch` would pay a full round trip each.

```lua
local futures = {}
for i = 1, 100 do
    futures[i] = pool:submit(MyJob, i)
end

local results = pool:awaitAll(futures)
```

## awaitAll

```lua
local results = pool:awaitAll(futures)
```

Waits for a list of Futures and returns their results in the same order.

## Async map variants

Each returns a Future that resolves to the same value its blocking form would return.

```lua
local future = pool:mapAsync(list, module)
local future = pool:mapTablesAsync(list, module)
local future = pool:FilterAsync(list, module)
local future = pool:PipelineAsync(data, steps)

local results = future:Await()
```

These are useful when you want to start parallel work and continue on the calling thread, collecting the result later.

## Futures

A Future represents a job that has not finished yet. All of the async methods and `submit` return one.

| Method | Description |
|--------|-------------|
| `future:Await()` | Yields until the job settles and returns its result (`nil` if it was cancelled or failed). |
| `future:Wait()` | Yields until the job settles, returns nothing. |
| `future:OnComplete(fn)` | Registers `fn(result, ok)` to run once the job finishes. Fires immediately if already settled. |
| `future:Cancel()` | Cancels the job. A result that arrives after cancellation is ignored. |
| `future:IsCompleted()` | True once the job has finished. |
| `future:IsCancelled()` | True if the job was cancelled. |

Waiting is event-based, not polling: a thread parked in `Await` or `Wait` is resumed when the job settles or is cancelled.

```lua
local future = pool:mapAsync(data, MyWorker)

future:OnComplete(function(results, ok)
    if ok then
        print("done with", #results, "results")
    end
end)

-- elsewhere, if the result is no longer needed
future:Cancel()
```

When a Future carries a failure, its `errors` field holds the structured error list described in [Error handling](../errors/).
