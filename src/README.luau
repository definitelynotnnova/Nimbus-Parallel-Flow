--[[
    ParallelFlow V10.3 by Nimbus Systems - High Performance Parallel Scripting
  
    --// Create a pool with 6 workers (actors)
    local pool = ParallelFlow.createPool({ size = 6 })
    

    --// Simple task dispatch
    local result = pool:dispatch(myModule, { x = 1, y = 2 })
    

    --// Parallel map (auto-heuristics for SharedTable/Buffers)
    local data = {1, 2, 3, 4, 5, 100}
    local results = pool:map(data, workerModule)
    

    --// Cleanup (important for memory)
    pool:destroy()

    createPool(config): returns a Pool
        config = {
            size: number? (default 4),
            timeout: number? (default 10s),
            onError: function? (callback for failures)
        }

    Pool:map(data, module): parallel table processing
    Pool:mapInto(data, target, module): write results directly to a SharedTable
    Pool:mapBuffer(data, stride, module): binary input, table output
    Pool:mapBufferOut(data, stride, outStride, module): binary to binary (fastest)
    Pool:prewarm(module): force workers to load a module early


	--// Some tips	
    Use mapBuffer() for massive arrays of numbers/vectors to avoid table overhead
    Actors are shared in Roblox, so avoid creating too many pools
    Always call pool:destroy() when your system is done
    Use mapInto() to write to SharedTables if you need to modify the input table
    
    --// Misc
    Documentation can be found in the respective devforum post and github
    Benchmarks and Benchmarks Scripts can also be downloaded from there
    
    @nnoveil 2026 MIT Liscense
]]
