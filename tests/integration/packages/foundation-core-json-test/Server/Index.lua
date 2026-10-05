local Json = Package.Require("foundation/Shared/foundation/core/json.lua")

local suite = FoundationTest.Suite("core-json")

local sample = {
	name = 'élève "quoted"',
	count = 42,
	ratio = 0.25,
	flags = { true, false },
	nested = { list = { 1, 2, 3 }, text = "line\nbreak" },
}

suite:Test("decodes what the engine JSON encoder writes", function()
	local ok, value = Json.Decode(JSON.stringify(sample))
	FoundationTest.True(ok, tostring(value))
	FoundationTest.Equal(value.name, sample.name)
	FoundationTest.Equal(value.count, 42)
	FoundationTest.Equal(math.type(value.count), "integer")
	FoundationTest.Equal(value.ratio, 0.25)
	FoundationTest.Equal(value.flags[2], false)
	FoundationTest.Equal(value.nested.list[3], 3)
	FoundationTest.Equal(value.nested.text, "line\nbreak")
end)

suite:Test("the engine JSON parser reads what Foundation encodes", function()
	local text = assert(Json.Encode(sample))
	local value = JSON.parse(text)
	FoundationTest.Equal(value.name, sample.name)
	FoundationTest.Equal(value.count, 42)
	FoundationTest.Equal(value.nested.text, "line\nbreak")
	FoundationTest.Equal(#value.nested.list, 3)
end)

suite:Run()
