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
			elseif name == "Set" or name == "Delete" or name == "Batch" or name == "Write" then
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
	local lines = {}
	control.lines = lines
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

	describe("versions and migrations", function()
		local function seed(namespace, values, version)
			for key, value in pairs(values) do
				memory:Set(namespace, key, value, function() end)
			end
			if version then
				memory:Set("foundation/versions", namespace, tostring(version), function() end)
			end
		end

		local function stored_version(namespace)
			local version
			memory:Get("foundation/versions", namespace, function(_, value)
				version = value
			end)
			return version
		end

		local function output()
			return table.concat(control.lines, "\n")
		end

		it("records the version of a new store without migrating", function()
			local called = false
			local fresh = register("fresh"):Store("data", {
				version = 3,
				migrations = {
					function()
						called = true
					end,
					function() end,
				},
			})
			expect.truthy(value_of(fresh:Set("a", 1)))
			expect.falsy(called)
			expect.equal(stored_version("fresh/data"), "3")
		end)

		it("treats existing data without a version as version 1 and migrates it in order", function()
			seed("bank", { ["alex"] = "10", ["sam"] = "3" })
			local bank = register("bank"):Store(nil, {
				version = 3,
				migrations = {
					[1] = function(entries)
						local result = {}
						for account, coins in pairs(entries) do
							result["account:" .. account] = { coins = coins }
						end
						return result
					end,
					[2] = function(entries)
						for _, account in pairs(entries) do
							account.gems = 0
						end
						return entries
					end,
				},
			})
			expect.same(value_of(bank:Get("account:alex")), { coins = 10, gems = 0 })
			expect.is_nil(value_of(bank:Get("alex")))
			expect.same(value_of(bank:Keys()), { "account:alex", "account:sam" })
			expect.equal(stored_version("bank"), "3")
			expect.contains(output(), "migrated 'bank' from version 1 to 3 (4 change(s))")
		end)

		it("starts from the stored version", function()
			seed("bank", { alex = '{"coins":10}', sam = '{"coins":5}' }, 2)
			local first_called = false
			local bank = register("bank"):Store(nil, {
				version = 3,
				migrations = {
					function(entries)
						first_called = true
						return entries
					end,
					function(entries)
						entries.alex.coins = entries.alex.coins * 100
						return entries
					end,
				},
			})
			expect.same(value_of(bank:Get("alex")), { coins = 1000 })
			expect.same(value_of(bank:Get("sam")), { coins = 5 })
			expect.falsy(first_called)
			expect.contains(output(), "migrated 'bank' from version 2 to 3 (1 change(s))")
		end)

		it("changes nothing and fails the package when a migration fails", function()
			seed("bank", { alex = "10" })
			local context = register("bank")
			local bank = context:Store(nil, {
				version = 2,
				migrations = {
					function()
						error("bad migration")
					end,
				},
			})
			local raw
			memory:Get("bank", "alex", function(_, value)
				raw = value
			end)
			expect.equal(raw, "10")
			expect.is_nil(stored_version("bank"))
			expect.equal(context:GetState(), "failed")
			expect.contains(
				output(),
				"the data of 'bank' could not be migrated from version 1 (the migration raised an error"
			)
			expect.contains(output(), "store_migration callback of bank failed")
			expect.equal(bank.unavailable, true)
		end)

		it("refuses migration results that cannot be stored", function()
			for _, case in ipairs({
				{
					function()
						return "oops"
					end,
					"returned a string instead of the table of entries",
				},
				{
					function()
						return { [""] = 1 }
					end,
					"returned the invalid key ''",
				},
				{
					function()
						return { a = function() end }
					end,
					"unsupported type function",
				},
			}) do
				runtime, register, memory, control = setup()
				seed("bank", { alex = "10" })
				local context = register("bank")
				context:Store(nil, { version = 2, migrations = { case[1] } })
				expect.equal(context:GetState(), "failed")
				expect.contains(output(), case[2])
			end
		end)

		it("refuses data newer than the declared version and leaves it untouched", function()
			seed("bank", { alex = "10" }, 5)
			local context = register("bank")
			local bank = context:Store(nil, { version = 2, migrations = {
				function(e)
					return e
				end,
			} })
			expect.equal(context:GetState(), "failed")
			expect.raises(function()
				bank:Get("alex")
			end, "belongs to a package that stopped")
			expect.equal(stored_version("bank"), "5")
			expect.contains(output(), "the data of 'bank' is version 5, newer than version 2")
		end)

		it("keeps the old data when the migrated data cannot be written", function()
			seed("bank", { alex = "10" })
			control.fail_writes = true
			local context = register("bank")
			local options = {
				version = 2,
				migrations = {
					function(entries)
						entries.alex = 20
						return entries
					end,
				},
			}
			context:Store(nil, options)
			expect.equal(context:GetState(), "failed")
			expect.is_nil(stored_version("bank"))
		end)

		it("validates the options at the caller's line", function()
			local context = register("opts")
			local cases = {
				{ { version = 0 }, "must be at least 1" },
				{ { version = 1.5 }, "'options.version' must be integer (got number)" },
				{ { version = 3, migrations = { function() end } }, "no migration from version 2" },
				{ { version = 1, schema = 1 }, "unknown field 'schema'" },
			}
			for _, case in ipairs(cases) do
				local message = expect.raises(function()
					context:Store("x", case[1])
				end, case[2])
				expect.truthy(tostring(message):find("stores_spec%.lua:%d+:"), tostring(message))
			end
			context:Store("y", { version = 1 })
			expect.raises(function()
				context:Store("y", { version = 2, migrations = {
					function(e)
						return e
					end,
				} })
			end, "'opts/y' is already open with another version")
		end)
	end)
end)
