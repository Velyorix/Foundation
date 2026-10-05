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
		Foundation.Register = nil
	end, "the Foundation table is read-only")
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

suite:Run()
