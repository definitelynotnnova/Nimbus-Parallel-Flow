---
title: Error handling
permalink: /errors/
---

A worker can fail on a single element without taking down the rest of the batch. Each element is run under its own `pcall`, so one bad value produces one recorded error, not a lost chunk. How those errors surface is controlled by `errorMode`.

## Return shape

`map` and `mapTables` return two values:

```lua
local results, errors = pool:map(data, MyWorker)
```

`results` holds one entry per input element, in order. `errors` is either `nil`, when nothing failed, or a list of entries:

```lua
{ index = <position in the input>, message = <string> }
```

The index is the position in the original input, even when the work was chunked across several workers.

## Continue mode (default)

```lua
local pool = ParallelFlow.createPool({ errorMode = "continue" })

local results, errors = pool:map(data, MyWorker)

if errors then
    for _, e in errors do
        warn(string.format("element %d failed: %s", e.index, e.message))
    end
end
```

A failed element leaves `nil` in its slot in `results` and adds an entry to `errors`. The rest of the results are intact, so a single bad element does not discard the work done on the others.

## Strict mode

```lua
local pool = ParallelFlow.createPool({ errorMode = "strict" })

local ok, results = pcall(function()
    return pool:map(data, MyWorker)
end)
```

The first failed element raises an error instead of being collected. Use this when a failure means the whole result is invalid and there is no point continuing.

## onError

```lua
local pool = ParallelFlow.createPool({
    onError = function(message)
        warn("[pool] " .. message)
    end,
})
```

`onError` receives a descriptive string for failures, timeouts, and lost chunks. It is independent of `errorMode`: it still fires in continue mode, as a side channel for logging, and in strict mode it fires before the error is raised. The structured `{ index, message }` data is on the `errors` return value, not here.

## Futures

For the async methods and `submit`, a failure settles the Future rather than returning an errors list. The Future's `errors` field carries the same structured entries, and `Await` returns `nil` for a failed job.

## Total failures

A timeout or a worker crash is different from an element error: the whole chunk is lost rather than individual elements. These are reported through `onError`, and in `map` they leave the affected slots empty rather than filling them with results.
