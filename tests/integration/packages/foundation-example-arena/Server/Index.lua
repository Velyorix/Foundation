local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Arena",
})

local PLAY = context:DeclarePermission("foundation-example-arena.play", {
	description = "Join arena matches",
	default = "everyone",
})
local MANAGE = context:DeclarePermission("foundation-example-arena.manage", {
	description = "Start matches and appoint referees",
	default = "operators",
})

context:RegisterCommand({
	name = "arena",
	permission = MANAGE,
	subcommands = {
		{
			name = "start",
			run = function(sender)
				sender:Reply("match started")
			end,
		},
		{
			name = "join",
			permission = PLAY,
			run = function(sender)
				sender:Reply(sender:GetName() .. " joined the match")
			end,
		},
		{
			name = "referee",
			arguments = { { name = "account" } },
			run = function(sender, args)
				context:AttachPermission(args.account, MANAGE, true, { duration = 10 * 60 * 1000 })
				sender:Reply(args.account .. " can manage matches for 10 minutes")
			end,
		},
	},
})
