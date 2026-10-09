local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Shop",
})

local S = Foundation.Schema
local prices = { apple = 10, sword = 150 }

context:DefineEvent("purchase", {
	fields = {
		buyer = S.String(),
		item = S.String(),
		price = S.Integer({ min = 0 }),
	},
	mutable = { "price" },
	cancellable = true,
})

context:RegisterCommand({
	name = "buy",
	description = "Buy an item",
	arguments = {
		{ name = "item", type = "enum", values = { "apple", "sword" } },
		{ name = "amount", type = "integer", min = 1, max = 10, default = 1 },
	},
	cooldown = 2000,
	run = function(sender, args)
		local event = context:Emit("purchase", {
			buyer = sender:GetName(),
			item = args.item,
			price = prices[args.item] * args.amount,
		})
		if event:IsCancelled() then
			sender:Reply("purchase refused")
			return
		end
		sender:Reply(
			string.format("%s bought %d %s for %d", sender:GetName(), args.amount, args.item, event:Get("price"))
		)
	end,
})
