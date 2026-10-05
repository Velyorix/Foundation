local function setup(locale)
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local Check = loader:require("foundation/core/check.lua")
	local Keys = loader:require("foundation/core/keys.lua")
	local Log = loader:require("foundation/core/log.lua")
	local Invoker = loader:require("foundation/core/invoke.lua")
	local Schema = loader:require("foundation/core/schema.lua")
	local messages = Messages.new({
		en = loader:require("foundation/locales/en/core.lua"),
		fr = loader:require("foundation/locales/fr/core.lua"),
	}, locale or "en")
	local errors = Errors.new(messages)
	local logged = {}
	local log = Log.new({
		sink = function(level, line)
			logged[#logged + 1] = { level = level, line = line }
		end,
		messages = messages,
		clock = function()
			return 0
		end,
	})
	local schema = Schema.new({
		errors = errors,
		check = Check.new(errors),
		keys = Keys.new(errors),
		invoker = Invoker.new({ log = log, side = "server" }),
	})
	return schema, Schema, logged
end

local function problems(err)
	local list = {}
	for index, problem in ipairs(err.details.problems) do
		list[index] = problem.message
	end
	return list
end

describe("Schema", function()
	local S, Schema, logged

	before_each(function()
		S, Schema, logged = setup()
	end)

	local function valid(node, value)
		local result, err = S:Validate(node, value)
		expect.is_nil(err, err and err.message)
		return result
	end

	local function invalid(node, value)
		local result, err = S:Validate(node, value)
		expect.is_nil(result)
		expect.equal(err.code, "validation_failed")
		expect.equal(err.category, "user")
		return problems(err), err
	end

	describe("scalars", function()
		it("checks types and reports the actual type", function()
			expect.equal(valid(S:String(), "a"), "a")
			expect.equal(valid(S:Boolean(), false), false)
			expect.same(invalid(S:String(), 5), { "$: expected string, got integer" })
			expect.same(invalid(S:Number(), "5"), { "$: expected number, got string" })
			expect.same(invalid(S:Boolean(), 0), { "$: expected boolean, got integer" })
		end)

		it("requires a value unless optional", function()
			expect.same(invalid(S:String(), nil), { "$: is required" })
			expect.is_nil(valid(S:Optional(S:String()), nil))
			expect.equal(valid(S:Optional(S:String(), "x"), nil), "x")
		end)

		it("accepts any non-nil value with Any", function()
			local value = { 1 }
			expect.equal(valid(S:Any(), value), value)
			expect.same(invalid(S:Any(), nil), { "$: is required" })
		end)

		it("checks numeric bounds, integers and finiteness", function()
			local node = S:Integer({ min = 1, max = 10 })
			expect.equal(valid(node, 3), 3)
			expect.equal(valid(node, 3.0), 3.0)
			expect.same(invalid(node, 2.5), { "$: must be an integer" })
			expect.same(invalid(node, 0), { "$: must be at least 1" })
			expect.same(invalid(node, 11), { "$: must be at most 10" })
			for _, value in ipairs({ 0 / 0, math.huge, -math.huge }) do
				expect.same(invalid(S:Number(), value), { "$: must be a finite number" })
			end
		end)

		it("counts string length in UTF-8 characters and checks patterns", function()
			local node = S:String({ min = 2, max = 3, pattern = "^%a+$" })
			expect.equal(valid(S:String({ max = 3 }), "été"), "été")
			expect.same(invalid(node, "a"), { "$: must have at least 2 characters" })
			expect.same(invalid(node, "abcd"), { "$: must have at most 3 characters" })
			expect.same(invalid(node, "a1"), { "$: has an invalid format" })
			expect.same(invalid(S:String(), "\255"), { "$: is not valid UTF-8 text" })
		end)

		it("restricts values with Enum", function()
			local node = S:Enum({ "en", "fr" })
			expect.equal(valid(node, "fr"), "fr")
			expect.same(invalid(node, "de"), { "$: must be one of en, fr" })
		end)
	end)

	describe("records", function()
		local player

		before_each(function()
			player = S:Record({
				name = S:String({ min = 1 }),
				level = S:Optional(S:Integer({ min = 1 }), 1),
				tags = S:Optional(S:List(S:String())),
			})
		end)

		it("returns a copy with defaults applied", function()
			local input = { name = "Ana" }
			local result = valid(player, input)
			expect.same(result, { name = "Ana", level = 1 })
			expect.falsy(result == input)
			expect.is_nil(input.level)
		end)

		it("rejects unknown fields by default", function()
			expect.same(invalid(player, { name = "Ana", lvl = 2 }), { "$.lvl: is not an allowed field" })
		end)

		it("can allow or strip unknown fields", function()
			local allow = S:Record({ a = S:Integer() }, { extra = "allow" })
			local strip = S:Record({ a = S:Integer() }, { extra = "strip" })
			expect.same(valid(allow, { a = 1, b = { 2 } }), { a = 1, b = { 2 } })
			expect.same(valid(strip, { a = 1, b = 2 }), { a = 1 })
		end)

		it("collects every problem with its path, in field order", function()
			local list, err = invalid(player, { level = 0, tags = { "a", 5 }, [3] = true })
			expect.same(list, {
				"$.level: must be at least 1",
				"$.name: is required",
				"$.tags[2]: expected string, got integer",
				"$[3]: is not an allowed field",
			})
			expect.equal(err.details.count, 4)
			expect.equal(err.message, "invalid value (4 problem(s)): $.level: must be at least 1")
			expect.equal(err.details.problems[2].reason, "validation.required")
		end)

		it("uses quoted paths for keys that are not identifiers", function()
			expect.same(invalid(S:Record({}), { ["my key"] = 1 }), { '$["my key"]: is not an allowed field' })
		end)

		it("renders problems in the active locale", function()
			local French = setup("fr")
			local _, err = French:Validate(French:Record({ name = French:String() }), {})
			expect.equal(err.details.problems[1].message, "$.name : est obligatoire")
		end)
	end)

	describe("lists and maps", function()
		it("validates items and bounds", function()
			local node = S:List(S:Integer(), { min = 1, max = 2 })
			expect.same(valid(node, { 1, 2 }), { 1, 2 })
			expect.same(invalid(node, {}), { "$: must have at least 1 items" })
			expect.same(invalid(node, { 1, 2, 3 }), { "$: must have at most 2 items" })
			expect.same(invalid(node, { [1] = 1, [3] = 3 }), { "$: must be a list without gaps" })
			expect.same(invalid(node, { x = 1 }), { "$: must be a list without gaps" })
		end)

		it("validates keys and values of maps", function()
			local node = S:Map(S:String({ max = 3 }), S:Integer(), { max = 2 })
			expect.same(valid(node, { ab = 1 }), { ab = 1 })
			expect.same(invalid(node, { abcd = 1 }), { "$.abcd: must have at most 3 characters" })
			expect.same(invalid(node, { a = "x" }), { "$.a: expected integer, got string" })
			expect.same(invalid(node, { a = 1, b = 2, c = 3 }), { "$: must have at most 2 entries" })
		end)
	end)

	describe("limits", function()
		it("stops at the maximum depth", function()
			local node = S:Any()
			for _ = 1, 20 do
				node = S:List(node)
			end
			local value = 1
			for _ = 1, 20 do
				value = { value }
			end
			local list = invalid(node, value)
			expect.equal(#list, 1)
			expect.contains(list[1], "is nested more than 16 levels deep")
		end)

		it("stops after too many values and accepts custom limits", function()
			local big = {}
			for index = 1, 50 do
				big[index] = index
			end
			local list = select(2, S:Validate(S:List(S:Integer()), big, { max_items = 10 }))
			expect.contains(problems(list)[1], "contains more than 10 values")
			expect.raises(function()
				S:Validate(S:Any(), 1, { max_nesting = 2 })
			end, "unknown field 'max_nesting'")
		end)

		it("keeps at most max_problems details but counts all of them", function()
			local _, limited = S:Validate(S:List(S:String()), { 1, 2, 3, 4, 5 }, { max_problems = 2 })
			expect.equal(#limited.details.problems, 2)
			expect.equal(limited.details.count, 5)
			expect.contains(limited.message, "(5 problem(s))")
		end)
	end)

	describe("custom validators", function()
		it("uses the result and reason returned by the function", function()
			local even = S:Custom("my-package:even", function(value)
				if value % 2 == 0 then
					return true
				end
				return false, "must be even"
			end)
			expect.equal(valid(S:Integer(), 2), 2)
			expect.equal(valid(even, 4), 4)
			expect.same(invalid(even, 3), { "$: must be even" })
		end)

		it("reports a failing function generically and logs it for the owning package", function()
			local broken = S:Custom("my-package:broken", function()
				error("secret internal detail")
			end)
			local list = invalid(broken, 1)
			expect.same(list, { "$: check 'my-package:broken' failed" })
			expect.falsy(list[1]:find("secret", 1, true))
			expect.contains(logged[1].line, "validator callback of my-package failed validator=my-package:broken")
		end)

		it("requires a namespaced key", function()
			expect.raises(function()
				S:Custom("even", function() end)
			end, "'key' is invalid: the namespace is missing")
		end)
	end)

	describe("building schemas", function()
		it("rejects invalid options at the caller's line", function()
			local expected_line
			local ok, message = pcall(function()
				expected_line = debug.getinfo(1, "l").currentline + 1
				S:Integer({ min = 5, max = 1 })
			end)
			expect.falsy(ok)
			expect.contains(message, "min must be at least 0 and not greater than max")
			expect.equal(tonumber(message:match("schema_spec%.lua:(%d+):")), expected_line)
		end)

		it("rejects unknown options, wrong option types and non-schemas", function()
			expect.raises(function()
				S:String({ length = 3 })
			end, "unknown field 'length'")
			expect.raises(function()
				S:String({ max = "3" })
			end, "'options.max' must be integer? (got string)")
			expect.raises(function()
				S:Number({ min = 0 / 0 })
			end, "must be a finite number")
			expect.raises(function()
				S:List({ kind = "string" })
			end, "'schema' must be schema (got table)")
			expect.raises(function()
				S:Enum({})
			end, "'values' is invalid: must not be empty")
			expect.raises(function()
				S:Record({ name = S:String() }, { extra = "keep" })
			end, "expected one of reject, allow, strip")
		end)

		it("recognizes schema nodes", function()
			expect.truthy(Schema.IsSchema(S:String()))
			expect.falsy(Schema.IsSchema({ kind = "string" }))
		end)
	end)
end)
