local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Facade = loader:require("foundation/core/facade.lua")
	local lines = {}
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function(_, line)
			lines[#lines + 1] = line
		end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	local handlers = {}
	local function register(id, capabilities)
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function(event, callback)
				handlers[id .. ":" .. event] = callback
			end,
		}
		return runtime.packages:Register(native, { api = "0.1", capabilities = capabilities })
	end
	local function load(id)
		handlers[id .. ":Load"]()
	end
	return runtime, Facade.new(runtime), register, load, lines
end

describe("Capabilities", function()
	local runtime, Foundation, register, load, lines

	before_each(function()
		runtime, Foundation, register, load, lines = setup()
	end)

	local function has(...)
		return Foundation.Capabilities.Has(...)
	end

	it("are available while the declaring package is ready", function()
		register("chat-plus", { "chat:colors", { name = "chat:emotes", version = "2.1" } })
		expect.falsy(has("chat:colors"))
		load("chat-plus")
		expect.truthy(has("chat:colors"))
		expect.truthy(has("chat:emotes", "2"))
		expect.truthy(has("chat:emotes", "2.1"))
		expect.falsy(has("chat:emotes", "2.2"))
		expect.falsy(has("chat:emotes", "1"))
		expect.falsy(has("chat:colors", "1"))
		runtime.packages:Disable("chat-plus", "unload")
		expect.falsy(has("chat:colors"))
	end)

	it("lists the packages that declare a capability", function()
		register("chat-plus", { { name = "chat:emotes", version = "2.1" } })
		register("emoji", { { name = "chat:emotes", version = "2.4" } })
		register("legacy", { { name = "chat:emotes", version = "1.0" } })
		load("chat-plus")
		load("emoji")
		load("legacy")
		expect.same(Foundation.Capabilities.Providers("chat:emotes", "2"), {
			{ package = "chat-plus", version = "2.1" },
			{ package = "emoji", version = "2.4" },
		})
		expect.equal(#Foundation.Capabilities.Providers("chat:emotes"), 3)
		expect.same(runtime.capabilities:Snapshot().capabilities["chat:emotes"][3], {
			package = "legacy",
			version = "1.0",
		})
	end)

	it("are not offered by a package that failed to start", function()
		local context = register("chat-plus", { "chat:colors" })
		context:OnReady(function()
			error("no database")
		end)
		load("chat-plus")
		expect.falsy(has("chat:colors"))
	end)

	it("announce changes with Foundation events", function()
		local seen = {}
		local watcher = register("watcher")
		for _, name in ipairs({ "capability_available", "capability_unavailable" }) do
			watcher:Listen("foundation:" .. name, function(event)
				seen[#seen + 1] = name .. ":" .. event:Get("capability") .. ":" .. event:Get("package")
			end)
		end
		register("chat-plus", { "chat:colors" })
		load("chat-plus")
		runtime.packages:Disable("chat-plus", "unload")
		expect.same(seen, {
			"capability_available:chat:colors:chat-plus",
			"capability_unavailable:chat:colors:chat-plus",
		})
	end)

	it("warns when a capability has the name of a service", function()
		register("coins"):ProvideService("economy:bank", "1.0", {})
		register("bank-flags", { "economy:bank" })
		load("bank-flags")
		expect.contains(table.concat(lines, "\n"), "bank-flags declares the capability 'economy:bank', which is also")
	end)

	it("refuses inconsistent declarations at the package's line", function()
		local cases = {
			{ "chat:colors", "'manifest.capabilities' must be table (got string)" },
			{ { "colors" }, "'manifest.capabilities[1]' is invalid: each entry is" },
			{ { { name = "chat:emotes", version = "2" } }, "'manifest.capabilities[1]' is invalid" },
			{ { { name = "chat:emotes", flag = true } }, "'manifest.capabilities[1]' is invalid" },
			{
				{ "chat:colors", "CHAT:COLORS" },
				"'manifest.capabilities[2]' is invalid: 'chat:colors' is listed twice",
			},
			{ { "foundation:core" }, "'foundation:core' uses a namespace reserved for Foundation" },
		}
		for index, case in ipairs(cases) do
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				register("bad" .. index, case[1])
			end)
			expect.falsy(ok)
			expect.contains(message, case[2])
			expect.equal(tonumber(message:match("capabilities_spec%.lua:(%d+):")), expected_line)
		end
	end)

	it("validates queries at the caller's line", function()
		local expected_line
		local ok, message = pcall(function()
			expected_line = debug.getinfo(1, "l").currentline + 1
			has("chat:colors", "latest")
		end)
		expect.falsy(ok)
		expect.contains(message, "must be '<major>' or '<major>.<minor>'")
		expect.equal(tonumber(message:match("capabilities_spec%.lua:(%d+):")), expected_line)
		expect.raises(function()
			has("colors")
		end, "'name' is invalid")
	end)
end)
