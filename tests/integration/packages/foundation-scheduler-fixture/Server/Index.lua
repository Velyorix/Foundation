local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local probe = { ticks = 0 }
context:Repeat(50, function()
	probe.ticks = probe.ticks + 1
end)
Package.Export("SchedulerFixture", probe)
