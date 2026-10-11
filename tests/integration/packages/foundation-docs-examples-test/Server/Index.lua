-- Runs the packages shown in the public documentation; scripts/check.py keeps the
-- documented code and files identical to these.
local suite = FoundationTest.Suite("docs-examples")

local function read(path)
	FoundationTest.True(File.Exists(path), path .. " does not exist")
	local file = File(path)
	local text = file:Read()
	file:Close()
	return (text:gsub("\r\n", "\n"))
end

local function expected(name)
	return read("Packages/foundation-docs-examples-test/expected/" .. name)
end

suite:Test("the greeter example registers and reacts to its event", function()
	FoundationTest.True(Server.IsPackageLoaded("foundation-example-greeter"))
	Events.Call("greeter:ping", "docs")
end)

suite:Test("the documented configuration files are the generated ones", function()
	FoundationTest.Equal(read("foundation/config.toml"), expected("config.toml"))
	FoundationTest.Equal(
		read("foundation/config/foundation-example-rewards.toml"),
		expected("foundation-example-rewards.toml")
	)
end)

suite:Do(function()
	for _ = 1, 3 do
		Events.Call("autosave:changed")
	end
end)

for _, line in ipairs({
	"buy apple 3",
	"buy sword",
	"buy pear",
	"foundation help buy",
	"foundation packages",
	"foundation services",
	"arena start",
	"arena referee 76561198000000009",
	"foundation permissions check 76561198000000009 foundation-example-arena.manage",
	"foundation permissions check 76561198000000010 foundation-example-arena.manage",
	"foundation permissions check 76561198000000011 foundation-example-arena.manage",
	"warp set spawn 0 0 100",
	"warp set arena 1200.5 -40 100",
	"warp list",
	"warp show arena",
	"warp delete spawn",
	"warp show spawn",
	"profile set 76561198000000021 Alex green",
	"profile show 76561198000000021",
	"profile show 76561198000000022",
	"nametag 76561198000000021",
	"nametag 76561198000000022",
}) do
	suite:Do(function()
		Console.RunCommand(line)
	end)
	suite:Wait(100)
end

-- Leaves time for the debounced save and the three announcements (one per second).
suite:Wait(3100)

suite:Run()
