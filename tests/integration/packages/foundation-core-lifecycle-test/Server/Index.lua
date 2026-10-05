local ALPHA = "foundation-lifecycle-alpha"
local BETA = "foundation-lifecycle-beta"
local probe = LifecycleProbe

local suite = FoundationTest.Suite("core-lifecycle")
local first_alpha

suite:Test("alpha and beta are ready after startup", function()
	FoundationTest.Equal(probe.contexts.alpha:GetState(), "ready")
	FoundationTest.Equal(probe.contexts.beta:GetState(), "ready")
	first_alpha = probe.contexts.alpha
end)

suite:Do(function()
	probe.reset()
	Server.ReloadPackage(BETA)
end)
suite:Wait(500)

suite:Test("reloading a dependent leaves its dependency untouched", function()
	FoundationTest.Equal(probe.text(), "beta:disabled,beta:released,beta:registered,beta:ready")
	FoundationTest.Equal(probe.contexts.alpha, first_alpha)
	FoundationTest.Equal(first_alpha:GetState(), "ready")
	FoundationTest.Equal(probe.contexts.beta:GetState(), "ready")
end)

suite:Do(function()
	probe.reset()
	Server.ReloadPackage(ALPHA)
end)
suite:Wait(500)

suite:Test("reloading a dependency disables its dependents first", function()
	FoundationTest.Equal(
		probe.text(),
		"beta:disabled,beta:released,alpha:disabled,alpha:released,alpha:registered,alpha:ready"
	)
	FoundationTest.Equal(probe.contexts.beta:GetState(), "disabled")
	FoundationTest.Equal(probe.contexts.alpha:GetState(), "ready")
	FoundationTest.Equal(first_alpha:GetState(), "disabled")
end)

suite:Do(function()
	probe.reset()
	Server.ReloadPackage(BETA)
end)
suite:Wait(500)

suite:Test("the dependent recovers once reloaded", function()
	FoundationTest.Equal(probe.text(), "beta:registered,beta:ready")
	FoundationTest.Equal(probe.contexts.beta:GetState(), "ready")
end)

suite:Run()
