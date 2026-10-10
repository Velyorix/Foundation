Foundation.Register(Package, {
	api = "0.1",
	name = "Coins",
	capabilities = { "economy:offline-payments" },
}):ProvideService("economy:bank", "1.0", {
	balances = {},
	Balance = function(self, account)
		return self.balances[account] or 0
	end,
	Deposit = function(self, account, amount)
		self.balances[account] = self:Balance(account) + amount
		return self.balances[account]
	end,
})
