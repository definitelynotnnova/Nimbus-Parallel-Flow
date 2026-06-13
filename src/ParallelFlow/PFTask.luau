--!strict
local Task = {}
Task.__index = Task

-- represents a running parallel task / future

function Task.new(id)
	local self = setmetatable({
		id = id,
		cancelled = false,
		completed = false,
		ok = false,
		result = nil,
		_onComplete = nil,
		_waiters = nil, -- threads parked in :Await()/:Wait()
	}, Task)
	return self
end

local function wake(self)
	if self._waiters then
		local ws = self._waiters
		self._waiters = nil
		for _, th in ws do
			task.spawn(th)
		end
	end
end

function Task:Cancel()
	if self.completed then return end
	self.cancelled = true
	wake(self) -- unblock anyone waiting
end

function Task:IsCancelled()
	return self.cancelled
end

function Task:IsCompleted()
	return self.completed
end

-- Yields until the task settles and RETURNS the result (nil if cancelled/failed).
function Task:Await()
	if not self.completed and not self.cancelled then
		self._waiters = self._waiters or {}
		table.insert(self._waiters, coroutine.running())
		coroutine.yield()
	end
	return self.result
end

-- Backward-compatible: yields until settled, no return value.
function Task:Wait()
	self:Await()
end

function Task:_finish(res, ok)
	if self.completed or self.cancelled then return end
	self.completed = true
	self.result = res
	self.ok = ok
	if self._onComplete then
		task.spawn(self._onComplete, res, ok)
	end
	wake(self)
end

function Task:OnComplete(fn)
	-- if already settled, fire immediately
	if self.completed and not self.cancelled then
		task.spawn(fn, self.result, self.ok)
	else
		self._onComplete = fn
	end
	return self
end

return Task
