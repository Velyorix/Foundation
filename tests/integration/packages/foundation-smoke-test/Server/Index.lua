local suite = FoundationTest.Suite("smoke")

local function find_package(name)
	for _, entry in ipairs(Server.GetPackages(true)) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

suite:Test("foundation package is loaded", function()
	FoundationTest.True(Server.IsPackageLoaded("foundation"), "foundation is not loaded")
end)

suite:Test("foundation is a script package", function()
	local entry = find_package("foundation")
	FoundationTest.True(entry ~= nil, "foundation missing from Server.GetPackages")
	FoundationTest.Equal(entry.type, PackageType.Script)
	FoundationTest.Equal(entry.title, "Foundation")
end)

suite:Run()
