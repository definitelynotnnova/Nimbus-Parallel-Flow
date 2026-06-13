---
title: Types
permalink: /types/
---

Data sent to a worker and returned from it crosses the actor boundary, so it is serialized into a `buffer` and decoded on the other side. The serializer handles this automatically for the types below. No annotation or schema is required.

## Built-in types

Primitives and containers:

`nil`, `boolean`, `number`, `string`, `buffer`, arrays, and maps.

Numbers are tagged as integer or float internally so that integer-heavy data uses a tighter encoding. Arrays and maps can be nested.

Roblox types:

`Vector2`, `Vector3`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Rect`, `Ray`, `Region3`, `NumberRange`, `BrickColor`, `Enum`, `DateTime`, `TweenInfo`, `ColorSequence`, `NumberSequence`, and others.

## Custom types

A type the serializer does not know about is registered once, before it is used. A codec declares a fixed `stride` in bytes and a pair of functions that write to and read from a buffer at a given offset.

```lua
local TypeCodecs = require(game.ReplicatedStorage.ParallelFlow.TypeCodecs)

TypeCodecs.register("MyType", {
    stride = 8,
    encode = function(buffer, offset, value)
        -- write `value` into `buffer` at `offset`, using `stride` bytes
    end,
    decode = function(buffer, offset)
        -- read `stride` bytes from `buffer` at `offset` and return the value
        return value
    end,
})
```

Once registered, values of that type can appear anywhere in the data passed to a worker, the same as a built-in type.

## Binary paths

For data that is already tightly packed, the binary paths skip the general serializer. `mapBuffer` and `mapVector3` hand the worker a `buffer` and an `offset` instead of a decoded value, and `mapBufferOut` writes results straight into an output buffer with no serialization on the way back. See [Mapping](../mapping/) for details.

## SharedTable

Above the configured thresholds, large or nested inputs are passed through a `SharedTable` rather than copied per chunk. This is automatic for `map`, and explicit for `mapInto`, which writes each result into a `SharedTable` you provide. A plain table target does not work for `mapInto`, because writes to it would not cross the actor boundary; the method requires a `SharedTable` and raises otherwise.
