local function backend()
	return Loader.new():require("foundation/core/storage_memory.lua").new()
end

local function result(fn)
	local ok, value
	fn(function(a, b)
		ok, value = a, b
	end)
	return ok, value
end

describe("Memory storage backend", function()
	local memory

	before_each(function()
		memory = backend()
	end)

	it("stores, reads, overwrites and deletes values per namespace", function()
		expect.same({ result(function(cb)
			memory:Get("shop", "a", cb)
		end) }, { true })
		result(function(cb)
			memory:Set("shop", "a", "1", cb)
		end)
		result(function(cb)
			memory:Set("shop", "a", "2", cb)
		end)
		result(function(cb)
			memory:Set("bank", "a", "other", cb)
		end)
		expect.same({ result(function(cb)
			memory:Get("shop", "a", cb)
		end) }, { true, "2" })
		expect.same({ result(function(cb)
			memory:Delete("shop", "a", cb)
		end) }, { true })
		expect.same({ result(function(cb)
			memory:Get("shop", "a", cb)
		end) }, { true })
		expect.same({ result(function(cb)
			memory:Get("bank", "a", cb)
		end) }, { true, "other" })
	end)

	it("lists keys by prefix, sorted and limited", function()
		for _, key in ipairs({ "homes/b", "homes/a", "warps/x", "homes/c" }) do
			result(function(cb)
				memory:Set("shop", key, "v", cb)
			end)
		end
		expect.same(
			{ result(function(cb)
				memory:Keys("shop", "homes/", 2, cb)
			end) },
			{ true, { "homes/a", "homes/b" } }
		)
	end)

	it("applies batches and reports usage", function()
		result(function(cb)
			memory:Set("shop", "old", "x", cb)
		end)
		result(function(cb)
			memory:Batch("shop", { { op = "set", key = "a", value = "12" }, { op = "delete", key = "old" } }, cb)
		end)
		expect.same({ result(function(cb)
			memory:Usage("shop", cb)
		end) }, { true, { count = 1, bytes = 3 } })
	end)
end)
