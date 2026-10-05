local SELF = "foundation-core-runtime-test"

local events = {}
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
context:OnReady(function()
	events[#events + 1] = "ready"
end)

local suite = FoundationTest.Suite("core-runtime")

suite:Test("Foundation is exported with the package version", function()
	local installed
	for _, entry in ipairs(Server.GetPackages(true)) do
		if entry.name == "foundation" then
			installed = entry.version
		end
	end
	FoundationTest.Equal(Foundation.VERSION, installed)
	FoundationTest.Equal(type(Foundation.API_VERSION), "string")
end)

suite:Test("Foundation is read-only", function()
	FoundationTest.Raises(function()
		-- selene: allow(unscoped_variables)
		Foundation.Register = nil
	end, "Foundation is read-only")
	FoundationTest.Equal(getmetatable(Foundation), false)
end)

suite:Test("the package registered in Index.lua is ready before Start", function()
	FoundationTest.Equal(context:GetId(), SELF)
	FoundationTest.Equal(context:GetState(), "ready")
	FoundationTest.Equal(table.concat(events, ","), "ready")
end)

suite:Test("registration errors point at the calling package", function()
	local err = FoundationTest.Raises(function()
		Foundation.Register(Package, { api = Foundation.API_VERSION, typo = true })
	end, "unknown field 'typo'")
	FoundationTest.True(
		tostring(err):find(SELF .. "/Server/Index.lua", 1, true) ~= nil,
		"error does not point at the package: " .. tostring(err)
	)
end)

suite:Test("Foundation.Keys parses keys and reports invalid ones", function()
	local key, namespace, path = Foundation.Keys.Parse("Spawn", SELF)
	FoundationTest.Equal(key, SELF .. ":spawn")
	FoundationTest.Equal(namespace, SELF)
	FoundationTest.Equal(path, "spawn")
	local missing, err = Foundation.Keys.Parse("no namespace")
	FoundationTest.Equal(missing, nil)
	FoundationTest.Equal(err.code, "invalid_key")
	FoundationTest.True(Foundation.Keys.IsReserved("foundation"))
	FoundationTest.Equal(select(2, Foundation.Keys.Split("a:b/c")), "b/c")
end)

suite:Test("Foundation.Keys is read-only and reports misuse at the caller", function()
	FoundationTest.Raises(function()
		-- selene: allow(unscoped_variables)
		Foundation.Keys.Parse = nil
	end, "Foundation.Keys is read-only")
	local err = FoundationTest.Raises(function()
		Foundation.Keys.Parse("key", 5)
	end, "'default_namespace' must be string? (got number)")
	FoundationTest.True(tostring(err):find(SELF .. "/Server/Index.lua", 1, true) ~= nil, tostring(err))
end)

suite:Test("Foundation.Schema validates values and applies defaults", function()
	local S = Foundation.Schema
	local settings = S.Record({
		language = S.Optional(S.Enum({ "en", "fr" }), "en"),
		max_homes = S.Integer({ min = 0, max = 50 }),
	})
	local result = S.Validate(settings, { max_homes = 3 })
	FoundationTest.Equal(result.language, "en")
	FoundationTest.Equal(result.max_homes, 3)
	local missing, err = S.Validate(settings, { max_homes = 99, extra = true })
	FoundationTest.Equal(missing, nil)
	FoundationTest.Equal(err.code, "validation_failed")
	FoundationTest.Equal(err.details.problems[1].message, "$.max_homes: must be at most 50")
	FoundationTest.Equal(err.details.problems[2].message, "$.extra: is not an allowed field")
end)

suite:Test("Foundation.Schema reports bad schemas at the caller", function()
	local err = FoundationTest.Raises(function()
		Foundation.Schema.Integer({ min = 2, max = 1 })
	end, "min must be at least 0 and not greater than max")
	FoundationTest.True(tostring(err):find(SELF .. "/Server/Index.lua", 1, true) ~= nil, tostring(err))
end)

suite:Test("a failing custom validator is reported for its package", function()
	local broken = Foundation.Schema.Custom(SELF .. ":broken", function()
		error("custom validator exploded")
	end)
	local _, err = Foundation.Schema.Validate(broken, 1)
	FoundationTest.Equal(err.details.problems[1].message, "$: check '" .. SELF .. ":broken' failed")
end)

suite:Run()
