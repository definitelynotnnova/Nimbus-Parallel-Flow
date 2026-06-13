---
title: Benchmarks
permalink: /benchmarks/
---

Run in Studio, on the server. Times are in milliseconds. `Ratio` is relative to the sequential baseline, where higher is faster. `pool:N` is a pool of N workers. `task.spawn` is a plain coroutine baseline, included to show that raw coroutines do not parallelize CPU work. The benchmark scripts live in the repository, not in the distributed module.

The full results below come from the latest main run, followed by the per-phase benchmarks.

## Main run

### Heavy compute (numbers)

A numeric workload with real per-element cost. This is the case parallel execution is meant for, and it is where the pool scales close to linearly with the worker count.

**100 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 3.99 | 3.99 | 0.06 | 1.00x |
| task.spawn | 4.79 | 4.64 | 0.43 | 0.83x |
| pool:1 | 6.77 | 6.71 | 0.70 | 0.59x |
| pool:2 | 6.80 | 6.93 | 0.35 | 0.59x |
| pool:3 | 6.89 | 6.93 | 0.47 | 0.58x |
| pool:4 | 6.94 | 6.90 | 0.60 | 0.58x |
| pool:6 | 6.85 | 6.79 | 0.78 | 0.58x |

**300 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 12.48 | 12.48 | 0.17 | 1.00x |
| task.spawn | 13.08 | 13.15 | 0.23 | 0.95x |
| pool:1 | 13.26 | 13.26 | 0.15 | 0.94x |
| pool:2 | 6.96 | 6.90 | 0.15 | 1.79x |
| pool:3 | 6.55 | 6.79 | 1.14 | 1.90x |
| pool:4 | 6.81 | 6.69 | 0.44 | 1.83x |
| pool:6 | 6.73 | 6.59 | 0.68 | 1.85x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 43.20 | 43.39 | 0.83 | 1.00x |
| task.spawn | 43.04 | 42.88 | 0.53 | 1.00x |
| pool:1 | 43.11 | 43.05 | 0.39 | 1.00x |
| pool:2 | 22.68 | 22.69 | 0.62 | 1.91x |
| pool:3 | 15.43 | 15.38 | 0.38 | 2.80x |
| pool:4 | 12.25 | 12.33 | 0.23 | 3.53x |
| pool:6 | 9.26 | 8.96 | 0.62 | 4.67x |

**3000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 125.47 | 125.49 | 0.41 | 1.00x |
| task.spawn | 127.17 | 126.55 | 1.61 | 0.99x |
| pool:1 | 125.43 | 125.78 | 1.19 | 1.00x |
| pool:2 | 65.54 | 65.55 | 1.32 | 1.91x |
| pool:3 | 45.15 | 45.01 | 0.41 | 2.78x |
| pool:4 | 35.04 | 35.09 | 0.33 | 3.58x |
| pool:6 | 26.04 | 25.19 | 2.29 | 4.82x |

### Vector3 transform

A lighter per-element workload. The compute is small, so small inputs sit at the round-trip floor and only the larger ones pull ahead.

**100 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 1.01 | 1.00 | 0.02 | 1.00x |
| task.spawn | 1.18 | 1.14 | 0.09 | 0.85x |
| pool:1 | 6.70 | 6.90 | 0.58 | 0.15x |
| pool:2 | 6.82 | 6.90 | 0.43 | 0.15x |
| pool:3 | 6.82 | 6.86 | 0.51 | 0.15x |
| pool:4 | 6.75 | 6.91 | 0.48 | 0.15x |
| pool:6 | 6.94 | 6.96 | 0.25 | 0.14x |

