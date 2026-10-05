-- The shutdown order itself is checked by the runner (expected_log_sequence).
local probe = LifecycleProbe

local suite = FoundationTest.Suite("core-shutdown")

suite:Test("alpha, beta and gamma are ready before the server stops", function()
	for _, name in ipairs({ "alpha", "beta", "gamma" }) do
		FoundationTest.Equal(probe.contexts[name]:GetState(), "ready", name)
	end
end)

suite:Run()
