local TOGGLE = "foundation/migration-fixture.txt"
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

local failures = {}
context:Listen("foundation:package_failed", function(event)
	failures[#failures + 1] = event:Get("message")
end)

local function use_version(version)
	local file = File(TOGGLE, true)
	file:Write(tostring(version))
	file:Close()
	Server.ReloadPackage("foundation-migration-fixture")
end

local suite = FoundationTest.Suite("core-migrations")

suite:Test("version 1 data is written", function()
	FoundationTest.Equal(MigrationFixture.version, 1)
end)

suite:Do(function()
	use_version(2)
end)
suite:Wait(800)

suite:Test("version 2 migrates the existing data", function()
	FoundationTest.Equal(MigrationFixture.version, 2)
	FoundationTest.Equal(MigrationFixture.alex and MigrationFixture.alex.coins, 10)
end)

suite:Do(function()
	use_version(3)
end)
suite:Wait(800)

suite:Test("a failing migration fails the package and changes nothing", function()
	FoundationTest.Equal(#failures, 1)
	FoundationTest.True(failures[1]:find("could not be migrated from version 2", 1, true), failures[1])
end)

suite:Do(function()
	use_version(2)
end)
suite:Wait(800)

suite:Test("the data is still at version 2 afterwards", function()
	FoundationTest.Equal(MigrationFixture.alex and MigrationFixture.alex.coins, 10)
	FoundationTest.Equal(#failures, 1)
end)

suite:Run()
