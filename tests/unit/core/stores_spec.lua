local function setup(options)
	options = options or {}
	local loader = Loader.new()
	local Runtime = loader:require("foundation/core/runtime.lua")
	local Memory = loader:require("foundation/core/storage_memory.lua")
	local memory = Memory.new()
	local control = { held = {}, fail_writes = false, reads = 0, settings = nil }
	-- Memory backend with knobs: held Sizes answers, failing writes, counted reads.
	local backend = setmetatable({}, {
		__index = function(_, name)
			local method = memory[name]
			if name == "Sizes" then
				return function(_, namespace, callback)
					if control.hold then
						control.held[#control.held + 1] = function()
							memory:Sizes(namespace, callback)
						end
					else
						memory:Sizes(namespace, callback)
					end
				end
			elseif name == "Get" then
				return function(_, ...)
					control.reads = control.reads + 1
					return memory:Get(...)
				end
			elseif name == "Set" or name == "Delete" or name == "Batch" then
				return function(_, ...)
					if control.fail_writes then
						local callback = select(select("#", ...), ...)
						return callback(false, "disk full")
					end
					return method(memory, ...)
				end
			end
			return function(_, ...)
				return method(memory, ...)
			end
		end,
	})
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
			return backend
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
	return runtime, register, memory, control
end

local function value_of(future)
	expect.equal(future:GetState(), "resolved", tostring(future:GetError()))
	return future:GetValue()
end

local function error_of(future)
	expect.equal(future:GetState(), "rejected")
	return future:GetError()
end

describe("Package stores", function()
	local runtime, register, memory, control, shop, store

	before_each(function()
		runtime, register, memory, control = setup()
		shop = register("shop")
		store = shop:Store()
	end)

	it("stores JSON values and reads them back as new tables", function()
		expect.truthy(value_of(store:Set("player:alex", { coins = 10, items = { "apple" } })))
		local first = value_of(store:Get("player:alex"))
		first.coins = 999
		expect.same(value_of(store:Get("player:alex")), { coins = 10, items = { "apple" } })
		expect.is_nil(value_of(store:Get("player:sam")))
		local raw
		memory:Get("shop", "player:alex", function(_, text)
			raw = text
		end)
		expect.equal(raw, '{"coins":10,"items":["apple"]}')
	end)

	it("answers missing keys and cached values without reading the backend", function()
		store:Set("a", 1)
		store:Get("a")
		store:Get("missing")
		expect.equal(control.reads, 0)
	end)

	it("reads values written before the store was opened", function()
		memory:Set("shop/archive", "old", '"kept"', function() end)
		local archive = shop:Store("archive")
		expect.equal(value_of(archive:Get("old")), "kept")
		expect.equal(value_of(archive:Get("old")), "kept")
		expect.equal(control.reads, 1)
		expect.same(value_of(archive:Keys()), { "old" })
	end)

	it("deletes, tells whether the key existed, and lists keys by prefix", function()
		store:Batch({
			{ op = "set", key = "homes/b", value = true },
			{ op = "set", key = "homes/a", value = true },
			{ op = "set", key = "warps/x", value = true },
		})
		expect.same(value_of(store:Keys("homes/")), { "homes/a", "homes/b" })
		expect.same(value_of(store:Keys("", 1)), { "homes/a" })
		expect.equal(value_of(store:Delete("homes/a")), true)
		expect.equal(value_of(store:Delete("homes/a")), false)
		expect.same(value_of(store:Keys("homes/")), { "homes/b" })
	end)

	it("keeps exact usage and enforces quotas", function()
		runtime.settings = { storage = { max_bytes_per_package = 20, max_keys_per_package = 2 } }
		store:Set("a", "123")
		expect.same(store:Usage(), { count = 1, bytes = 6, max_keys = 2, max_bytes = 20 })
		store:Set("a", "12345")
		expect.equal(store:Usage().bytes, 8)
		store:Set("b", 1)
		local err = error_of(store:Set("c", 1))
		expect.equal(err.code, "storage_quota")
		expect.equal(err.category, "developer")
		err = error_of(store:Set("a", "this value is far too long"))
		expect.equal(err.code, "storage_quota")
		expect.equal(value_of(store:Get("a")), "12345")
		expect.truthy(value_of(store:Set("a", "1")))
		expect.equal(store:Usage().count, 2)
	end)

	it("waits for its keys before answering", function()
		control.hold = true
		local late = register("late"):Store()
		local future = late:Get("x")
		local write = late:Set("y", 1)
		expect.equal(future:GetState(), "pending")
		control.hold = false
		for _, release in ipairs(control.held) do
			release()
		end
		expect.is_nil(value_of(future))
		expect.truthy(value_of(write))
	end)

	it("restores the previous state when a write fails", function()
		store:Set("a", "before")
		control.fail_writes = true
		local err = error_of(store:Set("a", "after"))
		expect.equal(err.code, "storage_failed")
		expect.equal(err.cause, "disk full")
		expect.equal(error_of(store:Delete("a")).code, "storage_failed")
		control.fail_writes = false
		expect.equal(value_of(store:Get("a")), "before")
		expect.equal(store:Usage().count, 1)
	end)

	it("reports values that are not valid JSON", function()
		memory:Set("shop/bad", "k", "{oops", function() end)
		local err = error_of(shop:Store("bad"):Get("k"))
		expect.equal(err.code, "storage_corrupt")
	end)

	it("returns the same store for the same name and separates names", function()
		expect.equal(shop:Store(), store)
		local homes = shop:Store("homes")
		homes:Set("k", 1)
		expect.is_nil(value_of(store:Get("k")))
		expect.equal(homes:GetName(), "shop/homes")
		expect.equal(store:GetName(), "shop")
	end)

	it("stops serving a stopped package but keeps its data", function()
		store:Set("a", 1)
		runtime.packages:Disable("shop", "unload")
		expect.raises(function()
			store:Get("a")
		end, "belongs to a package that stopped")
		local again = register("shop")
		expect.equal(value_of(again:Store():Get("a")), 1)
	end)

	it("validates keys, values and names at the caller's line", function()
		local cases = {
			{
				function()
					store:Get("")
				end,
				"'key' is invalid",
			},
			{
				function()
					store:Set("bad\nkey", 1)
				end,
				"'key' is invalid",
			},
			{
				function()
					store:Set("k", nil)
				end,
				"use Delete to remove a key",
			},
			{
				function()
					store:Set("k", function() end)
				end,
				"unsupported type function",
			},
			{
				function()
					store:Batch({ { op = "put", key = "k" } })
				end,
				"'operations[1]' is invalid",
			},
			{
				function()
					store:Keys(nil, 1.5)
				end,
				"'limit' must be integer? (got number)",
			},
			{
				function()
					shop:Store("Bad Name")
				end,
				"'name' is invalid",
			},
		}
		for _, case in ipairs(cases) do
			local message = expect.raises(case[1], case[2])
			expect.truthy(tostring(message):find("stores_spec%.lua:%d+:"), tostring(message))
		end
	end)

	it("rejects every operation when storage is unavailable", function()
		local unavailable_runtime, unavailable_register = setup({ unavailable = true })
		local unavailable = unavailable_register("shop"):Store()
		expect.equal(error_of(unavailable:Get("a")).code, "storage_unavailable")
		expect.equal(unavailable_runtime.stores:Snapshot().available, false)
	end)
end)
