-- Runs the packages shown in the public documentation; scripts/check.py keeps the
-- documented code identical to these files.
local suite = FoundationTest.Suite("docs-examples")

suite:Test("the greeter example registers and reacts to its event", function()
	FoundationTest.True(Server.IsPackageLoaded("foundation-example-greeter"))
	Events.Call("greeter:ping", "docs")
end)

suite:Run()
