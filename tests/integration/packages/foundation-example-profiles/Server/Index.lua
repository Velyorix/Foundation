local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Profiles",
})

local S = Foundation.Schema

local profile = context:DefineData(
	"profile",
	S.Record({
		nickname = S.String({ min = 1, max = 24 }),
		color = S.Optional(S.Enum({ "red", "green", "blue" }), "blue"),
	})
)
local visits = context:DefineData("visits", S.Integer({ min = 0 }), { default = 0 })

context:RegisterCommand({
	name = "profile",
	subcommands = {
		{
			name = "set",
			arguments = {
				{ name = "account" },
				{ name = "nickname", min = 1, max = 24 },
				{ name = "color", type = "enum", values = { "red", "green", "blue" }, default = "blue" },
			},
			run = function(sender, args)
				profile:Set(args.account, { nickname = args.nickname, color = args.color }):Then(function()
					sender:Reply("profile of " .. args.account .. " saved")
				end)
			end,
		},
		{
			name = "show",
			arguments = { { name = "account" } },
			run = function(sender, args)
				context:All({ profile:Get(args.account), visits:Get(args.account) }):Then(function(values)
					local current, count = values[1], values[2]
					if current == nil then
						sender:Reply(args.account .. " has no profile, " .. count .. " visit(s)")
						return
					end
					sender:Reply(string.format("%s (%s), %d visit(s)", current.nickname, current.color, count))
				end)
			end,
		},
	},
})

Player.Subscribe("Spawn", function(player)
	local account = player:GetAccountID()
	visits:Get(account):Then(function(count)
		return visits:Set(account, count + 1)
	end)
end)
