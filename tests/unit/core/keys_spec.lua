local function setup()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Keys = loader:require("foundation/core/keys.lua")
	local errors = Errors.new(Messages.new({ en = loader:require("foundation/locales/en/core.lua") }))
	return Keys.new(errors), Keys, Errors
end

describe("Keys", function()
	local keys, Keys, Errors

	before_each(function()
		keys, Keys, Errors = setup()
	end)

	describe("Parse", function()
		it("returns the key, its namespace and path", function()
			local key, namespace, path = keys:Parse("my-package:homes/spawn_point.v2")
			expect.equal(key, "my-package:homes/spawn_point.v2")
			expect.equal(namespace, "my-package")
			expect.equal(path, "homes/spawn_point.v2")
		end)

		it("normalizes to lowercase", function()
			expect.equal(keys:Parse("My-Package:Homes"), "my-package:homes")
		end)

		it("uses the default namespace when none is given", function()
			expect.equal(keys:Parse("homes", "My-Package"), "my-package:homes")
			expect.equal(keys:Parse("other:homes", "my-package"), "other:homes")
		end)

		it("returns a structured error for invalid text", function()
			for _, text in ipairs({
				"",
				"homes",
				":homes",
				"ns:",
				"ns:a b",
				"n s:a",
				"ns:/a",
				"ns:a/",
				"ns:a//b",
				"ns:a:b",
				"ns:é",
				string.rep("a", 65) .. ":b",
				"ns:" .. string.rep("a", 126),
				42,
				nil,
			}) do
				local key, err = keys:Parse(text)
				expect.is_nil(key, tostring(text))
				expect.truthy(Errors.Is(err), tostring(text))
				expect.equal(err.code, "invalid_key")
				expect.equal(err.category, "user")
			end
		end)

		it("explains why a key is rejected", function()
			local _, missing = keys:Parse("homes")
			expect.equal(missing.message, "'homes' is not a valid key: the namespace is missing ('<namespace>:<path>')")
			local _, long = keys:Parse("ns:" .. string.rep("a", 126))
			expect.contains(long.message, "longer than 128 characters")
		end)

		it("accepts keys of exactly the maximum length", function()
			local key = keys:Parse("ns:" .. string.rep("a", 125))
			expect.equal(#key, Keys.MAX_LENGTH)
		end)

		it("rejects a default namespace that is not a string", function()
			expect.raises(function()
				keys:Parse("homes", 5)
			end, "'default_namespace' must be string? (got number)")
		end)
	end)

	describe("Check", function()
		it("returns normalized keys", function()
			expect.equal(keys:Check("Api", 1, "key", "NS:Path"), "ns:path")
			expect.equal(keys:Check("Api", 1, "key", "path", { default_namespace = "pkg" }), "pkg:path")
		end)

		it("raises invalid_value at the line calling the public function", function()
			local function public_api(key)
				local checked = keys:Check("Api.Call", 2, "key", key)
				return checked
			end
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				public_api("no namespace")
			end)
			expect.falsy(ok)
			expect.contains(message, "[foundation:invalid_value] Api.Call: argument #2 'key' is invalid")
			expect.equal(tonumber(message:match("keys_spec%.lua:(%d+):")), expected_line)
		end)

		it("requires the owner's namespace when an owner is given", function()
			expect.equal(keys:Check("Api", 1, "key", "pkg:a", { owner = "pkg" }), "pkg:a")
			expect.raises(function()
				keys:Check("Api", 1, "key", "foundation:a", { owner = "pkg" })
			end, "must be in the 'pkg' namespace")
		end)
	end)

	it("splits valid keys", function()
		expect.same({ Keys.Split("pkg:a/b:c") }, { "pkg", "a/b:c" })
		expect.same({ Keys.Split("pkg:a/b") }, { "pkg", "a/b" })
	end)

	it("reserves the foundation namespace", function()
		expect.truthy(Keys.IsReserved("foundation"))
		expect.falsy(Keys.IsReserved("my-package"))
	end)
end)