**300 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 3.06 | 3.03 | 0.07 | 1.00x |
| task.spawn | 3.29 | 3.27 | 0.11 | 0.93x |
| pool:1 | 6.81 | 7.14 | 0.88 | 0.45x |
| pool:2 | 6.76 | 6.92 | 0.49 | 0.45x |
| pool:3 | 6.79 | 6.93 | 0.55 | 0.45x |
| pool:4 | 6.89 | 6.92 | 0.70 | 0.44x |
| pool:6 | 6.89 | 6.82 | 0.64 | 0.44x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 10.89 | 10.83 | 0.32 | 1.00x |
| task.spawn | 11.38 | 11.34 | 0.37 | 0.96x |
| pool:1 | 11.15 | 11.21 | 0.26 | 0.98x |
| pool:2 | 6.57 | 6.28 | 0.80 | 1.66x |
| pool:3 | 6.82 | 6.96 | 0.78 | 1.60x |
| pool:4 | 6.82 | 6.94 | 0.57 | 1.60x |
| pool:6 | 6.77 | 7.00 | 0.70 | 1.61x |

**3000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 31.41 | 31.45 | 0.48 | 1.00x |
| task.spawn | 34.07 | 34.05 | 0.67 | 0.92x |
| pool:1 | 32.72 | 32.64 | 0.59 | 0.96x |
| pool:2 | 16.95 | 16.98 | 0.16 | 1.85x |
| pool:3 | 12.05 | 12.13 | 0.28 | 2.61x |
| pool:4 | 9.59 | 9.61 | 0.26 | 3.28x |
| pool:6 | 7.54 | 7.58 | 0.25 | 4.17x |

### Nested table processing

Each element is a nested table, so serialization carries more weight. The speedup is real but lower than the flat numeric case.

**100 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 2.03 | 2.02 | 0.03 | 1.00x |
| task.spawn | 2.18 | 2.17 | 0.03 | 0.93x |
| pool:1 | 6.68 | 6.71 | 0.66 | 0.30x |
| pool:2 | 6.86 | 6.95 | 0.41 | 0.30x |
| pool:3 | 6.81 | 6.94 | 0.53 | 0.30x |
| pool:4 | 6.77 | 6.91 | 0.57 | 0.30x |
| pool:6 | 6.96 | 6.99 | 0.61 | 0.29x |

**300 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 6.52 | 6.53 | 0.11 | 1.00x |
| task.spawn | 6.58 | 6.67 | 0.17 | 0.99x |
| pool:1 | 7.64 | 7.63 | 0.17 | 0.85x |
| pool:2 | 6.74 | 6.85 | 0.83 | 0.97x |
| pool:3 | 6.93 | 7.04 | 0.65 | 0.94x |
| pool:4 | 6.89 | 6.83 | 0.73 | 0.95x |
| pool:6 | 6.97 | 7.14 | 0.73 | 0.94x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 20.95 | 20.89 | 0.29 | 1.00x |
| task.spawn | 22.08 | 21.78 | 0.85 | 0.95x |
| pool:1 | 24.33 | 24.36 | 0.30 | 0.86x |
| pool:2 | 14.14 | 14.17 | 0.21 | 1.48x |
| pool:3 | 10.49 | 10.54 | 0.15 | 2.00x |
| pool:4 | 8.91 | 8.90 | 0.27 | 2.35x |
| pool:6 | 7.34 | 7.36 | 0.31 | 2.85x |

**3000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 62.56 | 62.26 | 0.87 | 1.00x |
| task.spawn | 65.71 | 65.76 | 0.98 | 0.95x |
| pool:1 | 71.95 | 72.01 | 0.65 | 0.87x |
| pool:2 | 40.91 | 40.89 | 0.49 | 1.53x |
| pool:3 | 30.16 | 30.19 | 0.35 | 2.07x |
| pool:4 | 25.83 | 25.52 | 0.96 | 2.42x |
| pool:6 | 20.49 | 20.55 | 0.51 | 3.05x |

### Crossover analysis

Sweeping the input size to find where the pools overtake sequential. Only pool sizes that fit the client limit (1 to 3) are shown here.

**50 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 2.00 | 1.99 | 0.01 | 1.00x |
| pool:1 | 6.82 | 6.70 | 0.83 | 0.29x |
| pool:2 | 6.94 | 6.96 | 0.59 | 0.29x |
| pool:3 | 6.88 | 6.95 | 0.41 | 0.29x |

**100 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 4.12 | 4.10 | 0.12 | 1.00x |
| pool:1 | 6.88 | 7.20 | 0.80 | 0.60x |
| pool:2 | 6.74 | 6.72 | 0.64 | 0.61x |
| pool:3 | 6.82 | 6.92 | 0.33 | 0.60x |

