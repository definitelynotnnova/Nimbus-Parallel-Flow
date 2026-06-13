---
title: General
permalink: /general/
---

A pool owns a set of worker actors and the scheduler that feeds them. Create one, reuse it for many calls, and destroy it when done.

## Creating a pool

```lua
local pool = ParallelFlow.createPool(config?)
```

`config` is optional. Creating a pool spawns the workers, waits for each to bind its handlers, and runs a short latency calibration, so it should be done once and kept, not created per call.

## Configuration

```lua
ParallelFlow.createPool({
    size                  = 4,
    timeout               = 10,
    adaptive              = true,
    loadBalanceFactor     = 1,
    errorMode             = "continue",
    maxFrameMs            = 6,
    maxChunkSize          = nil,
    smallDatasetThreshold = 50,
    sharedTableThreshold  = 1000,
    nestedDataThreshold   = 10000,
    onError               = nil,
})
```

| Option | Default | Description |
|--------|---------|-------------|
| `size` | 4 | Number of workers. Clamped to 64 on the server and 3 on the client. |
| `timeout` | 10 | Seconds before a job that has not returned is dropped and counted as timed out. |
| `adaptive` | true | When true, the sequential-versus-parallel choice is made from a measured cost model. When false, it uses the fixed `smallDatasetThreshold`. |
| `loadBalanceFactor` | 1 | Chunks emitted per worker. A value above 1 produces more, smaller chunks, which improves balancing under uneven work at the cost of more round trips. |
| `errorMode` | "continue" | `"continue"` collects per-element errors and returns partial results. `"strict"` raises on the first failed element. See [Error handling](../errors/). |
| `maxFrameMs` | 6 | Per-frame time budget for dispatching chunks. The dispatch loop yields when it exceeds this, so a large input does not stall a frame. |
| `maxChunkSize` | nil | Upper bound on elements per chunk. `nil` means no explicit cap. |
| `smallDatasetThreshold` | 50 | When `adaptive` is off, inputs smaller than this run sequentially. |
| `sharedTableThreshold` | 1000 | Inputs at or above this size may be passed through a `SharedTable` instead of copied per chunk. |
| `nestedDataThreshold` | 10000 | The `SharedTable` threshold used when the elements are themselves tables. |
| `onError` | nil | Called with a descriptive string when a job fails, times out, or a chunk is lost. |

The two values that most affect behavior are `adaptive` and `size`. `adaptive` decides whether a given input is worth parallelizing at all; `size` sets the ceiling on speedup for inputs that are.

## Preloading a module

```lua
pool:prewarm(module)
```

Loads and caches the module on every worker so the first real call does not pay the require and synchronization cost. The map family calls this on its own the first time it sees a module, so explicit `prewarm` is only useful to move that one-time cost out of a latency-sensitive moment.

## Pool information

```lua
pool:getSize()        -- number of workers
pool:getFreeCount()   -- workers currently idle
pool:isClientPool()   -- true if the pool runs on the client
```

## Telemetry

`getStats` returns a snapshot of the pool's current state and the values the cost model has learned. It is cheap to call and safe to poll from a debug overlay.

```lua
local stats = pool:getStats()
```

| Field | Description |
|-------|-------------|
| `size` | Number of workers in the pool. |
| `free` | Workers idle at the moment of the call. |
| `busy` | Workers currently running a job (`size - free`). |
| `queued` | Threads waiting for a worker to free up. |
| `dispatched` | Total jobs sent since the pool was created. |
| `completed` | Jobs that returned successfully. |
| `failed` | Jobs that failed. |
| `timedOut` | Jobs dropped after exceeding `timeout`. |
| `avgRoundTripMs` | Smoothed round-trip time of completed jobs, including their compute. Observability only. |
| `latencyFloorMs` | The measured pure round-trip floor, from the startup calibration. This is the value the scheduler uses to decide sequential versus parallel. |
| `perWorker` | A list of how many jobs each worker has handled, by index. |
| `lastRunMs` | A list of the last measured compute time per worker, read from the worker actors. |
| `costModel` | A map of module name to the learned per-element cost in milliseconds. |

`costModel` and `latencyFloorMs` are what drive the adaptive decision. The per-element cost is filled in the first time a module runs through `map`; before that the entry is absent. `perWorker` shows how evenly work has been spread, which is the signal for tuning `loadBalanceFactor`.

```lua
local stats = pool:getStats()

print(string.format("latency floor: %.2f ms", stats.latencyFloorMs))

for moduleName, costMs in stats.costModel do
    print(string.format("%s: %.4f ms/element", moduleName, costMs))
end
```
