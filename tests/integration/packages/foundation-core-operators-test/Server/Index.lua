local PATH = "foundation/operators.json"
local VALID =
	'{"operators":{"76561198000000001":{"added_at":1760100000,"added_by":"console","name":"Sam O\'Neil"}},"version":1}\n'
local DAMAGED = '{"operators":{"76561198000000001":{"added_by":"console"}},"version":1}\n'

local function write(text)
	local file = File(PATH, true)
	file:Write(text)
	file:Close()
end

local function read()
	local file = File(PATH)
	local text = file:Read()
	file:Close()
	return text
end

local suite = FoundationTest.Suite("core-operators")

suite:Test("nobody is an operator without a file", function()
	FoundationTest.Equal(File.Exists(PATH), false)
	FoundationTest.Equal(Foundation.Operators.IsOperator("76561198000000001"), false)
end)

suite:Do(function()
	write(VALID)
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Test("operators are read from the file, names with quotes included", function()
	FoundationTest.Equal(Foundation.Operators.IsOperator("76561198000000001"), true)
	FoundationTest.Equal(Foundation.Operators.List()[1].name, "Sam O'Neil")
end)

suite:Do(function()
	write(DAMAGED)
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

suite:Test("a damaged file gives no operator and is left untouched", function()
	FoundationTest.Equal(Foundation.Operators.IsOperator("76561198000000001"), false)
	FoundationTest.Equal(read(), DAMAGED)
end)

suite:Do(function()
	Console.RunCommand("foundation op add 76561198000000002 Sam")
end)
suite:Wait(100)

suite:Do(function()
	write(VALID)
	Server.ReloadPackage("foundation")
end)
suite:Wait(500)

local commands = {
	"foundation op add 76561198000000002 Alex Doe",
	"foundation permissions check 76561198000000002 foundation.command.packages",
	"foundation op list",
}
for _, line in ipairs(commands) do
	suite:Do(function()
		Console.RunCommand(line)
	end)
	suite:Wait(100)
end

suite:Test("foundation op add writes the real file and grants operator permissions", function()
	FoundationTest.Equal(Foundation.Operators.IsOperator("76561198000000002"), true)
	FoundationTest.True(read():find('"76561198000000002":{"added_at":', 1, true), read())
	FoundationTest.Equal(Foundation.Permissions.Has("76561198000000002", "foundation.command.packages"), true)
end)

suite:Do(function()
	Console.RunCommand("foundation op remove 76561198000000002")
end)
suite:Wait(100)

suite:Test("foundation op remove takes the operator out of the file", function()
	FoundationTest.Equal(Foundation.Operators.IsOperator("76561198000000002"), false)
	FoundationTest.Equal(read():find("76561198000000002", 1, true), nil)
end)

suite:Run()
