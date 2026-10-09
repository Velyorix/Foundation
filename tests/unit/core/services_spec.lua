local function setup()
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local runtime = Runtime.new({
		side = "server",
		version = "0.1.0",
		api_version = "0.1",
		catalogs = { en = loader:require("foundation/locales/en/core.lua") },
		sink = function() end,
		clock = function()
			return 0
		end,
		now = function()
			return 0
		end,
	})
	runtime:Start()
	local function register(id)
		local native = {
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}
		return runtime.packages:Register(native, { api = "0.1" })
	end
	return runtime, register
end

local function bank(name, rate)
	local balances = {}
	return {
		name = name,
		Deposit = function(self, player, amount)
			balances[player] = (balances[player] or 0) + amount * (rate or 1)
			return self.name
		end,
		Balance = function(_, player)
			return balances[player] or 0
		end,
	}
end

local function line_of(message)
	return tonumber(tostring(message):match("services_spec%.lua:(%d+):"))
end

describe("Services", function()
	local runtime, register, coins, gems, shop

	before_each(function()
		runtime, register = setup()
		coins = register("coins")
		gems = register("gems")
		shop = register("shop")
	end)

	describe("providing and finding", function()
		it("returns the provider's implementation through a proxy", function()
			coins:ProvideService("economy:bank", "1.2", bank("coins"))
			local service, info = shop:GetService("economy:bank")
			expect.equal(service:Deposit("alex", 5), "coins")
			expect.equal(service:Balance("alex"), 5)
			expect.equal(service.name, "coins")
			expect.same({ info.provider, info.version, info.priority }, { "coins", "1.2", 0 })
		end)

		it("calls methods on the real implementation, which may update itself", function()
			coins:ProvideService("stats:counter", "1.0", {
				count = 0,
				Increment = function(self)
					self.count = self.count + 1
					return self.count
				end,
			})
			local counter = shop:GetService("stats:counter")
			expect.equal(counter:Increment(), 1)
			expect.equal(counter:Increment(), 2)
			expect.equal(counter.count, 2)
		end)

		it("keeps methods working when called with a dot", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			local service = shop:GetService("economy:bank")
			local deposit = service.Deposit
			expect.equal(deposit(service, "alex", 1), "coins")
		end)

		it("puts names without a namespace in the package's own", function()
			coins:ProvideService("bank", "1.0", bank("coins"))
			expect.truthy(shop:GetService("coins:bank"))
			expect.truthy(coins:GetService("bank"))
			expect.is_nil(shop:GetService("bank"))
		end)

		it("returns nil when nobody provides the service", function()
			expect.is_nil(shop:GetService("economy:bank"))
			expect.same(shop:GetServices("economy:bank"), {})
		end)

		it("selects by contract version", function()
			coins:ProvideService("economy:bank", "1.2", bank("coins"), { priority = 10 })
			gems:ProvideService("economy:bank", "2.0", bank("gems"))
			expect.equal(shop:GetService("economy:bank", "1").name, "coins")
			expect.equal(shop:GetService("economy:bank", "1.2").name, "coins")
			expect.is_nil(shop:GetService("economy:bank", "1.3"))
			expect.equal(shop:GetService("economy:bank", "2").name, "gems")
			expect.is_nil(shop:GetService("economy:bank", "3"))
			expect.equal(shop:GetService("economy:bank").name, "coins")
		end)

		it("prefers the highest priority, then the first registered", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"), { priority = 5 })
			gems:ProvideService("economy:bank", "1.1", bank("gems"), { priority = 20 })
			register("cash"):ProvideService("economy:bank", "1.0", bank("cash"), { priority = -1 })
			expect.equal(shop:GetService("economy:bank").name, "gems")
			local names = {}
			for index, entry in ipairs(shop:GetServices("economy:bank")) do
				names[index] = entry.provider .. "@" .. entry.priority
			end
			expect.same(names, { "gems@20", "coins@5", "cash@-1" })
		end)
	end)

	describe("registration rules", function()
		it("refuses two providers with the same priority for one contract version", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			expect.raises(function()
				gems:ProvideService("economy:bank", "1.4", bank("gems"))
			end, "'economy:bank' is already provided by coins with priority 0; choose another priority")
			expect.no_error(function()
				gems:ProvideService("economy:bank", "2.0", bank("gems"))
			end)
		end)

		it("replaces the package's own provider only when asked", function()
			coins:ProvideService("economy:bank", "1.0", bank("old"))
			expect.raises(function()
				coins:ProvideService("economy:bank", "1.1", bank("new"))
			end, "this package already provides 'economy:bank'; pass replace = true to replace it")
			local old = shop:GetService("economy:bank")
			coins:ProvideService("economy:bank", "1.1", bank("new"), { replace = true })
			expect.equal(shop:GetService("economy:bank").name, "new")
			expect.raises(function()
				return old.name
			end, "the provider of 'economy:bank' (coins) is no longer available")
		end)

		it("validates its arguments", function()
			local cases = {
				{ { "economy:bank", "1", {} }, "must be '<major>.<minor>', for example '1.0'" },
				{ { "economy:bank", "v1.0", {} }, "must be '<major>.<minor>'" },
				{ { "economy:bank", "1.0", "impl" }, "'implementation' must be table (got string)" },
				{ { "Economy Bank", "1.0", {} }, "'name' is invalid" },
				{ { "economy:bank", "1.0", {}, { weight = 1 } }, "unknown field 'weight'" },
				{
					{ "economy:bank", "1.0", {}, { priority = 1.5 } },
					"'options.priority' must be integer? (got number)",
				},
				{ { "economy:bank", "1.0", {}, { priority = 2000000 } }, "must be between -1000000 and 1000000" },
			}
			for _, case in ipairs(cases) do
				expect.raises(function()
					coins:ProvideService(table.unpack(case[1]))
				end, case[2])
			end
			expect.raises(function()
				shop:GetService("economy:bank", "latest")
			end, "must be '<major>' or '<major>.<minor>'")
		end)

		it("reports errors at the package's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				shop:GetService("economy:bank", "x")
			end)
			expect.falsy(ok)
			expect.equal(line_of(message), expected_line)
			ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				coins:ProvideService("economy:bank", "1", {})
			end)
			expect.falsy(ok)
			expect.equal(line_of(message), expected_line)
		end)
	end)

	describe("lifetime", function()
		it("removes the provider with its handle", function()
			local handle = coins:ProvideService("economy:bank", "1.0", bank("coins"))
			local service = shop:GetService("economy:bank")
			expect.truthy(handle:Release())
			expect.is_nil(shop:GetService("economy:bank"))
			expect.raises(function()
				service:Deposit("alex", 1)
			end, "is no longer available")
		end)

		it("removes providers of a disabled package and falls back to the next one", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"), { priority = 10 })
			gems:ProvideService("economy:bank", "1.0", bank("gems"))
			local held = shop:GetService("economy:bank")
			local deposit = held.Deposit
			runtime.packages:Disable("coins", "unload")
			expect.equal(shop:GetService("economy:bank").name, "gems")
			expect.raises(function()
				deposit(held, "alex", 1)
			end, "the provider of 'economy:bank' (coins) is no longer available")
			expect.equal(runtime.ownership:Count("coins"), 0)
		end)

		it("does not let consumers change the service", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			local service = shop:GetService("economy:bank")
			expect.raises(function()
				service.name = "hacked"
			end, "services cannot be modified")
			expect.equal(getmetatable(service), false)
		end)

		it("describes providers in the snapshot", function()
			coins:ProvideService("economy:bank", "1.2", bank("coins"), { priority = 3 })
			expect.same(runtime.services:Snapshot().services["economy:bank"], {
				{ owner = "coins", version = "1.2", priority = 3 },
			})
		end)
	end)

	describe("availability", function()
		local calls

		local function watch(context, name, version)
			calls = calls or {}
			return context:OnService(name, version, function(service, info)
				calls[#calls + 1] = service and (service.name .. "@" .. info.provider) or "none"
			end)
		end

		before_each(function()
			calls = {}
		end)

		it("reports the current provider at once, then every change of the best one", function()
			coins:ProvideService("economy:bank", "1.0", bank("coins"), { priority = 5 })
			watch(shop, "economy:bank")
			expect.same(calls, { "coins@coins" })
			gems:ProvideService("economy:bank", "1.0", bank("gems"), { priority = 1 })
			expect.same(calls, { "coins@coins" })
			local cash = register("cash"):ProvideService("economy:bank", "1.0", bank("cash"), { priority = 9 })
			expect.same(calls, { "coins@coins", "cash@cash" })
			cash:Release()
			expect.same(calls, { "coins@coins", "cash@cash", "coins@coins" })
			runtime.packages:Disable("coins", "unload")
			runtime.packages:Disable("gems", "unload")
			expect.same(calls, { "coins@coins", "cash@cash", "coins@coins", "gems@gems", "none" })
		end)

		it("waits silently until a matching provider appears", function()
			watch(shop, "economy:bank", "2")
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			expect.same(calls, {})
			gems:ProvideService("economy:bank", "2.1", bank("gems"))
			expect.same(calls, { "gems@gems" })
		end)

		it("reports a replacement once", function()
			coins:ProvideService("economy:bank", "1.0", bank("old"))
			watch(shop, "economy:bank")
			coins:ProvideService("economy:bank", "1.1", bank("new"), { replace = true })
			expect.same(calls, { "old@coins", "new@coins" })
		end)

		it("stops with its handle and with its package", function()
			local handle = watch(shop, "economy:bank")
			handle:Release()
			watch(gems, "economy:bank")
			runtime.packages:Disable("gems", "unload")
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			expect.same(calls, {})
			expect.equal(runtime.ownership:Count("shop"), 0)
		end)

		it("skips a watcher released by another one during the same change", function()
			local second
			shop:OnService("economy:bank", nil, function()
				second:Release()
			end)
			second = watch(gems, "economy:bank")
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			expect.same(calls, {})
		end)

		it("isolates a failing callback", function()
			shop:OnService("economy:bank", nil, function()
				error("watcher exploded")
			end)
			watch(gems, "economy:bank")
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			expect.same(calls, { "coins@coins" })
		end)

		it("validates its arguments", function()
			expect.raises(function()
				shop:OnService("economy:bank", "x", function() end)
			end, "must be '<major>' or '<major>.<minor>'")
			expect.raises(function()
				shop:OnService("economy:bank", nil, "fn")
			end, "'fn' must be function (got string)")
		end)

		it("emits Foundation events for each provider", function()
			local seen = {}
			for _, name in ipairs({ "service_available", "service_unavailable" }) do
				shop:Listen("foundation:" .. name, function(event)
					seen[#seen + 1] = name
						.. ":"
						.. event:Get("service")
						.. ":"
						.. event:Get("provider")
						.. ":"
						.. event:Get("version")
				end)
			end
			coins:ProvideService("economy:bank", "1.0", bank("coins"))
			coins:ProvideService("economy:bank", "1.1", bank("coins"), { replace = true })
			runtime.packages:Disable("coins", "unload")
			expect.same(seen, {
				"service_available:economy:bank:coins:1.0",
				"service_unavailable:economy:bank:coins:1.0",
				"service_available:economy:bank:coins:1.1",
				"service_unavailable:economy:bank:coins:1.1",
			})
		end)
	end)
end)
