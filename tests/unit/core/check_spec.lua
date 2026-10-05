local function new_check()
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local messages = Messages.new({ en = loader:require("foundation/locales/en/core.lua") })
	return Check.new(Errors.new(messages))
end

describe("Check", function()
	local check

	before_each(function()
		check = new_check()
	end)

	describe("Argument", function()
		it("returns the value when the type matches", function()
			expect.equal(check:Argument("Api", 1, "name", "x", "string"), "x")
			expect.equal(check:Argument("Api", 1, "count", 3, "integer"), 3)
			expect.equal(check:Argument("Api", 1, "count", 3.0, "integer"), 3.0)
			expect.equal(check:Argument("Api", 1, "ratio", 0.5, "number"), 0.5)
			expect.equal(check:Argument("Api", 1, "value", false, "any"), false)
		end)

		it("accepts nil for optional types only", function()
			expect.is_nil(check:Argument("Api", 2, "opts", nil, "table?"))
			expect.raises(function()
				check:Argument("Api", 2, "opts", nil, "table")
			end, "[foundation:invalid_argument] Api: argument #2 'opts' must be table (got nil)")
		end)

		it("rejects non-integral numbers and special values for integer", function()
			for _, value in ipairs({ 1.5, math.huge, -math.huge, 0 / 0 }) do
				expect.raises(function()
					check:Argument("Api", 1, "count", value, "integer")
				end, "must be integer (got number)")
			end
		end)

		it("rejects nil for any", function()
			expect.raises(function()
				check:Argument("Api", 1, "value", nil, "any")
			end, "must be any (got nil)")
		end)

		it("reports the caller of the public function", function()
			local function public_api(value)
				check:Argument("Public.Api", 1, "value", value, "string")
			end
			local ok, message = pcall(function()
				public_api(42) -- reported line
			end)
			expect.falsy(ok)
			local line = tonumber(message:match("check_spec%.lua:(%d+):"))
			expect.equal(line, debug.getinfo(1, "l").currentline - 4)
		end)

		it("honours an explicit level for checks made inside helpers", function()
			local function helper(value)
				check:Argument("Public.Api", 1, "value", value, "string", 3)
			end
			local function public_api(value)
				helper(value)
			end
			local ok, message = pcall(function()
				public_api(42) -- reported line
			end)
			expect.falsy(ok)
			local line = tonumber(message:match("check_spec%.lua:(%d+):"))
			expect.equal(line, debug.getinfo(1, "l").currentline - 4)
		end)

		it("rejects unsupported type names", function()
			expect.raises(function()
				check:Argument("Api", 1, "value", 1, "float")
			end, "unsupported type 'float'")
		end)
	end)

	describe("NonEmptyString", function()
		it("accepts non-empty strings", function()
			expect.equal(check:NonEmptyString("Api", 1, "id", "a"), "a")
		end)

		it("rejects empty strings and non-strings", function()
			expect.raises(function()
				check:NonEmptyString("Api", 1, "id", "")
			end, "[foundation:invalid_value] Api: argument #1 'id' is invalid: must not be empty")
			expect.raises(function()
				check:NonEmptyString("Api", 1, "id", 5)
			end, "must be string (got number)")
		end)
	end)

	describe("OneOf", function()
		it("returns allowed values", function()
			expect.equal(check:OneOf("Api", 3, "mode", "b", { "a", "b" }), "b")
		end)

		it("lists the allowed values when rejecting", function()
			expect.raises(function()
				check:OneOf("Api", 3, "mode", "c", { "a", "b" })
			end, "argument #3 'mode' is invalid: expected one of a, b")
		end)
	end)
end)
