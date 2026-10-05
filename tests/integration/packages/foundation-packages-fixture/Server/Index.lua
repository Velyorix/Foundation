local probe = PackagesProbe
local context = probe.registry:Register(Package, { api = "0.1" })
probe.contexts[#probe.contexts + 1] = context
probe.events[#probe.events + 1] = "registered"

context:Track("probe_resource", function()
	probe.events[#probe.events + 1] = "released"
end)
context:OnReady(function()
	probe.events[#probe.events + 1] = "ready"
end)
context:OnDisable(function()
	probe.events[#probe.events + 1] = "disabled"
end)
