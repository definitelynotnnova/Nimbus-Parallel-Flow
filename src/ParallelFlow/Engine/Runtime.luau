local Runtime = {}

local cache = {}
local history = {}
local MAX_CACHE = 50

-- helper to get and cache modules
local function loadModule(mod, idx)
	local c = cache[mod]
	if c then return c end

	-- roblox won't let us require in parallel, so we jump to serial
	task.synchronize()
	local ok, fn = pcall(require, mod)
	if ok then
		if #history >= MAX_CACHE then
			local old = table.remove(history, 1)
			if old then cache[old] = nil end
		end
		cache[mod] = fn
		table.insert(history, mod)
	else
		warn("worker " .. idx .. " couldn't load module: " .. tostring(fn))
	end
	task.desynchronize()
	
	return cache[mod]
end

-- deep promote sharedtables to plain tables
local function promote(val)
	if typeof(val) == "SharedTable" or type(val) == "table" then
		local t = {}
		for k, v in val do t[k] = promote(v) end
		return t
	end
	return val
end

function Runtime.start(actor, Lib)
	local wid = actor:GetAttribute("PF_Index") or 0
	local ref = actor:WaitForChild("PF_ResultEvent", 5)
	if not ref then
		warn("worker " .. actor.Name .. " is missing the result event")
		return
	end
	
	local event = ref.Value
	local Serializer = Lib -- using the injected serializer

	-- standard dispatch
	actor:BindToMessageParallel("pf_task", function(mod, args)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local raw = Serializer.decode(args)
		local ok, res = pcall(fn, raw)

		task.synchronize()
		event:Fire(wid, ok and Serializer.encode(res) or nil, ok)
	end)

	task.synchronize()
	event:Fire(wid) -- handshake

	-- basic parallel map
	actor:BindToMessageParallel("pf_map", function(mod, buf)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local data = Serializer.decode(buf)
		if not data then return end

		local n = #data
		local out = table.create(n)
		local failed = false

		for i = 1, n do
			local ok, res = pcall(fn, data[i])
			if ok then out[i] = res else failed = true break end
		end

		task.synchronize()
		event:Fire(wid, not failed and Serializer.encode(out) or nil, not failed)
	end)

	-- sharedtable map
	actor:BindToMessageParallel("pf_map_shared", function(mod, start, finish, shared)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local n = finish - start + 1
		local out = table.create(n)
		local failed = false

		for i = 1, n do
			local val = shared[start + i - 1]
			local ok, res = pcall(fn, promote(val))
			if ok then out[i] = res else failed = true break end
		end

		task.synchronize()
		event:Fire(wid, not failed and Serializer.encode(out) or nil, not failed)
	end)

	-- binary buffer map
	actor:BindToMessageParallel("pf_map_buffer", function(mod, buf, stride)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local n = buffer.len(buf) / stride
		local out = table.create(n)
		local failed = false

		for i = 1, n do
			local ok, res = pcall(fn, buf, (i - 1) * stride)
			if ok then out[i] = res else failed = true break end
		end

		task.synchronize()
		event:Fire(wid, not failed and Serializer.encode(out) or nil, not failed)
	end)

	-- map directly into a target table
	actor:BindToMessageParallel("pf_map_into", function(mod, start, finish, data, target)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local n = finish - start + 1
		local failed = false

		local input = data
		if typeof(data) == "SharedTable" then
			input = table.create(n)
			for i = 1, n do input[i] = promote(data[start + i - 1]) end
		end

		for i = 1, n do
			local val = (typeof(data) == "SharedTable") and input[i] or data[start + i - 1]
			local ok, res = pcall(fn, val)
			if ok then target[start + i - 1] = res else failed = true break end
		end

		task.synchronize()
		event:Fire(wid, nil, not failed)
	end)

	-- binary in, binary out
	actor:BindToMessageParallel("pf_map_buffer_out", function(mod, buf, stride, outStride)
		local fn = loadModule(mod, wid)
		if not fn then return end

		local n = buffer.len(buf) / stride
		local res = buffer.create(n * outStride)
		local ok = true

		for i = 1, n do
			local success = pcall(fn, buf, (i - 1) * stride, res, (i - 1) * outStride)
			if not success then ok = false break end
		end

		task.synchronize()
		event:Fire(wid, ok and res or nil, ok)
	end)
end

return Runtime
