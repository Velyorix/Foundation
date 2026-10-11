local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local store = context:Store()

local suite = FoundationTest.Suite("core-stores")

suite:Async("values written through a store come back from the real database", 5000, function(done)
	store
		:Set("profile:alex", { coins = 10, name = "Alex O'Neil" })
		:Then(function()
			return store:Get("profile:alex")
		end)
		:Then(function(profile)
			if profile.coins == 10 and profile.name == "Alex O'Neil" then
				done()
			else
				done("unexpected " .. tostring(profile.name))
			end
		end)
		:Catch(function(err)
			done(tostring(err))
		end)
end)

suite:Wait(500)

suite:Do(function()
	Server.ReloadPackage("foundation-storage-fixture")
end)
suite:Wait(800)

suite:Test("a reloaded package finds the data it wrote before", function()
	FoundationTest.Equal(StorageFixture.previous, 1)
	FoundationTest.Equal(StorageFixture.loads, 2)
end)

suite:Async("another package reads the fixture's persistent data, kept across the reload", 3000, function(done)
	context
		:ReadData("foundation-storage-fixture:visits")
		:Get("76561198000000001")
		:Then(function(count)
			if count == 2 then
				done()
			else
				done("visits " .. tostring(count))
			end
		end)
		:Catch(function(err)
			done(tostring(err))
		end)
end)

suite:Test("the database file is in the server's foundation folder", function()
	FoundationTest.True(File.Exists("foundation/data/foundation.db"))
end)

suite:Run()
