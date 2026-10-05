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
			return "async"
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

describe("Future", function()
	local runtime, context, timer, lines

	before_each(function()
		runtime, context, timer, lines = setup()
	end)

	it("settles once through the executor's resolve function", function()
		local resolve_later
		local future = context:Future(function(resolve)
			resolve_later = resolve
		end)
		expect.equal(future:GetState(), "pending")
		expect.truthy(resolve_later(42))
		expect.falsy(resolve_later(43))
		expect.falsy(future:Reject("late"))
		expect.equal(future:GetState(), "resolved")
		expect.equal(future:GetValue(), 42)
		expect.truthy(future:IsDone())
	end)

	it("can be settled directly when created without an executor", function()
		local future = context:Future()
		future:Reject("nope")
		expect.equal(future:GetState(), "rejected")
		expect.equal(future:GetError(), "nope")
	end)

	it("chains handlers and adopts returned futures", function()
		local inner = context:Future()
		local seen = {}
		local source = context:Future()
		source
			:Then(function(value)
				seen[#seen + 1] = value
				return inner
			end)
			:Then(function(value)
				seen[#seen + 1] = value
				return value * 2
			end)
			:Then(function(value)
				seen[#seen + 1] = value
			end)
		source:Resolve(1)
		expect.same(seen, { 1 })
		inner:Resolve(5)
		expect.same(seen, { 1, 5, 10 })
	end)

	it("passes rejections down the chain to Catch and recovers", function()
		local recovered
		context
			:Future(function(_, reject)
				reject("disk full")
			end)
			:Then(function()
				error("must not run")
			end)
			:Catch(function(err)
				return "recovered from " .. err
			end)
			:Then(function(value)
				recovered = value
			end)
		expect.equal(recovered, "recovered from disk full")
	end)

	it("runs handlers attached to an already settled future immediately", function()
		local future = context:Future()
		future:Resolve("done")
		local seen
		future:Then(function(value)
			seen = value
		end)
		expect.equal(seen, "done")
	end)

	it("turns a failing handler into an async_failed rejection logged for the package", function()
		local caught
		context
			:Future(function(resolve)
				resolve(1)
			end)
			:Then(function()
				error("handler exploded")
			end)
			:Catch(function(err)
				caught = err
			end)
		expect.equal(caught.code, "async_failed")
		expect.contains(tostring(caught.cause), "handler exploded")
		expect.contains(text(lines), "future_callback callback of async failed")
	end)

	it("rejects when the executor raises", function()
		local future = context:Future(function()
			error("executor exploded")
		end)
		expect.equal(future:GetState(), "rejected")
		expect.equal(future:GetError().code, "async_failed")
	end)

	it("runs Finally on both outcomes and passes the outcome through", function()
		local calls = 0
		local function count()
			calls = calls + 1
		end
		local final_value, final_error
		context
			:Future(function(resolve)
				resolve("v")
			end)
			:Finally(count)
			:Then(function(value)
				final_value = value
			end)
		local rejected = context:Future()
		rejected:Finally(count):Catch(function(err)
			final_error = err
		end)
		rejected:Reject("x")
		expect.equal(calls, 2)
		expect.equal(final_value, "v")
		expect.equal(final_error, "x")
	end)

	describe("All", function()
		it("resolves with every value in order", function()
			local first, second = context:Future(), context:Future()
			local values
			context:All({ first, second }):Then(function(result)
				values = result
			end)
			second:Resolve("b")
			expect.is_nil(values)
			first:Resolve("a")
			expect.same(values, { "a", "b" })
		end)

		it("rejects with the first error", function()
			local first, second = context:Future(), context:Future()
			local err
			context:All({ first, second }):Catch(function(reason)
				err = reason
			end)
			second:Reject("second failed")
			first:Reject("first failed")
			expect.equal(err, "second failed")
		end)

		it("resolves an empty list immediately and validates its input", function()
			expect.same(context:All({}):GetValue(), {})
			expect.raises(function()
				context:All({ 1 })
			end, "'futures[1]' must be future (got number)")
		end)
	end)

	describe("Timeout", function()
		it("rejects with a timeout error when nothing arrives in time", function()
			local future = context:Future():Timeout(100)
			timer:Advance(99)
			expect.equal(future:GetState(), "pending")
			timer:Advance(1)
			expect.equal(future:GetState(), "rejected")
			expect.equal(future:GetError().code, "timeout")
			expect.equal(future:GetError().message, "no result after 100 ms")
		end)

		it("does nothing once the future settled", function()
			local future = context:Future():Timeout(100)
			future:Resolve("in time")
			timer:Advance(200)
			expect.equal(future:GetState(), "resolved")
			expect.equal(timer:Pending(), 0)
		end)
	end)

	it("cancels pending futures without running callbacks when the package is disabled", function()
		local ran = false
		local future = context:Future()
		local chained = future:Then(function()
			ran = true
		end)
		future:Finally(function()
			ran = true
		end)
		runtime.packages:Disable("async", "unload")
		expect.equal(future:GetState(), "cancelled")
		expect.equal(chained:GetState(), "cancelled")
		future:Resolve("too late")
		expect.falsy(ran)
		expect.equal(runtime.ownership:Count("async"), 0)
	end)

	it("stops tracking settled futures", function()
		local future = context:Future()
		expect.equal(runtime.ownership:Count("async", "future"), 1)
		future:Resolve(true)
		expect.equal(runtime.ownership:Count("async", "future"), 0)
	end)

	it("validates handlers", function()
		expect.raises(function()
			context:Future():Then("not a function")
		end, "'on_resolved' must be function? (got string)")
		expect.raises(function()
			context:Future(42)
		end, "'executor' must be function? (got number)")
	end)
end)
