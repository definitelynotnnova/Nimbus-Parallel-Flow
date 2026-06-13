--[[
ParallelFlow V20 by Nimbus Systems

Nimbus Parallel Flow V20 is an adaptive parallel processing library

It automates task distribution across Actor workers, allowing large datasets
and compute-heavy workloads to execute without blocking the main thread

Designed for simulations, AI workloads, data processing and binary pipelines,
it dynamically balances throughput, latency and frame budget constraints while
providing a simple high-level API

Made for:

Massive Dataset Transformation
Binary Buffer Pipelines
Heterogeneous Job Scaling
Shared State Analysis
Adaptive Workload Balancing


Workers
-------
A worker is a ModuleScript that returns a function. The pool runs it per item.
    return function(value)
        return value * 2
    end


Setup
-----
    local ParallelFlow = require(ReplicatedStorage.ParallelFlow
    local pool = ParallelFlow.createPool()
    local results = pool:map({ 1, 2, 3, 4 }, workerModule)
    

Pool
----
ParallelFlow.createPool(config?)
    Create a pool of workers. Returns a Pool.
    
    
    

Running Work
------------
pool:dispatch(module, data)
    Run one item on a worker. Returns the result.

pool:submit(module, arg)
    Queue one item without blocking. Returns a Future. Many submits are
    processed together.

pool:awaitAll(futures)
    Wait for a list of Futures. Returns their results in order.

pool:map(list, module)
    Run a worker over a list. Returns results, errors.

pool:mapTables(list, module)
    Same as map, but always runs in parallel.

pool:Map(data, module)
    Pick the right path automatically from the data type.

pool:filter(list, module)
    Keep the items whose worker result is truthy.

pool:Pipeline(data, { moduleA, moduleB })
    Run several modules in order, feeding each result into the next.

pool:mapVector3(vectors, module)
    Run over a Vector3 list. The worker receives (buffer, offset).

pool:mapBuffer(buffer, stride, module)
    Binary input, list output. The worker receives (buffer, offset).

pool:mapBufferOut(buffer, stride, outStride, module)
    Binary input and output. The worker receives
    (inBuffer, inOffset, outBuffer, outOffset).

pool:mapInto(list, sharedTable, module)
    Write each result into the SharedTable. Returns nothing.
	

Async
-----
pool:mapAsync(list, module)
    Non-blocking map. Returns a Future.

pool:mapTablesAsync(list, module)
    Non-blocking mapTables. Returns a Future.

pool:FilterAsync(list, module)
    Non-blocking filter. Returns a Future.

pool:PipelineAsync(data, steps)
    Non-blocking Pipeline. Returns a Future.


Futures
-------
future:Await()          Yield until done. Returns the result.

future:Wait()           Yield until done.

future:OnComplete(fn)   Call fn(result, ok) once the work finishes.

future:Cancel()         Cancel the task.

future:IsCancelled()    True if the task was cancelled.

future:IsCompleted()    True if the task has finished.


Pool Info
---------
pool:prewarm(module)    Preload a module on every worker.

pool:getStats()         Return current pool statistics.

pool:getSize()          Number of workers.

pool:getFreeCount()     Number of idle workers.

pool:isClientPool()     True when the pool runs on the client.

pool:destroy()          Release the pool and its workers.


Configuration
-------------
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

size                    Number of workers.
timeout                 Seconds before a job is dropped.
adaptive                Choose sequential or parallel automatically.
loadBalanceFactor       Chunks per worker.
errorMode               "continue" or "strict".
maxFrameMs              Frame time budget.
maxChunkSize            Maximum items per chunk.
smallDatasetThreshold   Run sequentially below this size when adaptive is off.
sharedTableThreshold    Use a SharedTable above this size.
nestedDataThreshold     SharedTable threshold for nested data.
onError                 Called with an error message.


Errors
------
map and mapTables return results, errors.

Failed items are nil in results. errors is a list of
{ index, message }, or nil when nothing failed.

With errorMode "strict", they raise on the first failed item.


Custom Types
------------
    TypeCodecs.register(name, {
        stride = 8,
        encode = function(buffer, offset, value) end,
        decode = function(buffer, offset) return value end,
    })


Supported Types
---------------
nil, boolean, number, string, buffer, arrays, maps.

Vector2
Vector2int16
Vector3
Vector3int16
CFrame
Color3
UDim
UDim2
Rect
Ray
Region3
Region3int16
NumberRange
PhysicalProperties

BrickColor
EnumItem
Enum
UniqueId

DateTime
TweenInfo
ColorSequence
NumberSequence

ColorSequenceKeypoint
NumberSequenceKeypoint
FloatCurveKey
RotationCurveKey
PathWaypoint

and more.


@nnoveil 2026 MIT License
]]
