# Nimbus Parallel Flow

A parallel processing library for Roblox. It distributes work across worker `Actor`s, runs it in parallel, and returns the results in order. The actor messaging, binary serialization, and thread synchronization are handled internally.

A worker is a plain function applied to each element of an input. The library decides whether to run that work sequentially or split it across the workers, based on a cost estimate. Small inputs run sequentially, because the round-trip cost of crossing the actor boundary is higher than the compute. Larger inputs are chunked across the pool.

```lua
local ParallelFlow = require(ReplicatedStorage.ParallelFlow)
local pool = ParallelFlow.createPool()

local results = pool:map({ 1, 2, 3, 4 }, MyWorker)
```

Current version: V20.

## Table of contents

- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [Workers](#workers)
- [API reference](#api-reference)
- [Configuration](#configuration)
- [Error handling](#error-handling)
- [Supported types](#supported-types)
- [Performance](#performance)
- [Demos](#demos)
- [Internals](#internals)
- [License](#license)

## Overview

Roblox exposes `Actor`s for running code in parallel, but using them directly requires a fair amount of boilerplate: serializing data to cross the actor boundary, sending messages with `SendMessage`, receiving responses through a `BindableEvent`, reassembling results in order, and synchronizing and desynchronizing threads at the right points. For small workloads the round trip also costs more than the computation itself, so parallelizing unconditionally can be slower than a sequential loop.

This library implements that layer once. It measures the per-element cost of a worker and the round-trip latency of the pool, and uses those two values to decide whether parallelizing a given input is worthwhile.

## Installation

The library is distributed as a single assembled package. It is inserted as one unit; there are no scripts to place individually and no internal structure to assemble.

1. Obtain the package (the Creator Store model or the `.rbxm` file).
2. Insert it into `ReplicatedStorage`. It contains the serializer, the codecs, and the engine. The internal structure is not meant to be modified.
3. Require it where needed:

```lua
local ParallelFlow = require(game.ReplicatedStorage.ParallelFlow)
```

With Rojo or Wally, point the dependency at `ReplicatedStorage.ParallelFlow`.

The library runs on both the server (up to 64 workers) and the client (up to 3, which is the platform limit).

## Usage

Work is dispatched through a pool. Create one, send work to it, and destroy it when it is no longer needed.

```lua
local ParallelFlow = require(game.ReplicatedStorage.ParallelFlow)

-- create the pool once and reuse it
local pool = ParallelFlow.createPool({ size = 8 })

-- a worker is a ModuleScript that returns a function
local Square = game.ReplicatedStorage.Workers.Square

local numbers = {}
for i = 1, 5000 do numbers[i] = i end

local results, errors = pool:map(numbers, Square)

print(results[1])     --> 1
print(results[5000])  --> 25000000

pool:destroy()
```

For many independent jobs that are not a single list, use `submit`. It returns a Future immediately and coalesces all submissions made within the same frame into one round trip per worker:

```lua
local futures = {}
for i = 1, 100 do
    futures[i] = pool:submit(MyJob, i)
end

local results = pool:awaitAll(futures)
```

## Workers

A worker is a `ModuleScript` that returns a function. The pool calls it once per element of the input.

```lua
-- Square.luau
return function(value)
    return value * value
end
```

The function runs inside an isolated actor and does not share state with the rest of the game while it executes. It receives one element and returns one result.

Parallelization is most effective when the worker performs real computation per element (physics, geometry, CFrame transforms), since that is where the cost of splitting work across threads is offset. See `DemoEnjambre/BoidWorker.luau` for a worker that implements flocking.

## API reference

### Creating a pool

`ParallelFlow.createPool(config?)` returns a Pool. The config is optional.

### Running work

| Method | Description |
|--------|-------------|
| `pool:map(list, module)` | Runs the worker over the list. Returns `results, errors`. Chooses sequential or parallel automatically. |
| `pool:Map(data, module)` | Same, but selects the path based on the data type (list, Vector3, buffer). |
| `pool:mapTables(list, module)` | Like `map`, but always parallel. |
| `pool:dispatch(module, data)` | Runs a single element, blocking. Returns the result. |
| `pool:submit(module, arg)` | Queues a single job without blocking. Returns a Future. Submissions in the same frame are coalesced. |
| `pool:awaitAll(futures)` | Waits for a list of Futures and returns their results in order. |
| `pool:filter(list, module)` | Keeps the elements whose worker result is truthy. |
| `pool:Pipeline(data, { modA, modB })` | Runs several modules in sequence, feeding each result into the next. |

### Binary and shared-memory paths

| Method | Description |
|--------|-------------|
| `pool:mapVector3(vectors, module)` | Iterates a list of Vector3. The worker receives `(buffer, offset)`. |
| `pool:mapBuffer(buffer, stride, module)` | Binary input, list output. The worker receives `(buffer, offset)`. |
| `pool:mapBufferOut(buffer, stride, outStride, module)` | Binary input and output, with no serialization on the result. The worker receives `(inBuffer, inOffset, outBuffer, outOffset)`. |
| `pool:mapInto(list, sharedTable, module)` | Writes each result into a SharedTable. Returns nothing. |

### Asynchronous variants

These return a Future instead of blocking: `pool:mapAsync`, `pool:mapTablesAsync`, `pool:FilterAsync`, `pool:PipelineAsync`.

### Futures

| Method | Description |
|--------|-------------|
| `future:Await()` | Yields until done and returns the result. |
| `future:Wait()` | Yields until done, returns nothing. |
| `future:OnComplete(fn)` | Calls `fn(result, ok)` when the job finishes. |
| `future:Cancel()` | Cancels the task. |
| `future:IsCompleted()` | True if the task has finished. |
| `future:IsCancelled()` | True if the task was cancelled. |

### Pool information

| Method | Description |
|--------|-------------|
| `pool:prewarm(module)` | Preloads a module on every worker so the first run does not pay the load cost. |
| `pool:getStats()` | Returns live statistics: size, free workers, dispatched, completed, failed, average round-trip latency, learned per-module cost, and others. |
| `pool:getSize()` | Number of workers. |
| `pool:getFreeCount()` | Number of currently idle workers. |
| `pool:isClientPool()` | True if the pool runs on the client. |
| `pool:destroy()` | Releases the pool and its workers. |

## Configuration

Every value has a default, so `createPool()` with no argument is valid.

```lua
ParallelFlow.createPool({
    size                  = 4,          -- number of workers
    timeout               = 10,         -- seconds before a job is dropped
    adaptive              = true,       -- choose sequential or parallel automatically
    loadBalanceFactor     = 1,          -- chunks per worker (>1 improves balancing, adds overhead)
    errorMode             = "continue", -- "continue" or "strict"
    maxFrameMs            = 6,          -- per-frame time budget
    maxChunkSize          = nil,        -- maximum elements per chunk
    smallDatasetThreshold = 50,         -- run sequentially below this size when adaptive is off
    sharedTableThreshold  = 1000,       -- use a SharedTable above this size
    nestedDataThreshold   = 10000,      -- SharedTable threshold for nested data
    onError               = nil,        -- called with an error message
})
```

`adaptive` controls how the sequential-versus-parallel decision is made. When enabled (the default), the library micro-calibrates the worker and measures the pool's round-trip latency at startup, then decides per call. When disabled, it falls back to the fixed `smallDatasetThreshold`.

## Error handling

`map` and `mapTables` return two values: `results, errors`.

```lua
local results, errors = pool:map(data, MyWorker)

if errors then
    for _, e in errors do
        warn(string.format("element %d failed: %s", e.index, e.message))
    end
end
```

With `errorMode = "continue"` (the default), a failing element does not abort the rest. Its slot in `results` is `nil`, and it appears in `errors` as `{ index, message }`. When nothing fails, `errors` is `nil`.

With `errorMode = "strict"`, the first failing element raises immediately.

## Supported types

The binary serializer crosses the actor boundary with these without additional handling:

`nil`, `boolean`, `number`, `string`, `buffer`, arrays, and maps.

Roblox types: `Vector2`, `Vector3`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Rect`, `Ray`, `Region3`, `NumberRange`, `BrickColor`, `Enum`, `DateTime`, `TweenInfo`, `ColorSequence`, `NumberSequence`, and others.

A custom type is registered once:

```lua
local TypeCodecs = require(game.ReplicatedStorage.ParallelFlow.TypeCodecs)

TypeCodecs.register("MyType", {
    stride = 8,
    encode = function(buffer, offset, value) end,
    decode = function(buffer, offset) return value end,
})
```

## Performance

On large inputs with non-trivial per-element compute, throughput scales with the worker count. The historical benchmarks in the `Results` folder show roughly 5x with 6 workers on inputs of several thousand elements.

On small inputs, the cost of crossing the actor boundary previously set a fixed floor of about 16.5 ms (one frame) regardless of input. That floor dropped to about 6.8 ms after a fix to the workers' initial synchronization. The adaptive mode avoids paying it at all when the input is small enough that sequential execution is faster.

A single large monolithic payload does not benefit from chunking (the "extreme stress" benchmark), because transfer cost dominates. This is a known limit of the model rather than a defect.

The benchmark and verification scripts that produce these figures are not part of the module. They are kept in the repository's docs folder, alongside the debug code, for anyone who wants to review the methodology or reproduce the numbers.

## Demos

Each demo includes a `Driver` (orchestration) and a `Worker` (the parallelized work):

- `DemoEnjambre` a boids swarm with flocking, orbiting the player.
- `DemoCampoFuerza` a force field computed per worker.
- `DemoVortex`, `DemoFractal`, `DemoInteractivo` visual effects that distribute the computation across threads.

The demos and benchmarks live in the repository, not in the distributed package.

## Internals

Four components:

- `ParallelFlow.luau` is the Pool API and scheduler. It decides how to chunk, when to parallelize, and distributes chunks to free workers using a free-list and a wait queue.
- `Serializer.luau` converts data to binary over `buffer` to cross the actor boundary. It uses a re-entrant free-list of encode states, so concurrent encodes do not corrupt a shared buffer.
- `TypeCodecs.luau` packs and unpacks Roblox types and allows registering custom ones.
- `Engine/Runtime.luau` runs inside each actor. It handles the messages (`pf_map`, `pf_batch`, `pf_task`, and others), runs the worker with per-element isolation, and reports the elapsed time.

The adaptive model relies on two measurements: the per-element cost of the worker (micro-calibrated by running it over a sample) and the pool's pure round-trip latency (measured with a calibration round trip at startup). It uses these to estimate whether the computation is hidden under the latency floor or whether splitting it is worthwhile.

## License

MIT. See the copyright notice for terms.

By [@nnoveil](https://github.com/nnoveil), Nimbus Systems, 2026.
