local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local own = {}

context:RegisterCommand({
	name = "give",
	run = function(_, args)
		own[#own + 1] = args.target or "none"
	end,
	arguments = { { name = "target", optional = true } },
})

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

suite:Run()
