local probe = LifecycleProbe
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
probe.contexts.alpha = context
probe.record("alpha:registered")

context:Track("probe_resource", function()
	probe.record("alpha:released")
end)
context:OnReady(function()
	probe.record("alpha:ready")
end)
context:OnDisable(function()
	probe.record("alpha:disabled")
end)
