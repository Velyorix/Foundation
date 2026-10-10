local context = Foundation.Register(Package, {
	api = Foundation.API_VERSION,
	services = { { name = "economy:bank", version = "1" } },
})

local failures = {}
context:Listen("foundation:package_failed", function(event)
	failures[#failures + 1] = event:Get("package") .. ": " .. event:Get("message")
end)

context:ProvideService("economy:bank", "1.0", {
	name = "fallback",
	Deposit = function()
		return 0
	end,
})

local changes = {}
context:OnService("economy:bank", "1", function(service, info)
	changes[#changes + 1] = service and (service.name .. "@" .. info.version) or "none"
end)

local announced = {}
context:Listen("foundation:service_unavailable", function(event)
	announced[#announced + 1] = event:Get("service") .. ":" .. event:Get("provider")
end)

local suite = FoundationTest.Suite("core-services")
local held

suite:Test("the packages this suite needs are loaded", function()
	for _, name in ipairs({ "foundation-services-fixture", "foundation-services-consumer" }) do
		FoundationTest.True(Server.IsPackageLoaded(name), name .. " is not loaded; install and load it with this suite")
	end
end)

suite:Test("packages requiring a provided service become ready", function()
	FoundationTest.Equal(context:GetState(), "ready")
	FoundationTest.Equal(#failures, 0)
end)

suite:Test("a ready package's capabilities can be queried", function()
	FoundationTest.True(Foundation.Capabilities.Has("economy:interest", "1"))
	FoundationTest.Equal(
		Foundation.Capabilities.Providers("economy:interest")[1].package,
		"foundation-services-fixture"
	)
end)

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
	Console.RunCommand("foundation services")
end)
suite:Wait(100)

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
	FoundationTest.Equal(Foundation.Capabilities.Has("economy:interest"), false)
end)

suite:Test("losing the only compatible provider fails the packages that require it", function()
	FoundationTest.Equal(context:GetState(), "ready")
	FoundationTest.Equal(
		table.concat(failures, ";"),
		"foundation-services-consumer: the service 'economy:bank' (version 1.1) required by "
			.. "'foundation-services-consumer' is no longer provided"
	)
end)

-- When this package loads before the fixture, the watcher first sees its own fallback provider.
suite:Test("watchers follow the best provider and Foundation announces the loss", function()
	local history = table.concat(changes, ",")
	if history:sub(1, #"fallback@1.0,") == "fallback@1.0," then
		history = history:sub(#"fallback@1.0," + 1)
	end
	FoundationTest.Equal(history, "fixture@1.2,fallback@1.0")
	FoundationTest.Equal(table.concat(announced, ","), "economy:bank:foundation-services-fixture")
end)

suite:Run()
