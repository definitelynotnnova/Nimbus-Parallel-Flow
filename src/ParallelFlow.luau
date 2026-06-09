--!strict
local Serializer = require(script.Serializer)
local PFTask = require(script.PFTask)

local DEFAULT_CONFIG = {
	size = 4,
	timeout = 10,
	smallDatasetThreshold = 50,
	sharedTableThreshold = 1000,
	nestedDataThreshold = 10000,
	maxFrameMs = 6, -- Default budget: ~6ms
}

local Flow = {}
local Pool = {}
Pool.__index = Pool

-- helper to create our actors
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

-- grab a free worker or wait for one to show up
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

-- send worker back to the pool
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

-- internal runner for worker tasks
local function runJob(p, kind: string, mod: ModuleScript, parentTask: any?, ...): (boolean, any)
	local worker, idx = getWorker(p)
	local thread = coroutine.running()
	local decoded, ok, timeout

	p.handlers[idx] = function(enc: buffer?, success: boolean)
		p.handlers[idx] = nil
		ok = success
		decoded = enc and Serializer.decode(enc) or nil

		-- If task was cancelled mid-flight, we still return the worker but ignore result
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

	return ok, decoded
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

	local ready = 0
	event.Event:Connect(function(id, enc, ok)
		if not enc and ok == nil then
			ready += 1
			return
		end

		if p.dead then return end
		local h = p.handlers[id]
		if h then
			p.handlers[id] = nil
			h(enc, ok)
		end
		putWorker(p, id)
	end)

	for i = 1, size do
		p.workers[i] = spawn(runner, container, event, i)
		table.insert(p.free, i)
	end

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

function Pool:map(data: {any}, mod: ModuleScript, parentTask: any?): {any}
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("map needs a modulescript", 2)
	end

	local n = #data
	if n == 0 then return {} end

	if not self.warmed[mod] then self:prewarm(mod) end

	-- run sequential if dataset is tiny
	if n < (self.config.smallDatasetThreshold or 50) then
		local fn = require(mod)
		local res = table.create(n)
		for i, v in data do res[i] = fn(v) end
		return res
	end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)

	-- V18: Binary Pipeline Preference & Coarse Batching
	local sample = data[1]
	local elemSize = Serializer.estimateSize(sample)
	if n > (self.config.smallDatasetThreshold or 50) and elemSize > 100 then
		local targetBytes = 1024 * 1024 -- 1MB target
		if elemSize > 1000 then targetBytes = 512 * 1024 end -- 512KB for heavy data

		local adaptiveSize = math.floor(targetBytes / elemSize)
		-- Revert to 1 chunk per worker for balanced massive payloads
		chunkSize = math.clamp(adaptiveSize, 1, math.max(1, math.floor(n / workersCount)))
	end

	if self.config.maxChunkSize and chunkSize > self.config.maxChunkSize then
		chunkSize = self.config.maxChunkSize
	end

	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local _failed = false
	local loopFinished = false

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
			local ok, res
			if shared then
				ok, res = runJob(self, "pf_map_shared", mod, parentTask, start, finish, shared)
			else
				ok, res = runJob(self, "pf_map", mod, parentTask, Serializer.encode(data, start, finish))
			end

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
	if _failed and self.config.onError then
		self.config.onError("map finished with some errors")
	end
	return results
end

function Pool:mapAsync(data: {any}, mod: ModuleScript): any
	local t = PFTask.new()
	task.spawn(function()
		local res = self:map(data, mod, t)
		t:_finish(res, true)
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
			local ok, res = runJob(self, "pf_map", mod, parentTask, Serializer.encode(data, start, finish))
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

return Flow
