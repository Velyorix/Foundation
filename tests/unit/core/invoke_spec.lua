local function setup()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Invoker = loader:require("foundation/core/invoke.lua")
	local logged = {}
	local log = Log.new({
		sink = function(level, line)
			logged[#logged + 1] = { level = level, line = line }
		end,
		messages = Messages.new({ en = loader:require("foundation/locales/en/core.lua") }),
		clock = function()
			return 0
		end,
		repeat_window = 0,
	})
	return Invoker.new({ log = log, side = "server" }), logged
end

describe("Invoker", function()
	local invoker, logged
	local listener = { owner = "my-package", kind = "event_listener" }

	before_each(function()
		invoker, logged = setup()
	end)

	it("returns true and every result, including nils", function()
		local results = table.pack(invoker:Call(listener, function(a, b)
			return a + b, nil, "x"
		end, 1, 2))
		expect.equal(results.n, 4)
		expect.equal(results[1], true)
		expect.equal(results[2], 3)
		expect.is_nil(results[3])
		expect.equal(results[4], "x")
		expect.equal(#logged, 0)
	end)

	it("contains errors, returns them with a traceback and logs them for the owner", function()
		local ok, err = invoker:Call(listener, function()
			error("listener exploded")
		end)
		expect.falsy(ok)
		expect.contains(err, "listener exploded")
		expect.contains(err, "stack traceback")
		expect.equal(#logged, 1)
		expect.equal(logged[1].level, "error")
		expect.contains(logged[1].line, "event_listener callback of my-package failed")
		expect.contains(logged[1].line, "listener exploded")
	end)

	it("adds the caller's diagnostic fields to the log record", function()
		invoker:Call({ owner = "pkg", kind = "task", fields = { task = "autosave" } }, error)
		expect.contains(logged[1].line, "task callback of pkg failed task=autosave")
	end)

	it("keeps non-string error values readable", function()
		local ok, err = invoker:Call(listener, function()
			error({ code = "x" })
		end)
		expect.falsy(ok)
		expect.type(err, "table")
		expect.contains(logged[1].line, "table:")
	end)

	it("counts errors per owner and kind with the last message", function()
		invoker:Call(listener, error, "first")
		invoker:Call({ owner = "my-package", kind = "task" }, error, "second\nmore lines")
		invoker:Call({ owner = "other", kind = "task" }, error, "third")
		invoker:Call(listener, function() end)
		expect.equal(invoker:Errors("my-package"), 2)
		expect.equal(invoker:Errors("nobody"), 0)
		local snapshot = invoker:Snapshot()
		expect.equal(snapshot.total_errors, 3)
		expect.equal(snapshot.side, "server")
		expect.same(snapshot.owners["my-package"].kinds, { event_listener = 1, task = 1 })
		expect.equal(snapshot.owners["my-package"].last.kind, "task")
		expect.equal(snapshot.owners["my-package"].last.message, "second")
	end)

	describe("execution context", function()
		it("exposes the running callback and restores it afterwards", function()
			local seen
			expect.is_nil(invoker:Current())
			invoker:Call(listener, function()
				seen = invoker:Current()
			end)
			expect.equal(seen, listener)
			expect.is_nil(invoker:Current())
		end)

		it("tracks nested callbacks", function()
			local inner = { owner = "other", kind = "task" }
			local depths, owners = {}, {}
			invoker:Call(listener, function()
				depths[#depths + 1] = invoker:Depth()
				invoker:Call(inner, function()
					depths[#depths + 1] = invoker:Depth()
					owners[#owners + 1] = invoker:Current().owner
				end)
				owners[#owners + 1] = invoker:Current().owner
			end)
			expect.same(depths, { 1, 2 })
			expect.same(owners, { "other", "my-package" })
		end)

		it("restores the context after an error", function()
			invoker:Call(listener, function()
				invoker:Call({ owner = "inner", kind = "task" }, error, "boom")
				expect.equal(invoker:Current(), listener)
				error("outer")
			end)
			expect.equal(invoker:Depth(), 0)
		end)

		it("reports the side it was created for", function()
			expect.equal(invoker:Side(), "server")
		end)
	end)
end)
