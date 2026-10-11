local function setup(options)
	options = options or {}
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Memory = loader:require("foundation/core/storage_memory.lua")
	local Senders = loader:require("foundation/core/senders.lua")
	local memory = Memory.new()
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
		create_storage_backend = function()
			if options.unavailable then
				return nil
			end
			return memory
		end,
	})
	runtime:Start()
	local function register(id)
		return runtime.packages:Register({
			GetName = function()
				return id
			end,
			Subscribe = function() end,
		}, { api = "0.1" })
	end
	return runtime, register, memory, Senders
end

local function value_of(future)
	expect.equal(future:GetState(), "resolved", tostring(future:GetError()))
	return future:GetValue()
end

describe("Persistent data", function()
	local runtime, register, memory, Senders, economy, S, coins

	before_each(function()
		runtime, register, memory, Senders = setup()
		economy = register("economy")
		S = runtime.schema
		coins = economy:DefineData("coins", S:Integer({ min = 0 }), { default = 0 })
	end)

	it("returns the default until a value is set, per subject", function()
		expect.equal(coins:GetName(), "economy:coins")
		expect.equal(value_of(coins:Get("76561198000000001")), 0)
		coins:Set("76561198000000001", 150)
		expect.equal(value_of(coins:Get("76561198000000001")), 150)
		expect.equal(value_of(coins:Get("76561198000000002")), 0)
	end)

	it("keeps each package's data in its own namespace", function()
		coins:Set("alex", 5)
		local raw
		memory:Get("data:economy", "coins|alex", function(_, text)
			raw = text
		end)
		expect.equal(raw, "5")
		local other = register("shop"):DefineData("coins", S:Integer())
		expect.is_nil(value_of(other:Get("alex")))
	end)

	it("returns copies of table defaults and values", function()
		local inventory = economy:DefineData("inventory", S:List(S:String()), { default = {} })
		local first = value_of(inventory:Get("alex"))
		first[1] = "changed"
		expect.same(value_of(inventory:Get("alex")), {})
	end)

	it("validates values against the schema at the caller's line", function()
		local expected_line
		local ok, message = pcall(function()
			expected_line = debug.getinfo(1, "l").currentline + 1
			coins:Set("alex", -3)
		end)
		expect.falsy(ok)
		expect.contains(message, "does not match the schema of 'economy:coins': $: must be at least 0")
		expect.equal(tonumber(message:match("data_spec%.lua:(%d+):")), expected_line)
	end)

	it("stores the validated value, with the schema's defaults applied", function()
		local profile = economy:DefineData(
			"profile",
			S:Record({
				name = S:String(),
				level = S:Optional(S:Integer(), 1),
			})
		)
		profile:Set("alex", { name = "Alex" })
		expect.same(value_of(profile:Get("alex")), { name = "Alex", level = 1 })
	end)

	it("refuses subjects with control characters", function()
		expect.raises(function()
			coins:Get("alex\n")
		end, "'subject' is invalid")
	end)

	it("deletes a subject's value", function()
		coins:Set("alex", 9)
		expect.equal(value_of(coins:Delete("alex")), true)
		expect.equal(value_of(coins:Get("alex")), 0)
		expect.equal(value_of(coins:Delete("alex")), false)
	end)

	it("accepts player senders as subjects", function()
		local alex = Senders.new({ kind = "player", id = "76561198000000001", reply = function() end })
		coins:Set(alex, 7)
		expect.equal(value_of(coins:Get("76561198000000001")), 7)
	end)

	it("lets other packages read but not write", function()
		coins:Set("alex", 42)
		local shop = register("shop")
		local reader = shop:ReadData("economy:coins")
		expect.equal(reader:GetName(), "economy:coins")
		local future = reader:Get("alex")
		expect.equal(value_of(future), 42)
		expect.is_nil(value_of(reader:Get("sam")))
		expect.is_nil(reader.Set)
		expect.equal(runtime.ownership:Count("shop", "future"), 0)
	end)

	it("can still be read after the defining package stopped", function()
		coins:Set("alex", 3)
		runtime.packages:Disable("economy", "unload")
		expect.raises(function()
			coins:Get("alex")
		end, "'economy:coins' belongs to a package that stopped")
		expect.equal(value_of(register("shop"):ReadData("economy:coins"):Get("alex")), 3)
		local again = register("economy")
		expect.equal(value_of(again:DefineData("coins", S:Integer()):Get("alex")), 3)
	end)

	it("refuses invalid definitions and subjects", function()
		local cases = {
			{
				function()
					economy:DefineData("Coins", S:Integer())
				end,
				"'name' is invalid",
			},
			{
				function()
					economy:DefineData("gems", "integer")
				end,
				"'schema' must be schema (got string)",
			},
			{
				function()
					economy:DefineData("gems", S:Integer(), { default = "x" })
				end,
				"the default value does not match",
			},
			{
				function()
					economy:DefineData("gems", S:Integer(), { persistent = true })
				end,
				"unknown field 'persistent'",
			},
			{
				function()
					economy:DefineData("coins", S:Integer())
				end,
				"'economy:coins' is already defined",
			},
			{
				function()
					coins:Get("")
				end,
				"'subject' is invalid",
			},
			{
				function()
					coins:Get(42)
				end,
				"'subject' is invalid",
			},
			{
				function()
					coins:Set(Senders.new({ kind = "console", reply = function() end }), 1)
				end,
				"'subject' is invalid",
			},
			{
				function()
					economy:DefineData("note", S:String()):Set("alex", string.rep("a", 1048577))
				end,
				"'value' is invalid: larger than 1048576 bytes",
			},
			{
				function()
					economy:ReadData("coins")
				end,
				"'key' is invalid",
			},
		}
		for _, case in ipairs(cases) do
			local message = expect.raises(case[1], case[2])
			expect.truthy(tostring(message):find("data_spec%.lua:%d+:"), tostring(message))
		end
	end)

	it("rejects reads when storage is unavailable", function()
		local _, unavailable_register = setup({ unavailable = true })
		local reader = unavailable_register("shop"):ReadData("economy:coins")
		local future = reader:Get("alex")
		expect.equal(future:GetState(), "rejected")
		expect.equal(future:GetError().code, "storage_unavailable")
	end)
end)
