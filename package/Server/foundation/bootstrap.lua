local Runtime = Package.Require("foundation/core/runtime.lua")
local Facade = Package.Require("foundation/core/facade.lua")
local Log = Package.Require("foundation/core/log.lua")
local Audit = Package.Require("foundation/core/audit.lua")
local Files = Package.Require("foundation/core/files.lua")
local Json = Package.Require("foundation/core/json.lua")
local Sensitive = Package.Require("foundation/core/sensitive.lua")
local I18n = Package.Require("foundation/core/i18n.lua")
local Config = Package.Require("foundation/core/config.lua")
local Settings = Package.Require("foundation/core/settings.lua")
local PackageConfigs = Package.Require("foundation/core/package_config.lua")
local version = Package.Require("foundation/version.lua")

local Bootstrap = {}

local function engine_files()
	return Files.new({
		Open = function(path, truncate)
			return File(path, truncate)
		end,
		Exists = File.Exists,
		CreateDirectory = File.CreateDirectory,
		IsDirectory = File.IsDirectory,
		Rename = File.Rename,
	})
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
		now_ms = function()
			return Server.GetTime()
		end,
		timer = Timer,
		create_config = function(rt)
			return Config.new({
				spec = Settings(rt.schema, rt.messages, I18n.IsLocale),
				files = engine_files(),
				parse = TOML.Parse,
				schema = rt.schema,
				log = rt.log:For("foundation", "config"),
				errors = rt.errors,
				mask = Sensitive.MASK,
			})
		end,
		create_package_configs = function(rt)
			return PackageConfigs.new({
				files = engine_files(),
				parse = TOML.Parse,
				schema = rt.schema,
				check = rt.check,
				log = rt.log,
				invoker = rt.invoker,
			})
		end,
		create_audit = function(rt)
			return Audit.new({
				files = engine_files(),
				json = Json,
				sensitive = Sensitive,
				now = now,
				check = rt.check,
				log = rt.log,
			})
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
