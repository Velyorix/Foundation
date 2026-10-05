local FakeTimer = require("tests.support.fake_timer")

local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local timer = FakeTimer.new()
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
		now_ms = function()
			return timer:Now()
		end,
		timer = timer.api,
	})
	runtime:Start()
	local native = {
		GetName = function()
			return "clock"
		end,
		Subscribe = function() end,
	}
	local context = runtime.packages:Register(native, { api = "0.1" })
	return runtime, context, timer, lines
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

describe("Scheduler", function()
	local runtime, context, timer, lines

	before_each(function()
		runtime, context, timer, lines = setup()
	end)

	describe("one-shot tasks", function()
		it("runs NextTick on the next timer pass, not synchronously", function()
			local ran = false
			local task = context:NextTick(function()
				ran = true
			end)
			expect.falsy(ran)
			expect.equal(task:GetState(), "scheduled")
			timer:Advance(0)
			expect.truthy(ran)
			expect.equal(task:GetState(), "completed")
			expect.equal(task:GetRuns(), 1)
			expect.falsy(task:IsActive())
		end)

		it("runs Delay after the given time", function()
			local ran = false
			context:Delay(100, function()
				ran = true
			end)
			timer:Advance(99)
			expect.falsy(ran)
			timer:Advance(1)
			expect.truthy(ran)
		end)

		it("can be cancelled once", function()
			local ran = false
			local task = context:Delay(50, function()
				ran = true
			end)
			expect.truthy(task:Cancel())
			expect.falsy(task:Cancel())
			timer:Advance(100)
			expect.falsy(ran)
			expect.equal(task:GetState(), "cancelled")
			expect.equal(timer:Pending(), 0)
		end)

		it("marks a failing task as failed and logs it for the package", function()
			local task = context:Delay(10, function()
				error("task exploded")
			end)
			timer:Advance(10)
			expect.equal(task:GetState(), "failed")
			expect.contains(text(lines), "task callback of clock failed id=1 task=delay")
			expect.contains(text(lines), "task exploded")
		end)

		it("forgets finished tasks", function()
			context:Delay(10, function() end)
			expect.equal(runtime.ownership:Count("clock", "task"), 1)
			expect.equal(runtime.scheduler:Snapshot().active, 1)
			timer:Advance(10)
			expect.equal(runtime.ownership:Count("clock", "task"), 0)
			expect.equal(runtime.scheduler:Snapshot().active, 0)
		end)
	end)

	describe("repeating tasks", function()
		it("runs every interval until cancelled", function()
			local runs = 0
			local task = context:Repeat(100, function()
				runs = runs + 1
			end)
			timer:Advance(350)
			expect.equal(runs, 3)
			expect.equal(task:GetRuns(), 3)
			task:Cancel()
			timer:Advance(500)
			expect.equal(runs, 3)
			expect.equal(timer:Pending(), 0)
		end)

		it("stops when the callback returns false", function()
			local runs = 0
			local task = context:Repeat(10, function()
				runs = runs + 1
				return runs < 2
			end)
			timer:Advance(100)
			expect.equal(runs, 2)
			expect.equal(task:GetState(), "completed")
		end)

		it("stops after consecutive failures and resets the count after a success", function()
			local runs = 0
			local task = context:Repeat(10, function()
				runs = runs + 1
				if runs ~= 3 then
					error("tick failed")
				end
			end, { max_failures = 3 })
			timer:Advance(100)
			expect.equal(runs, 6, "fail, fail, success (reset), fail, fail, fail")
			expect.equal(task:GetState(), "failed")
			expect.contains(text(lines), "repeating task of clock stopped after 3 consecutive failures")
		end)

		it("can cancel itself from its callback", function()
			local task
			task = context:Repeat(10, function()
				task:Cancel()
			end)
			timer:Advance(100)
			expect.equal(task:GetRuns(), 1)
			expect.equal(task:GetState(), "cancelled")
		end)
	end)

	describe("debounce and throttle", function()
		it("runs a debounced function once, with the last arguments, after a quiet period", function()
			local calls = {}
			local debounced = context:Debounce(100, function(value)
				calls[#calls + 1] = value
			end)
			debounced:Trigger("a")
			timer:Advance(50)
			debounced:Trigger("b")
			timer:Advance(99)
			expect.same(calls, {})
			timer:Advance(1)
			expect.same(calls, { "b" })
		end)

		it("can cancel a pending debounced call", function()
			local ran = false
			local debounced = context:Debounce(10, function()
				ran = true
			end)
			debounced:Trigger()
			expect.truthy(debounced:Cancel())
			timer:Advance(20)
			expect.falsy(ran)
		end)

		it("runs a throttled function at most once per period", function()
			local calls = 0
			local throttled = context:Throttle(100, function()
				calls = calls + 1
			end)
			expect.truthy(throttled:Trigger())
			expect.falsy(throttled:Trigger())
			timer:Advance(99)
			expect.falsy(throttled:Trigger())
			timer:Advance(1)
			expect.truthy(throttled:Trigger())
			expect.equal(calls, 2)
			throttled:Cancel()
			timer:Advance(200)
			expect.falsy(throttled:Trigger())
		end)
	end)

	it("cancels everything a package scheduled when it is disabled", function()
		local ran = {}
		context:Delay(10, function()
			ran[#ran + 1] = "delay"
		end)
		context:Repeat(10, function()
			ran[#ran + 1] = "repeat"
		end)
		local debounced = context:Debounce(10, function()
			ran[#ran + 1] = "debounce"
		end)
		local throttled = context:Throttle(10, function()
			ran[#ran + 1] = "throttle"
		end)
		debounced:Trigger()
		runtime.packages:Disable("clock", "unload")
		timer:Advance(100)
		expect.same(ran, {})
		expect.equal(timer:Pending(), 0)
		expect.falsy(debounced:Trigger())
		expect.falsy(throttled:Trigger())
		expect.equal(runtime.ownership:Count("clock"), 0)
	end)

	describe("argument checks", function()
		it("rejects bad delays and intervals at the package's line", function()
			expect.raises(function()
				context:Delay(-1, function() end)
			end, "'milliseconds' is invalid: must be between 0 and 2147483647 milliseconds")
			expect.raises(function()
				context:Repeat(5, function() end)
			end, "must be between 10 and 2147483647 milliseconds")
			expect.raises(function()
				context:Delay(1.5, function() end)
			end, "'milliseconds' must be integer (got number)")
			expect.raises(function()
				context:Delay(10, "later")
			end, "'fn' must be function (got string)")
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				context:Repeat(1, function() end)
			end)
			expect.falsy(ok)
			expect.equal(tonumber(message:match("scheduler_spec%.lua:(%d+):")), expected_line)
		end)
	end)
end)
