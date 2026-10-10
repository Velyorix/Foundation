local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Salary",
	services = { { name = "economy:bank", version = "1" } },
})

local bank

context:OnService("economy:bank", "1", function(service, info)
	bank = service
	if service then
		Console.Log("salaries are paid through %s", info.provider)
	else
		Console.Log("no bank available, salaries are paused")
	end
end)

context:OnReady(function()
	Console.Log("paid 100 to alex, balance %d", bank:Deposit("alex", 100))
	if Foundation.Capabilities.Has("economy:offline-payments") then
		Console.Log("offline players are paid too")
	end
end)
