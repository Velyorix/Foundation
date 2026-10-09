local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local received = {}

context:RegisterCommand({
	name = "give",
	aliases = { "g" },
	description = "Give an item",
	arguments = { { name = "item" }, { name = "amount", type = "integer", min = 1, default = 1 } },
	run = function(sender, args)
		received[#received + 1] = sender:GetKind() .. ":" .. args.item .. ":" .. args.amount
		sender:Reply("gave " .. args.amount .. " " .. args.item)
	end,
})

Package.Export("CommandsFixture", { received = received })
