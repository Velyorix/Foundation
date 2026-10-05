local FIXTURE = "foundation-config-fixture"
local PATH = "foundation/config/" .. FIXTURE .. ".toml"

local function write(text)
	local file = File(PATH, true)
	file:Write(text)
	file:Close()
end

local suite = FoundationTest.Suite("core-package-config")

suite:Test("the package file is created with valid TOML and the defaults", function()
	FoundationTest.True(File.Exists(PATH), "package config file not created")
	local file = File(PATH)
	local data = TOML.Parse(file:Read(0))
	file:Close()
	FoundationTest.Equal(data.motd, "Welcome")
	FoundationTest.Equal(data.homes.max, 3)
	FoundationTest.Equal(ConfigFixture.settings:Get("homes.max"), 3)
end)

suite:Do(function()
	write('config_version = 1\nmotd = "Hello from the file"\n\n[homes]\nmax = 9\n')
	Server.ReloadPackage(FIXTURE)
end)
suite:Wait(500)

suite:Test("a reloaded package reads the administrator's values", function()
	FoundationTest.Equal(ConfigFixture.settings:Get("motd"), "Hello from the file")
	FoundationTest.Equal(ConfigFixture.settings:Get("homes.max"), 9)
end)

suite:Do(function()
	write('motd = "' .. string.rep("x", 40) .. '"\n')
	Server.ReloadPackage(FIXTURE)
end)
suite:Wait(500)

suite:Test("an invalid file leaves the package on its defaults", function()
	FoundationTest.Equal(ConfigFixture.settings:Get("motd"), "Welcome")
end)

suite:Run()
