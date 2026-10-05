local function new_errors(locale)
	local loader = Loader.new()
	local Messages = loader:require("foundation/core/messages.lua")
	local Errors = loader:require("foundation/core/errors.lua")
	local catalogs = {
		en = loader:require("foundation/locales/en/core.lua"),
		fr = loader:require("foundation/locales/fr/core.lua"),
	}
	return Errors.new(Messages.new(catalogs, locale or "en")), Errors
end

describe("Errors", function()
	it("builds structured values with code, category, message and params", function()
		local errors = new_errors()
		local err = errors:New("invalid_state", { api = "X.Y", reason = "not ready" })
		expect.equal(err.code, "invalid_state")
		expect.equal(err.category, "developer")
		expect.equal(err.message, "X.Y: not ready")
		expect.same(err.params, { api = "X.Y", reason = "not ready" })
		expect.equal(tostring(err), "[foundation:invalid_state] X.Y: not ready")
	end)

	it("copies params so later changes by the caller do not alter the error", function()
		local errors = new_errors()
		local params = { api = "A", reason = "r" }
		local err = errors:New("invalid_state", params)
		params.reason = "changed"
		expect.equal(err.params.reason, "r")
	end)

	it("keeps cause, owner and details", function()
		local errors = new_errors()
		local cause = errors:New("invalid_state", { api = "inner", reason = "x" })
		local err = errors:New("invalid_state", { api = "outer", reason = "y" }, {
			cause = cause,
			owner = "my-package",
			details = { attempt = 2 },
		})
		expect.equal(err.cause, cause)
		expect.equal(err.owner, "my-package")
		expect.same(err.details, { attempt = 2 })
	end)

	it("renders messages in the active locale", function()
		local errors = new_errors("fr")
		local err = errors:New("invalid_state", { api = "X", reason = "r" })
		expect.equal(err.message, "X : r")
	end)

	it("recognizes its values with Is", function()
		local errors, Errors = new_errors()
		expect.truthy(Errors.Is(errors:New("invalid_state", {})))
		expect.falsy(Errors.Is({ code = "invalid_state" }))
		expect.falsy(Errors.Is("[foundation:invalid_state] x"))
	end)

	it("assigns every code a known category and a message in each core catalog", function()
		local _, Errors = new_errors()
		local loader = Loader.new()
		local en = loader:require("foundation/locales/en/core.lua")
		local fr = loader:require("foundation/locales/fr/core.lua")
		for code, category in pairs(Errors.CODES) do
			expect.truthy(Errors.CATEGORIES[category], "unknown category for " .. code)
			expect.truthy(en["error." .. code], "missing English message for " .. code)
			expect.truthy(fr["error." .. code], "missing French message for " .. code)
		end
	end)

	it("rejects unknown codes", function()
		local errors = new_errors()
		expect.raises(function()
			errors:New("no_such_code")
		end, "unknown error code 'no_such_code'")
	end)

	describe("Raise", function()
		it("raises the formatted string at the caller of the raising function by default", function()
			local errors = new_errors()
			local function public_api()
				errors:Raise("invalid_state", { api = "Public.Api", reason = "closed" })
			end
			local ok, message = pcall(function()
				public_api() -- line reported in the error
			end)
			expect.falsy(ok)
			expect.contains(message, "errors_spec.lua:")
			expect.contains(message, "[foundation:invalid_state] Public.Api: closed")
			local line = tonumber(message:match("errors_spec%.lua:(%d+):"))
			local source_line = debug.getinfo(1, "l").currentline - 6
			expect.equal(line, source_line)
		end)
	end)
end)
