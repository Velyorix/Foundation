-- Shared by the lifecycle fixtures; each event is also printed so the runner can check
-- ordering after the server has stopped.
local probe = { events = {}, contexts = {} }

function probe.record(event)
	probe.events[#probe.events + 1] = event
	Console.Log("[LIFECYCLE] %s", event)
end

function probe.reset()
	probe.events = {}
end

function probe.text()
	return table.concat(probe.events, ",")
end

Package.Export("LifecycleProbe", probe)