**200 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 8.60 | 8.63 | 0.30 | 1.00x |
| pool:1 | 8.97 | 9.09 | 0.24 | 0.96x |
| pool:2 | 6.76 | 6.91 | 0.79 | 1.27x |
| pool:3 | 6.75 | 6.72 | 0.52 | 1.27x |

**500 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 21.59 | 21.57 | 0.65 | 1.00x |
| pool:1 | 21.30 | 21.32 | 0.31 | 1.01x |
| pool:2 | 11.32 | 11.20 | 0.31 | 1.91x |
| pool:3 | 7.83 | 7.76 | 0.24 | 2.76x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 42.22 | 42.15 | 0.42 | 1.00x |
| pool:1 | 43.96 | 43.85 | 0.75 | 0.96x |
| pool:2 | 22.55 | 22.61 | 0.33 | 1.87x |
| pool:3 | 15.68 | 15.71 | 0.21 | 2.69x |

**2000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 83.45 | 83.68 | 0.91 | 1.00x |
| pool:1 | 85.03 | 84.53 | 2.37 | 0.98x |
| pool:2 | 43.79 | 43.51 | 0.64 | 1.91x |
| pool:3 | 30.38 | 30.51 | 0.31 | 2.75x |

**5000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 213.49 | 213.38 | 1.49 | 1.00x |
| pool:1 | 211.58 | 210.21 | 3.63 | 1.01x |
| pool:2 | 110.15 | 110.32 | 1.21 | 1.94x |
| pool:3 | 75.08 | 75.16 | 0.52 | 2.84x |

### Pool scaling (client-focused)

The same workload across pool sizes, marking which sizes fit the 3-worker client limit and which are server only.

**300 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 12.68 | 12.68 | 0.00 | 1.00x |
| pool:1 (fits client limit) | 13.49 | 13.42 | 0.41 | 0.94x |
| pool:2 (fits client limit) | 6.89 | 6.93 | 0.20 | 1.84x |
| pool:3 (fits client limit) | 7.01 | 7.06 | 0.83 | 1.81x |
| pool:4 (server-only) | 6.83 | 6.95 | 0.35 | 1.86x |
| pool:6 (server-only) | 6.82 | 7.06 | 0.58 | 1.86x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 41.70 | 41.70 | 0.00 | 1.00x |
| pool:1 (fits client limit) | 42.77 | 42.69 | 0.70 | 0.98x |
| pool:2 (fits client limit) | 22.40 | 22.44 | 0.32 | 1.86x |
| pool:3 (fits client limit) | 15.65 | 15.69 | 0.18 | 2.66x |
| pool:4 (server-only) | 12.07 | 12.05 | 0.22 | 3.45x |
| pool:6 (server-only) | 9.42 | 9.39 | 0.31 | 4.43x |

**3000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 124.99 | 124.99 | 0.00 | 1.00x |
| pool:1 (fits client limit) | 126.69 | 126.96 | 1.26 | 0.99x |
| pool:2 (fits client limit) | 65.78 | 65.35 | 1.38 | 1.90x |
| pool:3 (fits client limit) | 46.05 | 46.00 | 0.63 | 2.71x |
| pool:4 (server-only) | 35.94 | 35.18 | 1.57 | 3.48x |
| pool:6 (server-only) | 25.42 | 25.27 | 0.39 | 4.92x |

### Heavy payload (SharedTable focus)

Large nested tables, where the input is routed through a SharedTable. The crossover sits higher because the per-element compute is modest relative to the data size.

**500 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 5.62 | 5.63 | 0.17 | 1.00x |
| pool:2 | 6.95 | 7.10 | 0.52 | 0.81x |
| pool:4 | 6.94 | 6.96 | 0.49 | 0.81x |
| pool:6 | 7.04 | 7.20 | 0.72 | 0.80x |

**1000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 11.29 | 11.31 | 0.19 | 1.00x |
| pool:2 | 7.99 | 7.88 | 0.27 | 1.41x |
| pool:4 | 6.54 | 6.69 | 0.84 | 1.73x |
| pool:6 | 6.79 | 6.78 | 0.99 | 1.66x |

