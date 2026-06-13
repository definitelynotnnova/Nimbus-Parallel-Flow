--!strict
local Serializer = require(script.Serializer)
local PFTask = require(script.PFTask)

local DEFAULT_CONFIG = {
	size = 4,
	timeout = 10,
	smallDatasetThreshold = 50,
	sharedTableThreshold = 1000,
	nestedDataThreshold = 10000,
	maxFrameMs = 6, -- ~6ms budget
	loadBalanceFactor = 1, -- >1 improves balance, adds overhead
	adaptive = true, -- auto picks sequential or parallel
	seedRoundTripMs = 7, -- initial round-trip estimate (ms)
	calibrationSamples = 16, -- samples for cost estimation
	errorMode = "continue", -- continue = collect errors, strict = throw
}

local Flow = {}
local Pool = {}
Pool.__index = Pool

-- helper to create actors
local function spawn(runner: Script, container: Instance, event: BindableEvent, index: number): Actor
	local actor = Instance.new("Actor")
	actor.Name = "PF_" .. index
	runner:Clone().Parent = actor
	actor:SetAttribute("PF_Index", index)

	local ref = Instance.new("ObjectValue")
	ref.Name = "PF_ResultEvent"
	ref.Value = event
	ref.Parent = actor

	actor.Parent = container
	return actor
end

