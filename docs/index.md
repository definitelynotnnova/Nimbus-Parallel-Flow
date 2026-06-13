---
title: Home
permalink: /
---

A parallel processing library for Roblox. It distributes work across worker `Actor`s, runs it in parallel, and returns the results in order. The actor messaging, binary serialization, and thread synchronization are handled internally.

A worker is a plain function applied to each element of an input. The library decides whether to run that work sequentially or split it across the workers, based on a measured cost estimate. Small inputs run sequentially, because the round-trip cost of crossing the actor boundary is higher than the compute. Larger inputs are chunked across the pool.

```lua
local ParallelFlow = require(game.ReplicatedStorage.ParallelFlow)
local pool = ParallelFlow.createPool()

local results = pool:map({ 1, 2, 3, 4 }, MyWorker)
```

Current version: V20.

## How it works

Data is serialized into a `buffer` before crossing the actor boundary, then decoded back on the worker side. Moving a buffer between actors is cheaper for the engine than moving structured tables, so the serializer keeps the encode and decode cost low: per-type fast paths, buffer reuse through a re-entrant free-list, and binary paths that skip serialization entirely on the result.

The sequential-versus-parallel decision is made from two measurements taken at runtime. The first is the per-element cost of the worker, micro-calibrated by running it over a small sample. The second is the pool's pure round-trip latency, measured with a calibration round trip when the pool starts. If the worker is cheap enough that the compute hides under the round-trip floor, the work runs sequentially; otherwise it is chunked across the workers.

## Where to go next

The [Quickstart](quickstart/) walks through a worker and a pool from scratch. [General](general/) covers pool creation and every configuration option, [Mapping](mapping/) the work methods, and [Async & Futures](async/) the non-blocking API. The [Benchmarks](benchmarks/) page has the full set of measured results.

## License

MIT. By [@nnoveil](https://github.com/nnoveil), Nimbus Systems, 2026.
