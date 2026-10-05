describe("Sensitive", function()
	local Sensitive = Loader.new():require("foundation/core/sensitive.lua")

	it("recognizes sensitive names case-insensitively", function()
		for _, name in ipairs({
			"password",
			"DB_Password",
			"authToken",
			"api_key",
			"connection_string",
			"Authorization",
		}) do
			expect.truthy(Sensitive.IsSensitiveName(name), name)
		end
		for _, name in ipairs({ "user", "path", "count", "owner" }) do
			expect.falsy(Sensitive.IsSensitiveName(name), name)
		end
	end)

	it("masks sensitive fields recursively without modifying the input", function()
		local input = { user = "ana", password = "p", nested = { token = "t", list = { { secret = "s", ok = 1 } } } }
		local masked = Sensitive.MaskFields(input)
		expect.same(masked, {
			user = "ana",
			password = "***",
			nested = { token = "***", list = { { secret = "***", ok = 1 } } },
		})
		expect.equal(input.password, "p")
	end)

	it("handles cycles and non-table values", function()
		local cyclic = { name = "x" }
		cyclic.self = cyclic
		local masked = Sensitive.MaskFields(cyclic)
		expect.equal(masked.self, masked)
		expect.equal(Sensitive.MaskFields("plain"), "plain")
		expect.is_nil(Sensitive.MaskFields(nil))
	end)
end)
