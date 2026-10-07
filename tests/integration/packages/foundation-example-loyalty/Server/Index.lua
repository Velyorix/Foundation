local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Loyalty",
	depends = { "foundation-example-shop" },
})

local PURCHASE = "foundation-example-shop:purchase"

context:Listen(PURCHASE, function(event)
	event:Set("price", event:Get("price") * 9 // 10)
end)

context:Listen(PURCHASE, function(event)
	if event:Get("item") == "sword" and event:Get("buyer") == "console" then
		event:Cancel()
	end
end, { priority = "high" })

context:Listen("foundation:command_completed", function(event)
	Console.Log("%s ran %s (%s)", event:Get("name"), event:Get("command"), event:Get("outcome"))
end, { priority = "monitor" })
