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
