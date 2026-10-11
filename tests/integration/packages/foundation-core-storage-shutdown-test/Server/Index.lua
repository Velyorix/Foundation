-- What this package writes, including from its disable hook while the server stops, is checked
-- in the database after the server exited (post_checks in suites.json).
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local store = context:Store()

context:OnDisable(function()
	store:Set("from-disable-hook", true)
	for index = 1, 100 do
		store:Set("hook" .. index, index)
	end
end)

local suite = FoundationTest.Suite("core-storage-shutdown")
suite:Test("writes are queued right before the server stops", function()
	for index = 1, 300 do
		store:Set("k" .. index, index)
	end
end)
suite:Run()
