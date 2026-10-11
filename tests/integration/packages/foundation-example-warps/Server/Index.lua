local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Warps",
})

-- Version 1 stored { x, y, z }; version 2 adds the map name.
local warps = context:Store("warps", {
	version = 2,
	migrations = {
		[1] = function(entries)
			for name, position in pairs(entries) do
				entries[name] = { map = "default", position = position }
			end
			return entries
		end,
	},
})

context:RegisterCommand({
	name = "warp",
	subcommands = {
		{
			name = "set",
			arguments = {
				{ name = "name", min = 1, max = 32 },
				{ name = "x", type = "number" },
				{ name = "y", type = "number" },
				{ name = "z", type = "number" },
			},
			run = function(sender, args)
				warps
					:Set(args.name, { map = "default", position = { args.x, args.y, args.z } })
					:Then(function()
						sender:Reply("warp " .. args.name .. " saved")
					end)
					:Catch(function(err)
						sender:Reply("warp not saved: " .. err.message)
					end)
			end,
		},
		{
			name = "show",
			arguments = { { name = "name" } },
			run = function(sender, args)
				warps:Get(args.name):Then(function(warp)
					if warp == nil then
						sender:Reply("no warp named " .. args.name)
						return
					end
					local x, y, z = table.unpack(warp.position)
					sender:Reply(string.format("%s: %g %g %g on %s", args.name, x, y, z, warp.map))
				end)
			end,
		},
		{
			name = "list",
			run = function(sender)
				warps:Keys():Then(function(names)
					sender:Reply(#names .. " warp(s): " .. table.concat(names, ", "))
				end)
			end,
		},
		{
			name = "delete",
			arguments = { { name = "name" } },
			run = function(sender, args)
				warps:Delete(args.name):Then(function(existed)
					sender:Reply(existed and ("warp " .. args.name .. " deleted") or ("no warp named " .. args.name))
				end)
			end,
		},
	},
})