-- get free worker or yield
local function getWorker(p): (Actor, number)
	if p.dead then error("pool is destroyed", 3) end

	local free = p.free
	local idx = free[#free]
	if idx then
		free[#free] = nil
		return p.workers[idx], idx
	end

	local thread = coroutine.running()
	p.waitTail += 1
	p.waiters[p.waitTail] = thread
	return coroutine.yield()
end

-- return worker to pool
local function putWorker(p, idx: number)
	if p.dead then return end

	if p.waitHead <= p.waitTail then
		local thread = p.waiters[p.waitHead]
		p.waiters[p.waitHead] = nil
		p.waitHead += 1
		task.spawn(thread, p.workers[idx], idx)
	else
		table.insert(p.free, idx)
	end
end

-- internal worker job runner
local function runJob(p, kind: string, mod: ModuleScript, parentTask: any?, ...): (boolean, any)
	local worker, idx = getWorker(p)
	local thread = coroutine.running()
	local decoded, ok, timeout, errors

	-- telemetry: feeds getStats and stats model
	local stats = p.stats
	stats.dispatched += 1
	stats.perWorker[idx] += 1
	local sentClock = os.clock()

	p.handlers[idx] = function(enc: buffer?, success: boolean, errs: any)
		p.handlers[idx] = nil

		-- pool-side round-trip latency (EWMA)
		local rt = (os.clock() - sentClock) * 1000
		if stats.samples == 0 then
			stats.avgRoundTripMs = rt
		else
			stats.avgRoundTripMs += 0.15 * (rt - stats.avgRoundTripMs)
		end
		stats.samples += 1

		ok = success
		errors = errs
		if success then stats.completed += 1 else stats.failed += 1 end
		-- pf_map_buffer_out returns a RAW result buffer (zero-serialization path);
		-- every other kind returns a Serializer-encoded payload.
		if kind == "pf_map_buffer_out" then
			decoded = enc
		else
			decoded = enc and Serializer.decode(enc) or nil
		end

		-- ignore result if cancelled mid-flight
		if parentTask and parentTask:IsCancelled() then
			putWorker(p, idx)
			return
		end

		task.spawn(thread)
	end

	worker:SendMessage(kind, mod, ...)

	local timer = task.delay(p.timeout, function()
		if p.handlers[idx] then
			p.handlers[idx] = nil
			timeout = true
			stats.timedOut += 1
			if p.config.onError then
				p.config.onError("worker " .. idx .. " timed out on " .. kind)
			end
			task.spawn(thread)
		end
	end)

	coroutine.yield()
	if timeout then return false, nil end
	pcall(task.cancel, timer)

	-- Final cancellation check after resume
	if parentTask and parentTask:IsCancelled() then
		return false, nil
	end

	return ok, decoded, errors
end

function Flow.createPool(config)
	local cfg = table.clone(DEFAULT_CONFIG)
	if config then
		for k, v in config do cfg[k] = v end
	end

	local RunService = game:GetService("RunService")
	local isClient = RunService:IsClient()
	local maxThreadsForPlatform = isClient and 3 or 64

	local size = math.clamp(cfg.size or (isClient and 3 or 4), 1, maxThreadsForPlatform)
	local event = Instance.new("BindableEvent")
	local container = script.Engine
	local runner = container.Runner

	local p = setmetatable({}, Pool)
	p.workers = table.create(size)
	p.free = table.create(size)
	p.handlers = {}
	p.waiters = {}
	p.waitHead = 1
	p.waitTail = 0
	p.size = size
	p.timeout = cfg.timeout or 10
	p.event = event
	p.dead = false
	p.config = cfg
	p.warmed = {} -- track warmed modules
	p.stats = {
		dispatched = 0,
		completed = 0,
		failed = 0,
		timedOut = 0,
		samples = 0,
		avgRoundTripMs = 0,
		latencyFloorMs = 0, -- measured pure round-trip floor
		perWorker = table.create(size, 0),
	}
	p.cost = {} -- per-module learned cost
	p.pending = {} -- submit() requests for current frame
	p.flushScheduled = false

	local ready = 0
	local readyEvent = Instance.new("BindableEvent")
	event.Event:Connect(function(id, enc, ok, errs)
		if not enc and ok == nil then
			ready += 1
			if ready >= size then readyEvent:Fire() end
			return
		end

		if p.dead then return end
		local h = p.handlers[id]
		if h then
			p.handlers[id] = nil
			h(enc, ok, errs)
		end
		putWorker(p, id)
	end)

	for i = 1, size do
		p.workers[i] = spawn(runner, container, event, i)
		table.insert(p.free, i)
	end

	-- Wait until every worker has bound its handlers and sent its handshake.
	-- Without this, the first dispatch could race an unready worker and come
	-- back as a silent nil. A 5s fallback guards against a worker that dies.
	if ready < size then
		local guard = task.delay(5, function() readyEvent:Fire() end)
		readyEvent.Event:Wait()
		pcall(task.cancel, guard)
	end
	readyEvent:Destroy()

	return p
end

function Pool:dispatch(mod: ModuleScript, data: any, parentTask: any?): any?
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("dispatch needs a modulescript", 2)
	end

	if not self.warmed[mod] then self:prewarm(mod) end
	local ok, res = runJob(self, "pf_task", mod, parentTask, Serializer.encode(data))
	if not ok then
		if self.config.onError then self.config.onError("dispatch failed") end
		return nil
	end
	return res
end

-- submit() + transparent coalescing

-- Run one batch of buffered jobs (start..finish of `batch`) in a single
-- round-trip and resolve each job's future with its result.
function Pool:_runBatch(batch: {any}, start: number, finish: number)
	local worker, idx = getWorker(self)
	local count = finish - start + 1

	local mods = table.create(count)
	local args = table.create(count)
	for i = start, finish do
		local j = i - start + 1
		mods[j] = batch[i].mod
		args[j] = batch[i].arg
	end

	local stats = self.stats
	stats.dispatched += count
	stats.perWorker[idx] += count

	local thread = coroutine.running()
	local results, batchErrs, timedOut
	self.handlers[idx] = function(enc: buffer?, _success: boolean, errs: any)
		self.handlers[idx] = nil
		results = enc and Serializer.decode(enc) or nil
		batchErrs = errs
		task.spawn(thread)
	end

	-- encode(args, 1, count): per-element tagging, safe for heterogeneous args
	worker:SendMessage("pf_batch", mods, Serializer.encode(args, 1, count))

	local timer = task.delay(self.timeout, function()
		if self.handlers[idx] then
			self.handlers[idx] = nil
			timedOut = true
			stats.timedOut += count
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	pcall(task.cancel, timer)

	-- per-job failures keyed by local index so each future resolves independently
	local errSet
	if batchErrs then
		errSet = {}
		for _, e in batchErrs do errSet[e.index] = e.message end
	end

	for i = start, finish do
		local future = batch[i].future
		if not future:IsCancelled() then
			local localIdx = i - start + 1
			if timedOut or not results then
				stats.failed += 1
				future:_finish(nil, false)
			elseif errSet and errSet[localIdx] then
				stats.failed += 1
				future.errors = { { index = 0, message = errSet[localIdx] } }
				future:_finish(nil, false)
			else
				stats.completed += 1
				future:_finish(results[localIdx], true)
			end
		end
	end
end

-- drain per-frame buffer
function Pool:_flush()
	self.flushScheduled = false
	if self.dead then return end

	local batch = self.pending
	self.pending = {}

	local n = #batch
	if n == 0 then return end

	local workersCount = #self.workers
	local perWorker = math.ceil(n / workersCount)

	for start = 1, n, perWorker do
		local finish = math.min(start + perWorker - 1, n)
		task.spawn(function()
			self:_runBatch(batch, start, finish)
		end)
	end
end

-- queue one job (returns Future immediately)
function Pool:submit(mod: ModuleScript, arg: any): any
	if self.dead then error("pool is destroyed", 2) end
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("submit needs a modulescript", 2)
	end

	local future = PFTask.new()
	table.insert(self.pending, { mod = mod, arg = arg, future = future })

	if not self.flushScheduled then
		self.flushScheduled = true
		task.defer(function() self:_flush() end)
	end
	return future
end

-- await list of futures
function Pool:awaitAll(futures: {any}): {any}
	local results = table.create(#futures)
	for i, f in futures do
		results[i] = f:Await()
	end
	return results
end

-- learn per-element cost via sample
function Pool:_perElemCost(mod: ModuleScript, data: {any}, n: number): number
	local rec = self.cost[mod]
	if rec then return rec.w end

	local fn = require(mod)
	local k = math.min(n, self.config.calibrationSamples or 16)
	if k < 1 then return 0 end

	local t0 = os.clock()
	for i = 1, k do pcall(fn, data[i]) end -- pcall: a faulty sample element must not crash calibration
	local w = ((os.clock() - t0) * 1000) / k -- ms per element

	self.cost[mod] = { w = w, n = k }
	return w
end

-- measure pure round-trip floor L
function Pool:_calibrateLatency(mod: ModuleScript, data: {any})
	if self.dead then return end
	local k = math.min(#data, self.config.calibrationSamples or 16)
	if k < 1 then return end

	local worker, idx = getWorker(self)
	local thread = coroutine.running()
	local sent = os.clock()
	local rt = 0
	self.handlers[idx] = function()
		self.handlers[idx] = nil
		rt = (os.clock() - sent) * 1000
		task.spawn(thread)
	end
	worker:SendMessage("pf_map", mod, Serializer.encode(data, 1, k))

	local timer = task.delay(self.timeout, function()
		if self.handlers[idx] then
			self.handlers[idx] = nil
			rt = self.config.seedRoundTripMs or 7
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	pcall(task.cancel, timer)

	self.stats.latencyFloorMs = math.max(rt, 0.1)
end

-- decide sequential vs parallel via cost
function Pool:_shouldRunSequential(mod: ModuleScript, data: {any}, n: number): boolean
	local w = self:_perElemCost(mod, data, n)
	local P = #self.workers

	if self.stats.latencyFloorMs <= 0 then
		self:_calibrateLatency(mod, data)
	end
	local L = self.stats.latencyFloorMs
	if L <= 0 then L = self.config.seedRoundTripMs or 7 end

	-- parallel time ~ max(L, compute/P): for light chunks the per-worker compute
	-- hides under the round-trip floor, so the two overlap rather than add.
	local tSeq = n * w
	local tPar = math.max(L, (n * w) / P)
	return tSeq <= tPar
end

-- surface task errors
function Pool:_reportErrors(label: string, errors: any)
	if not errors then return end
	if self.config.onError then
		self.config.onError(string.format("%s: %d element(s) failed; first @ index %d: %s",
			label, #errors, errors[1].index, errors[1].message))
	end
	if self.config.errorMode == "strict" then
		local f = errors[1]
		error(string.format("%s: element %d failed: %s", label, f.index, f.message), 3)
	end
end

function Pool:map(data: {any}, mod: ModuleScript, parentTask: any?): {any}
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("map needs a modulescript", 2)
	end

	local n = #data
	if n == 0 then return {} end

	if not self.warmed[mod] then self:prewarm(mod) end

	-- decide sequential vs parallel: cost model (adaptive) or static threshold
	local runSequential
	if self.config.adaptive then
		runSequential = self:_shouldRunSequential(mod, data, n)
	else
		runSequential = n < (self.config.smallDatasetThreshold or 50)
	end
	if runSequential then
		local fn = require(mod)
		local res = table.create(n)
		local seqErrors = nil
		for i = 1, n do
			local ok, r = pcall(fn, data[i])
			if ok then
				res[i] = r
			else
				seqErrors = seqErrors or {}
				seqErrors[#seqErrors + 1] = { index = i, message = tostring(r) }
			end
		end
		self:_reportErrors("map", seqErrors)
		return res, seqErrors
	end

	local workersCount = #self.workers
	local targetChunks = workersCount * (self.config.loadBalanceFactor or 1)
	local chunkSize = math.ceil(n / targetChunks)

	-- binary pipeline preference
	local sample = data[1]
	local elemSize = Serializer.estimateSize(sample)
	if n > (self.config.smallDatasetThreshold or 50) and elemSize > 100 then
		local targetBytes = 1024 * 1024 -- 1MB target
		if elemSize > 1000 then targetBytes = 512 * 1024 end -- 512KB for heavy data

		local adaptiveSize = math.floor(targetBytes / elemSize)
		-- cap so we keep at least targetChunks pieces (load balancing) on massive payloads
		chunkSize = math.clamp(adaptiveSize, 1, math.max(1, math.floor(n / targetChunks)))
	end

	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false
	local mapErrors = nil

	-- check for sharedtable use
	local shared
	local okShared, ST = pcall(function() return SharedTable end)

	if okShared and ST and n >= (self.config.sharedTableThreshold or 1000) then
		local threshold = type(data[1]) == "table" and (self.config.nestedDataThreshold or 5000) or (self.config.sharedTableThreshold or 1000)
		if n >= threshold then
			pcall(function()
				shared = ST.new(data)
			end)
		end
	end

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		if parentTask and parentTask:IsCancelled() then break end

		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local ok, res, errs
			if shared then
				ok, res, errs = runJob(self, "pf_map_shared", mod, parentTask, start, finish, shared)
			else
				ok, res, errs = runJob(self, "pf_map", mod, parentTask, Serializer.encode(data, start, finish))
			end

			if res then
				-- recover partial results even if some elements errored
				table.move(res, 1, finish - start + 1, start, results)
			elseif not ok then
				_failed = true -- total chunk failure (timeout / worker crash)
			end

			if errs then
				mapErrors = mapErrors or {}
				for _, e in errs do
					mapErrors[#mapErrors + 1] = { index = start + e.index - 1, message = e.message }
				end
			end

			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then 
				task.spawn(thread) 
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end

	if _failed and self.config.onError then
		self.config.onError("map: one or more chunks failed (timeout or worker crash)")
	end
	self:_reportErrors("map", mapErrors)
	return results, mapErrors
end

function Pool:mapAsync(data: {any}, mod: ModuleScript): any
	local t = PFTask.new()
	task.spawn(function()
		-- pcall so "strict" errorMode rejects the future instead of leaking a thread error
		local pok, res, errs = pcall(function() return self:map(data, mod, t) end)
		if pok then
			t.errors = errs
			t:_finish(res, true)
		else
			t.errors = { { index = 0, message = tostring(res) } }
			t:_finish(nil, false)
		end
	end)
	return t
end

function Pool:Map(data: any, mod: ModuleScript, parentTask: any?): any
	if typeof(data) == "buffer" then
		return self:mapBuffer(data, 8, mod, parentTask) -- default stride 8
	elseif type(data) == "table" then
		if typeof(data[1]) == "Vector3" then
			return self:mapVector3(data, mod, parentTask)
		else
			return self:map(data, mod, parentTask)
		end
	end
	error("Unsupported data type for Map", 2)
end

function Pool:filter(data: {any}, mod: ModuleScript, parentTask: any?): {any}
	local mask = self:map(data, mod, parentTask)
	local out = {}
	for i, v in data do
		if mask[i] then table.insert(out, v) end
	end
	return out
end

function Pool:FilterAsync(data: {any}, mod: ModuleScript): any
	local t = PFTask.new()
	task.spawn(function()
		local res = self:filter(data, mod, t)
		t:_finish(res, true)
	end)
	return t
end

function Pool:Pipeline(data: any, steps: {ModuleScript}, parentTask: any?): any
	local current = data
	for _, mod in steps do
		if parentTask and parentTask:IsCancelled() then break end
		current = self:Map(current, mod, parentTask)
	end
	return current
end

function Pool:PipelineAsync(data: any, steps: {ModuleScript}): any
	local t = PFTask.new()
	task.spawn(function()
		local res = self:Pipeline(data, steps, t)
		t:_finish(res, true)
	end)
	return t
end

function Pool:mapTables(data: {any}, mod: ModuleScript, parentTask: any?): {any}
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("mapTables needs a modulescript", 2)
	end

	local n = #data
	if n == 0 then return {} end
	if not self.warmed[mod] then self:prewarm(mod) end

	local workersCount = #self.workers
	local targetChunks = workersCount * (self.config.loadBalanceFactor or 1)
	local chunkSize = math.ceil(n / targetChunks)
	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false
	local mapErrors = nil

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		if parentTask and parentTask:IsCancelled() then break end
		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local ok, res, errs = runJob(self, "pf_map", mod, parentTask, Serializer.encode(data, start, finish))
			if res then
				table.move(res, 1, finish - start + 1, start, results)
			elseif not ok then
				_failed = true
			end
			if errs then
				mapErrors = mapErrors or {}
				for _, e in errs do
					mapErrors[#mapErrors + 1] = { index = start + e.index - 1, message = e.message }
				end
			end
			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then
				task.spawn(thread)
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end

	self:_reportErrors("mapTables", mapErrors)
	return results, mapErrors
end

function Pool:mapTablesAsync(data: {any}, mod: ModuleScript): any
	local t = PFTask.new()
	task.spawn(function()
		local res = self:mapTables(data, mod, t)
		t:_finish(res, true)
	end)
	return t
end

function Pool:mapVector3(data: {Vector3}, mod: ModuleScript, parentTask: any?): {any}
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("mapVector3 needs a modulescript", 2)
	end

	local n = #data
	if n == 0 then return {} end
	if not self.warmed[mod] then self:prewarm(mod) end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		if parentTask and parentTask:IsCancelled() then break end
		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local chunk = buffer.create((finish - start + 1) * 12)
			for i = start, finish do
				local v = data[i]
				local off = (i - start) * 12
				buffer.writef32(chunk, off,     v.X)
				buffer.writef32(chunk, off + 4, v.Y)
				buffer.writef32(chunk, off + 8, v.Z)
			end

			local ok, res = runJob(self, "pf_map_buffer", mod, parentTask, chunk, 12)
			if ok and res then
				table.move(res, 1, finish - start + 1, start, results)
			else
				_failed = true
			end
			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then 
				task.spawn(thread) 
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end
	return results
end

function Pool:mapInto(data: {any}, target: any, mod: ModuleScript, parentTask: any?)
	if typeof(target) ~= "SharedTable" then
		error("mapInto requires a SharedTable target; writes to a plain table do not cross the actor boundary and are silently lost", 2)
	end

	local n = #data
	if n == 0 then return end

	if not self.warmed[mod] then self:prewarm(mod) end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		if parentTask and parentTask:IsCancelled() then break end
		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local ok, _ = runJob(self, "pf_map_into", mod, parentTask, start, finish, data, target)
			if not ok then _failed = true end
			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then 
				task.spawn(thread) 
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end
	if _failed and self.config.onError then self.config.onError("mapInto failed") end
end

function Pool:mapBuffer(data: buffer, stride: number, mod: ModuleScript, parentTask: any?): {any}
	local n = buffer.len(data) / stride
	if n == 0 then return {} end

	if not self.warmed[mod] then self:prewarm(mod) end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local offset = (start - 1) * stride
			local byteSize = (finish - start + 1) * stride
			local chunk = buffer.create(byteSize)
			buffer.copy(chunk, 0, data, offset, byteSize)

			local ok, res = runJob(self, "pf_map_buffer", mod, parentTask, chunk, stride)
			if ok and res then
				table.move(res, 1, finish - start + 1, start, results)
			else
				_failed = true
			end

			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then 
				task.spawn(thread) 
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end
	return results
end

function Pool:mapBufferOut(data: buffer, stride: number, outStride: number, mod: ModuleScript, parentTask: any?): buffer
	local n = buffer.len(data) / stride
	if n == 0 then return buffer.create(0) end

	if not self.warmed[mod] then self:prewarm(mod) end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local resultBuf = buffer.create(n * outStride)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false

	local frameStart = os.clock()
	local budget = self.config.maxFrameMs / 1000

	for start = 1, n, chunkSize do
		if parentTask and parentTask:IsCancelled() then break end
		local finish = math.min(start + chunkSize - 1, n)

		if os.clock() - frameStart > budget then
			task.wait()
			frameStart = os.clock()
		end

		pending += 1
		task.spawn(function()
			local offset = (start - 1) * stride
			local byteSize = (finish - start + 1) * stride
			local chunk = buffer.create(byteSize)
			buffer.copy(chunk, 0, data, offset, byteSize)

			local ok, res = runJob(self, "pf_map_buffer_out", mod, parentTask, chunk, stride, outStride)
			if ok and typeof(res) == "buffer" then
				buffer.copy(resultBuf, (start - 1) * outStride, res, 0, buffer.len(res))
			else
				_failed = true
			end

			pending -= 1
			if pending == 0 and loopFinished and coroutine.status(thread) == "suspended" then 
				task.spawn(thread) 
			end
		end)
	end

	loopFinished = true
	if pending > 0 then coroutine.yield() end
	return resultBuf
end

function Pool:prewarm(mod: ModuleScript)
	if self.warmed[mod] then return end
	self.warmed[mod] = true

	local count = #self.workers
	local pending = count
	local done = Instance.new("BindableEvent")

	for i = 1, count do
		task.spawn(function()
			pcall(function()
				self.workers[i]:SendMessage("pf_warmup", mod)
			end)
			pending -= 1
			if pending == 0 then done:Fire() end
		end)
	end

	task.delay(5, function()
		if pending > 0 then
			pending = 0
			done:Fire()
		end
	end)

	if pending > 0 then
		done.Event:Wait()
	end
	done:Destroy()
end

function Pool:destroy()
	if self.dead then return end
	self.dead = true
	-- settle any futures still waiting in the submit buffer
	for _, job in self.pending do
		job.future:Cancel()
	end
	table.clear(self.pending)
	self.event:Destroy()
	for _, a in self.workers do a:Destroy() end
	table.clear(self.workers)
	table.clear(self.free)
	table.clear(self.handlers)
	table.clear(self.waiters)
end

function Pool:getSize() return self.size end
function Pool:getFreeCount() return #self.free end
function Pool:isClientPool() return game:GetService("RunService"):IsClient() end

-- live pool telemetry
function Pool:getStats()
	local s = self.stats
	local free = #self.free
	local queued = self.waitTail - self.waitHead + 1
	if queued < 0 then queued = 0 end

	-- per-worker last measured compute time, read from the actor attributes
	local lastRunMs = table.create(self.size)
	for i = 1, self.size do
		local a = self.workers[i]
		lastRunMs[i] = (a and a:GetAttribute("PF_LastRunMs")) or 0
	end

	-- learned per-element cost (ms) keyed by module name
	local costModel = {}
	for mod, rec in self.cost do
		costModel[mod.Name] = rec.w
	end

	return {
		size = self.size,
		free = free,
		busy = self.size - free,
		queued = queued,
		dispatched = s.dispatched,
		completed = s.completed,
		failed = s.failed,
		timedOut = s.timedOut,
		avgRoundTripMs = s.avgRoundTripMs,
		latencyFloorMs = s.latencyFloorMs,
		perWorker = table.clone(s.perWorker),
		lastRunMs = lastRunMs,
		costModel = costModel,
	}
end

return Flow
