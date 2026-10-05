local function fake_package(name, version)
	local package = { subscriptions = {}, unsubscribed = {} }
	function package.GetName()
		return name
	end
	function package.GetTitle()
		return name .. " title"
	end
	function package.GetVersion()
		return version or "1.0.0"
	end
	function package.Subscribe(event, callback)
		package.subscriptions[event] = package.subscriptions[event] or {}
		table.insert(package.subscriptions[event], callback)
		return callback
	end
	function package.Unsubscribe(event, callback)
		package.unsubscribed[#package.unsubscribed + 1] = { event, callback }
	end
	function package.fire(event)
		for _, callback in ipairs(package.subscriptions[event] or {}) do
			callback()
		end
	end
	return package
end

local function setup(api_version)
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Ownership = loader:require("foundation/core/ownership.lua")
	local Invoker = loader:require("foundation/core/invoke.lua")
	local Registry = loader:require("foundation/core/packages.lua")
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
	local check = Check.new(Errors.new(messages))
	local invoker = Invoker.new({ log = log, side = "server" })
	local ownership = Ownership.new({ check = check, invoker = invoker })
	local registry = Registry.new({
		check = check,
		log = log,
		ownership = ownership,
		invoker = invoker,
		api_version = api_version or "0.1",
	})
	return registry, ownership, logged
end

local function logged_lines(logged)
	local lines = {}
	for index, entry in ipairs(logged) do
		lines[index] = entry.line
	end
	return table.concat(lines, "\n")
end

describe("package registry", function()
	local registry, ownership, logged

	before_each(function()
		registry, ownership, logged = setup()
	end)

	describe("Register", function()
		it("uses the native package name and fills defaults from the native package", function()
			local native = fake_package("my-package", "2.3.4")
			local context = registry:Register(native, { api = "0.1" })
			expect.equal(context:GetId(), "my-package")
			expect.equal(context:GetName(), "my-package title")
			expect.equal(context:GetVersion(), "2.3.4")
			expect.equal(context:GetState(), "initializing")
			expect.truthy(context:IsActive())
			expect.contains(logged_lines(logged), "registered my-package 2.3.4 (API 0.1)")
		end)

		it("prefers manifest values over native ones", function()
			local context = registry:Register(fake_package("pkg"), { api = "0.1", name = "Nice", version = "9.9.9" })
			expect.equal(context:GetName(), "Nice")
			expect.equal(context:GetVersion(), "9.9.9")
		end)

		it("subscribes to the package's Load and Unload events", function()
			local native = fake_package("pkg")
			registry:Register(native, { api = "0.1" })
			expect.equal(#native.subscriptions.Load, 1)
			expect.equal(#native.subscriptions.Unload, 1)
		end)

		it("validates the native package object", function()
			expect.raises(function()
				registry:Register(nil, { api = "0.1" })
			end, "argument #1 'package' must be table (got nil)")
			expect.raises(function()
				registry:Register({ GetName = function() end }, { api = "0.1" })
			end, "'package.Subscribe' must be function")
		end)

		it("rejects invalid package names", function()
			for _, name in ipairs({ "My-Package", "under_score", "-dash", string.rep("a", 65) }) do
				expect.raises(function()
					registry:Register(fake_package(name), { api = "0.1" })
				end, "must contain only lowercase letters, digits and '-' (at most 64 characters)")
			end
		end)

		it("reports the line of the caller for manifest errors", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				registry:Register(fake_package("pkg"), { api = "0.1", depends = { "Bad" } })
			end)
			expect.falsy(ok)
			expect.equal(tonumber(message:match("packages_spec%.lua:(%d+):")), expected_line)
			expect.contains(message, "'manifest.depends[1]' is invalid")
		end)

		it("rejects unknown manifest fields and mismatching ids", function()
			expect.raises(function()
				registry:Register(fake_package("pkg"), { api = "0.1", dependz = {} })
			end, "unknown field 'dependz'")
			expect.raises(function()
				registry:Register(fake_package("pkg"), { api = "0.1", id = "other" })
			end, "'other' does not match the package folder name 'pkg'")
			expect.raises(function()
				registry:Register(fake_package("pkg"), { api = "0.1", version = 2 })
			end, "'manifest.version' must be string? (got number)")
		end)

		it("requires a well-formed api field", function()
			expect.raises(function()
				registry:Register(fake_package("pkg"), {})
			end, "'manifest.api' must be string (got nil)")
			expect.raises(function()
				registry:Register(fake_package("pkg"), { api = "v1" })
			end, "must be '<major>' or '<major>.<minor>'")
		end)

		describe("API compatibility", function()
			it("requires the exact minor before 1.0", function()
				expect.no_error(function()
					registry:Register(fake_package("a"), { api = "0.1" })
				end)
				expect.raises(function()
					registry:Register(fake_package("b"), { api = "0" })
				end, "[foundation:incompatible_api] b requires Foundation API 0; this server runs API 0.1")
				expect.raises(function()
					registry:Register(fake_package("c"), { api = "0.2" })
				end, "incompatible_api")
			end)

			it("accepts older minors of the same major from 1.0 on", function()
				local stable = setup("1.3")
				for _, api in ipairs({ "1", "1.0", "1.3" }) do
					expect.no_error(function()
						stable:Register(fake_package("p" .. api:gsub("%.", "-")), { api = api })
					end)
				end
				expect.raises(function()
					stable:Register(fake_package("newer"), { api = "1.4" })
				end, "incompatible_api")
				expect.raises(function()
					stable:Register(fake_package("major"), { api = "2.0" })
				end, "incompatible_api")
			end)
		end)

		it("refuses a second registration while the package is active or failed", function()
			local native = fake_package("pkg")
			registry:Register(native, { api = "0.1" })
			expect.raises(function()
				registry:Register(native, { api = "0.1" })
			end, "'pkg' is already registered (initializing)")
		end)

		it("requires declared dependencies to be registered and active", function()
			expect.raises(function()
				registry:Register(fake_package("child"), { api = "0.1", depends = { "parent" } })
			end, "'child' requires 'parent', which is not registered or not active")
			registry:Register(fake_package("parent"), { api = "0.1" })
			expect.no_error(function()
				registry:Register(fake_package("child"), { api = "0.1", depends = { "parent" } })
			end)
		end)

		it("does not require soft dependencies", function()
			expect.no_error(function()
				registry:Register(fake_package("pkg"), { api = "0.1", soft_depends = { "optional" } })
			end)
		end)
	end)

	describe("ready", function()
		it("becomes ready on the native Load event after its ready hooks", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			local seen = {}
			context:OnReady(function(ctx)
				seen[#seen + 1] = ctx:GetState()
			end)
			context:OnReady(function()
				seen[#seen + 1] = "second"
			end)
			native.fire("Load")
			expect.same(seen, { "initializing", "second" })
			expect.equal(context:GetState(), "ready")
			expect.contains(logged_lines(logged), "pkg is ready")
			native.fire("Load")
			expect.equal(#seen, 2, "ready hooks run once")
		end)

		it("refuses ready hooks once ready", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			native.fire("Load")
			expect.raises(function()
				context:OnReady(function() end)
			end, "'pkg' has already finished initializing")
		end)

		it("fails the package when a ready hook fails, running disable hooks and releasing resources", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			local released, disabled = false, false
			context:Track("listener", function()
				released = true
			end)
			context:OnDisable(function()
				disabled = true
			end)
			context:OnReady(function()
				error("cannot start")
			end)
			native.fire("Load")
			expect.equal(context:GetState(), "failed")
			expect.truthy(released)
			expect.truthy(disabled)
			expect.falsy(context:IsActive())
			local text = logged_lines(logged)
			expect.contains(text, "ready_hook callback of pkg failed")
			expect.contains(text, "pkg failed: a ready hook of 'pkg' failed")
			expect.equal(registry:Snapshot().packages[1].failure, "a ready hook of 'pkg' failed")
		end)
	end)

	describe("disable", function()
		it("runs disable hooks newest first while resources still exist, then releases them", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			local events = {}
			context:Track("listener", function()
				events[#events + 1] = "released"
			end)
			context:OnDisable(function()
				events[#events + 1] = "hook1 resources=" .. ownership:Count("pkg")
			end)
			context:OnDisable(function()
				events[#events + 1] = "hook2"
			end)
			native.fire("Load")
			native.fire("Unload")
			expect.same(events, { "hook2", "hook1 resources=1", "released" })
			expect.equal(context:GetState(), "disabled")
			expect.contains(logged_lines(logged), "pkg disabled: package unloaded")
		end)

		it("is idempotent", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			local calls = 0
			context:OnDisable(function()
				calls = calls + 1
			end)
			expect.truthy(registry:Disable("pkg", "unload"))
			expect.falsy(registry:Disable("pkg", "unload"))
			native.fire("Unload")
			expect.equal(calls, 1)
			expect.falsy(registry:Disable("unknown", "unload"))
		end)

		it("makes the context unusable", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			native.fire("Unload")
			expect.raises(function()
				context:Track("listener", function() end)
			end, "[foundation:invalid_state] context:Track: the context of 'pkg' is disabled")
			expect.raises(function()
				context:OnDisable(function() end)
			end, "is disabled and can no longer be used")
		end)

		it("refuses resources registered from a disable hook", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			local raised
			context:OnDisable(function(ctx)
				local ok, err = pcall(ctx.Track, ctx, "late", function() end)
				raised = not ok and err
			end)
			native.fire("Unload")
			expect.contains(raised, "can no longer be used")
			expect.equal(ownership:Count("pkg"), 0)
		end)

		it("disables dependents first", function()
			local parent_native = fake_package("parent")
			local parent = registry:Register(parent_native, { api = "0.1" })
			local child = registry:Register(fake_package("child"), { api = "0.1", depends = { "parent" } })
			local order = {}
			parent:OnDisable(function()
				order[#order + 1] = "parent"
			end)
			child:OnDisable(function()
				order[#order + 1] = "child"
			end)
			parent_native.fire("Unload")
			expect.same(order, { "child", "parent" })
			expect.equal(child:GetState(), "disabled")
			expect.contains(logged_lines(logged), "child disabled: a dependency was disabled")
		end)

		it("disables dependents when a dependency fails", function()
			local parent_native = fake_package("parent")
			local parent = registry:Register(parent_native, { api = "0.1" })
			local child = registry:Register(fake_package("child"), { api = "0.1", depends = { "parent" } })
			parent:OnReady(function()
				error("broken")
			end)
			parent_native.fire("Load")
			expect.equal(parent:GetState(), "failed")
			expect.equal(child:GetState(), "disabled")
			expect.contains(logged_lines(logged), "child disabled: a dependency failed")
		end)

		it("moves a failed package to disabled when it unloads", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			context:OnReady(function()
				error("x")
			end)
			native.fire("Load")
			native.fire("Unload")
			expect.equal(context:GetState(), "disabled")
		end)
	end)

	describe("reload", function()
		it("accepts a new registration after unload and ignores stale native hooks", function()
			local first_native = fake_package("pkg")
			local first = registry:Register(first_native, { api = "0.1" })
			first_native.fire("Load")
			first_native.fire("Unload")

			local second_native = fake_package("pkg")
			local second = registry:Register(second_native, { api = "0.1" })
			expect.equal(second:GetState(), "initializing")
			expect.no_error(function()
				second:Track("listener", function() end)
			end)
			first_native.fire("Unload")
			first_native.fire("Load")
			expect.equal(second:GetState(), "initializing", "old hooks must not touch the new entry")
			expect.falsy(first:IsActive())
			second_native.fire("Load")
			expect.equal(second:GetState(), "ready")
		end)
	end)

	describe("Shutdown", function()
		it("disables every package newest first and detaches native hooks", function()
			local natives = { fake_package("a"), fake_package("b") }
			local order = {}
			for _, native in ipairs(natives) do
				local context = registry:Register(native, { api = "0.1" })
				context:OnDisable(function(ctx)
					order[#order + 1] = ctx:GetId()
				end)
				native.fire("Load")
			end
			registry:Shutdown()
			expect.same(order, { "b", "a" })
			expect.contains(logged_lines(logged), "a disabled: Foundation is stopping")
			for _, native in ipairs(natives) do
				expect.equal(#native.unsubscribed, 2)
			end
		end)

		it("ignores native hooks firing after shutdown", function()
			local native = fake_package("pkg")
			local context = registry:Register(native, { api = "0.1" })
			registry:Shutdown()
			local count = #logged
			native.fire("Unload")
			native.fire("Load")
			expect.equal(#logged, count)
			expect.equal(context:GetState(), "disabled")
		end)
	end)

	it("summarizes packages in registration order", function()
		local native = fake_package("pkg", "1.2.3")
		local context = registry:Register(native, { api = "0.1", author = "me", depends = {} })
		context:Track("listener", function() end)
		registry:Register(fake_package("other"), { api = "0.1", depends = { "pkg" } })
		local snapshot = registry:Snapshot()
		expect.equal(snapshot.api_version, "0.1")
		expect.same(snapshot.packages[1], {
			id = "pkg",
			name = "pkg title",
			version = "1.2.3",
			author = "me",
			api = "0.1",
			state = "initializing",
			depends = {},
			resources = 1,
			errors = 0,
		})
		expect.same(snapshot.packages[2].depends, { "pkg" })
		expect.equal(registry:State("pkg"), "initializing")
		expect.is_nil(registry:State("missing"))
	end)
end)
