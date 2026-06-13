---
title: Installation
permalink: /installation/
---

The library is distributed as a single assembled package. It is inserted as one unit. There are no scripts to place individually and no internal structure to assemble.

1. Obtain the package (the Creator Store model or the `.rbxm` file).
2. Insert it into `ReplicatedStorage`. It already contains the serializer, the type codecs, and the engine. The internal structure is not meant to be modified.
3. Require it where needed:

```lua
local ParallelFlow = require(game.ReplicatedStorage.ParallelFlow)
```

With Rojo or Wally, point the dependency at `ReplicatedStorage.ParallelFlow`.

## Server and client

The library runs on both sides. The worker limit differs:

- Server: up to 64 workers.
- Client: up to 3 workers, which is the platform limit.

`createPool` clamps the requested size to the limit for the side it runs on, so a config written for the server still works on the client without changes. `pool:isClientPool()` returns whether a given pool is running on the client.

## What ships in the package

The distributed package is the runtime only. The demos and the benchmark scripts live in the repository, not in the package.
