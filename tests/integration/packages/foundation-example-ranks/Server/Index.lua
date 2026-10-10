local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Ranks",
})

local ranks = { ["76561198000000011"] = "moderator" }
local grants = {
	moderator = {
		["foundation-example-arena.manage"] = true,
		["foundation.command.packages"] = true,
	},
}

context:ProvideService("foundation:permission_provider", "1.0", {
	Check = function(_, account, node)
		local rank = ranks[account]
		if rank and grants[rank][node] then
			return true
		end
		return nil
	end,
})
