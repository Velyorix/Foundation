describe("Json.Encode", function()
	local Json = Loader.new():require("foundation/core/json.lua")

	local function encoded(value)
		local text, reason, params = Json.Encode(value)
		expect.truthy(text, tostring(reason))
		return text, params
	end

	it("encodes scalars", function()
		expect.equal(encoded("a"), '"a"')
		expect.equal(encoded(true), "true")
		expect.equal(encoded(false), "false")
		expect.equal(encoded(nil), "null")
		expect.equal(encoded(42), "42")
		expect.equal(encoded(-7), "-7")
	end)

	it("keeps floats distinguishable from integers and round-trips them", function()
		expect.equal(encoded(1.0), "1.0")
		expect.equal(encoded(0.5), "0.5")
		expect.equal(encoded(0.1), "0.1")
		expect.equal(tonumber(encoded(1 / 3)), 1 / 3)
		expect.equal(encoded(1e20), "1e+20")
	end)

	it("escapes quotes, backslashes and control characters", function()
		expect.equal(encoded('a"b\\c\n\t\1'), '"a\\"b\\\\c\\n\\t\\u0001"')
	end)

	it("passes UTF-8 through", function()
		expect.equal(encoded("élève"), '"élève"')
	end)

	it("encodes sequences as arrays and other tables as objects with sorted keys", function()
		expect.equal(encoded({ 1, "two", false }), '[1,"two",false]')
		expect.equal(encoded({ b = 1, a = { c = "x" } }), '{"a":{"c":"x"},"b":1}')
		expect.equal(encoded({}), "{}")
	end)

	it("rejects tables mixing sequence and string keys", function()
		-- selene: allow(mixed_table)
		local text, reason, params = Json.Encode({ 1, x = 2 })
		expect.is_nil(text)
		expect.equal(reason, "reason.json_key_type")
		expect.same(params, { path = "$", type = "number" })
	end)

	it("rejects sparse arrays", function()
		local text, reason = Json.Encode({ [1] = "a", [3] = "c" })
		expect.is_nil(text)
		expect.equal(reason, "reason.json_key_type")
	end)

	it("rejects unsupported values with their path", function()
		local _, reason, params = Json.Encode({ list = { 1, function() end } })
		expect.equal(reason, "reason.json_unsupported_type")
		expect.same(params, { path = "$.list[2]", type = "function" })
	end)

	it("rejects non-finite numbers", function()
		for _, value in ipairs({ math.huge, -math.huge, 0 / 0 }) do
			local _, reason = Json.Encode({ value = value })
			expect.equal(reason, "reason.json_non_finite")
		end
	end)

	it("rejects cycles but accepts shared references", function()
		local shared = { x = 1 }
		expect.equal(encoded({ a = shared, b = shared }), '{"a":{"x":1},"b":{"x":1}}')
		local cyclic = {}
		cyclic.self = cyclic
		local _, reason, params = Json.Encode(cyclic)
		expect.equal(reason, "reason.json_cycle")
		expect.equal(params.path, "$.self")
	end)

	it("limits nesting depth", function()
		local root = {}
		local node = root
		for _ = 1, 40 do
			node.child = {}
			node = node.child
		end
		local _, reason = Json.Encode(root)
		expect.equal(reason, "reason.json_depth")
	end)
end)

