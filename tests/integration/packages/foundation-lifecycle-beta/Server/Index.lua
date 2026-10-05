local probe = LifecycleProbe
local context = Foundation.Register(Package, {
	api = Foundation.API_VERSION,
	depends = { "foundation-lifecycle-alpha" },
})
probe.contexts.beta = context
probe.record("beta:registered")

context:Track("probe_resource", function()
	probe.record("beta:released")
end)
context:OnReady(function()
	probe.record("beta:ready")
end)
context:OnDisable(function()
	probe.record("beta:disabled")
end)
