local PATH = "foundation/config.toml"

local function write(text)
	local file = File(PATH, true)
	file:Write(text)
	file:Close()
end

local suite = FoundationTest.Suite("core-config")

suite:Test("the generated file is valid TOML holding the defaults", function()
	FoundationTest.True(File.Exists(PATH), "config file not created")
	local file = File(PATH)
	local data = TOML.Parse(file:Read(0))
	file:Close()
	FoundationTest.Equal(data.config_version, 1)
	FoundationTest.Equal(data.language, "en")
	FoundationTest.Equal(data.log.level, "info")
	FoundationTest.Equal(#data.log.debug_categories, 0)
end)

suite:Do(function()
	write('config_version = 1\nlanguage = "fr"\n\n[log]\nlevel = "debug"\n')
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Do(function()
	write('language = 5\n\n[log]\nlevel = "loud"\nextra = 1\n')
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Do(function()
	write("language = = broken\n")
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Test("Foundation kept running through every reload", function()
	FoundationTest.Equal(type(Foundation.Register), "function")
end)

suite:Run()
