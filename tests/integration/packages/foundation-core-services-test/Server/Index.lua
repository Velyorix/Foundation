local context = Foundation.Register(Package, { api = Foundation.API_VERSION })

context:ProvideService("economy:bank", "1.0", {
	name = "fallback",
	Deposit = function()
		return 0
	end,
})

local suite = FoundationTest.Suite("core-services")
local held

suite:Test("the best provider of another package is returned and callable", function()
	local bank, info = context:GetService("economy:bank", "1.1")
	FoundationTest.Equal(info.provider, "foundation-services-fixture")
	FoundationTest.Equal(bank:Deposit("alex", 5), 5)
	FoundationTest.Equal(bank:Deposit("alex", 2), 7)
	FoundationTest.Equal(bank.deposits, 2)
	FoundationTest.Equal(#context:GetServices("economy:bank"), 2)
	held = bank
end)

suite:Do(function()
	Server.UnloadPackage("foundation-services-fixture")
end)
suite:Wait(300)

suite:Test("after the provider unloads, old references fail and lookups fall back", function()
	FoundationTest.Raises(function()
		held:Deposit("alex", 1)
	end, "is no longer available")
	FoundationTest.Equal(context:GetService("economy:bank", "1.1"), nil)
	FoundationTest.Equal(context:GetService("economy:bank").name, "fallback")
end)

suite:Run()
