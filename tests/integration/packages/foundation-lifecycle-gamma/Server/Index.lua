local probe = LifecycleProbe
local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
probe.contexts.gamma = context
probe.record("gamma:registered")

context:Track("probe_resource", function()
	probe.record("gamma:released")
end)
context:OnReady(function()
	probe.record("gamma:ready")
end)
context:OnDisable(function()
	probe.record("gamma:disabled")
end)
