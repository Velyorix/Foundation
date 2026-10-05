local Runtime = Package.Require("foundation/core/runtime.lua")
local Facade = Package.Require("foundation/core/facade.lua")
local Log = Package.Require("foundation/core/log.lua")
local Audit = Package.Require("foundation/core/audit.lua")
local version = Package.Require("foundation/version.lua")

local Bootstrap = {}

local function engine_files()
	return {
		Open = function(path, truncate)
			return File(path, truncate)
		end,
		Exists = File.Exists,
		CreateDirectory = File.CreateDirectory,
		IsDirectory = File.IsDirectory,
	}
end

local function now()
	return math.floor(Server.GetTime() / 1000)
end

function Bootstrap.Start()
	local runtime = Runtime.new({
		side = "server",
		version = version.PRODUCT,
		api_version = version.API,
		catalogs = {
			en = Package.Require("foundation/locales/en/core.lua"),
			fr = Package.Require("foundation/locales/fr/core.lua"),
		},
		sink = Log.console_sink(Console),
		clock = function()
			return Server.GetTime() / 1000
		end,
		now = now,
		create_audit = function(rt)
			return Audit.new({ files = engine_files(), now = now, check = rt.check, log = rt.log })
		end,
	})
	runtime:Start()

	-- Server "Stop" fires before packages unload; an Unload without it is a reload of
	-- Foundation alone, which leaves dependents holding the old instance.
	local server_stopping = false
	Server.Subscribe("Stop", function()
		server_stopping = true
	end)
	Package.Subscribe("Unload", function()
		if not server_stopping and runtime:IsRunning() then
			local active = runtime:ActivePackages()
			if #active > 0 then
				runtime.log:Warning("runtime.unloaded_with_dependents", {
					count = #active,
					ids = table.concat(active, ", "),
					command = "package reload " .. table.concat(active, " "),
				})
			end
		end
		runtime:Stop()
	end)

	Package.Export("Foundation", Facade.new(runtime))
	return runtime
end

return Bootstrap
