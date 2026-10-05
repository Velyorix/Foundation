local Scheduler = {}
Scheduler.__index = Scheduler

local Task = {}
Task.__index = Task

local Debounced = {}
Debounced.__index = Debounced

local Throttled = {}
Throttled.__index = Throttled

Scheduler.MIN_INTERVAL = 10
Scheduler.MAX_DELAY = 2147483647
Scheduler.DEFAULT_MAX_FAILURES = 3

-- options: timer (SetTimeout, SetInterval, ClearTimeout, ClearInterval), now_ms,
-- invoker, ownership, check, log
function Scheduler.new(options)
	return setmetatable({
		timer = options.timer,
		now_ms = options.now_ms,
		invoker = options.invoker,
		ownership = options.ownership,
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
		log = options.log,
		sequence = 0,
		active = {},
	}, Scheduler)
end

-- `level` as for Check: 2 is the caller of the scheduler method.
function Scheduler:check_delay(api, index, name, value, minimum, level)
	self.check:Argument(api, index, name, value, "integer", level + 1)
	if value < minimum or value > Scheduler.MAX_DELAY then
		self.errors:Raise("invalid_value", {
			api = api,
			index = index,
			name = name,
			reason = self.messages:Format("reason.delay_range", { min = minimum, max = Scheduler.MAX_DELAY }),
		}, level + 1)
	end
end

function Scheduler:new_task(owner, kind, fn, delay)
	self.sequence = self.sequence + 1
	local task = setmetatable({
		id = self.sequence,
		owner = owner,
		kind = kind,
		fn = fn,
		delay = delay,
		state = "scheduled",
		runs = 0,
		failures = 0,
		scheduler = self,
	}, Task)
	task.info = { owner = owner, kind = "task", fields = { task = kind, id = task.id } }
	task.handle = self.ownership:Track(owner, "task", function()
		task:stop("cancelled")
	end, { kind = kind, delay = delay })
	self.active[task] = true
	return task
end

function Task:stop(state)
	if self.state ~= "scheduled" and self.state ~= "running" then
		return false
	end
	self.state = state
	local scheduler = self.scheduler
	if self.timer_id then
		if self.kind == "repeat" then
			scheduler.timer.ClearInterval(self.timer_id)
		else
			scheduler.timer.ClearTimeout(self.timer_id)
		end
		self.timer_id = nil
	end
	scheduler.active[self] = nil
	if self.handle:IsActive() then
		self.handle:Release()
	end
	return true
end

function Task:Cancel()
	return self:stop("cancelled")
end

function Task:IsActive()
	return self.state == "scheduled" or self.state == "running"
end

function Task:GetState()
	return self.state
end

function Task:GetRuns()
	return self.runs
end

function Task:run_once()
	if self.state ~= "scheduled" then
		return
	end
	self.timer_id = nil
	self.state = "running"
	self.runs = 1
	local ok = self.scheduler.invoker:Call(self.info, self.fn)
	self:stop(ok and "completed" or "failed")
end

function Scheduler:schedule_once(owner, kind, fn, delay)
	local task = self:new_task(owner, kind, fn, delay)
	task.timer_id = self.timer.SetTimeout(function()
		task:run_once()
	end, delay)
	return task
end

function Scheduler:NextTick(owner, fn, api, level)
	self.check:Argument(api, 1, "fn", fn, "function", level)
	return self:schedule_once(owner, "next_tick", fn, 0)
end

function Scheduler:Delay(owner, milliseconds, fn, api, level)
	self:check_delay(api, 1, "milliseconds", milliseconds, 0, level)
	self.check:Argument(api, 2, "fn", fn, "function", level)
	return self:schedule_once(owner, "delay", fn, milliseconds)
end

function Scheduler:Repeat(owner, milliseconds, fn, options, api, level)
	self:check_delay(api, 1, "milliseconds", milliseconds, Scheduler.MIN_INTERVAL, level)
	self.check:Argument(api, 2, "fn", fn, "function", level)
	self.check:Argument(api, 3, "options", options, "table?", level)
	options = options or {}
	self.check:Argument(api, 3, "options.max_failures", options.max_failures, "integer?", level)
	local task = self:new_task(owner, "repeat", fn, milliseconds)
	task.max_failures = options.max_failures or Scheduler.DEFAULT_MAX_FAILURES
	task.timer_id = self.timer.SetInterval(function()
		if task.state ~= "scheduled" then
			return false
		end
		task.state = "running"
		task.runs = task.runs + 1
		local ok, result = self.invoker:Call(task.info, task.fn)
		if task.state ~= "running" then
			return false
		end
		task.state = "scheduled"
		if not ok then
			task.failures = task.failures + 1
			if task.failures >= task.max_failures then
				self.log
					:For(owner, "scheduler")
					:Warning("scheduler.task_stopped", { owner = owner, failures = task.failures })
				task:stop("failed")
				return false
			end
			return
		end
		task.failures = 0
		if result == false then
			task:stop("completed")
			return false
		end
	end, milliseconds)
	return task
end

-- Runs fn(...) with the arguments of the last Trigger once no Trigger happened for
-- `milliseconds`.
function Scheduler:Debounce(owner, milliseconds, fn, api, level)
	self:check_delay(api, 1, "milliseconds", milliseconds, 0, level)
	self.check:Argument(api, 2, "fn", fn, "function", level)
	local debounced = setmetatable({ scheduler = self, owner = owner, milliseconds = milliseconds, fn = fn }, Debounced)
	debounced.handle = self.ownership:Track(owner, "debounce", function()
		debounced.stopped = true
		if debounced.task then
			debounced.task:Cancel()
		end
	end)
	return debounced
end

function Debounced:Trigger(...)
	if self.stopped then
		return false
	end
	if self.task then
		self.task:Cancel()
	end
	local arguments = table.pack(...)
	self.task = self.scheduler:schedule_once(self.owner, "debounce", function()
		self.fn(table.unpack(arguments, 1, arguments.n))
	end, self.milliseconds)
	return true
end

function Debounced:Cancel()
	if self.task then
		return self.task:Cancel()
	end
	return false
end

-- Runs fn(...) immediately at most once per `milliseconds`; extra calls are dropped.
function Scheduler:Throttle(owner, milliseconds, fn, api, level)
	self:check_delay(api, 1, "milliseconds", milliseconds, 0, level)
	self.check:Argument(api, 2, "fn", fn, "function", level)
	local throttled = setmetatable({
		scheduler = self,
		milliseconds = milliseconds,
		fn = fn,
		info = { owner = owner, kind = "task", fields = { task = "throttle" } },
	}, Throttled)
	throttled.handle = self.ownership:Track(owner, "throttle", function()
		throttled.stopped = true
	end)
	return throttled
end

-- Returns true when fn ran.
function Throttled:Trigger(...)
	if self.stopped then
		return false
	end
	local now = self.scheduler.now_ms()
	if self.last and now - self.last < self.milliseconds then
		return false
	end
	self.last = now
	self.scheduler.invoker:Call(self.info, self.fn, ...)
	return true
end

function Throttled:Cancel()
	self.stopped = true
	if self.handle:IsActive() then
		self.handle:Release()
	end
end

function Scheduler:Snapshot()
	local owners, total = {}, 0
	for task in pairs(self.active) do
		local stats = owners[task.owner]
		if not stats then
			stats = { next_tick = 0, delay = 0, ["repeat"] = 0, debounce = 0 }
			owners[task.owner] = stats
		end
		stats[task.kind] = stats[task.kind] + 1
		total = total + 1
	end
	return { active = total, owners = owners }
end

return Scheduler