describe("Json.Decode", function()
	local Json = Loader.new():require("foundation/core/json.lua")

	local function decoded(text, limits)
		local ok, value, params = Json.Decode(text, limits)
		expect.truthy(ok, tostring(value) .. " " .. tostring(params and params.position))
		return value
	end

	local function rejected(text, limits)
		local ok, reason, params = Json.Decode(text, limits)
		expect.falsy(ok, "accepted " .. tostring(text))
		return reason, params or {}
	end

	it("decodes scalars and keeps integers apart from floats", function()
		expect.equal(decoded('"a"'), "a")
		expect.equal(decoded("true"), true)
		expect.equal(decoded("false"), false)
		expect.is_nil(decoded("null"))
		expect.equal(math.type(decoded("42")), "integer")
		expect.equal(decoded("-7"), -7)
		expect.equal(math.type(decoded("1.0")), "float")
		expect.equal(decoded("1.5e2"), 150.0)
		expect.equal(math.type(decoded("1e2")), "float")
		expect.equal(decoded("9007199254740993"), 9007199254740993)
		expect.equal(math.type(decoded("99999999999999999999")), "float")
	end)

	it("decodes strings with escapes and unicode", function()
		expect.equal(decoded('"a\\"b\\\\c\\/d\\n\\t\\u00e9"'), 'a"b\\c/d\n\té')
		expect.equal(decoded('"\\ud83d\\ude00"'), "😀")
		expect.equal(decoded('"élève"'), "élève")
	end)

	it("decodes objects and arrays with whitespace", function()
		expect.same(decoded(' { "a" : [ 1 , 2 ] , "b" : { } } '), { a = { 1, 2 }, b = {} })
		expect.same(decoded("[]"), {})
	end)

	it("drops null object members", function()
		expect.same(decoded('{"a":null,"b":1}'), { b = 1 })
	end)

	it("rejects malformed input with the position", function()
		local cases = {
			"",
			"{",
			'{"a":1,}',
			"[1,]",
			"01",
			"1.",
			".5",
			"+1",
			"'a'",
			"{a:1}",
			'"unterminated',
			'"bad \\x escape"',
			'"\\u12"',
			'"\\udc00"',
			'"\\ud83d"',
			"tru",
			"1 2",
			'"tab\there"',
		}
		for _, text in ipairs(cases) do
			local reason = rejected(text)
			expect.equal(reason, "reason.json_syntax", text)
		end
		local _, params = rejected('{"a": x}')
		expect.equal(params.position, 7)
	end)

	it("rejects duplicate keys and null in arrays", function()
		local reason, params = rejected('{"a":1,"a":2}')
		expect.equal(reason, "reason.json_duplicate_key")
		expect.equal(params.key, "a")
		expect.equal(params.position, 8)
		expect.equal(rejected("[1,null]"), "reason.json_null_in_array")
	end)

	it("enforces size, depth and UTF-8", function()
		local reason, params = rejected("[1,2,3]", { max_bytes = 5 })
		expect.equal(reason, "reason.json_too_large")
		expect.equal(params.max, 5)
		expect.equal(rejected(string.rep("[", 40) .. string.rep("]", 40)), "reason.json_decode_depth")
		expect.same(decoded("[[1]]", { max_depth = 2 }), { { 1 } })
		expect.equal(rejected("[[[1]]]", { max_depth = 2 }), "reason.json_decode_depth")
		expect.equal(rejected('"\255"'), "reason.json_utf8")
		expect.equal(rejected(5), "reason.json_syntax")
	end)

	it("round-trips values produced by Encode", function()
		local seed = 12345
		local function random(n)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n
		end
		local function generate(depth)
			local choice = random(depth > 3 and 4 or 6)
			if choice == 0 then
				return random(2) == 1
			elseif choice == 1 then
				return random(100000) - 50000
			elseif choice == 2 then
				return (random(100000) - 50000) / 7
			elseif choice == 3 then
				local chars = { "a", "é", '"', "\\", "\n", "😀", " ", "/" }
				local parts = {}
				for index = 1, random(6) do
					parts[index] = chars[random(#chars) + 1]
				end
				return table.concat(parts)
			elseif choice == 4 then
				local list = {}
				for index = 1, random(4) + 1 do
					list[index] = generate(depth + 1)
				end
				return list
			end
			local map = {}
			for index = 1, random(4) do
				map["k" .. index .. random(10)] = generate(depth + 1)
			end
			return map
		end
		for _ = 1, 200 do
			local value = generate(1)
			local text = assert(Json.Encode(value))
			local ok, back = Json.Decode(text)
			expect.truthy(ok, text)
			expect.same(back, value, text)
			if type(value) == "number" then
				expect.equal(math.type(back), math.type(value), text)
			end
		end
	end)
end)
