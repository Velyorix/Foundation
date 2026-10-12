local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

local seen = {}
local changes = {}
context:OnRegistry("foundation-registries-fixture:weapons", function(weapons)
	seen[#seen + 1] = weapons and weapons:GetName() or "none"
	if weapons then
		weapons:Register("laser", { damage = 50, slot = "heavy" })
		weapons:OnChange(function(action, key)
			if key == "foundation-registries-fixture:rifle" then
				changes[#changes + 1] = action
			end
		end)
	end
end)

local suite = FoundationTest.Suite("core-registries")
local held

suite:Test("a registry defined by a package loaded later is announced to watchers", function()
	FoundationTest.True(Server.IsPackageLoaded("foundation-registries-fixture"), "load foundation-registries-fixture")
	FoundationTest.Equal(table.concat(seen, ","), "foundation-registries-fixture:weapons")
end)

suite:Test("entries of both packages are read with the schema defaults applied", function()
	held = context:Registry("foundation-registries-fixture:weapons")
	FoundationTest.Equal(held:Count(), 3)
	FoundationTest.Equal(held:Get("foundation-registries-fixture:rifle").slot, "primary")
	FoundationTest.Equal(held:Get("foundation-core-registries-test:laser").damage, 50)
	FoundationTest.Equal(
		table.concat(held:Keys(), ","),
		"foundation-core-registries-test:laser,foundation-registries-fixture:musket,foundation-registries-fixture:rifle"
	)
end)

suite:Test("old names and deprecated entries still resolve", function()
	FoundationTest.Equal(held:Get("foundation-registries-fixture:gun").damage, 30)
	FoundationTest.Equal(held:Resolve("foundation-registries-fixture:gun"), "foundation-registries-fixture:rifle")
	FoundationTest.Equal(held:Get("foundation-registries-fixture:musket").damage, 12)
end)

suite:Test("a taken key and invalid values are refused", function()
	FoundationTest.Raises(function()
		held:Register("laser", { damage = 1 })
	end, "is already registered")
	FoundationTest.Raises(function()
		held:Register("blade", { damage = 0 })
	end, "must be at least 1")
end)

suite:Do(function()
	Server.UnloadPackage("foundation-registries-fixture")
end)
suite:Wait(300)

suite:Test("the registry goes away with its package", function()
	FoundationTest.Equal(table.concat(seen, ","), "foundation-registries-fixture:weapons,none")
	FoundationTest.Equal(context:Registry("foundation-registries-fixture:weapons"), nil)
	FoundationTest.Raises(function()
		held:Get("foundation-core-registries-test:laser")
	end, "was removed because the package that defined it stopped")
end)

suite:Do(function()
	Server.LoadPackage("foundation-registries-fixture")
end)
suite:Wait(300)

suite:Test("contributions come back when the package defines it again", function()
	FoundationTest.Equal(#seen, 3)
	local weapons = context:Registry("foundation-registries-fixture:weapons")
	FoundationTest.Equal(weapons:Count(), 3)
	FoundationTest.Equal(weapons:Get("foundation-core-registries-test:laser").slot, "heavy")
	FoundationTest.Equal(table.concat(changes, ","), "added,removed,added")
end)

suite:Run()
