local Futures = {}
Futures.__index = Futures

local Future = {}
Future.__index = Future

-- options: invoker, ownership, scheduler (optional, for Timeout), check
function Futures.new(options)
	return setmetatable({
		invoker = options.invoker,
		ownership = options.ownership,
		scheduler = options.scheduler,
		check = options.check,
		errors = options.check.errors,
		messages = options.check.errors.messages,
	}, Futures)
end

function Futures.IsFuture(value)
	return type(value) == "table" and getmetatable(value) == Future
end

function Futures:Create(owner)
	local future = setmetatable({
		owner = owner,
		manager = self,
		state = "pending",
		callbacks = {},
		info = { owner = owner, kind = "future_callback" },
	}, Future)
	future.handle = self.ownership:Track(owner, "future", function()
		future:Cancel()
	end)
	return future
end

function Future:settle(state, payload)
	if self.state ~= "pending" then
		return false
	end
	self.state = state
	if state == "resolved" then
		self.value = payload
	elseif state == "rejected" then
		self.error = payload
	end
	local callbacks = self.callbacks
	self.callbacks = {}
	if self.handle:IsActive() then
		self.handle:Release()
	end
	for _, callback in ipairs(callbacks) do
		callback(state, payload)
	end
	return true
end

function Future:Resolve(value)
	return self:settle("resolved", value)
end

function Future:Reject(err)
	return self:settle("rejected", err)
end

-- Pending callbacks never run after cancellation.
function Future:Cancel()
	return self:settle("cancelled")
end

function Future:GetState()
	return self.state
end

function Future:IsDone()
	return self.state ~= "pending"
end

function Future:GetValue()
	return self.value
end

function Future:GetError()
	return self.error
end

function Future:on_settle(callback)
	if self.state == "pending" then
		self.callbacks[#self.callbacks + 1] = callback
	else
		callback(self.state, self.state == "resolved" and self.value or self.error)
	end
end

-- Settles `target` with the outcome of handler(payload), adopting returned futures.
function Future:run_handler(target, handler, payload)
	local ok, result = self.manager.invoker:Call(self.info, handler, payload)
	if not ok then
		target:Reject(self.manager.errors:New("async_failed", nil, { owner = self.owner, cause = result }))
	elseif Futures.IsFuture(result) then
		result:on_settle(function(state, value)
			target:settle(state, value)
		end)
	else
		target:Resolve(result)
	end
end

function Future:Then(on_resolved, on_rejected)
	local check = self.manager.check
	check:Argument("future:Then", 1, "on_resolved", on_resolved, "function?")
	check:Argument("future:Then", 2, "on_rejected", on_rejected, "function?")
	local next_future = self.manager:Create(self.owner)
	self:on_settle(function(state, payload)
		if state == "resolved" then
			if on_resolved then
				self:run_handler(next_future, on_resolved, payload)
			else
				next_future:Resolve(payload)
			end
		elseif state == "rejected" then
			if on_rejected then
				self:run_handler(next_future, on_rejected, payload)
			else
				next_future:Reject(payload)
			end
		else
			next_future:Cancel()
		end
	end)
	return next_future
end

function Future:Catch(on_rejected)
	self.manager.check:Argument("future:Catch", 1, "on_rejected", on_rejected, "function")
	local next_future = self:Then(nil, on_rejected)
	return next_future
end

-- Runs `fn` on resolution or rejection and passes the original outcome through.
function Future:Finally(fn)
	self.manager.check:Argument("future:Finally", 1, "fn", fn, "function")
	local next_future = self.manager:Create(self.owner)
	self:on_settle(function(state, payload)
		if state ~= "cancelled" then
			self.manager.invoker:Call(self.info, fn)
		end
		next_future:settle(state, payload)
	end)
	return next_future
end

-- Rejects with a `timeout` error when still pending after `milliseconds`; returns self.
function Future:Timeout(milliseconds)
	local manager = self.manager
	manager.check:Argument("future:Timeout", 1, "milliseconds", milliseconds, "integer")
	if not manager.scheduler then
		manager.errors:Raise("invalid_state", {
			api = "future:Timeout",
			reason = manager.messages:Format("reason.no_scheduler"),
		})
	end
	if self.state == "pending" then
		local task = manager.scheduler:Delay(self.owner, milliseconds, function()
			self:Reject(manager.errors:New("timeout", { milliseconds = milliseconds }, { owner = self.owner }))
		end, "future:Timeout", 2)
		self:on_settle(function()
			task:Cancel()
		end)
	end
	return self
end

-- `level` as for Check, seen from the caller of New.
function Futures:New(owner, executor, api, level)
	self.check:Argument(api, 1, "executor", executor, "function?", level)
	local future = self:Create(owner)
	if executor then
		local ok, err = self.invoker:Call(future.info, executor, function(value)
			return future:Resolve(value)
		end, function(reason)
			return future:Reject(reason)
		end)
		if not ok then
			future:Reject(self.errors:New("async_failed", nil, { owner = owner, cause = err }))
		end
	end
	return future
end

function Futures:All(owner, futures, api, level)
	self.check:Argument(api, 1, "futures", futures, "table", level)
	for index, item in ipairs(futures) do
		if not Futures.IsFuture(item) then
			self.errors:Raise("invalid_argument", {
				api = api,
				index = 1,
				name = "futures[" .. index .. "]",
				expected = "future",
				actual = type(item),
			}, level + 1)
		end
	end
	local combined = self:Create(owner)
	local results, remaining = {}, #futures
	if remaining == 0 then
		combined:Resolve(results)
		return combined
	end
	for index, item in ipairs(futures) do
		item:on_settle(function(state, payload)
			if state == "resolved" then
				results[index] = payload
				remaining = remaining - 1
				if remaining == 0 then
					combined:Resolve(results)
				end
			elseif state == "rejected" then
				combined:Reject(payload)
			else
				combined:Cancel()
			end
		end)
	end
	return combined
end

return Futures