**2000 elements**

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 22.50 | 22.60 | 0.47 | 1.00x |
| pool:2 | 15.32 | 15.14 | 0.43 | 1.47x |
| pool:4 | 9.66 | 9.62 | 0.25 | 2.33x |
| pool:6 | 8.54 | 8.58 | 0.34 | 2.63x |

### Extreme data stress (5000 elements, large payloads)

5000 elements with heavy payloads, stressing concurrency limits. The high ratio here comes from the sequential baseline being dominated by raw compute, which the pool spreads cleanly.

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 212.08 | 211.85 | 1.68 | 1.00x |
| pool:2 | 57.96 | 57.98 | 0.74 | 3.66x |
| pool:4 | 41.80 | 41.79 | 1.50 | 5.07x |
| pool:6 | 37.87 | 37.39 | 1.09 | 5.60x |

### Vectorized buffer stress (mapBuffer, 5000 elements)

Using the `mapBuffer` path so the input crosses as raw binary rather than serialized tables.

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential (buffer) | 208.51 | 208.32 | 2.40 | 1.00x |
| pool:2 | 110.13 | 110.07 | 1.51 | 1.89x |
| pool:4 | 57.04 | 57.00 | 0.37 | 3.66x |
| pool:6 | 42.26 | 41.14 | 2.87 | 4.93x |

### Direct binary pipeline (mapBufferOut, 5000 elements)

Binary in, binary out, with no table serialization on either side.

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential (binary-io) | 106.86 | 106.91 | 0.96 | 1.00x |
| pool:2 | 55.15 | 55.05 | 0.61 | 1.94x |
| pool:4 | 29.24 | 29.25 | 0.38 | 3.65x |
| pool:6 | 20.87 | 20.73 | 0.35 | 5.12x |

### Mixed Roblox types (1000 elements)

A mix of centralized Roblox types going through TypeCodecs, to confirm the codec layer adds no measurable overhead on a real workload.

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential | 29.70 | 29.78 | 0.83 | 1.00x |
| pool:2 | 15.78 | 15.80 | 0.25 | 1.88x |
| pool:4 | 8.87 | 8.75 | 0.33 | 3.35x |
| pool:6 | 7.00 | 6.92 | 0.44 | 4.24x |

### Functional checks

Not timing tables; these confirm behavior under the same run.

| Check | Result |
|-------|--------|
| Ergonomic `Map()` over 10000 items | processed in 117.50 ms |
| Frame budgeting (2 ms budget) | 213.52 ms total, yielded across frames to hold the budget (PASS) |
| Task cancellation | task settled, pool health OK afterward |
| Dispatch after `destroy` | raises "pool is destroyed" as expected |

## Phase benchmarks

The phases isolate one change each, on top of the main suite.

### Phase 3, many independent small jobs (N=100, pool:4)

Comparing a serialized `dispatch` loop against `submit` with `awaitAll`. The dispatch loop pays one round trip per job; `submit` coalesces all jobs of a frame into roughly one round trip per worker.

| Implementation | Avg | Med | SD | Ratio |
|----------------|-----|-----|----|-------|
| sequential (main thread) | 16.47 | 16.51 | 0.28 | 1.00x |
| dispatch loop (serialized) | 201.23 | 174.86 | 52.72 | 0.08x |
| submit + awaitAll (coalesced) | 8.85 | 6.85 | 3.90 | 1.86x |

### Phase 1, load balancing under uneven work

Phase 1 measures `loadBalanceFactor` on a skewed workload, where a few elements are far heavier than the rest. The console output for this run was not captured to a results file, so the table is not reproduced here. Run `Phase1_Benchmark` in Studio to regenerate it.

### Phase 2, adaptive crossover

Phase 2 sweeps the input size with the adaptive scheduler on, printing the per-element cost, the latency floor, and the size at which it switches from sequential to parallel. The console output for this run was not captured to a results file. The Crossover analysis tables in the main run above cover the same crossover behavior; run `Phase2_Benchmark` in Studio to regenerate the dedicated table.
