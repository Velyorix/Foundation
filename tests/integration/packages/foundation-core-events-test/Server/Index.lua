local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

local EVENT = "foundation-events-fixture:purchase"
local calls = {}

local discount = context:Listen(EVENT, function(event)
	calls[#calls + 1] = "discount"
	event:Set("price", event:Get("price") - 2)
end, { priority = "low" })

context:Listen(EVENT, function()
	calls[#calls + 1] = "broken"
	error("listener failure")
end)

context:Listen(EVENT, function(event)
	calls[#calls + 1] = "guard"
	if event:Get("item") == "forbidden" then
		event:Cancel()
	end
end, { priority = "high" })

context:Listen(EVENT, function()
	calls[#calls + 1] = "monitor"
end, { priority = "monitor", ignore_cancelled = true })

local suite = FoundationTest.Suite("core-events")

suite:Test("listeners of another package run in priority order and change the event", function()
	calls = {}
	local price, cancelled = EventsFixture.Purchase("apple", 10)
	FoundationTest.Equal(price, 8)
	FoundationTest.Equal(cancelled, false)
	FoundationTest.Equal(table.concat(calls, ","), "discount,broken,guard,monitor")
end)

suite:Test("a cancelled event skips listeners that ignore cancellation", function()
	calls = {}
	local _, cancelled = EventsFixture.Purchase("forbidden", 10)
	FoundationTest.Equal(cancelled, true)
	FoundationTest.Equal(table.concat(calls, ","), "discount,broken,guard")
end)

suite:Test("a released listener no longer runs", function()
	FoundationTest.True(discount:Release())
	local price = EventsFixture.Purchase("apple", 10)
	FoundationTest.Equal(price, 10)
end)

local remaining
suite:Do(function()
	remaining = context:Listen(EVENT, function() end, { priority = "lowest" })
	Server.UnloadPackage("foundation-events-fixture")
end)
suite:Wait(300)

suite:Test("unloading the defining package removes the event and its listeners", function()
	FoundationTest.Equal(remaining:IsActive(), false)
	FoundationTest.Raises(function()
		context:Listen(EVENT, function() end)
	end, "is not a defined event")
end)

suite:Run()
