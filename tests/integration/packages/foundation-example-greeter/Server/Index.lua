local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Greeter",
})

local function on_ping(player_name)
	Console.Log("pong for %s", player_name)
end

Events.Subscribe("greeter:ping", on_ping)
context:Track("event_listener", function()
	Events.Unsubscribe("greeter:ping", on_ping)
end)

context:OnReady(function()
	Console.Log("Greeter is ready")
end)

context:OnDisable(function()
	Console.Log("Greeter is shutting down")
end)
