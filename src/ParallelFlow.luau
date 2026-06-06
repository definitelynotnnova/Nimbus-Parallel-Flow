-- core logic for parallel flow pools
local Serializer = require(script.Serializer)

local DEFAULT_CONFIG = {
	size = 4,
	timeout = 10,
	smallDatasetThreshold = 50,
	sharedTableThreshold = 1000,
	nestedDataThreshold = 5000,
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
local function runJob(p, kind: string, mod: ModuleScript, ...): (boolean, any)
	local worker, idx = getWorker(p)
	local thread = coroutine.running()
	local decoded, ok, timeout

	p.handlers[idx] = function(enc: buffer?, success: boolean)
		p.handlers[idx] = nil
		ok = success
		decoded = enc and Serializer.decode(enc) or nil
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
	return ok, decoded
end

function Flow.createPool(config)
	local cfg = table.clone(DEFAULT_CONFIG)
	if config then
		for k, v in config do cfg[k] = v end
	end

	local size = math.clamp(cfg.size or 4, 1, 64)
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

	local ready, running = 0, coroutine.running()
	event.Event:Connect(function(id, enc, ok)
		if not enc and ok == nil then
			ready += 1
			if ready == size and coroutine.status(running) == "suspended" then task.spawn(running) end
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

	if ready < size then
		task.delay(5, function() if ready < size then ready = size; task.spawn(running) end end)
		coroutine.yield()
	end

	return p
end

function Pool:dispatch(mod: ModuleScript, data: any): any?
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("dispatch needs a modulescript", 2)
	end

	local ok, res = runJob(self, "pf_task", mod, Serializer.encode(data))
	if not ok then
		if self.config.onError then self.config.onError("dispatch failed") end
		return nil
	end
	return res
end

function Pool:map(data: {any}, mod: ModuleScript): {any}
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		error("map needs a modulescript", 2)
	end

	local n = #data
	if n == 0 then return {} end

	-- run sequential if dataset is tiny
	if n < (self.config.smallDatasetThreshold or 50) then
		local fn = require(mod)
		local res = table.create(n)
		for i, v in data do res[i] = fn(v) end
		return res
	end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local failed = false

	-- check for sharedtable use
	local shared
	local okShared, ST = pcall(function() return SharedTable end)

	if okShared and ST and n >= (self.config.sharedTableThreshold or 1000) then
		local threshold = type(data[1]) == "table" and (self.config.nestedDataThreshold or 5000) or (self.config.sharedTableThreshold or 1000)
		if n >= threshold then
			shared = ST.new(data)
		end
	end

	for i = 1, workersCount do
		local start = (i - 1) * chunkSize + 1
		local finish = math.min(i * chunkSize, n)
		if start > n then break end

		pending += 1
		task.spawn(function()
			local ok, res
			if shared then
				ok, res = runJob(self, "pf_map_shared", mod, start, finish, shared)
			else
				ok, res = runJob(self, "pf_map", mod, Serializer.encode(data, start, finish))
			end

			if ok and res then
				table.move(res, 1, finish - start + 1, start, results)
			else
				failed = true
			end

			pending -= 1
			if pending == 0 then task.spawn(thread) end
		end)
	end

	coroutine.yield()
	if failed and self.config.onError then
		self.config.onError("map finished with some errors")
	end
	return results
end

function Pool:mapInto(data: {any}, target: any, mod: ModuleScript)
	local n = #data
	if n == 0 then return end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	local pending = 0
	local thread = coroutine.running()
	local failed = false

	for i = 1, workersCount do
		local start = (i - 1) * chunkSize + 1
		local finish = math.min(i * chunkSize, n)
		if start > n then break end

		pending += 1
		task.spawn(function()
			local ok, _ = runJob(self, "pf_map_into", mod, start, finish, data, target)
			if not ok then failed = true end
			pending -= 1
			if pending == 0 then task.spawn(thread) end
		end)
	end

	coroutine.yield()
	if failed and self.config.onError then self.config.onError("mapInto failed") end
end

function Pool:mapBuffer(data: buffer, stride: number, mod: ModuleScript): {any}
	local n = buffer.len(data) / stride
	if n == 0 then return {} end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	local pending = 0
	local results = table.create(n)
	local thread = coroutine.running()
	local failed = false

	for i = 1, workersCount do
		local start = (i - 1) * chunkSize + 1
		local finish = math.min(i * chunkSize, n)
		if start > n then break end

		pending += 1
		task.spawn(function()
			local offset = (start - 1) * stride
			local size = (finish - start + 1) * stride
			local chunk = buffer.create(size)
			buffer.copy(chunk, 0, data, offset, size)

			local ok, res = runJob(self, "pf_map_buffer", mod, chunk, stride)
			if ok and res then
				table.move(res, 1, finish - start + 1, start, results)
			else
				failed = true
			end

			pending -= 1
			if pending == 0 then task.spawn(thread) end
		end)
	end

	coroutine.yield()
	return results
end

function Pool:mapBufferOut(data: buffer, stride: number, outStride: number, mod: ModuleScript): buffer
	local n = buffer.len(data) / stride
	if n == 0 then return buffer.create(0) end

	local workersCount = #self.workers
	local chunkSize = math.ceil(n / workersCount)
	local pending = 0
	local resultBuf = buffer.create(n * outStride)
	local thread = coroutine.running()
	local failed = false

	for i = 1, workersCount do
		local start = (i - 1) * chunkSize + 1
		local finish = math.min(i * chunkSize, n)
		if start > n then break end

		pending += 1
		task.spawn(function()
			local offset = (start - 1) * stride
			local size = (finish - start + 1) * stride
			local chunk = buffer.create(size)
			buffer.copy(chunk, 0, data, offset, size)

			local ok, res = runJob(self, "pf_map_buffer_out", mod, chunk, stride, outStride)
			if ok and typeof(res) == "buffer" then
				buffer.copy(resultBuf, (start - 1) * outStride, res, 0, buffer.len(res))
			else
				failed = true
			end

			pending -= 1
			if pending == 0 then task.spawn(thread) end
		end)
	end

	coroutine.yield()
	return resultBuf
end

function Pool:prewarm(mod: ModuleScript)
	local count = #self.workers
	local pending = count
	local thread = coroutine.running()

	for i = 1, count do
		task.spawn(function()
			pcall(function()
				runJob(self, "pf_task", mod, Serializer.encode(nil))
			end)
			pending -= 1
			if pending == 0 then task.spawn(thread) end
		end)
	end

	task.delay(2, function()
		if pending > 0 then
			pending = 0
			task.spawn(thread)
		end
	end)
	coroutine.yield()
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

return Flow
