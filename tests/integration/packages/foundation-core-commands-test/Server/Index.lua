local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local own = {}

context:RegisterCommand({
	name = "give",
	run = function(_, args)
		own[#own + 1] = args.target or "none"
	end,
	arguments = { { name = "target", optional = true } },
})

local settings = context:Config({
	fields = { { key = "motd", schema = Foundation.Schema.String(), default = "Hello", reload = "hot" } },
})
local changes = {}
settings:OnChange(function(changed, values)
	changes[#changes + 1] = table.concat(changed, ",") .. "=" .. values.motd
end)

local suite = FoundationTest.Suite("core-commands")

local function run(text)
	suite:Do(function()
		Console.RunCommand(text)
	end)
	suite:Wait(150)
end

run('give "golden apple" 3')
run("g pear")
run("give apple many")
run("foundation-core-commands-test:give alex")

suite:Test("console input reaches the command with quotes and defaults", function()
	FoundationTest.Equal(table.concat(CommandsFixture.received, ","), "console:golden apple:3,console:pear:1")
end)

suite:Test("the second package reaches its command through its namespaced label", function()
	FoundationTest.Equal(table.concat(own, ","), "alex")
end)

suite:Do(function()
	Server.UnloadPackage("foundation-commands-fixture")
end)
suite:Wait(300)
run("g pear")
run("give bob")

suite:Test("a freed label goes to the next package; a vanished alias is unknown", function()
	FoundationTest.Equal(table.concat(CommandsFixture.received, ","), "console:golden apple:3,console:pear:1")
	FoundationTest.Equal(table.concat(own, ","), "alex,bob")
end)

run("foundation version")
run("foundation packages")
run("foundation help give")
suite:Do(function()
	local file = File(settings:GetPath(), true)
	file:Write('motd = "Welcome back"\n')
	file:Close()
end)
run("foundation reload-config")

suite:Test("reload-config applies hot settings from the real file", function()
	FoundationTest.Equal(settings:Get("motd"), "Welcome back")
	FoundationTest.Equal(table.concat(changes, ";"), "motd=Welcome back")
end)

suite:Test("reload-config is recorded in the audit log", function()
	local path = "foundation/audit/audit-" .. os.date("!%Y-%m-%d", math.floor(Server.GetTime() / 1000)) .. ".log"
	FoundationTest.True(File.Exists(path), path .. " does not exist")
	local file = File(path)
	local text = file:Read()
	file:Close()
	FoundationTest.True(text:find('"action":"foundation:command/foundation/reload-config"', 1, true), text)
end)

suite:Run()
