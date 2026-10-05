-- Manual-clock replacement for the engine Timer: nothing fires until Advance is called.
local FakeTimer = {}
FakeTimer.__index = FakeTimer

function FakeTimer.new()
	local timer = setmetatable({ now = 0, next_id = 0, timers = {} }, FakeTimer)
	timer.api = {
		SetTimeout = function(fn, milliseconds)
			return timer:add(fn, milliseconds or 0, nil)
		end,
		SetInterval = function(fn, milliseconds)
			return timer:add(fn, milliseconds or 0, milliseconds or 0)
		end,
		ClearTimeout = function(id)
			timer.timers[id] = nil
		end,
		ClearInterval = function(id)
			timer.timers[id] = nil
		end,
	}
	return timer
end

function FakeTimer:add(fn, delay, interval)
	self.next_id = self.next_id + 1
	self.timers[self.next_id] = { at = self.now + delay, fn = fn, interval = interval }
	return self.next_id
end

function FakeTimer:Now()
	return self.now
end

function FakeTimer:Pending()
	local count = 0
	for _ in pairs(self.timers) do
		count = count + 1
	end
	return count
end

function FakeTimer:Advance(milliseconds)
	local target = self.now + milliseconds
	while true do
		local next_id, next_timer
		for id, timer in pairs(self.timers) do
			if
				timer.at <= target
				and (not next_timer or timer.at < next_timer.at or (timer.at == next_timer.at and id < next_id))
			then
				next_id, next_timer = id, timer
			end
		end
		if not next_timer then
			break
		end
		self.now = math.max(self.now, next_timer.at)
		local keep = next_timer.fn()
		if self.timers[next_id] == next_timer then
			if next_timer.interval and keep ~= false then
				next_timer.at = next_timer.at + math.max(next_timer.interval, 1)
			else
				self.timers[next_id] = nil
			end
		end
	end
	self.now = target
end

return FakeTimer
