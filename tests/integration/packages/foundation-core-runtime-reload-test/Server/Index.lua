local first_instance = Foundation
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

local suite = FoundationTest.Suite("core-runtime-reload")

suite:Do(function()
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Test("reloading Foundation alone disables its packages and exports a new instance", function()
	FoundationTest.Equal(context:GetState(), "disabled")
	FoundationTest.True(Foundation ~= first_instance, "global still points at the old instance")
	FoundationTest.Raises(function()
		first_instance.Register(Package, { api = first_instance.API_VERSION })
	end, "Foundation is not running (state: stopped)")
end)

suite:Run()
