--!strict
local Task = {}
Task.__index = Task

-- represents a running parallel task

function Task.new(id)
	local self = setmetatable({
		id = id,
		cancelled = false,
		completed = false,
		_onComplete = nil,
	}, Task)
	return self
end

function Task:Cancel()
	if self.completed then return end
	self.cancelled = true
end

function Task:IsCancelled()
	return self.cancelled
end

function Task:Wait()
	while not self.completed and not self.cancelled do
		task.wait()
	end
end

function Task:_finish(res, ok)
	self.completed = true
	if self._onComplete and not self.cancelled then
		task.spawn(self._onComplete, res, ok)
	end
end

function Task:OnComplete(fn)
	self._onComplete = fn
	return self
end

return Task
