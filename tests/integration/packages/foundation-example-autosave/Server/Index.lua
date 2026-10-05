local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Autosave",
})

local unsaved = 0

local save = context:Debounce(500, function()
	Console.Log("saved %d change(s)", unsaved)
	unsaved = 0
end)

local report = context:Throttle(2000, function(count)
	Console.Log("unsaved changes: %d", count)
end)

local function on_changed()
	unsaved = unsaved + 1
	report:Trigger(unsaved)
	save:Trigger()
end

Events.Subscribe("autosave:changed", on_changed)
context:Track("event_listener", function()
	Events.Unsubscribe("autosave:changed", on_changed)
end)
