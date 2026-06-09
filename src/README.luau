--[[
ParallelFlow V19 by Nimbus Systems

=======================================================================
Core Allocation
=======================================================================


Adding workers beyond available cores does not improve throughput.
In testing, pools 3-6 stayed near ~1.26x.

Parallel work is usually slower below ~50-100 elements, with light
per-element work, or on single-core servers. The map heuristic already
handles this automatically.

=======================================================================
Method Selection
=======================================================================

dispatch        Single heavy job off the main thread
map             Plain tables with automatic heuristics
mapTables       Force parallel execution
Map             Auto-detects best path
mapVector3      Vector3 arrays, ~30% faster than map
mapBuffer       Binary input, table output
mapBufferOut    Binary input/output, fastest path
mapInto         Writes into SharedTable directly
filter          Parallel filtering
Pipeline        Multi-stage heavy workloads
*Async          Non-blocking variants returning PFTask

For homogeneous numeric or Vector3 data, prefer binary paths.
Their gains become more noticeable on core-limited servers.

=======================================================================
API Reference
=======================================================================

local pool = ParallelFlow.createPool({ size = 6 })

local result = pool:dispatch(myModule, { x = 1, y = 2 })

local results = pool:map({1, 2, 3, 4, 5, 100}, workerModule)

local results = pool:Map(data, workerModule)

local results = pool:mapTables(data, workerModule)

local vectors = {Vector3.new(1,0,0), Vector3.new(0,1,0)}
local results = pool:mapVector3(vectors, vec3Worker)

pool:mapInto(data, sharedTarget, workerModule)

local results = pool:mapBuffer(dataBuf, 8, workerModule)

local outBuf = pool:mapBufferOut(dataBuf, 8, 4, workerModule)

local result = pool:Pipeline(data, {stepA, stepB, stepC})

local filtered = pool:filter(data, predicateModule)

local task = pool:mapAsync(data, workerModule)
local task = pool:mapTablesAsync(data, workerModule)
local task = pool:FilterAsync(data, predicateModule)
local task = pool:PipelineAsync(data, {stepA, stepB})

task:Cancel()
task:IsCancelled()
task:Wait()
task:OnComplete(fn)

pool:prewarm(mod)

pool:getSize()
pool:getFreeCount()
pool:isClientPool()

pool:destroy()

=======================================================================
Custom Types (TypeCodecs)
=======================================================================

Register custom Serializer types:

TypeCodecs.register("MyType", {
    stride = 8,
    encode = function(buf, offset, value) ... end,
    decode = function(buf, offset) return value end,
})

Fields:

    stride > 0  Fixed-size type
    stride = 0  Variable-size type

encode(buf, offset, value)
    Serializes a value into the buffer.

decode(buf, offset)
    Reconstructs a value from the buffer.

Once registered, the type becomes available to the Serializer.

=======================================================================
createPool(config)
=======================================================================

config = {
    size:                  number?   (auto: client=3, server=4),
    timeout:               number?   (default 10s),
    maxChunkSize:          number?,
    maxFrameMs:            number?   (default 6ms),
    smallDatasetThreshold: number?   (default 50),
    sharedTableThreshold:  number?   (default 1000),
    nestedDataThreshold:   number?   (default 10000),
    onError:               function?,
}

Returns a Pool.

=======================================================================
Pool Methods
=======================================================================

Pool:dispatch(mod, data, parentTask?)
    Runs one item on a worker and returns the result.
    Automatically prewarmed on first use.

Pool:map(data, mod, parentTask?)
    Parallel table processing with automatic heuristics.

    - Sequential below smallDatasetThreshold (50)
    - SharedTable above sharedTableThreshold (1000)
    - Adaptive chunk sizing (~1MB target)
    - Respects maxChunkSize and maxFrameMs

Pool:mapTables(data, mod, parentTask?)
    Forces parallel execution regardless of size.

Pool:Map(data, mod, parentTask?)
    Smart routing:

    - buffer input   >> mapBuffer
    - Vector3 array  >> mapVector3
    - plain table    >> map

Pool:mapVector3(data, mod, parentTask?)
    Packs Vector3 values as 3xf32 (12 bytes).
    Worker receives (buf, offset).
    ~30% faster than map.

Pool:mapInto(data, target, mod, parentTask?)
    Writes results directly into target.
    No return value, allocation, or copy.

Pool:mapBuffer(data, stride, mod, parentTask?)
    Binary input.
    Worker receives (buf, offset).
    Returns a table.

Pool:mapBufferOut(data, stride, outStride, mod, parentTask?)
    Binary input/output.

    Worker:
        fn(inBuf, inOffset, outBuf, outOffset)

    Fastest path available.
    Measured 2.20x vs map at 1.20x on the same core-limited pool.

Pool:filter(data, mod, parentTask?)
    Parallel predicate filtering.
    Internally maps then applies a boolean mask.

Pool:Pipeline(data, steps, parentTask?)
    Sequential module chain.
    Output from each step becomes input for the next.
    Uses :Map automatically.

    N steps = N round trips.
    Combine cheap stages when possible.

Pool:prewarm(mod)
    Preloads a module on all workers.
    Removes first-dispatch require() cost.

Pool:mapAsync / mapTablesAsync / FilterAsync / PipelineAsync
    Non-blocking variants.
    Return PFTask immediately.

Pool:destroy()
    Destroys all Actors and BindableEvent resources.
    Using the pool afterward raises an error.

=======================================================================
Serializer - Supported Types
=======================================================================

Primitives:
    nil, boolean, number (int32 or f64), string

Roblox:
    Vector2, Vector2int16, Vector3, Vector3int16,
    CFrame, Color3, UDim, UDim2, Rect, Ray,
    Region3, Region3int16, NumberRange, Enum,
    Axes, Faces, UniqueId, DateTime, TweenInfo,
    ColorSequenceKeypoint, NumberSequenceKeypoint,
    ColorSequence, NumberSequence, FloatCurveKey,
    RotationCurveKey, PathWaypoint

Collections:
    arrays, maps,
    homogeneous number arrays (T_ANUM),
    homogeneous Vector3 arrays (T_AV3),
    homogeneous CFrame arrays (T_ACF),
    schema-compressed struct arrays (T_SMAP),
    raw buffers (T_BUF)

T_SMAP:
    For identical-key tables, keys are written once and only
    values are interleaved. Useful for large struct arrays.

Custom types:

TypeCodecs.register("MyType", {
    stride = 8,
    encode = function(buf, offset, v) ... end,
    decode = function(buf, offset) return ... end,
})

stride = 0 marks variable-length types.

=======================================================================
Runtime
=======================================================================

Each worker runs:
    Runner_server >> Runtime.start()

Message types:

    pf_task
    pf_map
    pf_map_shared
    pf_map_buffer
    pf_map_into
    pf_map_buffer_out
    pf_warmup

Workers cache up to 50 modules using LRU eviction.

require() always runs in serial using:
    task.synchronize()
    task.desynchronize()

Each worker updates:

    PF_Busy
    PF_LastRunMs

All payloads return through Serializer.encode().

=======================================================================
Benchmark Results
=======================================================================

Workload:
    1500 elements
    ~4000-step trigonometric kernel per element

Data:
    Homogeneous numeric data

Method:
    Average of 8 runs
    2 warmup runs
    Prewarmed pools

Studio (6+ physical cores)

    sequential .......... 120.0 ms   baseline
    task.spawn .......... 123.4 ms   0.97x
    pool 1 .............. 120.5 ms   1.00x
    pool 2 ..............  62.3 ms   1.93x
    pool 3 ..............  42.7 ms   2.81x
    pool 4 ..............  32.6 ms   3.69x
    pool 5 ..............  27.0 ms   4.45x
    pool 6 ..............  23.5 ms   5.11x
    stddev .............. 0.5-1.7 ms

Live Server

    sequential .......... 359.0 ms   baseline
    task.spawn .......... 377.6 ms   0.95x
    pool 1 .............. 369.0 ms   0.97x
    pool 2 .............. 282.7 ms   1.27x
    pool 3 .............. 310.2 ms   1.16x
    pool 4 .............. 280.7 ms   1.28x
    pool 5 .............. 285.0 ms   1.26x
    pool 6 .............. 284.6 ms   1.26x
    stddev .............. 11-45 ms

Pool 6 Binary Paths

    map ................. 298.2 ms   1.20x
    mapBuffer ........... 171.8 ms   2.09x
    mapBufferOut ........ 163.3 ms   2.20x
    
//Advanced Benchmarking and Benchmarking code available on Devforum

Scaling is close to linear on dedicated hardware.
On shared Roblox servers it levels out near ~1.20x, where
serialization becomes the main bottleneck.

Binary paths reached ~2.20x on the same pool.

Results depend on workload. Lighter or mixed datasets trend
closer to ~1.0x.

=======================================================================
VERSION 19.0.0
=======================================================================

- Auto pool-size detection
- Adaptive batching with maxChunkSize
- Native Vector3 and homogeneous table binary paths
- maxFrameMs frame-budget enforcement
- PFTask cancellation propagation
- Unified :Map() dispatch
- :Pipeline() and :filter() operators
- TypeCodecs registry for custom types

@nnoveil 2026 MIT License
More info on GitHub and DevForum
]]
