local function setup()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Ownership = loader:require("foundation/core/ownership.lua")
	local Invoker = loader:require("foundation/core/invoke.lua")
	local messages = Messages.new({ en = loader:require("foundation/locales/en/core.lua") })
	local logged = {}
	local log = Log.new({
		sink = function(level, line)
			logged[#logged + 1] = { level = level, line = line }
		end,
		messages = messages,
		clock = function()
			return 0
		end,
		repeat_window = 0,
	})
	local invoker = Invoker.new({ log = log, side = "server" })
	return Ownership.new({ check = Check.new(Errors.new(messages)), invoker = invoker }), logged, invoker
end

local function noop() end

describe("Ownership", function()
	local tracker, logged, invoker

	before_each(function()
		tracker, logged, invoker = setup()
	end)

	describe("Track", function()
		it("returns active handles with increasing sequence numbers", function()
			local first = tracker:Track("pkg", "listener", noop)
			local second = tracker:Track("pkg", "task", noop, { name = "tick" })
			expect.truthy(first:IsActive())
			expect.equal(first.owner, "pkg")
			expect.equal(first.kind, "listener")
			expect.truthy(second.sequence > first.sequence)
			expect.same(second.info, { name = "tick" })
		end)

		it("copies info so later changes do not affect diagnostics", function()
			local info = { name = "a" }
			local handle = tracker:Track("pkg", "listener", noop, info)
			info.name = "b"
			expect.equal(handle.info.name, "a")
		end)

		it("validates arguments", function()
			expect.raises(function()
				tracker:Track("", "listener", noop)
			end, "'owner' is invalid: must not be empty")
			expect.raises(function()
				tracker:Track("pkg", "listener", "not a function")
			end, "'release' must be function (got string)")
			expect.raises(function()
				tracker:Track("pkg", "listener", noop, 5)
			end, "'info' must be table? (got number)")
		end)

		it("counts resources per owner and kind", function()
			tracker:Track("a", "listener", noop)
			tracker:Track("a", "listener", noop)
			tracker:Track("a", "task", noop)
			tracker:Track("b", "task", noop)
			expect.equal(tracker:Count("a"), 3)
			expect.equal(tracker:Count("a", "listener"), 2)
			expect.equal(tracker:Count("b", "listener"), 0)
			expect.equal(tracker:Count("unknown"), 0)
		end)
	end)

	describe("Release", function()
		it("runs the release callback once and reports whether it ran", function()
			local calls = 0
			local handle = tracker:Track("pkg", "listener", function(released)
				calls = calls + 1
				expect.equal(released.kind, "listener")
			end)
			expect.truthy(handle:Release())
			expect.falsy(handle:Release())
			expect.falsy(tracker:Release(handle))
			expect.equal(calls, 1)
			expect.falsy(handle:IsActive())
			expect.equal(tracker:Count("pkg"), 0)
		end)

		it("rejects values that are not handles of this tracker", function()
			local other = setup()
			local foreign = other:Track("pkg", "listener", noop)
			expect.raises(function()
				tracker:Release({ owner = "pkg" })
			end, "must be resource handle (got table)")
			expect.raises(function()
				tracker:Release(foreign)
			end, "[foundation:invalid_argument]")
		end)

		it("logs a failing release with its trace and still forgets the resource", function()
			local handle = tracker:Track("pkg", "listener", function()
				error("release exploded")
			end)
			expect.no_error(function()
				handle:Release()
			end)
			expect.falsy(handle:IsActive())
			expect.equal(tracker:Count("pkg"), 0)
			expect.equal(#logged, 1)
			expect.equal(logged[1].level, "error")
			expect.contains(logged[1].line, "foundation/core: release callback of pkg failed id=1 resource=listener")
			expect.contains(logged[1].line, "release exploded")
			expect.equal(tracker:Snapshot().release_failures, 1)
		end)
	end)

	describe("ReleaseOwner", function()
		it("releases newest first and only the given owner", function()
			local order = {}
			for index = 1, 3 do
				tracker:Track("pkg", "listener", function()
					order[#order + 1] = index
				end)
			end
			tracker:Track("other", "listener", function()
				order[#order + 1] = "other"
			end)
			local released, failed = tracker:ReleaseOwner("pkg")
			expect.same(order, { 3, 2, 1 })
			expect.equal(released, 3)
			expect.equal(failed, 0)
			expect.equal(tracker:Count("other"), 1)
		end)

		it("is idempotent", function()
			local calls = 0
			tracker:Track("pkg", "listener", function()
				calls = calls + 1
			end)
			tracker:ReleaseOwner("pkg")
			local released = tracker:ReleaseOwner("pkg")
			expect.equal(released, 0)
			expect.equal(calls, 1)
		end)

		it("continues after a failing release and reports the failure count", function()
			local order = {}
			tracker:Track("pkg", "a", function()
				order[#order + 1] = "a"
			end)
			tracker:Track("pkg", "b", function()
				error("boom")
			end)
			tracker:Track("pkg", "c", function()
				order[#order + 1] = "c"
			end)
			local released, failed = tracker:ReleaseOwner("pkg")
			expect.same(order, { "c", "a" })
			expect.equal(released, 2)
			expect.equal(failed, 1)
			expect.equal(tracker:Count("pkg"), 0)
			expect.equal(invoker:Errors("pkg"), 1)
		end)

		it("skips handles released by another release callback", function()
			local calls = 0
			local first = tracker:Track("pkg", "listener", function()
				calls = calls + 1
			end)
			tracker:Track("pkg", "group", function()
				first:Release()
			end)
			local released = tracker:ReleaseOwner("pkg")
			expect.equal(calls, 1)
			expect.equal(released, 1)
		end)

		it("refuses new resources while releasing", function()
			local raised
			tracker:Track("pkg", "listener", function()
				local ok, err = pcall(tracker.Track, tracker, "pkg", "listener", noop)
				raised = not ok and err
			end)
			tracker:ReleaseOwner("pkg")
			expect.contains(raised, "'pkg' is disabled and cannot register new resources")
			expect.equal(tracker:Count("pkg"), 0)
		end)

		it("ignores a nested ReleaseOwner for the same owner", function()
			local nested
			tracker:Track("pkg", "listener", function()
				nested = { tracker:ReleaseOwner("pkg") }
			end)
			tracker:ReleaseOwner("pkg")
			expect.same(nested, { 0, 0 })
		end)
	end)

	describe("closing owners", function()
		it("refuses new resources after a closing release until reopened", function()
			tracker:Track("pkg", "listener", noop)
			tracker:ReleaseOwner("pkg", true)
			expect.truthy(tracker:IsClosed("pkg"))
			expect.raises(function()
				tracker:Track("pkg", "listener", noop)
			end, "[foundation:invalid_state] Ownership:Track: 'pkg' is disabled")
			tracker:Open("pkg")
			expect.falsy(tracker:IsClosed("pkg"))
			expect.no_error(function()
				tracker:Track("pkg", "listener", noop)
			end)
		end)

		it("can close an owner that never tracked anything", function()
			tracker:ReleaseOwner("fresh", true)
			expect.truthy(tracker:IsClosed("fresh"))
		end)
	end)

	it("reports totals per owner and kind", function()
		tracker:Track("a", "listener", noop)
		tracker:Track("a", "task", noop)
		local handle = tracker:Track("b", "task", noop)
		handle:Release()
		tracker:ReleaseOwner("c", true)
		expect.same(tracker:Snapshot(), {
			total = 2,
			owners = {
				a = { count = 2, kinds = { listener = 1, task = 1 }, closed = false },
				b = { count = 0, kinds = {}, closed = false },
				c = { count = 0, kinds = {}, closed = true },
			},
			release_failures = 0,
		})
	end)
end)
