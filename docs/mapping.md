---
title: Mapping
permalink: /mapping/
---

These methods apply a worker module across an input. They block until the work finishes; for the non-blocking forms see [Async & Futures](../async/).

## map

```lua
local results, errors = pool:map(list, module)
```

Runs the worker over the list and returns the results in the same order. The second return value is a list of `{ index, message }` entries for elements that failed, or `nil` when none did. `map` chooses sequential or parallel execution based on the cost model (or `smallDatasetThreshold` when `adaptive` is off). For large or nested inputs it may route through a `SharedTable` automatically. See [Error handling](../errors/) for the error semantics.

## Map

```lua
local results = pool:Map(data, module)
```

A convenience that dispatches based on the type of `data`: a `buffer` goes to `mapBuffer`, a list of `Vector3` goes to `mapVector3`, and any other list goes to `map`. Useful when the input type is known to be one of these but you do not want to branch by hand.

## mapTables

```lua
local results, errors = pool:mapTables(list, module)
```

Like `map`, but always parallel; it skips the sequential decision. Use it when the input is known to be large enough that parallel execution is the right path and you want to avoid the calibration step.

## dispatch

```lua
local result = pool:dispatch(module, data)
```

Runs the worker on a single value and blocks until it returns. For more than one value, prefer `map` (a collection) or `submit` (independent jobs), which are far cheaper per item.

## filter

```lua
local kept = pool:filter(list, module)
```

Runs the worker over the list and keeps the original elements whose result is truthy. The worker acts as a predicate.

## Pipeline

```lua
local result = pool:Pipeline(data, { moduleA, moduleB, moduleC })
```

Runs each module in sequence, feeding the result of one into the next through `Map`. Each stage is parallelized on its own.

## Binary paths

These hand the worker raw buffer memory rather than decoded values, which avoids serialization for tightly packed numeric data.

### mapVector3

```lua
local results = pool:mapVector3(vectors, module)
```

Iterates a list of `Vector3`. Each vector is packed as three `f32` values (12 bytes). The worker receives `(buffer, offset)` and reads its vector from there:

```lua
-- worker
return function(buf, offset)
    local x = buffer.readf32(buf, offset)
    local y = buffer.readf32(buf, offset + 4)
    local z = buffer.readf32(buf, offset + 8)
    return x + y + z
end
```

### mapBuffer

```lua
local results = pool:mapBuffer(data, stride, module)
```

Binary input, list output. `stride` is the byte size of one element. The worker receives `(buffer, offset)` and returns one value per element.

### mapBufferOut

```lua
local outBuffer = pool:mapBufferOut(data, stride, outStride, module)
```

Binary input and binary output, with no serialization on the result. The worker receives `(inBuffer, inOffset, outBuffer, outOffset)` and writes its result directly into the output buffer. `stride` is the input element size, `outStride` the output element size. This is the lowest-overhead path when both ends of the computation are numeric.

```lua
-- worker
return function(inBuf, inOff, outBuf, outOff)
    local v = buffer.readf32(inBuf, inOff)
    buffer.writef32(outBuf, outOff, v * 2)
end
```

### mapInto

```lua
pool:mapInto(list, sharedTable, module)
```

Writes each result into the `SharedTable` you pass, at the matching index, and returns nothing. The target must be a `SharedTable`; a plain table is rejected, because writes to it would not survive crossing the actor boundary.
