local context = Foundation.Register(Package, {
	api = Foundation.API_VERSION,
	capabilities = { { name = "economy:interest", version = "1.0" } },
})
local balances = {}

context:ProvideService("economy:bank", "1.2", {
	name = "fixture",
	Deposit = function(self, player, amount)
		balances[player] = (balances[player] or 0) + amount
		self.deposits = (self.deposits or 0) + 1
		return balances[player]
	end,
}, { priority = 10 })
