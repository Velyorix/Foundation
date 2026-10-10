local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
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
	local natives = {}
	local function register(id, manifest)
		local handlers = {}
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function(event, callback)
				handlers[event] = callback
			end,
		}
		natives[id] = handlers
		manifest = manifest or {}
		manifest.api = "0.1"
		return runtime.packages:Register(native, manifest)
	end
	local function load(id)
		natives[id].Load()
	end
	return runtime, register, load, lines
end

describe("Service requirements", function()
	local runtime, register, load, lines

	before_each(function()
		runtime, register, load, lines = setup()
	end)

	local function state(id)
		return runtime.packages:State(id)
	end

	it("lets a package become ready when its required services are provided", function()
		register("coins"):ProvideService("economy:bank", "1.3", {})
		register("shop", { services = { { name = "economy:bank", version = "1.2" } } })
		load("coins")
		load("shop")
		expect.equal(state("shop"), "ready")
	end)

	it("finds providers registered after the consumer, before the Load event", function()
		register("shop", { services = { { name = "economy:bank" } } })
		register("coins"):ProvideService("economy:bank", "1.0", {})
		load("shop")
		expect.equal(state("shop"), "ready")
	end)

	it("fails a package whose required service is missing or too old", function()
		register("coins"):ProvideService("economy:bank", "1.1", {})
		register("shop", { services = { { name = "economy:bank", version = "1.2" } } })
		load("shop")
		expect.equal(state("shop"), "failed")
		expect.contains(
			table.concat(lines, "\n"),
			"shop failed: 'shop' requires the service 'economy:bank' (version 1.2), which no package provides"
		)
	end)

	it("does not block on optional services", function()
		register("shop", { services = { { name = "economy:bank", optional = true } } })
		load("shop")
		expect.equal(state("shop"), "ready")
	end)

	it("fails a ready package when the last compatible provider stops", function()
		local coins = register("coins")
		coins:ProvideService("economy:bank", "1.0", {}, { priority = 5 })
		local gems = register("gems")
		gems:ProvideService("economy:bank", "1.0", {})
		local shop = register("shop", { services = { { name = "economy:bank" } } })
		local disabled = false
		shop:OnDisable(function()
			disabled = true
		end)
		load("shop")
		runtime.packages:Disable("coins", "unload")
		expect.equal(state("shop"), "ready")
		runtime.packages:Disable("gems", "unload")
		expect.equal(state("shop"), "failed")
		expect.truthy(disabled)
		expect.contains(
			table.concat(lines, "\n"),
			"shop failed: the service 'economy:bank' (any version) required by 'shop' is no longer provided"
		)
	end)

	it("keeps a package ready when an optional service goes away", function()
		local coins = register("coins")
		local handle = coins:ProvideService("economy:bank", "1.0", {})
		register("shop", { services = { { name = "economy:bank", optional = true } } })
		load("shop")
		handle:Release()
		expect.equal(state("shop"), "ready")
	end)

	it("only judges a starting package when it becomes ready", function()
		local handle = register("coins"):ProvideService("economy:bank", "1.0", {})
		register("shop", { services = { { name = "economy:bank" } } })
		handle:Release()
		expect.equal(state("shop"), "initializing")
		register("gems"):ProvideService("economy:bank", "1.0", {})
		load("shop")
		expect.equal(state("shop"), "ready")
	end)

	it("keeps a package ready through a replacement", function()
		local coins = register("coins")
		coins:ProvideService("economy:bank", "1.0", {})
		register("shop", { services = { { name = "economy:bank" } } })
		load("shop")
		coins:ProvideService("economy:bank", "1.1", {}, { replace = true })
		expect.equal(state("shop"), "ready")
	end)

	it("validates the manifest field at the package's line", function()
		local cases = {
			{ "economy:bank", "'manifest.services' must be table (got string)" },
			{ { "economy:bank" }, "'manifest.services[1]' is invalid: each entry is" },
			{ { { name = "bank" } }, "'manifest.services[1]' is invalid" },
			{ { { name = "economy:bank", version = "latest" } }, "'manifest.services[1]' is invalid" },
			{ { { name = "economy:bank", required = true } }, "'manifest.services[1]' is invalid" },
			{
				{ { name = "economy:bank" }, { name = "Economy:Bank" } },
				"'manifest.services[2]' is invalid: 'economy:bank' is listed twice",
			},
		}
		for index, case in ipairs(cases) do
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				register("shop" .. index, { services = case[1] })
			end)
			expect.falsy(ok)
			expect.contains(message, case[2])
			expect.equal(tonumber(message:match("service_requirements_spec%.lua:(%d+):")), expected_line)
		end
	end)
end)
