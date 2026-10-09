local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local balances = {}

context:ProvideService("economy:bank", "1.2", {
	name = "fixture",
	Deposit = function(self, player, amount)
		balances[player] = (balances[player] or 0) + amount
		self.deposits = (self.deposits or 0) + 1
		return balances[player]
	end,
}, { priority = 10 })
