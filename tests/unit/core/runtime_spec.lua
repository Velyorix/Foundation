local function fake_package(name)
	local package = { subscriptions = {} }
	function package.GetName()
		return name
	end
	function package.Subscribe(event, callback)
		package.subscriptions[event] = package.subscriptions[event] or {}
		table.insert(package.subscriptions[event], callback)
	end
	function package.fire(event)
		for _, callback in ipairs(package.subscriptions[event] or {}) do
			callback()
		end
	end
	return package
end

local function setup(overrides)
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Facade = loader:require("foundation/core/facade.lua")
	local lines = {}
	local env = {
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = {
			en = loader:require("foundation/locales/en/core.lua"),
			fr = loader:require("foundation/locales/fr/core.lua"),
		},
		sink = function(level, line)
			lines[#lines + 1] = { level = level, line = line }
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 1000
		end,
	}
	for key, value in pairs(overrides or {}) do
		env[key] = value
	end
	local runtime = Runtime.new(env)
	return runtime, Facade, lines
end

local function text(lines)
	local parts = {}
	for index, entry in ipairs(lines) do
		parts[index] = entry.line
	end
	return table.concat(parts, "\n")
end

describe("Runtime", function()
	it("starts its components in order and logs the start", function()
		local runtime, _, lines = setup()
		expect.truthy(runtime:Start())
		expect.truthy(runtime:IsRunning())
		local snapshot = runtime:Snapshot()
		local names = {}
		for index, component in ipairs(snapshot.components) do
			names[index] = component.name .. ":" .. component.state
		end
		expect.same(names, {
			"log:running",
			"invoker:running",
			"schema:running",
			"ownership:running",
			"packages:running",
			"i18n:running",
			"config:absent",
			"audit:absent",
		})
		expect.equal(snapshot.state, "running")
		expect.equal(snapshot.started_at, 1000)
		expect.contains(text(lines), "Foundation 0.1.0 started (API 0.1, server)")
	end)

	it("renders startup messages in the configured locale", function()
		local runtime, _, lines = setup({ locale = "fr" })
		runtime:Start()
		expect.contains(text(lines), "Foundation 0.1.0 démarré (API 0.1, server)")
	end)

	it("refuses to start twice", function()
		local runtime = setup()
		runtime:Start()
		expect.raises(function()
			runtime:Start()
		end, "Foundation has already been started")
	end)

	it("keeps running when an optional component fails", function()
		local runtime, _, lines = setup({
			create_audit = function()
				error("disk unavailable")
			end,
		})
		expect.truthy(runtime:Start())
		local audit = runtime:Snapshot().components[8]
		expect.same(audit, { name = "audit", required = false, state = "unavailable" })
		expect.contains(text(lines), "component 'audit' is unavailable")
		expect.contains(text(lines), "disk unavailable")
	end)

	it("creates the audit component through the environment", function()
		local runtime = setup({
			create_audit = function(rt)
				return {
					Snapshot = function()
						return { owner = rt.env.side }
					end,
				}
			end,
		})
		runtime:Start()
		expect.same(runtime:Snapshot().audit, { owner = "server" })
	end)

	it("reports a required component failure and refuses work", function()
		local runtime, _, lines = setup({ api_version = false })
		expect.falsy(runtime:Start())
		expect.equal(runtime:Snapshot().state, "failed")
		expect.contains(text(lines), "Foundation could not start: component 'packages' failed")
		expect.raises(function()
			runtime:RequireRunning("Foundation.Register")
		end, "[foundation:invalid_state] Foundation.Register: Foundation could not start")
	end)

	it("stops once, disabling packages and flushing the log", function()
		local runtime, _, lines = setup()
		runtime:Start()
		local native = fake_package("pkg")
		local context = runtime.packages:Register(native, { api = "0.1" })
		native.fire("Load")
		expect.equal(runtime:ActivePackages()[1], "pkg")
		expect.truthy(runtime:Stop())
		expect.falsy(runtime:Stop())
		expect.equal(context:GetState(), "disabled")
		expect.equal(runtime:Snapshot().state, "stopped")
		expect.contains(text(lines), "pkg disabled: Foundation is stopping")
		expect.contains(text(lines), "Foundation stopped")
		expect.raises(function()
			runtime:RequireRunning("Foundation.Register")
		end, "Foundation is not running (state: stopped)")
	end)
end)

describe("Foundation facade", function()
	local runtime, Facade, facade

	before_each(function()
		runtime, Facade = setup()
		runtime:Start()
		facade = Facade.new(runtime)
	end)

	it("exposes the versions", function()
		expect.equal(facade.VERSION, "0.1.0")
		expect.equal(facade.API_VERSION, "0.1")
	end)

	it("registers packages through the runtime", function()
		local context = facade.Register(fake_package("pkg"), { api = "0.1" })
		expect.equal(context:GetId(), "pkg")
		expect.equal(runtime.packages:State("pkg"), "initializing")
	end)

	it("reports registration errors at the package's line", function()
		local expected_line
		local ok, message = pcall(function()
			expected_line = debug.getinfo(1, "l").currentline + 1
			facade.Register(fake_package("pkg"), { api = "0.1", unknown = true })
		end)
		expect.falsy(ok)
		expect.equal(tonumber(message:match("runtime_spec%.lua:(%d+):")), expected_line)
	end)

	it("reports a stopped runtime at the package's line", function()
		runtime:Stop()
		local expected_line
		local ok, message = pcall(function()
			expected_line = debug.getinfo(1, "l").currentline + 1
			facade.Register(fake_package("pkg"), { api = "0.1" })
		end)
		expect.falsy(ok)
		expect.contains(message, "Foundation is not running (state: stopped)")
		expect.equal(tonumber(message:match("runtime_spec%.lua:(%d+):")), expected_line)
	end)

	it("is read-only and hides its metatable", function()
		expect.raises(function()
			facade.Register = nil
		end, "[foundation:invalid_state] Foundation.Register: Foundation is read-only")
		expect.raises(function()
			facade.Extra = 1
		end, "read-only")
		expect.equal(getmetatable(facade), false)
		expect.is_nil(rawget(facade, "Register"))
	end)
end)
