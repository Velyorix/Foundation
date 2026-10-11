local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Name Tags",
})

local profiles = context:ReadData("foundation-example-profiles:profile")

context:RegisterCommand({
	name = "nametag",
	arguments = { { name = "account" } },
	run = function(sender, args)
		profiles:Get(args.account):Then(function(profile)
			if profile == nil then
				sender:Reply(args.account .. ": no name tag")
				return
			end
			sender:Reply(string.format("%s: [%s] %s", args.account, profile.color, profile.nickname))
		end)
	end,
})
